import gleam/erlang/process
import gleam/otp/static_supervisor as supervisor
import http
import logging.{Notice}
import settings
import simplifile
import watcher
import wisp

pub fn main() {
  logging.configure()

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(index_html) = simplifile.read(static_directory <> "/index.html")

  let initializer_subject = process.new_subject()

  let settings_name = process.new_name("settings")
  let parties_manager_name = process.new_name("parties_manager")

  let watcher_starter_name = process.new_name("watcher_starter")
  let watcher_name = process.new_name("watcher")

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(settings.supervised(settings_name))
    |> supervisor.add(watcher.supervised(watcher_starter_name, watcher_name))
    |> supervisor.add(http.supervised(
      initializer_subject,
      static_directory,
      index_html,
    ))
    |> supervisor.start()

  let watcher_starter_actor = process.named_subject(watcher_starter_name)

  logging.log(logging.Debug, "Sending watcher init to watcher starter actor")

  // wait for watcher starter to be ready
  process.sleep(100)
  process.send(watcher_starter_actor, watcher.Init)

  let settings_actor = process.named_subject(settings_name)

  let watcher_actor = process.named_subject(watcher_name)

  // wait for watcher to start
  process.sleep(300)
  logging.log(logging.Debug, "Sending settings actor to watcher")
  watcher.set_settings_actor(watcher_actor, settings_actor)

  let init = fn(init_subject) {
    logging.log(logging.Debug, "Received init subject from http process")
    process.send(
      init_subject,
      http.Init(settings: settings_actor, parties_manager_name:),
    )
    logging.log(logging.Debug, "Sent init to http process")
    // wait for parties manager to start
    process.sleep(1000)
    watcher.set_parties_manager_actor(
      watcher_actor,
      process.named_subject(parties_manager_name),
    )
  }

  case process.receive(initializer_subject, 2000) {
    Ok(init_subject) -> init(init_subject)
    Error(_) ->
      logging.log(
        logging.Critical,
        "Failed to receive init subject from http process",
      )
  }

  logging.log(Notice, "Started server supervisor")

  loop_handle_start(initializer_subject, init)
}

fn loop_handle_start(main_process_subject, init) {
  let init_subject = process.receive_forever(main_process_subject)
  logging.log(logging.Alert, "Restarting server due to crash")
  init(init_subject)

  loop_handle_start(main_process_subject, init)
}
