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

const chat_bottom_id = "chat-bottom"

pub fn handle_chat_message(
  chat: Chat,
  new_message: party.ChatMessage,
) -> #(Chat, effect.Effect(a)) {
  #(
    Chat(..chat, messages: [new_message, ..chat.messages]),
    effect.after_paint(fn(_dispatch, _root) { scroll_into_view(chat_bottom_id) }),
  )
}

@external(javascript, "./chat.ffi.mjs", "scroll_into_view")
fn scroll_into_view(id: String) -> Nil

pub fn view(chat: Chat, personal_id: Int) {
  let messages =
    chat.messages
    |> list.map(fn(message) {
      let message_elements = case message {
        party.User(id:, name:, message:) -> {
          let #(color, symbol) = names.get_styling_by_id(id, personal_id)
          html.span([attribute.class("flex gap-1 items-center")], [
            html.span(
              [attribute.class("font-bold flex gap-1 items-center " <> color)],
              [element.text(name), symbol, element.text(": ")],
            ),
            element.text(message),
          ])
        }
        party.Server(message:) ->
          html.span([attribute.class("text-gray-500 italic")], [
            element.text(message),
          ])
      }
      html.li([], [message_elements])
    })
  html.div(
    [attribute.class("bg-slate-100 rounded-xl p-5 w-96 h-fit")],
    [
      html.h2([attribute.class("text-3xl")], [html.text("Chat")]),
      html.ul(
        [attribute.class("list-none text-xl overflow-y-auto h-96")],
        list.reverse([
          html.span(
            [attribute.id(chat_bottom_id), attribute.class("h-[1px]")],
            [],
          ),
          ..messages
        ]),
      ),
      html.form([event.on_submit(fn(_) { SendChatMessage })], [
        html.div([attribute.class("flex bg-white gap-2 rounded-xl")], [
          html.input([
            attribute.class("w-full text-2xl"),
            attribute.placeholder("Type a message..."),
            attribute.value(chat.current_chat_message),
            event.on_input(UpdateChatMessage),
          ]),
          html.button([attribute.class("text-2xl bg-gray-200 rounded-md p-1")], [
            html.text("Send"),
          ]),
        ]),
      ]),
    ],
  )
}
