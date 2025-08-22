import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor
import gleam/string
import logging
import party
import settings
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

pub fn start(settings: settings.SettingsSubject) {
  actor.new(Model(parties: dict.new(), settings:))
  |> actor.on_message(handle_message)
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
  }
}
