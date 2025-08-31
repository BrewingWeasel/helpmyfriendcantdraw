import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option
import gleam/result

pub type Party {
  Party(
    players: dict.Dict(Int, Player),
    drawings_layout: DrawingsLayout,
    overlap: Int,
    duration: option.Option(Int),
  )
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
  Chat(messages: List(ChatMessage), current_chat_message: String)
}

pub type ChatMessage {
  User(id: Int, name: String, message: String)
  Server(message: String)
}

pub fn chat_message_to_json(chat_message: ChatMessage) -> json.Json {
  case chat_message {
    User(id:, name:, message:) ->
      json.object([
        #("t", json.int(0)),
        #("id", json.int(id)),
        #("name", json.string(name)),
        #("message", json.string(message)),
      ])
    Server(message:) ->
      json.object([#("t", json.int(1)), #("message", json.string(message))])
  }
}

pub fn chat_message_decoder() -> decode.Decoder(ChatMessage) {
  use variant <- decode.field("t", decode.int)
  case variant {
    0 -> {
      use id <- decode.field("id", decode.int)
      use name <- decode.field("name", decode.string)
      use message <- decode.field("message", decode.string)
      decode.success(User(id:, name:, message:))
    }
    1 -> {
      use message <- decode.field("message", decode.string)
      decode.success(Server(message:))
    }
    _ -> decode.failure(Server("invalid message"), "ChatMessage")
  }
}

pub fn to_json(party: Party) -> json.Json {
  let Party(players:, drawings_layout:, overlap:, duration:) = party
  json.object([
    #("players", json.dict(players, int.to_string, player_to_json)),
    #("drawings_layout", drawings_layout_to_json(drawings_layout)),
    #("overlap", json.int(overlap)),
    #("duration", case duration {
      option.Some(d) -> json.int(d)
      option.None -> json.null()
    }),
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
  use overlap <- decode.field("overlap", decode.int)
  use duration <- decode.field("duration", decode.optional(decode.int))
  decode.success(Party(players:, drawings_layout:, overlap:, duration:))
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
    overlap: 30,
    duration: option.None,
  )
}
