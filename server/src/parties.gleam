import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/result
import gleam/string
import logging
import party
import settings
import simplifile
import ws

pub type Model {
  Model(
    parties: Dict(String, party.PartyActor),
    settings: settings.SettingsSubject,
  )
}

pub type Message {
  NewParty(
    name: String,
    conn: ws.Connection,
    reply_to: Subject(#(String, party.PartyActor)),
  )
  GetParty(code: String, reply_to: Subject(Result(party.PartyActor, Nil)))
  CloseParty(code: String)
  ControlAction(party: String)
}

const alphabet = [
  "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P",
  "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
]

fn create_party_code() {
  [
    list.sample(alphabet, 1),
    list.sample(alphabet, 1),
    list.sample(alphabet, 1),
    list.sample(alphabet, 1),
  ]
  |> list.flatten()
  |> string.concat()
}

pub type PartiesManager =
  actor.Started(Subject(Message))

pub fn start(
  settings: settings.SettingsSubject,
  name: process.Name(Message),
) -> Result(actor.Started(Subject(Message)), actor.StartError) {
  actor.new(Model(parties: dict.new(), settings:))
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start()
}

pub fn create_party(
  manager: PartiesManager,
  name: String,
  conn: ws.Connection,
) -> #(String, party.PartyActor) {
  actor.call(manager.data, 100, NewParty(name, conn, _))
}

pub fn get_party(
  manager: PartiesManager,
  code: String,
) -> Result(party.PartyActor, Nil) {
  actor.call(manager.data, 100, GetParty(code, _))
}

pub fn close_party(manager: PartiesManager, code: String) -> Nil {
  actor.send(manager.data, CloseParty(code))
}

pub fn control_action(manager: process.Subject(Message), party: String) -> Nil {
  actor.send(manager, ControlAction(party))
}

fn handle_message(model: Model, message: Message) -> actor.Next(Model, Message) {
  case message {
    NewParty(name, conn, reply_to) -> {
      let party_code = create_party_code()
      let party = party.create(name, conn, model.settings)
      actor.send(reply_to, #(party_code, party))

      actor.continue(
        Model(..model, parties: model.parties |> dict.insert(party_code, party)),
      )
    }
    GetParty(code, reply_to) -> {
      actor.send(reply_to, dict.get(model.parties, code))

      actor.continue(model)
    }
    CloseParty(code) -> {
      logging.log(logging.Notice, "Closing party with code: " <> code)
      actor.continue(Model(..model, parties: dict.delete(model.parties, code)))
    }
    ControlAction(party_code) -> {
      logging.log(logging.Notice, "Received control action for " <> party_code)
      let parties = case party_code {
        "all" -> {
          model.parties |> dict.values()
        }
        code -> {
          model.parties
          |> dict.get(code)
          |> result.map(list.wrap)
          |> result.unwrap([])
        }
      }
      handle_control_action(party_code, parties)
      actor.continue(model)
    }
  }
}

fn handle_control_action(code: String, parties) {
  let assert Ok(current_dir) = simplifile.current_directory()
  let file = current_dir <> "/actions/" <> code

  file
  |> simplifile.read()
  |> result.unwrap("")
  |> string.split("\n")
  |> list.filter_map(fn(action) {
    case action {
      "broadcast " <> message -> Ok(party.Brodcast(message))
      "mimic " <> arguments -> {
        case string.split_once(arguments, on: "|") {
          Ok(#(name, message)) -> {
            Ok(party.Mimic(string.trim(name), string.trim(message)))
          }
          Error(_) -> {
            logging.log(
              logging.Warning,
              "Invalid mimic action was discarded: [" <> action <> "]",
            )
            Error(Nil)
          }
        }
      }
      // ignore empty lines
      "" -> Error(Nil)
      _ -> {
        logging.log(
          logging.Warning,
          "Unknown action was discarded: [" <> action <> "]",
        )
        Error(Nil)
      }
    }
  })
  |> list.each(fn(action) {
    parties
    |> list.each(fn(party: party.PartyActor) { actor.send(party.data, action) })
  })

  let _ = simplifile.delete(file)
  Nil
}
