import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
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
  )
}

pub type NeighborDetails {
  NeighborDetails(neighbors: Dict(Direction, Id), x_offset: Int, y_offset: Int)
}

pub type Message {
  Join(conn: ws.Connection, name: String, reply_to: process.Subject(Int))
  Leave(id: Id)
  Kick(id: Id)
  SendMessage(id: Id, message: String)
  StartDrawing
  SendDrawing(
    id: Id,
    items: List(history.HistoryItem),
    color: String,
    direction: Direction,
  )
  HistoryFunction(
    id: Id,
    direction: Direction,
    respond_with: fn(Direction) -> messages.ServerMessage,
  )
  SetLayout(party.DrawingsLayout)
  EndDrawing(history: List(history.HistoryItem))
  SendFinalDrawing(history: List(history.HistoryItem), id: Id)
}

pub type PartyActor =
  actor.Started(process.Subject(Message))

pub fn create(player: String, conn: ws.Connection) -> PartyActor {
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
    ))
    |> actor.on_message(handle_message)
    |> actor.start()
  actor
}

pub fn join(party: PartyActor, name: String, conn: ws.Connection) {
  actor.call(party.data, 100, Join(conn:, name:, reply_to: _))
}

pub fn leave(party: PartyActor, id: Int) {
  actor.send(party.data, Leave(id))
}

pub fn kick(party: PartyActor, id: Int) {
  actor.send(party.data, Kick(id))
}

pub fn start_drawing(party: PartyActor) {
  actor.send(party.data, StartDrawing)
}

pub fn set_layout(party: PartyActor, layout: party.DrawingsLayout) {
  actor.send(party.data, SetLayout(layout))
}

pub fn end_drawing(party: PartyActor, history) {
  actor.send(party.data, EndDrawing(history))
}

pub fn send_final_drawing(party: PartyActor, history, id) {
  actor.send(party.data, SendFinalDrawing(history, id))
}

pub fn send_chat_message(party: PartyActor, id: Id, message: String) {
  actor.send(party.data, SendMessage(id, message))
}

pub fn send_drawing(
  party: PartyActor,
  id: Int,
  items: List(history.HistoryItem),
  color: String,
  direction: Direction,
) {
  actor.send(party.data, SendDrawing(id, items, color, direction))
}

pub fn history_function(
  party: PartyActor,
  id: Int,
  direction: Direction,
  respond_with,
) {
  actor.send(party.data, HistoryFunction(id, direction, respond_with))
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

      actor.send(reply_to, id)

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
        _ -> remove_user(model, id)
      }
    }
    Kick(id) -> {
      case dict.get(model.connections, id) {
        Ok(conn) -> {
          process.send(
            conn,
            messages.Disconnected("You were kicked from the party"),
          )
        }
        Error(_) -> Nil
      }
      remove_user(model, id)
    }
    SendMessage(id, message) -> {
      model.connections
      |> dict.values()
      |> list.each(fn(connection) {
        process.send(connection, messages.ChatMessage(id, message))
      })

      actor.continue(model)
    }
    StartDrawing -> {
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
        Model(..model, directions:, full_drawing_x_size:, full_drawing_y_size:),
      )
    }
    SendDrawing(id, items, color, direction) -> {
      use opposite_direction <- send_drawing_message(id, direction)
      messages.DrawingSent(items, color, opposite_direction)
    }
    HistoryFunction(id, direction, respond_with) -> {
      use opposite_direction <- send_drawing_message(id, direction)
      respond_with(opposite_direction)
    }
    SetLayout(layout) -> {
      let party = party.Party(..model.party, drawings_layout: layout)

      model.connections
      |> dict.values()
      |> list.each(fn(connection) {
        process.send(connection, messages.LayoutSet(layout))
      })

      actor.continue(Model(..model, party:))
    }
    EndDrawing(history) -> {
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
    SendFinalDrawing(history, id) -> {
      actor.continue(add_drawing_to_history(model, id, history))
    }
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

fn remove_user(model: Model, id: Int) -> actor.Next(Model, Message) {
  let connections = model.connections |> dict.delete(id)

  connections
  |> dict.values()
  |> list.each(fn(connection) {
    process.send(connection, messages.UserLeft(id))
  })

  let party =
    party.Party(..model.party, players: model.party.players |> dict.delete(id))

  actor.continue(
    Model(
      ..model,
      party:,
      connections:,
      needed_ids: model.needed_ids
        |> list.filter(fn(needed_id) { needed_id != id }),
    ),
  )
}
