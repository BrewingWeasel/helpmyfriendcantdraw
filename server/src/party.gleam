import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/list
import gleam/otp/actor
import gleam/result
import shared/history.{type Direction, Down, Left, Right, Up}
import shared/messages
import shared/party
import ws

pub type Model {
  Model(
    party_member_index: Int,
    party: party.Party,
    connections: Dict(Int, ws.Connection),
    directions: Dict(Int, Dict(Direction, Int)),
  )
}

pub type Message {
  Join(conn: ws.Connection, name: String, reply_to: process.Subject(Int))
  Leave(id: Int)
  Kick(id: Int)
  SendMessage(id: Int, message: String)
  StartDrawing
  SendDrawing(
    id: Int,
    items: List(history.HistoryItem),
    color: String,
    direction: Direction,
  )
  HistoryFunction(
    id: Int,
    direction: Direction,
    respond_with: fn(Direction) -> messages.ServerMessage,
  )
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

pub fn send_chat_message(party: PartyActor, id: Int, message: String) {
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
      use current_directions <- result.try(dict.get(model.directions, id))
      use id_to_send_to <- result.try(dict.get(current_directions, direction))
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
          players: model.party.players |> dict.insert(id, party.Player(name)),
        )

      process.send(conn, messages.PartyInfo(new_party, id))

      actor.send(reply_to, id)

      let model =
        Model(
          ..model,
          party_member_index: id,
          party: new_party,
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

      let assert [first, second, ..] = players
      let assert [last, second_to_last, ..] = players |> list.reverse()
      let directions =
        list.window(players, 3)
        |> list.map(fn(player_ids) {
          let assert [before, current, after] = player_ids as "window of 3"
          #(current, dict.from_list([#(Up, before), #(Down, after)]))
        })
        |> dict.from_list()
        |> dict.insert(first, dict.from_list([#(Down, second)]))
        |> dict.insert(last, dict.from_list([#(Up, second_to_last)]))

      directions
      |> dict.to_list()
      |> list.each(fn(item) {
        let #(id, direction) = item

        case dict.get(model.connections, id) {
          Ok(conn) ->
            process.send(
              conn,
              messages.DrawingInit(
                top: dict.has_key(direction, Up),
                left: dict.has_key(direction, Left),
                right: dict.has_key(direction, Right),
                bottom: dict.has_key(direction, Down),
              ),
            )
          Error(_) -> Nil
        }
      })

      actor.continue(Model(..model, directions:))
    }
    SendDrawing(id, items, color, direction) -> {
      use opposite_direction <- send_drawing_message(id, direction)
      messages.DrawingSent(items, color, opposite_direction)
    }
    HistoryFunction(id, direction, respond_with) -> {
      use opposite_direction <- send_drawing_message(id, direction)
      respond_with(opposite_direction)
    }
  }
}

fn remove_user(model: Model, id: Int) -> actor.Next(Model, Message) {
  let connections = model.connections |> dict.delete(id)

  connections
  |> dict.values()
  |> list.each(fn(connection) {
    process.send(connection, messages.UserLeft(id))
  })

  let party = party.Party(players: model.party.players |> dict.delete(id))

  actor.continue(Model(..model, party:, connections:))
}
