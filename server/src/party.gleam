import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import logging
import settings
import shared/history.{type Direction, Down, Left, Right, Up}
import shared/messages
import shared/party
import ws

pub type Id =
  Int

pub type Model {
  Model(
    party_member_index: Int,
    party: party.Party,
    connections: Dict(Id, ws.Connection),
    directions: Dict(Id, NeighborDetails),
    full_drawing: List(history.HistoryItem),
    needed_ids: List(Id),
    full_drawing_x_size: Int,
    full_drawing_y_size: Int,
    removed_players: List(Id),
    muted_status: MutedStatus,
    locked: Bool,
    settings: settings.SettingsSubject,
  )
}

pub type MutedStatus {
  Individuals(List(Id))
  Party
}

pub type NeighborDetails {
  NeighborDetails(neighbors: Dict(Direction, Id), x_offset: Int, y_offset: Int)
}

pub type Message {
  Join(
    conn: ws.Connection,
    name: String,
    reply_to: process.Subject(Result(Id, String)),
  )
  ClientMessage(id: Id, message: messages.ClientMessage)
  Brodcast(message: String)
  Mimic(name: String, message: String)
  Leave(id: Id)
}

pub type PartyActor =
  actor.Started(process.Subject(Message))

pub fn create(
  player: String,
  conn: ws.Connection,
  settings: settings.SettingsSubject,
) -> PartyActor {
  let assert Ok(actor) =
    actor.new(Model(
      party_member_index: 0,
      party: party.new(player),
      connections: dict.from_list([#(0, conn)]),
      directions: dict.new(),
      full_drawing: [],
      needed_ids: [0],
      full_drawing_x_size: 0,
      full_drawing_y_size: 0,
      removed_players: [],
      muted_status: Individuals([]),
      locked: False,
      settings:,
    ))
    |> actor.on_message(handle_message)
    |> actor.start()
  actor
}

pub fn join(party: PartyActor, name: String, conn: ws.Connection) {
  actor.call(party.data, 100, Join(conn:, name:, reply_to: _))
}

pub fn client_message(
  party: PartyActor,
  id: Id,
  message: messages.ClientMessage,
) {
  actor.send(party.data, ClientMessage(id, message))
}

pub fn leave(party: PartyActor, id: Id) {
  actor.send(party.data, Leave(id))
}

pub fn handle_message(
  model: Model,
  message: Message,
) -> actor.Next(Model, Message) {
  let send_drawing_message = fn(id, direction, handler) {
    let updated = {
      use neighbor_details <- result.try(dict.get(model.directions, id))
      use id_to_send_to <- result.try(dict.get(
        neighbor_details.neighbors,
        direction,
      ))
      use conn_to_send_to <- result.try(dict.get(
        model.connections,
        id_to_send_to,
      ))

      let opposite_direction = case direction {
        Up -> Down
        Down -> Up
        Left -> Right
        Right -> Left
      }
      process.send(conn_to_send_to, handler(opposite_direction))
      Ok(model)
    }
    case updated {
      Ok(new_model) -> actor.continue(new_model)
      Error(_) -> actor.continue(model)
    }
  }

  case message {
    Join(conn:, name:, reply_to:) -> {
      use <- bool.lazy_guard(when: model.locked, return: fn() {
        actor.send(reply_to, Error("Party is locked"))
        actor.continue(model)
      })

      use <- bool.lazy_guard(
        when: dict.size(model.connections)
          >= settings.get_settings(model.settings).max_party_size,
        return: fn() {
          actor.send(reply_to, Error("Party is already full"))
          actor.continue(model)
        },
      )

      let id = model.party_member_index + 1

      model.connections
      |> dict.values()
      |> list.each(fn(connection) {
        process.send(connection, messages.UserJoined(name:, id:))
      })

      let new_party =
        party.Party(
          ..model.party,
          players: model.party.players |> dict.insert(id, party.Player(name)),
        )

      process.send(conn, messages.PartyInfo(new_party, id))

      actor.send(reply_to, Ok(id))

      let model =
        Model(
          ..model,
          party_member_index: id,
          party: new_party,
          needed_ids: [id, ..model.needed_ids],
          connections: model.connections |> dict.insert(id, conn),
        )

      actor.continue(model)
    }
    Leave(id) -> {
      case id {
        0 -> {
          model.connections
          |> dict.values()
          |> list.each(fn(connection) {
            process.send(connection, messages.Disconnected("Party was closed"))
          })
          actor.stop()
        }
        _ ->
          case list.contains(model.removed_players, id) {
            False -> remove_users(model, [id], "disconnected")
            True -> actor.continue(model)
          }
      }
    }
    Brodcast(message) -> {
      send_to_all(
        model.connections,
        messages.ChatMessage(party.Server(message)),
      )
      actor.continue(model)
    }
    Mimic(name, message) -> {
      let user =
        model.party.players
        |> dict.to_list()
        |> list.find(fn(pair) {
          let #(_user_id, player) = pair
          player.name == name
        })

      case user {
        Ok(#(user_id, party.Player(name:))) -> {
          send_to_all(
            model.connections,
            messages.ChatMessage(party.User(user_id, name, message)),
          )
        }
        Error(_) -> {
          logging.log(
            logging.Warning,
            "Could not find user with name " <> name <> " to mimic",
          )
        }
      }

      actor.continue(model)
    }
    ClientMessage(id, message) -> {
      let require_permissions = fn(run) {
        case id {
          0 -> run()
          _ -> {
            logging.log(
              logging.Warning,
              "Invalid permissions for user " <> int.to_string(id),
            )
            actor.continue(model)
          }
        }
      }

      let respond_with_server_message = fn(server_message) {
        case dict.get(model.connections, id) {
          Ok(connection) ->
            process.send(
              connection,
              messages.ChatMessage(party.Server(server_message)),
            )
          Error(_) -> Nil
        }
      }

      case message {
        messages.KickUser(id_to_kick) -> {
          use <- require_permissions()
          kick_users(model, [id_to_kick])
        }
        messages.SendChatMessage(message) -> {
          use <- try_to_run_command(model, id, message)

          let send = fn() {
            let name = case dict.get(model.party.players, id) {
              Ok(player) -> player.name
              Error(Nil) -> "unknown"
            }

            send_to_all(
              model.connections,
              messages.ChatMessage(party.User(id:, name:, message:)),
            )

            actor.continue(model)
          }

          case model.muted_status, id {
            _, 0 -> send()
            Party, _ -> {
              logging.log(
                logging.Debug,
                "User "
                  <> int.to_string(id)
                  <> " tried to send a message but the party is muted",
              )
              respond_with_server_message(
                "You cannot send messages while the party is muted",
              )

              actor.continue(model)
            }
            Individuals(muted_users), _ -> {
              use <- bool.lazy_guard(
                when: list.contains(muted_users, id),
                return: fn() {
                  logging.log(
                    logging.Debug,
                    "User "
                      <> int.to_string(id)
                      <> " tried to send a message but the is muted",
                  )
                  respond_with_server_message(
                    "You cannot send messages while you are muted",
                  )
                  actor.continue(model)
                },
              )
              send()
            }
          }
        }
        messages.StartDrawing -> {
          let players = dict.keys(model.party.players)

          use <- bool.lazy_guard(when: list.length(players) < 2, return: fn() {
            actor.continue(model)
          })

          let assert [first, second, ..] = players
          let assert [last, second_to_last, ..] = players |> list.reverse()

          let #(before_dir, after_dir) = case model.party.drawings_layout {
            party.Horizontal -> #(Left, Right)
            party.Vertical -> #(Up, Down)
          }

          let standard_x_offset = case model.party.drawings_layout {
            party.Horizontal -> 1
            party.Vertical -> 0
          }

          let standard_y_offset = case model.party.drawings_layout {
            party.Horizontal -> 0
            party.Vertical -> 1
          }

          let num_players = list.length(players)

          let #(full_drawing_x_size, full_drawing_y_size) = case
            model.party.drawings_layout
          {
            party.Horizontal -> #(num_players, 1)
            party.Vertical -> #(1, num_players)
          }

          let directions =
            list.window(players, 3)
            |> list.index_map(fn(player_ids, i) {
              let assert [before, current, after] = player_ids as "window of 3"
              #(
                current,
                NeighborDetails(
                  x_offset: standard_x_offset * { i + 1 },
                  y_offset: standard_y_offset * { i + 1 },
                  neighbors: dict.from_list([
                    #(before_dir, before),
                    #(after_dir, after),
                  ]),
                ),
              )
            })
            |> dict.from_list()
            |> dict.insert(
              first,
              NeighborDetails(
                x_offset: 0,
                y_offset: 0,
                neighbors: dict.from_list([#(after_dir, second)]),
              ),
            )
            |> dict.insert(
              last,
              NeighborDetails(
                x_offset: standard_x_offset * { num_players - 1 },
                y_offset: standard_y_offset * { num_players - 1 },
                neighbors: dict.from_list([#(before_dir, second_to_last)]),
              ),
            )

          directions
          |> dict.to_list()
          |> list.each(fn(item) {
            let #(id, NeighborDetails(neighbors:, ..)) = item

            case dict.get(model.connections, id) {
              Ok(conn) ->
                process.send(
                  conn,
                  messages.DrawingInit(
                    top: dict.has_key(neighbors, Up),
                    left: dict.has_key(neighbors, Left),
                    right: dict.has_key(neighbors, Right),
                    bottom: dict.has_key(neighbors, Down),
                  ),
                )
              Error(_) -> Nil
            }
          })

          actor.continue(
            Model(
              ..model,
              directions:,
              full_drawing_x_size:,
              full_drawing_y_size:,
            ),
          )
        }
        messages.SendDrawing(items, pen_settings, direction) -> {
          use opposite_direction <- send_drawing_message(id, direction)
          messages.DrawingSent(items, pen_settings, opposite_direction)
        }
        messages.SetLayout(layout) -> {
          let party = party.Party(..model.party, drawings_layout: layout)

          send_to_all(model.connections, messages.LayoutSet(layout))

          actor.continue(Model(..model, party:))
        }
        messages.EndDrawing(history) -> {
          model.connections
          |> dict.to_list()
          |> list.each(fn(pair) {
            let #(id, connection) = pair
            case id {
              0 -> Nil
              _ -> process.send(connection, messages.RequestDrawing)
            }
          })

          actor.continue(add_drawing_to_history(model, 0, history))
        }
        messages.SendFinalDrawing(history) ->
          actor.continue(add_drawing_to_history(model, id, history))
        messages.Undo(direction) -> {
          use opposite_direction <- send_drawing_message(id, direction)
          messages.UndoSent(opposite_direction)
        }
        messages.Redo(direction) -> {
          use opposite_direction <- send_drawing_message(id, direction)
          messages.RedoSent(opposite_direction)
        }
        messages.CreateParty(..) | messages.JoinParty(..) ->
          panic as "should not be handled here"
      }
    }
  }
}

fn kick_users(model: Model, ids: List(Id)) -> actor.Next(Model, Message) {
  list.each(ids, fn(id_to_kick) {
    case dict.get(model.connections, id_to_kick) {
      Ok(conn) -> {
        process.send(
          conn,
          messages.Disconnected("You were kicked from the party"),
        )
      }
      Error(_) -> Nil
    }
  })
  remove_users(model, ids, reason: "was kicked from the party")
}

fn try_to_run_command(
  model: Model,
  id: Id,
  message: String,
  otherwise: fn() -> actor.Next(Model, Message),
) -> actor.Next(Model, Message) {
  use <- bool.lazy_guard(id != 0, return: otherwise)

  let get_matching_users = fn(users) {
    let possible_users = string.split(users, " ")

    let matching_users =
      model.party.players
      |> dict.to_list()
      |> list.filter_map(fn(pair) {
        let #(user_id, player) = pair
        case list.contains(possible_users, player.name) {
          True -> Ok(user_id)
          False -> Error(Nil)
        }
      })

    case matching_users {
      [] -> {
        let _ =
          model.connections
          |> dict.get(0)
          |> result.map(fn(leader_connection) {
            process.send(
              leader_connection,
              messages.ChatMessage(party.Server(
                "No users found when running " <> message,
              )),
            )
          })
        Nil
      }
      _ -> Nil
    }
    matching_users
  }

  case message {
    "/kick " <> users -> {
      let matching_users = get_matching_users(users)
      kick_users(model, matching_users)
    }
    "/lock" -> {
      send_to_all(
        model.connections,
        messages.ChatMessage(party.Server("The party was locked")),
      )
      actor.continue(Model(..model, locked: True))
    }
    "/unlock" -> {
      send_to_all(
        model.connections,
        messages.ChatMessage(party.Server("The party was unlocked")),
      )
      actor.continue(Model(..model, locked: False))
    }
    "/mute" <> users -> {
      case string.trim(users) {
        "" -> {
          send_to_all(
            model.connections,
            messages.ChatMessage(party.Server("The party was muted")),
          )
          actor.continue(Model(..model, muted_status: Party))
        }
        users -> {
          let matching_users = get_matching_users(users)
          send_to_all(
            model.connections,
            messages.ChatMessage(party.Server("Muted users: " <> users)),
          )
          actor.continue(
            Model(..model, muted_status: Individuals(matching_users)),
          )
        }
      }
    }
    "/unmute" <> users -> {
      case string.trim(users) {
        "" -> {
          send_to_all(
            model.connections,
            messages.ChatMessage(party.Server("Unmuted party")),
          )
          actor.continue(Model(..model, muted_status: Individuals([])))
        }
        users -> {
          let matching_users = get_matching_users(users)
          send_to_all(
            model.connections,
            messages.ChatMessage(party.Server("Unmuted " <> users)),
          )
          case model.muted_status {
            Party ->
              actor.continue(
                Model(
                  ..model,
                  muted_status: Individuals(
                    model.connections
                    |> dict.keys()
                    |> list.filter(fn(id) {
                      id != 0 || !list.contains(matching_users, id)
                    }),
                  ),
                ),
              )
            Individuals(already_muted) -> {
              actor.continue(
                Model(
                  ..model,
                  muted_status: Individuals(
                    already_muted
                    |> list.filter(fn(id) { !list.contains(matching_users, id) }),
                  ),
                ),
              )
            }
          }
        }
      }
    }
    _ -> otherwise()
  }
}

fn add_drawing_to_history(model: Model, id, history) {
  case dict.get(model.directions, id) {
    Ok(NeighborDetails(x_offset:, y_offset:, ..)) -> {
      let needed_ids =
        model.needed_ids
        |> list.filter(fn(needed_id) { needed_id != id })

      let full_drawing =
        list.append(
          list.map(history, fn(history_item) {
            case history_item {
              history.Point(x:, y:) ->
                history.Point(
                  x: x + { x_offset * history.canvas_width },
                  y: y + { y_offset * history.canvas_height },
                )
              item -> item
            }
          }),
          model.full_drawing,
        )

      case needed_ids {
        [] -> {
          model.connections
          |> dict.values()
          |> list.each(fn(connection) {
            process.send(
              connection,
              messages.DrawingFinalized(
                full_drawing,
                model.full_drawing_x_size * history.canvas_width,
                model.full_drawing_y_size * history.canvas_height,
              ),
            )
          })
        }
        _ -> Nil
      }

      Model(..model, full_drawing:, needed_ids:)
    }
    Error(_) -> model
  }
}

fn remove_users(
  model: Model,
  ids: List(Int),
  reason reason: String,
) -> actor.Next(Model, Message) {
  let connections =
    model.connections |> dict.filter(fn(id, _) { !list.contains(ids, id) })

  ids
  |> list.each(fn(id) {
    send_to_all(connections, messages.UserLeft(id))

    let name = case dict.get(model.party.players, id) {
      Ok(player) -> player.name
      Error(Nil) -> "unknown"
    }

    send_to_all(
      connections,
      messages.ChatMessage(party.Server(name <> " " <> reason)),
    )
  })

  let party =
    party.Party(
      ..model.party,
      players: model.party.players
        |> dict.filter(fn(id, _) { !list.contains(ids, id) }),
    )

  actor.continue(
    Model(
      ..model,
      party:,
      connections:,
      needed_ids: model.needed_ids
        |> list.filter(fn(needed_id) { !list.contains(ids, needed_id) }),
      removed_players: list.append(ids, model.removed_players),
    ),
  )
}

fn send_to_all(connections, msg) {
  connections
  |> dict.values()
  |> list.each(fn(connection) { process.send(connection, msg) })
}
