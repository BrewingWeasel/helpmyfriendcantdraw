import gleam/list
import gleam/string
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element
import lustre/element/html
import lustre/event
import shared/list_changing

pub type Model {
  Model(
    items: List(String),
    changes: List(list_changing.Msg),
    new_item_text: String,
  )
}

pub fn init(items: List(String)) -> #(Model, Effect(Msg)) {
  #(Model(items:, changes: [], new_item_text: ""), effect.none())
}

pub type Msg {
  ListChanging(list_changing.Msg)
  Empty
  Close
  Input(String)
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    ListChanging(list_changing.NewItem(item) as change) -> {
      let new_items = [item, ..model.items]
      #(
        Model(new_item_text: "", items: new_items, changes: [
          change,
          ..model.changes
        ]),
        effect.none(),
      )
    }
    ListChanging(list_changing.RemoveItem(item) as change) -> {
      let new_items = model.items |> list.filter(fn(i) { i != item })
      #(
        Model(..model, items: new_items, changes: [change, ..model.changes]),
        effect.none(),
      )
    }
    Input(text) -> #(Model(..model, new_item_text: text), effect.none())
    Empty -> #(model, effect.none())
    // should be handled higher up
    Close -> #(model, effect.none())
  }
}

pub fn view(model: Model) {
  let items =
    model.items
    |> list.map(fn(item) {
      html.tr([], [
        html.th([attribute.class("text-left")], [element.text(item)]),
        html.th(
          [
            attribute.class(
              "text-red-500 text-3xl px-12 cursor-pointer hover:scale-125 duration-200 ease-in-out select-none",
            ),
            event.on_click(ListChanging(list_changing.RemoveItem(item))),
          ],
          [element.text("x")],
        ),
      ])
    })

  html.div(
    [
      attribute.class(
        "z-50 fixed left-0 top-0 w-screen h-screen bg-[rgba(0,0,0,0.4)] flex",
      ),
      event.on_click(Close),
    ],
    [
      html.div(
        [
          attribute.class("bg-slate-200 rounded-xl p-5 w-128 mx-auto my-auto"),
          event.stop_propagation(event.on_click(Empty)),
        ],
        [
          html.div([attribute.class("flex max-h-[55vh] overflow-auto")], [
            html.div([attribute.class("mx-auto")], [html.table([], items)]),
          ]),
          html.form(
            [
              event.on_submit(fn(_) {
                ListChanging(list_changing.NewItem(model.new_item_text))
              }),
              attribute.class("flex justify-center"),
            ],
            [
              html.input([
                attribute.class("bg-white rounded-lg p-1 mt-4 text-2xl"),
                attribute.placeholder("new prompt"),
                attribute.value(model.new_item_text),
                event.on_input(Input),
              ]),
              html.button(
                [
                  attribute.class(
                    "bg-rose-200 text-2xl py-1 px-2 rounded-lg ml-4 mt-4 cursor-pointer disabled:cursor-not-allowed",
                  ),
                  attribute.disabled(model.new_item_text == ""),
                ],
                [element.text("add")],
              ),
            ],
          ),
          html.div([attribute.class("flex justify-end")], [
            html.button(
              [
                attribute.class(
                  "text-3xl bg-slate-300 px-2 rounded-lg cursor-pointer select-none",
                ),
                event.on_click(Close),
              ],
              [element.text("ok")],
            ),
          ]),
        ],
      ),
    ],
  )
}
