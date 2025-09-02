import gleam/bool
import gleam/dict
import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import shared/messages
import shared/party.{type Chat, type SharedParty, Chat, SharedParty}
import util/names

pub type Msg {
  UpdateChatMessage(String)
  SendChatMessage
  TryComplete
}

pub fn update(model: SharedParty, msg: Msg, ws) -> #(SharedParty, Effect(Msg)) {
  case msg {
    UpdateChatMessage(message) -> #(
      SharedParty(
        ..model,
        chat: Chat(
          ..model.chat,
          current_chat_message: message,
          just_pressed_tab: False,
        ),
      ),
      effect.none(),
    )
    TryComplete -> {
      let model =
        SharedParty(..model, chat: Chat(..model.chat, just_pressed_tab: True))
      let assert [to_complete, ..rest] =
        model.chat.current_chat_message |> string.split(" ") |> list.reverse()

      use <- bool.lazy_guard(to_complete == "", fn() { #(model, effect.none()) })

      let complete_with = case to_complete {
        "/" <> _command -> [
          "/code", "/clear", "/help", "/kick", "/lock", "/unlock", "/mute",
          "/unmute",
        ]
        _name -> model.info.players |> dict.values |> list.map(fn(p) { p.name })
      }

      let completion = complete(to_complete, complete_with)

      case completion {
        Ok(completed) -> {
          let new_message =
            [completed, ..rest] |> list.reverse() |> string.join(" ")

          #(
            SharedParty(
              ..model,
              chat: Chat(..model.chat, current_chat_message: new_message),
            ),
            effect.none(),
          )
        }
        Error(_) -> #(model, effect.none())
      }
    }
    SendChatMessage -> {
      case ws, string.trim(model.chat.current_chat_message) {
        None, _ | _, "" -> #(model, effect.none())
        Some(ws), msg -> {
          handle_message(model, ws, msg)
        }
      }
    }
  }
}

const chat_bottom_id = "chat-bottom"

pub fn scroll_down() {
  effect.after_paint(fn(_dispatch, _root) { scroll_into_view(chat_bottom_id) })
}

pub fn handle_chat_message(
  chat: Chat,
  new_message: party.ChatMessage,
) -> #(Chat, effect.Effect(a)) {
  #(Chat(..chat, messages: [new_message, ..chat.messages]), scroll_down())
}

fn handle_message(model, ws, message) {
  let model =
    SharedParty(..model, chat: Chat(..model.chat, current_chat_message: ""))

  let default_send = fn() {
    let message = messages.SendChatMessage(message)
    #(model, ws.send(ws, message |> messages.encode_client_message()))
  }

  let update_chat = fn(chat_updater) {
    #(SharedParty(..model, chat: chat_updater(model.chat)), scroll_down())
  }

  case message {
    "/" <> command -> {
      let #(command, _args) =
        command |> string.split_once(" ") |> result.unwrap(#(command, ""))

      case echo command {
        "help" -> {
          use chat <- update_chat()

          let extra_commands = case model.id {
            0 ->
              ", /kick <user>, /lock, /unlock, /mute (<user>), /unmute (<user>)"
            _ -> ""
          }

          Chat(..chat, messages: [
            party.Server(
              "Available commands: /code, /clear, /help" <> extra_commands,
            ),
            ..chat.messages
          ])
        }
        "code" -> {
          use chat <- update_chat()
          Chat(..chat, messages: [
            party.Server("The room code is " <> model.code <> "."),
            ..chat.messages
          ])
        }
        "clear" -> {
          use chat <- update_chat()
          Chat(..chat, messages: [])
        }
        "kick" | "lock" | "unlock" | "mute" | "unmute" -> default_send()
        _ -> {
          use chat <- update_chat
          Chat(..chat, messages: [
            party.Server(
              "Unknown command: "
              <> command
              <> ". Type /help for a list of commands.",
            ),
            ..chat.messages
          ])
        }
      }
    }
    _ -> default_send()
  }
}

fn complete(current: String, options: List(String)) {
  let processed_current = string.lowercase(current)
  let available_completions =
    options
    |> list.filter(fn(option) {
      string.starts_with(string.lowercase(option), processed_current)
    })

  case available_completions {
    [single] -> Ok(single)
    _ -> Error(Nil)
  }
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
          html.span([], [
            html.span(
              [attribute.class("font-bold flex-inline gap-1 items-center " <> color)],
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
  html.div([attribute.class("bg-slate-100 rounded-xl p-5 w-96 h-fit")], [
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
          event.advanced("keydown", {
            use key <- decode.field("key", decode.string)

            let pass_through = fn() {
              decode.failure(
                event.handler(TryComplete, False, False),
                "ignore key",
              )
            }

            case key, chat.just_pressed_tab {
              "Tab", False ->
                decode.success(event.handler(TryComplete, True, True))
              _, _ -> pass_through()
            }
          }),
        ]),
        html.button([attribute.class("text-2xl bg-gray-200 rounded-md p-1")], [
          html.text("Send"),
        ]),
      ]),
    ]),
  ])
}
