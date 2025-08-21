import gleam/dynamic/decode
import gleam/json
import shared/history
import shared/party

pub type PenSettings {
  PenSettings(color: String, size: Int)
}

fn pen_settings_to_json(pen_settings: PenSettings) -> json.Json {
  let PenSettings(color:, size:) = pen_settings
  json.object([#("color", json.string(color)), #("size", json.int(size))])
}

fn pen_settings_decoder() -> decode.Decoder(PenSettings) {
  use color <- decode.field("color", decode.string)
  use size <- decode.field("size", decode.int)
  decode.success(PenSettings(color:, size:))
}

pub type ClientMessage {
  CreateParty(name: String)
  JoinParty(code: String, name: String)
  KickUser(id: Int)
  SendDrawing(
    history: List(history.HistoryItem),
    pen_settings: PenSettings,
    direction: history.Direction,
  )
  SetLayout(layout: party.DrawingsLayout)
  SendChatMessage(message: String)
  StartDrawing
  Undo(direction: history.Direction)
  Redo(direction: history.Direction)
  EndDrawing(history: List(history.HistoryItem))
  SendFinalDrawing(history: List(history.HistoryItem))
}

pub fn encode_client_message(msg: ClientMessage) -> String {
  let #(msg_type_number, attached_data) = case msg {
    CreateParty(name) -> #(0, [#("name", json.string(name))])
    JoinParty(code, name) -> #(1, [
      #("code", json.string(code)),
      #("name", json.string(name)),
    ])
    KickUser(id) -> #(2, [#("id", json.int(id))])
    SendChatMessage(message) -> #(3, [#("message", json.string(message))])
    StartDrawing -> #(4, [])
    SendDrawing(history, pen_settings, direction) -> {
      let attached_data = [
        #("history", json.array(history, history.history_item_to_json)),
        #("pen_settings", pen_settings_to_json(pen_settings)),
        #("direction", history.direction_to_json(direction)),
      ]
      #(5, attached_data)
    }
    Undo(direction) -> {
      let attached_data = [#("direction", history.direction_to_json(direction))]
      #(6, attached_data)
    }
    Redo(direction) -> {
      let attached_data = [#("direction", history.direction_to_json(direction))]
      #(7, attached_data)
    }
    SetLayout(layout) -> {
      let attached_data = [#("layout", party.drawings_layout_to_json(layout))]
      #(8, attached_data)
    }
    EndDrawing(history) -> {
      let attached_data = [
        #("history", json.array(history, history.history_item_to_json)),
      ]
      #(9, attached_data)
    }
    SendFinalDrawing(history) -> {
      let attached_data = [
        #("history", json.array(history, history.history_item_to_json)),
      ]
      #(10, attached_data)
    }
  }
  json.object([#("t", json.int(msg_type_number)), ..attached_data])
  |> json.to_string()
}

pub fn decode_client_message(
  data: String,
) -> Result(ClientMessage, json.DecodeError) {
  let client_decoder = {
    use type_ <- decode.field("t", decode.int)
    case type_ {
      0 -> {
        use name <- decode.field("name", decode.string)
        decode.success(CreateParty(name:))
      }
      1 -> {
        use code <- decode.field("code", decode.string)
        use name <- decode.field("name", decode.string)
        decode.success(JoinParty(code:, name:))
      }
      2 -> {
        use id <- decode.field("id", decode.int)
        decode.success(KickUser(id:))
      }
      3 -> {
        use message <- decode.field("message", decode.string)
        decode.success(SendChatMessage(message:))
      }
      4 -> decode.success(StartDrawing)
      5 -> {
        use history <- decode.field(
          "history",
          decode.list(history.history_item_decoder()),
        )
        use pen_settings <- decode.field("pen_settings", pen_settings_decoder())
        use direction <- decode.field("direction", history.direction_decoder())
        decode.success(SendDrawing(history:, pen_settings:, direction:))
      }
      6 -> {
        use direction <- decode.field("direction", history.direction_decoder())
        decode.success(Undo(direction:))
      }
      7 -> {
        use direction <- decode.field("direction", history.direction_decoder())
        decode.success(Redo(direction:))
      }
      8 -> {
        use layout <- decode.field("layout", party.drawings_layout_decoder())
        decode.success(SetLayout(layout:))
      }
      9 -> {
        use history <- decode.field(
          "history",
          decode.list(history.history_item_decoder()),
        )
        decode.success(EndDrawing(history:))
      }
      10 -> {
        use history <- decode.field(
          "history",
          decode.list(history.history_item_decoder()),
        )
        decode.success(SendFinalDrawing(history:))
      }
      _ -> decode.failure(CreateParty(""), "no type found")
    }
  }
  json.parse(from: data, using: client_decoder)
}

pub type ServerMessage {
  PartyCreated(code: String)
  UserJoined(name: String, id: Int)
  PartyInfo(party: party.Party, id: Int)
  UserLeft(id: Int)
  Disconnected(reason: String)
  ChatMessage(message: party.ChatMessage)
  DrawingInit(top: Bool, left: Bool, right: Bool, bottom: Bool)
  DrawingSent(
    history: List(history.HistoryItem),
    pen_settings: PenSettings,
    direction: history.Direction,
  )
  UndoSent(direction: history.Direction)
  RedoSent(direction: history.Direction)
  LayoutSet(layout: party.DrawingsLayout)
  RequestDrawing
  DrawingFinalized(history: List(history.HistoryItem), x_size: Int, y_size: Int)
}

pub fn encode_server_message(msg: ServerMessage) -> String {
  let #(msg_type_number, attached_data) = case msg {
    PartyCreated(code) -> #(0, [#("code", json.string(code))])
    UserJoined(name, id) -> #(1, [
      #("name", json.string(name)),
      #("id", json.int(id)),
    ])
    PartyInfo(party, id) -> #(2, [
      #("party", party.to_json(party)),
      #("id", json.int(id)),
    ])
    UserLeft(id) -> #(3, [#("id", json.int(id))])
    Disconnected(reason) -> #(4, [#("reason", json.string(reason))])
    ChatMessage(message) -> #(5, [
      #("message", party.chat_message_to_json(message)),
    ])
    DrawingInit(top, left, right, bottom) -> {
      let attached_data = [
        #("top", json.bool(top)),
        #("left", json.bool(left)),
        #("right", json.bool(right)),
        #("bottom", json.bool(bottom)),
      ]
      #(6, attached_data)
    }
    DrawingSent(history, pen_settings, direction) -> {
      let attached_data = [
        #("history", json.array(history, history.history_item_to_json)),
        #("pen_settings", pen_settings_to_json(pen_settings)),
        #("direction", history.direction_to_json(direction)),
      ]
      #(7, attached_data)
    }
    UndoSent(direction) -> {
      let attached_data = [#("direction", history.direction_to_json(direction))]
      #(8, attached_data)
    }
    RedoSent(direction) -> {
      let attached_data = [#("direction", history.direction_to_json(direction))]
      #(9, attached_data)
    }
    LayoutSet(layout) -> {
      let attached_data = [#("layout", party.drawings_layout_to_json(layout))]
      #(10, attached_data)
    }
    RequestDrawing -> #(11, [])
    DrawingFinalized(history, x_size, y_size) -> {
      let attached_data = [
        #("history", json.array(history, history.history_item_to_json)),
        #("x_size", json.int(x_size)),
        #("y_size", json.int(y_size)),
      ]
      #(12, attached_data)
    }
  }
  json.object([#("t", json.int(msg_type_number)), ..attached_data])
  |> json.to_string()
}

pub fn decode_server_message(
  data: String,
) -> Result(ServerMessage, json.DecodeError) {
  let server_decoder = {
    use type_ <- decode.field("t", decode.int)
    case type_ {
      0 -> {
        use code <- decode.field("code", decode.string)
        decode.success(PartyCreated(code:))
      }
      1 -> {
        use name <- decode.field("name", decode.string)
        use id <- decode.field("id", decode.int)
        decode.success(UserJoined(name:, id:))
      }
      2 -> {
        use party_json <- decode.field("party", party.decoder())
        use id <- decode.field("id", decode.int)
        decode.success(PartyInfo(party: party_json, id:))
      }
      3 -> {
        use id <- decode.field("id", decode.int)
        decode.success(UserLeft(id:))
      }
      4 -> {
        use reason <- decode.field("reason", decode.string)
        decode.success(Disconnected(reason:))
      }
      5 -> {
        use message <- decode.field("message", party.chat_message_decoder())
        decode.success(ChatMessage(message:))
      }
      6 -> {
        use top <- decode.field("top", decode.bool)
        use left <- decode.field("left", decode.bool)
        use right <- decode.field("right", decode.bool)
        use bottom <- decode.field("bottom", decode.bool)
        decode.success(DrawingInit(top:, left:, right:, bottom:))
      }
      7 -> {
        use history <- decode.field(
          "history",
          decode.list(history.history_item_decoder()),
        )
        use pen_settings <- decode.field("pen_settings", pen_settings_decoder())
        use direction <- decode.field("direction", history.direction_decoder())
        decode.success(DrawingSent(history:, pen_settings:, direction:))
      }
      8 -> {
        use direction <- decode.field("direction", history.direction_decoder())
        decode.success(UndoSent(direction:))
      }
      9 -> {
        use direction <- decode.field("direction", history.direction_decoder())
        decode.success(RedoSent(direction:))
      }
      10 -> {
        use layout <- decode.field("layout", party.drawings_layout_decoder())
        decode.success(LayoutSet(layout:))
      }
      11 -> decode.success(RequestDrawing)
      12 -> {
        use history <- decode.field(
          "history",
          decode.list(history.history_item_decoder()),
        )
        use x_size <- decode.field("x_size", decode.int)
        use y_size <- decode.field("y_size", decode.int)
        decode.success(DrawingFinalized(history:, x_size:, y_size:))
      }
      _ -> decode.failure(PartyCreated(code: ""), "no type found")
    }
  }
  json.parse(from: data, using: server_decoder)
}
