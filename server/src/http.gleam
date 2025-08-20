import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string
import gleam/string_tree
import logging.{Debug, Notice, Warning}
import mist.{type Connection, type ResponseData}
import parties
import party
import shared/messages
import wisp
import wisp/wisp_mist
import ws

pub type Init {
  Init
}

pub fn supervised(main_process, static_directory, index_html) {
  supervision.supervisor(fn() {
    let assert Ok(init_subject) as actor =
      actor.new(Nil)
      |> actor.on_message(fn(_state, msg) {
        let Init = msg
        logging.log(Debug, "Init received")
        start(static_directory, index_html)

        actor.continue(Nil)
      })
      |> actor.start()

    process.send(main_process, init_subject.data)
    logging.log(Debug, "Init subject sent")
    actor
  })
}

fn start(static_directory, index_html) {
  logging.log(Notice, "Starting http")
  let assert Ok(parties_manager) = parties.start()
  logging.log(Notice, "Parties manager started")

  let selector = process.new_selector()
  let secret_key_base = wisp.random_string(64)

  let wisp_handler = fn(req) {
    let req = wisp.method_override(req)
    use <- wisp.log_request(req)
    use <- wisp.rescue_crashes()
    use req <- wisp.handle_head(req)

    use <- wisp.serve_static(req, under: "static", from: static_directory)

    case req.method {
      http.Get -> wisp.html_response(string_tree.from_string(index_html), 200)
      _ -> wisp.not_found()
    }
  }

  let assert Ok(_) =
    fn(request: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(request) {
        ["ws"] -> {
          mist.websocket(
            request:,
            on_init: fn(_conn) {
              let server_msg_subject: process.Subject(messages.ServerMessage) =
                process.new_subject()
              let selector = selector |> process.select(server_msg_subject)
              #(
                WebsocketState(
                  subject: server_msg_subject,
                  party: None,
                  manager: parties_manager,
                  id: -1,
                  owner: False,
                  code: None,
                ),
                Some(selector),
              )
            },
            on_close: fn(state) {
              let assert Some(party) = state.party
              party.leave(party, state.id)
              case state.id {
                0 -> {
                  let assert Some(code) = state.code
                  parties.close_party(parties_manager, code)
                }
                _ -> Nil
              }
            },
            handler: handle_generic_ws_message,
          )
        }
        _ -> wisp_mist.handler(wisp_handler, secret_key_base)(request)
      }
    }
    |> mist.new
    |> mist.port(3000)
    |> mist.start()

  logging.log(Notice, "Server started")

  process.sleep_forever()
}

type WebsocketState {
  WebsocketState(
    subject: process.Subject(messages.ServerMessage),
    party: Option(party.PartyActor),
    manager: parties.PartiesManager,
    id: Int,
    owner: Bool,
    code: Option(String),
  )
}

fn handle_generic_ws_message(state, message, conn) {
  case message {
    mist.Text(text) -> {
      case messages.decode_client_message(text) {
        Ok(message) ->
          handle_client_message(state, message, conn) |> mist.continue()
        Error(_) -> mist.continue(state)
      }
    }
    mist.Binary(binary) -> {
      logging.log(
        Warning,
        "Ignoring received binary message: " <> string.inspect(binary),
      )
      mist.continue(state)
    }
    mist.Custom(server_message) -> {
      logging.log(Debug, "Sent message: " <> string.inspect(message))
      case ws.send(conn, server_message) {
        Error(e) ->
          logging.log(
            logging.Error,
            "unable to send message: " <> string.inspect(e),
          )
        Ok(_) -> Nil
      }

      case server_message {
        messages.Disconnected(_reason) -> mist.stop()
        _ -> mist.continue(state)
      }
    }
    mist.Closed | mist.Shutdown -> {
      logging.log(
        logging.Info,
        "shutting down connection [" <> string.inspect(process.self()) <> "]",
      )
      mist.stop()
    }
  }
}

fn run_party_function(
  state: WebsocketState,
  function: fn(party.PartyActor) -> a,
) -> WebsocketState {
  case state.party {
    Some(party) -> {
      function(party)
      state
    }
    None -> state
  }
}

fn handle_client_message(
  state: WebsocketState,
  message: messages.ClientMessage,
  conn: mist.WebsocketConnection,
) -> WebsocketState {
  case message {
    messages.CreateParty(name:) -> {
      logging.log(Debug, "Received message: " <> string.inspect(message))

      let #(party_code, party) =
        parties.create_party(state.manager, name, state.subject)
      logging.log(Notice, "Party created with code: " <> party_code)

      let assert Ok(_) = ws.send(conn, messages.PartyCreated(party_code))

      WebsocketState(
        ..state,
        party: Some(party),
        owner: True,
        id: 0,
        code: Some(party_code),
      )
    }
    messages.JoinParty(code:, name:) -> {
      logging.log(
        Debug,
        "[" <> code <> "]: Received message: " <> string.inspect(message),
      )

      case parties.get_party(state.manager, code) {
        Ok(party) -> {
          let id = party.join(party, name, state.subject)
          WebsocketState(..state, party: Some(party), id:, code: Some(code))
        }
        Error(Nil) -> {
          let _ =
            ws.send(
              conn,
              messages.Disconnected("No party found with code " <> code),
            )
          state
        }
      }
    }
    message -> {
      logging.log(
        logging.Debug,
        "["
          <> option.unwrap(state.code, "????")
          <> ":"
          <> int.to_string(state.id)
          <> "]: Received message: "
          <> string.inspect(message),
      )
      run_party_function(state, fn(party) {
        party.client_message(party, state.id, message)
      })
    }
  }
}
