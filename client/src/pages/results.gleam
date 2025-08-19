import components/chat
import gleam/list
import gleam/option.{type Option}
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import pages/drawing
import shared/history
import shared/messages
import shared/party

pub type Model {
  Model(
    history: List(history.HistoryItem),
    x_size: Int,
    y_size: Int,
    ws: Option(ws.WebSocket),
    party: party.SharedParty,
  )
}

pub fn init(
  history: List(history.HistoryItem),
  x_size: Int,
  y_size: Int,
  ws: Option(ws.WebSocket),
  party: party.SharedParty,
) -> Model {
  Model(history, x_size, y_size, ws, party)
}

pub type Msg {
  ShowDrawing
  ReturnToParty
  ChatMessage(chat.Msg)
}

const canvas_id = "final-drawing-canvas"

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ShowDrawing -> {
      model.history
      |> list.reverse()
      |> drawing.follow_history_for_other_canvas(
        canvas_id,
        [],
        messages.PenSettings(drawing.default_color, drawing.default_size),
      )
      #(model, effect.none())
    }
    ChatMessage(chat_msg) -> {
      let #(new_chat, chat_effect) =
        chat.update(model.party.chat, chat_msg, model.ws)
      #(
        Model(..model, party: party.SharedParty(..model.party, chat: new_chat)),
        chat_effect |> effect.map(ChatMessage),
      )
    }
    ReturnToParty -> panic as "should be handled by the router"
  }
}

pub fn view(model: Model) {
  html.div([attribute.class("max-h-screen")], [
    html.div(
      [attribute.class("flex flex-wrap gap-4 justify-center p-2 max-w-screen")],
      [
        html.div([attribute.class("p-2 bg-gray-100 rounded-lg")], [
          html.canvas([
            attribute.class(
              "bg-white border-gray-300 border-2 w-auto h-auto max-w-[80vw] max-h-[80vh]",
            ),
            attribute.id(canvas_id),
            attribute.width(model.x_size),
            attribute.height(model.y_size),
          ]),
        ]),
        chat.view(model.party.chat, model.party.id)
          |> element.map(ChatMessage),
        html.button(
          [
            attribute.class("bg-rose-200 rounded-lg p-1 mt-2 max-h-12"),
            event.on_click(ReturnToParty),
          ],
          [html.text("Return to Party")],
        ),
      ],
    ),
  ])
}
