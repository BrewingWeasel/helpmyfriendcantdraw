import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/function
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision
import gleam/result
import gleam/string
import logging
import simplifile

pub type SettingsSubject =
  Subject(Message)

pub type Settings {
  Settings(max_party_size: Int)
}

pub type Message {
  ReadSettings
  GetSettings(reply_to: Subject(Settings))
}

pub fn supervised(settings_name) {
  supervision.supervisor(fn() { start(settings_name) })
}

fn start(settings_name) {
  read_settings()
  |> actor.new()
  |> actor.on_message(handle_message)
  |> actor.named(settings_name)
  |> actor.start()
}

fn read_settings() {
  let config =
    "./config/settings"
    |> simplifile.read()
    |> result.lazy_unwrap(fn() {
      logging.log(logging.Error, "Failed to read settings file, using defaults")
      ""
    })
    |> string.split(on: "\n")
    |> list.filter_map(fn(line) {
      use #(key, value) <- result.try(string.split_once(line, on: "="))
      Ok(#(string.trim(key), string.trim(value)))
    })
    |> dict.from_list()

  let get_setting = fn(key, default, map_with) {
    config
    |> dict.get(key)
    |> result.try(fn(value) {
      case map_with(value) {
        Ok(v) -> Ok(v)
        Error(e) -> {
          logging.log(
            logging.Error,
            "Invalid value for setting " <> key <> ": " <> e,
          )
          Error(Nil)
        }
      }
    })
    |> result.lazy_unwrap(fn() {
      logging.log(
        logging.Warning,
        "Missing setting " <> key <> ", using default",
      )
      default
    })
    |> function.tap(fn(value) {
      logging.log(
        logging.Debug,
        "Setting " <> key <> ": " <> string.inspect(value),
      )
    })
  }

  logging.log(logging.Notice, "Reading settings from config file")

  Settings(
    max_party_size: get_setting("max_party_size", 8, fn(value) {
      int.parse(value) |> result.replace_error("Expected an integer")
    }),
  )
}

pub fn get_settings(settings: SettingsSubject) -> Settings {
  actor.call(settings, 1000, GetSettings)
}

pub fn update_settings(settings: SettingsSubject) -> Nil {
  actor.send(settings, ReadSettings)
}

fn handle_message(
  settings: Settings,
  message: Message,
) -> actor.Next(Settings, Message) {
  case message {
    ReadSettings -> {
      actor.continue(read_settings())
    }
    GetSettings(reply_to) -> {
      actor.send(reply_to, settings)
      actor.continue(settings)
    }
  }
}
