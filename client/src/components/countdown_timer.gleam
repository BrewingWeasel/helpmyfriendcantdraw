import gleam/float
import gleam/int
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp
import lustre
import lustre/attribute
import lustre/component
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html

const component_name = "countdown-timer"

pub fn register() {
  let component =
    lustre.component(init, update, view, [
      component.on_attribute_change("duration", fn(value) {
        use #(duration, started_at) <- result.try(string.split_once(value, ";"))
        use parsed_duration <- result.try(int.parse(duration))
        use parsed_unix_timestamp <- result.try(int.parse(started_at))
        Ok(SetTimer(
          parsed_duration,
          parsed_unix_timestamp |> timestamp.from_unix_seconds(),
        ))
      }),
      component.adopt_styles(True),
    ])

  lustre.register(component, component_name)
}

pub fn element(duration: Int, original_time: Int) -> Element(msg) {
  element.element(
    component_name,
    [
      attribute.attribute(
        "duration",
        int.to_string(duration) <> ";" <> int.to_string(original_time),
      ),
    ],
    [],
  )
}

pub type Model {
  Model(seconds_left: Int)
}

fn init(_) -> #(Model, effect.Effect(Msg)) {
  #(Model(seconds_left: 0), effect.none())
}

pub type Msg {
  Tick
  SetTimer(duration: Int, initial_timestamp: timestamp.Timestamp)
}

fn tick() -> Effect(Msg) {
  use dispatch <- effect.from
  use <- set_timeout(1000)

  dispatch(Tick)
}

@external(javascript, "./countdown_timer.ffi.mjs", "set_timeout")
fn set_timeout(ms: Int, callback: fn() -> a) -> Nil

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg, model.seconds_left {
    Tick, 0 -> #(model, effect.none())
    Tick, remaining -> #(Model(remaining - 1), tick())
    SetTimer(seconds, original_timestamp), _ -> {
      let now = timestamp.system_time()
      let seconds_already_passed =
        timestamp.difference(original_timestamp, now)
        |> duration.to_seconds()
        |> float.ceiling()
        |> float.truncate()
      #(Model(seconds - seconds_already_passed), tick())
    }
  }
}

fn view(model: Model) -> Element(msg) {
  let minutes = int.to_string(model.seconds_left / 60)
  let seconds =
    model.seconds_left % 60
    |> int.to_string()
    |> string.pad_start(to: 2, with: "0")

  let attributes = case model.seconds_left < 10 {
    True -> [attribute.class("text-red-400")]
    False -> []
  }

  html.div(
    [
      attribute.style("font-family", "Caveat Brush"),
      attribute.class("text-2xl"),
      ..attributes
    ],
    [element.text(minutes <> ":" <> seconds)],
  )
}
