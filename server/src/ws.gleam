import gleam/erlang/process
import mist
import shared/messages

pub fn send(connection, server_message) {
  server_message
  |> messages.encode_server_message()
  |> mist.send_text_frame(connection, _)
}

pub type Connection =
  process.Subject(messages.ServerMessage)
