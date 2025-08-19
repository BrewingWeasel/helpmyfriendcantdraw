import gleam/dynamic/decode
import gleam/json

pub const canvas_width = 800

pub const canvas_height = 600

pub type Direction {
  Up
  Down
  Left
  Right
}

pub type HistoryItem {
  Point(x: Int, y: Int)
  Color(color: String)
  Size(size: Int)
  PenUp
}

pub fn history_item_to_json(history_item: HistoryItem) -> json.Json {
  case history_item {
    Point(x:, y:) ->
      json.object([
        #("t", json.int(0)),
        #("x", json.int(x)),
        #("y", json.int(y)),
      ])
    Color(color:) ->
      json.object([#("t", json.int(1)), #("color", json.string(color))])
    Size(size:) -> json.object([#("t", json.int(2)), #("size", json.int(size))])
    PenUp -> json.object([#("t", json.int(3))])
  }
}

pub fn history_item_decoder() -> decode.Decoder(HistoryItem) {
  use type_ <- decode.field("t", decode.int)
  case type_ {
    0 -> {
      use x <- decode.field("x", decode.int)
      use y <- decode.field("y", decode.int)
      decode.success(Point(x:, y:))
    }
    1 -> {
      use color <- decode.field("color", decode.string)
      decode.success(Color(color:))
    }
    2 -> {
      use size <- decode.field("size", decode.int)
      decode.success(Size(size:))
    }
    3 -> decode.success(PenUp)
    _ -> decode.failure(PenUp, "Direction")
  }
}

pub fn direction_decoder() -> decode.Decoder(Direction) {
  use variant <- decode.then(decode.int)
  case variant {
    0 -> decode.success(Up)
    1 -> decode.success(Down)
    2 -> decode.success(Left)
    3 -> decode.success(Right)
    _ -> decode.failure(Up, "Direction")
  }
}

pub fn direction_to_json(direction: Direction) -> json.Json {
  case direction {
    Up -> json.int(0)
    Down -> json.int(1)
    Left -> json.int(2)
    Right -> json.int(3)
  }
}
