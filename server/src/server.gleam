import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import http
import logging.{Notice}
import simplifile
import wisp

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(index_html) = simplifile.read(static_directory <> "/index.html")

  let main_process_subject = process.new_subject()
  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(http.supervised(
      main_process_subject,
      static_directory,
      index_html,
    ))
    |> supervisor.start()

  let init = fn(init_subject) {
    logging.log(logging.Debug, "Received init subject from http process")
    process.send(init_subject, http.Init)
    logging.log(logging.Debug, "Sent init to http process")
  }

  case process.receive(main_process_subject, 2000) {
    Ok(init_subject) -> init(init_subject)
    Error(_) ->
      logging.log(
        logging.Critical,
        "Failed to receive init subject from http process",
      )
  }

  logging.log(Notice, "Started server supervisor")

  loop_handle_start(main_process_subject, init)
}

fn loop_handle_start(main_process_subject, init) {
  let init_subject = process.receive_forever(main_process_subject)
  logging.log(logging.Alert, "Restarting server due to crash")
  init(init_subject)

  loop_handle_start(main_process_subject, init)
}
