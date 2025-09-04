import gleam/dynamic/decode
import gleam/json
import gleam/list

pub type Msg {
  NewItem(String)
  RemoveItem(String)
}

pub fn encode_msg(msg: Msg) -> json.Json {
  case msg {
    NewItem(item) ->
      json.object([#("t", json.int(0)), #("item", json.string(item))])
    RemoveItem(item) ->
      json.object([#("t", json.int(2)), #("item", json.string(item))])
  }
}

pub fn decode_msg() -> decode.Decoder(Msg) {
  use tag <- decode.field("t", decode.int)
  case tag {
    0 -> {
      use item <- decode.field("item", decode.string)
      decode.success(NewItem(item))
    }
    2 -> {
      use item <- decode.field("item", decode.string)
      decode.success(RemoveItem(item))
    }
    _ -> decode.failure(NewItem(""), "Unknown tag")
  }
}

// TODO: optimize while maintaining order
pub fn apply_batch_changes(
  items: List(String),
  changes: List(Msg),
) -> List(String) {
  changes
  |> list.reverse()
  |> list.fold(items, fn(acc, change) {
    case change {
      NewItem(item) -> [item, ..acc]
      RemoveItem(item) -> list.filter(acc, fn(i) { i != item })
    }
  })
}
