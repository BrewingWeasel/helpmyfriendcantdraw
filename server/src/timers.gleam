import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/order
import gleam/otp/actor
import gleam/otp/supervision
import gleam/time/duration
import gleam/time/timestamp
import logging

pub type TimersSubject =
  Subject(Message)

pub type Model {
  Model(timers: dict.Dict(String, #(timestamp.Timestamp, fn() -> Nil)))
}

pub type Message {
  AddTimer(id: String, duration: duration.Duration, call_after: fn() -> Nil)
  Tick
}

pub fn supervised(name) {
  supervision.supervisor(fn() { start(name) })
}

fn start(name) {
  process.spawn(fn() {
    // ensure timers actor has started
    process.sleep(2000)

    logging.log(logging.Debug, "initializing tick loop for timer")
    let subject = process.named_subject(name)
    tick_loop(subject)
  })

  Model(timers: dict.new())
  |> actor.new
  |> actor.on_message(handle_message)
  |> actor.named(name)
  |> actor.start()
}

pub fn add_timer(
  timers: TimersSubject,
  id: String,
  duration: duration.Duration,
  call_after: fn() -> Nil,
) -> Nil {
  actor.send(timers, AddTimer(id, duration:, call_after:))
}

fn add_timer_again_after(
  timers: TimersSubject,
  id: String,
  duration: duration.Duration,
  call_after: fn() -> Nil,
) {
  call_after()
  actor.send(
    timers,
    AddTimer(id, duration:, call_after: fn() {
      add_timer_again_after(timers, id, duration, call_after)
    }),
  )
}

pub fn add_timer_on_loop(
  timers: TimersSubject,
  id: String,
  duration: duration.Duration,
  call_after: fn() -> Nil,
) -> Nil {
  actor.send(
    timers,
    AddTimer(id, duration:, call_after: fn() {
      add_timer_again_after(timers, id, duration, call_after)
    }),
  )
}

fn handle_message(model: Model, message: Message) -> actor.Next(Model, Message) {
  case message {
    Tick -> {
      let current_time = timestamp.system_time()
      let timers =
        dict.filter(model.timers, fn(_id, pair) {
          let #(wait_until, then_call) = pair
          let is_ready = timestamp.compare(current_time, wait_until) != order.Lt
          case is_ready {
            True -> then_call()
            False -> Nil
          }

          !is_ready
        })
      actor.continue(Model(timers))
    }
    AddTimer(id, duration:, call_after:) -> {
      logging.log(logging.Debug, "adding timer with id " <> id)
      let time_to_wait_until = timestamp.add(timestamp.system_time(), duration)

      actor.continue(
        Model(
          timers: dict.insert(model.timers, id, #(
            time_to_wait_until,
            call_after,
          )),
        ),
      )
    }
  }
}

fn tick_loop(subject) {
  actor.send(subject, Tick)
  process.sleep(1000)
  tick_loop(subject)
}
