import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

pub type Model {
  Model(name: String, code: Option(String))
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(Model(name: "", code: None), effect.none())
}

pub type Msg {
  JoinRoom
  UseCode
  UpdateRoomCode(String)
  ChangeName(String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UseCode -> #(Model(..model, code: Some("")), effect.none())
    UpdateRoomCode(code) -> {
      #(Model(..model, code: Some(string.uppercase(code))), effect.none())
    }
    JoinRoom -> #(model, effect.none())
    ChangeName(name) -> {
      #(Model(..model, name:), effect.none())
    }
  }
}

pub fn view(model: Model) -> Element(Msg) {
  let code_entering = case model.code {
    Some(code) ->
      html.form([attribute.class("flex"), event.on_submit(fn(_) { JoinRoom })], [
        html.input([
          attribute.class("text-3xl text-center mt-2 text-green-500"),
          attribute.placeholder("code"),
          event.on_input(UpdateRoomCode),
          attribute.value(code),
          attribute.maxlength(4),
          attribute.size("4"),
          attribute.autofocus(True),
        ]),
        html.button(
          [
            attribute.class(
              "mt-2 text-center text-3xl hover:scale-110 hover:rotate-[0.5deg] tracking-tight duration-200 ease-in-out cursor-pointer",
            ),
          ],
          [html.text("join ->")],
        ),
      ])
    None -> element.none()
  }

  html.div(
    [
      attribute.class(
        "w-screen h-screen flex flex-col items-center justify-center text-4xl",
      ),
    ],
    [
      html.input([
        attribute.value(model.name),
        event.on_input(ChangeName),
        attribute.maxlength(16),
        attribute.class("text-center text-gray-500 block mb-12 sm:mb-0"),
        attribute.placeholder("enter your name"),
      ]),
      html.div(
        [
          attribute.class(
            "w-screen flex justify-center items-center sm:gap-8 text-4xl h-20 flex-col sm:flex-row",
          ),
        ],
        [
          html.div([], [
            html.button(
              [
                event.on_click(JoinRoom),
                attribute.class(
                  "hover:scale-110 hover:rotate-[1deg] hover:tracking-wide tracking-tight duration-200 ease-in-out cursor-pointer",
                ),
              ],
              [html.text("create room")],
            ),
          ]),
          html.p([attribute.class("text-6xl")], [html.text("OR")]),
          html.div([], [
            html.button(
              [
                event.on_click(UseCode),
                attribute.class(
                  "hover:scale-110 hover:-rotate-[1.5deg] hover:tracking-wide tracking-tight duration-200 ease-in-out cursor-pointer",
                ),
              ],
              [html.text("join with code")],
            ),
            code_entering,
          ]),
        ],
      ),
    ],
  )
}
