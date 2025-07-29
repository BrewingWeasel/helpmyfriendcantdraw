import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import shared/messages
import shared/party.{type Chat, Chat}
import util/names

pub type Msg {
  UpdateChatMessage(String)
  SendChatMessage
}

pub fn update(model: Chat, msg: Msg, ws) -> #(Chat, Effect(Msg)) {
  case msg {
    UpdateChatMessage(message) -> #(
      Chat(..model, current_chat_message: message),
      effect.none(),
    )
    SendChatMessage -> {
      case ws, string.trim(model.current_chat_message) {
        None, _ | _, "" -> #(model, effect.none())
        Some(ws), msg -> {
          let message = messages.SendChatMessage(msg)
          #(
            Chat(..model, current_chat_message: ""),
            ws.send(ws, message |> messages.encode_client_message()),
          )
        }
      }
    }
  }
}

pub fn handle_chat_message(
  info: party.Party,
  chat: Chat,
  id: Int,
  message: String,
) -> Chat {
  let name = case dict.get(info.players, id) {
    Ok(player) -> player.name
    Error(Nil) -> "Unknown"
  }

  let new_message = #(id, name, message)
  Chat(..chat, messages: [new_message, ..chat.messages])
}

pub fn view(chat: Chat, personal_id: Int) {
  html.div([attribute.class("bg-slate-100 rounded-xl p-5 w-96 flex-none")], [
    html.h2([], [html.text("Chat")]),
    html.ul(
      [attribute.class("list-none text-xl overflow-y-auto h-96")],
      chat.messages
        |> list.reverse()
        |> list.map(fn(item) {
          let #(id, name, message) = item
          let #(color, symbol) = names.get_styling_by_id(id, personal_id)
          html.li([], [
            html.span([attribute.class("font-bold " <> color)], [
              element.text(name),
              element.text(symbol),
              element.text(": "),
            ]),
            element.text(message),
          ])
        }),
    ),
    html.form([event.on_submit(fn(_) { SendChatMessage })], [
      html.div([attribute.class("flex gap-2")], [
        html.input([
          attribute.class("w-full text-2xl"),
          attribute.placeholder("Type a message..."),
          attribute.value(chat.current_chat_message),
          event.on_input(UpdateChatMessage),
        ]),
        html.button([attribute.class("text-2xl")], [html.text("Send")]),
      ]),
    ]),
  ])
}
