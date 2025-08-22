import filespy
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string
import logging
import settings
import simplifile

pub type WatcherSubject =
  Subject(filespy.Change(Message))

pub type Model {
  Model(settings: Option(settings.SettingsSubject))
}

pub type Message {
  SettingsActorObtained(settings: settings.SettingsSubject)
}

pub type Init {
  Init
}

pub fn supervised(watcher_starter_name, watcher_name) {
  supervision.worker(fn() {
    actor.new(Nil)
    |> actor.named(watcher_starter_name)
    |> actor.on_message(fn(_model, _init) {
      logging.log(logging.Debug, "Starting watcher")
      process.spawn(fn() { start(watcher_name) })
      process.sleep(200)
      let assert Ok(watcher_process) = process.named(watcher_name)
      process.link(watcher_process)

      actor.continue(Nil)
    })
    |> actor.start()
  })
}

pub fn set_settings_actor(
  watcher: WatcherSubject,
  settings_actor: settings.SettingsSubject,
) {
  actor.send(watcher, filespy.Custom(SettingsActorObtained(settings_actor)))
}

fn start(watcher_name) -> Nil {
  let assert Ok(current_dir) = simplifile.current_directory()

  let assert Ok(_) =
    filespy.new()
    |> filespy.add_dir(current_dir <> "/config")
    |> filespy.set_initial_state(Model(None))
    |> filespy.set_actor_handler(fn(model, message) {
      logging.log(logging.Debug, "watcher received " <> string.inspect(message))
      case message {
        filespy.Custom(SettingsActorObtained(settings)) -> {
          logging.log(logging.Debug, "Settings actor obtained")
          actor.continue(Model(Some(settings)))
        }
        filespy.Change(path:, events: _) -> {
          case string.ends_with(path, "settings") {
            True ->
              case model.settings {
                Some(settings) -> {
                  settings.update_settings(settings)
                }
                None -> Nil
              }
            False -> Nil
          }
          actor.continue(model)
        }
      }
    })
    |> filespy.set_name(watcher_name)
    |> filespy.start()

  logging.log(logging.Info, "Watcher started")

  process.sleep_forever()
}
