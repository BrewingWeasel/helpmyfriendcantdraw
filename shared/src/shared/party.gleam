import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result

pub type Party {
  Party(players: dict.Dict(Int, Player), drawings_layout: DrawingsLayout)
}

pub type DrawingsLayout {
  Vertical
  Horizontal
}

pub fn drawings_layout_to_json(drawings_layout: DrawingsLayout) -> json.Json {
  case drawings_layout {
    Vertical -> json.string("v")
    Horizontal -> json.string("h")
  }
}

pub fn drawings_layout_decoder() -> decode.Decoder(DrawingsLayout) {
  use variant <- decode.then(decode.string)
  case variant {
    "v" -> decode.success(Vertical)
    "h" -> decode.success(Horizontal)
    _ -> decode.failure(Vertical, "DrawingsLayout")
  }
}

pub type SharedParty {
  SharedParty(info: Party, code: String, chat: Chat, id: Int)
}

pub type Chat {
  Chat(messages: List(#(Int, String, String)), current_chat_message: String)
}

pub fn to_json(party: Party) -> json.Json {
  let Party(players:, drawings_layout:) = party
  json.object([
    #("players", json.dict(players, int.to_string, player_to_json)),
    #("drawings_layout", drawings_layout_to_json(drawings_layout)),
  ])
}

pub fn decoder() -> decode.Decoder(Party) {
  use players <- decode.field(
    "players",
    decode.dict(
      decode.string |> decode.map(fn(n) { int.parse(n) |> result.unwrap(0) }),
      player_decoder(),
    ),
  )
  use drawings_layout <- decode.field(
    "drawings_layout",
    drawings_layout_decoder(),
  )
  decode.success(Party(players:, drawings_layout:))
}

pub type Player {
  Player(name: String)
}

fn player_to_json(player: Player) -> json.Json {
  let Player(name:) = player
  json.object([#("name", json.string(name))])
}

fn player_decoder() -> decode.Decoder(Player) {
  use name <- decode.field("name", decode.string)
  decode.success(Player(name:))
}

pub fn new(name: String) -> Party {
  Party(
    players: dict.from_list([#(0, Player(name))]),
    drawings_layout: Horizontal,
  )
}
