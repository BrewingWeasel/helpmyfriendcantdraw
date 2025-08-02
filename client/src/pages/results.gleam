import gleam/list
import gleam/option.{type Option}
import lustre/attribute
import lustre/effect
import lustre/element/html
import lustre_websocket as ws
import pages/drawing
import shared/history

pub type Model {
  Model(
    history: List(history.HistoryItem),
    x_size: Int,
    y_size: Int,
    ws: Option(ws.WebSocket),
  )
}

pub fn init(history, x_size, y_size, ws) -> Model {
  Model(history, x_size, y_size, ws)
}

pub type Msg {
  ShowDrawing
}

const canvas_id = "final-drawing-canvas"

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ShowDrawing -> {
      model.history
      |> list.reverse()
      |> drawing.follow_history_for_other_canvas(canvas_id, [], "black")
      #(model, effect.none())
    }
  }
}

pub fn view(model: Model) {
  html.div([], [
    html.div([], [
      html.canvas([
        attribute.id(canvas_id),
        attribute.width(model.x_size),
        attribute.height(model.y_size),
      ]),
    ]),
  ])
}
