import filespy
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/string
import logging
import parties
import settings
import simplifile

pub type WatcherSubject =
  Subject(filespy.Change(Message))

pub type Model {
  Model(
    settings: Option(settings.SettingsSubject),
    party_manager: Option(process.Subject(parties.Message)),
  )
}

pub type Message {
  SettingsActorObtained(settings: settings.SettingsSubject)
  PartiesManagerActorObtained(settings: process.Subject(parties.Message))
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

pub fn set_parties_manager_actor(
  watcher: WatcherSubject,
  parties_manager: process.Subject(parties.Message),
) {
  actor.send(
    watcher,
    filespy.Custom(PartiesManagerActorObtained(parties_manager)),
  )
}

fn start(watcher_name) -> Nil {
  let assert Ok(current_dir) = simplifile.current_directory()

  let assert Ok(_) =
    filespy.new()
    |> filespy.add_dir(current_dir <> "/config")
    |> filespy.add_dir(current_dir <> "/actions")
    |> filespy.set_initial_state(Model(None, None))
    |> filespy.set_actor_handler(fn(model, message) {
      logging.log(logging.Debug, "watcher received " <> string.inspect(message))
      case message {
        filespy.Custom(SettingsActorObtained(settings)) -> {
          logging.log(logging.Debug, "Settings actor obtained")
          actor.continue(Model(..model, settings: Some(settings)))
        }
        filespy.Custom(PartiesManagerActorObtained(parties_manager)) -> {
          logging.log(logging.Debug, "Settings actor obtained")
          actor.continue(Model(..model, party_manager: Some(parties_manager)))
        }
        filespy.Change(path:, events:) -> {
          let path_segments = string.split(path, "/") |> list.reverse()
          case path_segments {
            ["settings", "config", ..] ->
              case model.settings {
                Some(settings) -> {
                  settings.update_settings(settings)
                }
                None -> Nil
              }
            [code, "actions", ..] -> {
              case list.contains(events, filespy.Created), model.party_manager {
                True, Some(party_manager) -> {
                  parties.control_action(party_manager, code)
                }
                _, _ -> Nil
              }
            }
            _ -> Nil
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
