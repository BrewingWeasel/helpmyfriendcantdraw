// IMPORTS ---------------------------------------------------------------------

import gleam/dynamic/decode
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared/history.{
  type HistoryItem, Color, Down, Left, PenUp, Point, Right, Up,
}
import shared/messages
import shared/party

import lustre_websocket as ws

// MODEL -----------------------------------------------------------------------

pub type CanvasDetails {
  CanvasDetails(
    top: Bool,
    left: Bool,
    bottom: Bool,
    right: Bool,
    width: Int,
    height: Int,
    edge: Int,
  )
}

pub type OtherSidesHistory {
  OtherSidesHistory(
    top: List(HistoryItem),
    left: List(HistoryItem),
    bottom: List(HistoryItem),
    right: List(HistoryItem),
    top_history_index: Int,
    left_history_index: Int,
    bottom_history_index: Int,
    right_history_index: Int,
  )
}

pub type PersonsalEdgesHistory {
  PersonalEdgesHistory(
    top: List(Bool),
    left: List(Bool),
    bottom: List(Bool),
    right: List(Bool),
  )
}

pub type Model {
  Model(
    is_drawing: Bool,
    other_sides_history: OtherSidesHistory,
    personal_edges_history: PersonsalEdgesHistory,
    history: List(HistoryItem),
    current_color: String,
    history_pos: Int,
    ws: option.Option(ws.WebSocket),
    canvas_details: CanvasDetails,
    party: party.SharedParty,
  )
}

pub type DrawingInit {
  DrawingInit(ws: ws.WebSocket, party: party.SharedParty)
}

pub fn init(init: DrawingInit) -> #(Model, effect.Effect(Msg)) {
  let model =
    Model(
      history: [Color("black")],
      other_sides_history: OtherSidesHistory(
        top: [],
        left: [],
        bottom: [],
        right: [],
        top_history_index: 0,
        left_history_index: 0,
        bottom_history_index: 0,
        right_history_index: 0,
      ),
      personal_edges_history: PersonalEdgesHistory(
        top: [],
        left: [],
        bottom: [],
        right: [],
      ),
      is_drawing: False,
      current_color: "black",
      history_pos: 0,
      ws: Some(init.ws),
      canvas_details: CanvasDetails(
        top: False,
        left: False,
        bottom: False,
        right: False,
        width: 800,
        height: 600,
        edge: 30,
      ),
      party: init.party,
    )
  #(model, effect.after_paint(fn(dispatch, _) { dispatch(Reset) }))
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  MouseMoved(x: Int, y: Int)
  StartDrawing(x: Int, y: Int)
  SetColor(color: String)
  StopDrawing
  BackHistory
  ForwardHistory
  MouseLeave
  Reset
}

@external(javascript, "./drawing.ffi.mjs", "draw_at_other_canvas")
fn draw_at_other_canvas(
  canvas_name: String,
  color: String,
  strokes: List(#(Int, Int)),
) -> Nil

pub fn handle_drawing_sent(model: Model, history, color, direction) {
  let #(canvas_name, updated_other_sides) = case direction {
    Up -> {
      let past_history = case model.other_sides_history.top_history_index {
        0 -> model.other_sides_history.top
        index -> take_history(model.other_sides_history.top, index + 1)
      }

      #(
        "t",
        OtherSidesHistory(
          ..model.other_sides_history,
          top: list.append([PenUp, ..history], [Color(color), ..past_history]),
          top_history_index: 0,
        ),
      )
    }
    Left -> {
      let past_history = case model.other_sides_history.left_history_index {
        0 -> model.other_sides_history.left
        index -> take_history(model.other_sides_history.left, index + 1)
      }

      #(
        "l",
        OtherSidesHistory(
          ..model.other_sides_history,
          left: list.append([PenUp, ..history], [Color(color), ..past_history]),
          left_history_index: 0,
        ),
      )
    }
    Down -> {
      let past_history = case model.other_sides_history.bottom_history_index {
        0 -> model.other_sides_history.bottom
        index -> take_history(model.other_sides_history.bottom, index + 1)
      }

      #(
        "b",
        OtherSidesHistory(
          ..model.other_sides_history,
          bottom: list.append([PenUp, ..history], [Color(color), ..past_history]),
          bottom_history_index: 0,
        ),
      )
    }
    Right -> {
      let past_history = case model.other_sides_history.right_history_index {
        0 -> model.other_sides_history.right
        index -> take_history(model.other_sides_history.right, index + 1)
      }

      #(
        "r",
        OtherSidesHistory(
          ..model.other_sides_history,
          right: list.append([PenUp, ..history], [Color(color), ..past_history]),
          right_history_index: 0,
        ),
      )
    }
  }
  draw_at_other_canvas(
    canvas_name <> "-canvas",
    color,
    history
      |> list.map(fn(item) {
        case item {
          Point(x, y) -> Ok(#(x, y))
          _ -> Error(Nil)
        }
      })
      |> result.values(),
  )
  Model(..model, other_sides_history: updated_other_sides)
}

pub fn handle_history_change_sent(
  model: Model,
  direction: history.Direction,
  history_offset history_offset: Int,
) -> Model {
  let #(other_sides_history, history_to_follow, index, canvas_name) = case
    direction
  {
    Up -> {
      let index = model.other_sides_history.top_history_index + history_offset
      #(
        OtherSidesHistory(..model.other_sides_history, top_history_index: index),
        model.other_sides_history.top,
        index,
        "t-canvas",
      )
    }
    Left -> {
      let index = model.other_sides_history.left_history_index + history_offset
      #(
        OtherSidesHistory(
          ..model.other_sides_history,
          left_history_index: index,
        ),
        model.other_sides_history.left,
        index,
        "l-canvas",
      )
    }
    Down -> {
      let index =
        model.other_sides_history.bottom_history_index + history_offset
      #(
        OtherSidesHistory(
          ..model.other_sides_history,
          bottom_history_index: index,
        ),
        model.other_sides_history.bottom,
        index,
        "b-canvas",
      )
    }
    Right -> {
      let index = model.other_sides_history.right_history_index + history_offset
      #(
        OtherSidesHistory(
          ..model.other_sides_history,
          right_history_index: index,
        ),
        model.other_sides_history.right,
        index,
        "r-canvas",
      )
    }
  }

  clear_alternate_canvas(canvas_name)

  history_to_follow
  |> take_history(index + 1)
  |> list.reverse()
  |> follow_history_for_edge(canvas_name, [], "black")

  Model(..model, other_sides_history:)
}

fn follow_history_for_edge(
  history: List(HistoryItem),
  canvas_name: String,
  to_draw: List(#(Int, Int)),
  color: String,
) -> Nil {
  case history {
    [] -> Nil
    [PenUp, ..rest] -> {
      draw_at_other_canvas(canvas_name, color, to_draw)
      follow_history_for_edge(rest, canvas_name, [], color)
    }
    [Point(x, y), ..rest] ->
      follow_history_for_edge(rest, canvas_name, [#(x, y), ..to_draw], color)
    [Color(new_color), ..rest] ->
      follow_history_for_edge(rest, canvas_name, to_draw, new_color)
  }
}

pub fn update(model: Model, msg: Msg) {
  let send_history_message = fn(ws, history, direction, message, pos) {
    let dropped = list.drop(history, pos)
    case dropped {
      [True, ..] ->
        Ok(
          message(direction)
          |> messages.encode_client_message()
          |> ws.send(ws, _),
        )
      _ -> Error(Nil)
    }
  }

  case msg {
    MouseMoved(_, _) if !model.is_drawing -> #(model, effect.none())
    MouseMoved(x:, y:) -> {
      draw_point(x, y)
      #(Model(..model, history: [Point(x, y), ..model.history]), effect.none())
    }
    StartDrawing(x:, y:) -> {
      draw_point(x, y)
      let new_history = case model.history_pos {
        0 -> model.history
        _ -> take_history(model.history, model.history_pos + 1)
      }
      #(
        Model(
          ..model,
          is_drawing: True,
          history: [Point(x, y), Color(model.current_color), ..new_history],
          history_pos: 0,
        ),
        effect.none(),
      )
    }
    StopDrawing -> {
      stop_drawing(model)
    }
    MouseLeave -> {
      case model.is_drawing {
        True -> stop_drawing(model)
        False -> #(model, effect.none())
      }
    }
    Reset -> {
      echo "resetting"
      clear()
      model.history |> list.reverse() |> follow_history()
      draw_tooltips(model.canvas_details)
      #(model, effect.none())
    }
    BackHistory -> {
      clear()
      let history_pos = echo model.history_pos + 1

      model.history
      |> echo
      |> take_history(history_pos + 1)
      |> list.reverse()
      |> follow_history()

      let assert Some(ws) = model.ws

      let messages =
        [
          send_history_message(
            ws,
            model.personal_edges_history.top,
            Up,
            messages.Undo,
            model.history_pos,
          ),
          send_history_message(
            ws,
            model.personal_edges_history.left,
            Left,
            messages.Undo,
            model.history_pos,
          ),
          send_history_message(
            ws,
            model.personal_edges_history.bottom,
            Down,
            messages.Undo,
            model.history_pos,
          ),
          send_history_message(
            ws,
            model.personal_edges_history.right,
            Right,
            messages.Undo,
            model.history_pos,
          ),
        ]
        |> result.values()
        |> effect.batch()

      set_color(model.current_color)

      #(Model(..model, history_pos:), messages)
    }
    ForwardHistory -> {
      case model.history_pos {
        0 -> #(model, effect.none())
        pos -> {
          let history_pos = pos - 1
          clear()

          model.history
          |> take_history(history_pos + 1)
          |> list.reverse()
          |> follow_history()

          let assert Some(ws) = model.ws

          let messages =
            [
              send_history_message(
                ws,
                model.personal_edges_history.top,
                Up,
                messages.Redo,
                history_pos,
              ),
              send_history_message(
                ws,
                model.personal_edges_history.left,
                Left,
                messages.Redo,
                history_pos,
              ),
              send_history_message(
                ws,
                model.personal_edges_history.bottom,
                Down,
                messages.Redo,
                history_pos,
              ),
              send_history_message(
                ws,
                model.personal_edges_history.right,
                Right,
                messages.Redo,
                history_pos,
              ),
            ]
            |> result.values()
            |> effect.batch()

          set_color(model.current_color)

          #(Model(..model, history_pos:), messages)
        }
      }
    }
    SetColor(color) -> {
      set_color(color)
      #(
        Model(..model, current_color: color, history: [
          Color(color),
          ..model.history
        ]),
        effect.none(),
      )
    }
  }
}

fn take_history(history: List(HistoryItem), pos: Int) -> List(HistoryItem) {
  case history {
    [] -> []
    history if pos == 0 -> [PenUp, ..history]
    [PenUp, ..rest] -> take_history(rest, pos - 1)
    [_, ..rest] -> take_history(rest, pos)
  }
}

fn display_history(history: List(HistoryItem)) -> List(HistoryItem) {
  list.map(history, fn(item) {
    case item {
      PenUp -> "up"
      Point(_, _) -> ""
      Color(color) -> color
    }
  })
  |> echo
  history
}

fn follow_history(history: List(HistoryItem)) -> Nil {
  case history {
    [] -> Nil
    [PenUp, ..rest] -> {
      end_drawing()
      follow_history(rest)
    }
    [Point(x, y), ..rest] -> {
      draw_point(x, y)
      follow_history(rest)
    }
    [Color(color), ..rest] -> {
      set_color(color)
      follow_history(rest)
    }
  }
}

@external(javascript, "./drawing.ffi.mjs", "draw_tooltips")
pub fn draw_tooltips(canvas_details: CanvasDetails) -> Nil

@external(javascript, "./drawing.ffi.mjs", "draw_point")
fn draw_point(x: Int, y: Int) -> Nil

@external(javascript, "./drawing.ffi.mjs", "end_drawing")
fn end_drawing() -> Nil

@external(javascript, "./drawing.ffi.mjs", "clear")
fn clear() -> Nil

@external(javascript, "./drawing.ffi.mjs", "clear_alternate_canvas")
fn clear_alternate_canvas(name: String) -> Nil

@external(javascript, "./drawing.ffi.mjs", "set_color")
fn set_color(color: String) -> Nil

// @external(javascript, "./drawing.ffi.mjs", "get_buffer")
// fn get_buffer(bits: BitArray) -> String

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  let on_mousemove =
    event.on("mousemove", {
      use x <- decode.field("offsetX", decode.int)
      use y <- decode.field("offsetY", decode.int)

      decode.success(MouseMoved(x, y))
    })

  let on_mousedown =
    event.on("mousedown", {
      use x <- decode.field("offsetX", decode.int)
      use y <- decode.field("offsetY", decode.int)

      decode.success(StartDrawing(x, y))
    })

  // border-t-2 border-l-2 border-b-2 border-r-2
  let middle_class = "border-gray-300"

  let #(top, middle_class) =
    view_vertical_canvas_edge(
      model.canvas_details.top,
      "t",
      middle_class,
      model,
    )

  let #(bottom, middle_class) =
    view_vertical_canvas_edge(
      model.canvas_details.bottom,
      "b",
      middle_class,
      model,
    )

  let get_side = fn(side, side_exists, main_class) {
    let side_border = "border-" <> side <> "-2"
    case side_exists {
      True -> {
        #(
          option.Some(
            html.canvas([
              attribute.class(middle_class <> " bg-slate-100 " <> side_border),
              attribute.id(side <> "-canvas"),
              attribute.width(model.canvas_details.edge),
              attribute.height(model.canvas_details.height),
            ]),
          ),
          main_class,
        )
      }
      False -> #(None, main_class <> " " <> side_border)
    }
  }

  let #(left, main_class) =
    get_side("l", model.canvas_details.left, middle_class)
  let #(right, main_class) =
    get_side("r", model.canvas_details.right, main_class)

  let main_canvas =
    html.div([attribute.class("relative")], [
      html.canvas([
        attribute.class(main_class <> " z-0"),
        attribute.id("drawing-canvas"),
        attribute.width(model.canvas_details.width),
        attribute.height(model.canvas_details.height),
        on_mousedown,
        event.on_mouse_up(StopDrawing),
        on_mousemove,
        event.on_mouse_leave(MouseLeave),
      ]),
      html.canvas([
        attribute.class("absolute top-0 left-0 z-10 pointer-events-none"),
        attribute.id("tooltip-canvas"),
        attribute.width(model.canvas_details.width),
        attribute.height(model.canvas_details.height),
      ]),
    ])

  let center =
    html.div([attribute.class("flex")], case left, right {
      Some(left_canvas), Some(right_canvas) -> [
        left_canvas,
        main_canvas,
        right_canvas,
      ]
      Some(left_canvas), None -> [left_canvas, main_canvas]
      None, Some(right_canvas) -> [main_canvas, right_canvas]
      None, None -> [main_canvas]
    })

  let canvas =
    html.div([], case top, bottom {
      Some(top_canvas), Some(bottom_canvas) -> [
        top_canvas,
        center,
        bottom_canvas,
      ]
      Some(top_canvas), None -> [top_canvas, center]
      None, Some(bottom_canvas) -> [center, bottom_canvas]
      None, None -> [center]
    })

  html.div(
    [
      attribute.class(
        "w-screen h-screen flex justify-center items-center flex-col",
      ),
      on_mousemove,
    ],
    [
      html.script(
        [],
        "
const canvas =
  document.getElementById('drawing-canvas');
const ctx =
  canvas.getContext('2d');

    ",
      ),
      view_drawing_ui(),
      canvas,
    ],
  )
}

fn view_vertical_canvas_edge(exists, edge, main_class, model: Model) {
  let vertical_edge_border = "border-" <> edge <> "-2"

  case exists {
    True -> {
      let get_corner = fn(side, side_exists, borders) {
        let side_border = "border-" <> side <> "-2"
        case side_exists {
          True -> #(
            option.Some(
              html.canvas([
                attribute.class(
                  vertical_edge_border
                  <> " border-gray-300 bg-slate-200 "
                  <> side_border,
                ),
                attribute.id(edge <> "-" <> side <> "-canvas"),
                attribute.width(model.canvas_details.edge),
                attribute.height(model.canvas_details.edge),
              ]),
            ),
            borders,
          )
          False -> #(None, borders <> " " <> side_border)
        }
      }

      let borders = vertical_edge_border <> " border-gray-300 bg-slate-100"
      let #(left, borders) = get_corner("l", model.canvas_details.left, borders)
      let #(right, borders) =
        get_corner("r", model.canvas_details.right, borders)
      let main_section =
        html.canvas([
          attribute.class(borders),
          attribute.id(edge <> "-canvas"),
          attribute.width(model.canvas_details.width),
          attribute.height(model.canvas_details.edge),
        ])

      let canvases =
        html.div([attribute.class("flex")], case left, right {
          Some(left_side), Some(right_side) -> [
            left_side,
            main_section,
            right_side,
          ]
          Some(left_side), None -> [left_side, main_section]
          None, Some(right_side) -> [main_section, right_side]
          None, None -> [main_section]
        })
      #(Some(canvases), main_class)
    }
    False -> #(None, main_class <> " " <> vertical_edge_border)
  }
}

fn view_drawing_ui() -> Element(Msg) {
  let colors = [
    "#000000", "#ffffff", "#006400", "#bdb76b", "#00008b", "#48d1cc", "#ff0000",
    "#ffa500", "#ffff00", "#00ff00", "#00fa9a", "#0000ff", "#ff00ff", "#6495ed",
    "#ff1493", "#ffb6c1",
  ]

  let color_buttons =
    colors
    |> list.map(fn(color) {
      html.button(
        [
          attribute.class("w-6 h-6 rounded-full border border-slate-600"),
          attribute.style("background-color", color),
          event.on_click(SetColor(color)),
        ],
        [],
      )
    })
  html.div([attribute.class("flex p-2")], [
    html.div(
      [attribute.class("flex gap-1 p-2 rounded-lg shadow-sm bg-slate-100")],
      color_buttons,
    ),
    html.button([event.on_click(BackHistory)], [element.text("back")]),
    html.button([event.on_click(ForwardHistory)], [element.text("forward")]),
    html.button([event.on_click(Reset)], [element.text("reset")]),
  ])
}

fn stop_drawing(model: Model) {
  end_drawing()

  let recent_drawn =
    list.take_while(model.history, fn(item) {
      case item {
        PenUp -> False
        _ -> True
      }
    })

  let #(top, left, bottom, right) =
    recent_drawn
    |> list.fold(#([], [], [], []), fn(acc, item) {
      case item {
        Point(x, y) -> {
          let #(top, left, bottom, right) = acc
          let top = case y {
            y if y < model.canvas_details.edge -> [item, ..top]
            _ -> top
          }
          let left = case x {
            x if x < model.canvas_details.edge -> [item, ..left]
            _ -> left
          }
          let bottom_border =
            model.canvas_details.height - model.canvas_details.edge
          let bottom = case y {
            y if y > bottom_border -> [Point(x, y - bottom_border), ..bottom]
            _ -> bottom
          }
          let right_border =
            model.canvas_details.width - model.canvas_details.edge
          let right = case x {
            x if x > right_border -> [Point(x - right_border, y), ..right]
            _ -> right
          }
          #(top, left, bottom, right)
        }
        _ -> acc
      }
    })

  let assert Some(ws) = model.ws

  let to_message = fn(history, direction) {
    case history {
      [] -> option.None
      _ ->
        messages.SendDrawing(history, model.current_color, direction)
        |> messages.encode_client_message()
        |> ws.send(ws, _)
        |> option.Some
    }
  }

  let messages =
    option.values([
      to_message(top, Up),
      to_message(left, Left),
      to_message(bottom, Down),
      to_message(right, Right),
    ])

  let personal_edges_history =
    PersonalEdgesHistory(
      top: [top != [], ..model.personal_edges_history.top],
      left: [left != [], ..model.personal_edges_history.left],
      bottom: [bottom != [], ..model.personal_edges_history.bottom],
      right: [right != [], ..model.personal_edges_history.right],
    )

  #(
    Model(
      ..model,
      is_drawing: False,
      personal_edges_history:,
      history: [PenUp, ..model.history] |> display_history(),
    ),
    effect.batch(messages),
  )
}
