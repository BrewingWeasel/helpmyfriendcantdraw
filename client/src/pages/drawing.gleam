// IMPORTS ---------------------------------------------------------------------

import components/chat
import components/countdown_timer
import components/icons
import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/array
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared/history.{
  type HistoryItem, Color, Down, Left, PenUp, Point, Right, Size, Up,
}
import shared/messages.{type PenSettings, PenSettings}
import shared/party

import lustre_websocket as ws

const pen_size_1 = 6

const pen_size_2 = 12

const pen_size_3 = 36

const pen_size_4 = 128

const pen_sizes = [pen_size_1, pen_size_2, pen_size_3, pen_size_4]

pub const default_size = pen_size_2

pub const default_color = "#000000"

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
    pen_settings: PenSettings,
    history_pos: Int,
    max_history_pos: Int,
    ws: option.Option(ws.WebSocket),
    canvas_details: CanvasDetails,
    party: party.SharedParty,
    is_ready: Bool,
    cursor_details: CursorDetails,
    server_start_timestamp: Int,
    colors: array.Array(String),
  )
}

pub type DrawingInit {
  DrawingInit(
    ws: ws.WebSocket,
    party: party.SharedParty,
    server_start_timestamp: Int,
  )
}

pub fn init(init: DrawingInit) -> #(Model, effect.Effect(Msg)) {
  let model =
    Model(
      history: [Color(default_color), Size(default_size)],
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
      pen_settings: PenSettings(color: default_color, size: default_size),
      history_pos: 0,
      max_history_pos: 0,
      ws: Some(init.ws),
      canvas_details: CanvasDetails(
        top: False,
        left: False,
        bottom: False,
        right: False,
        width: history.canvas_width,
        height: history.canvas_height,
        edge: init.party.info.overlap,
      ),
      party: init.party,
      is_ready: False,
      cursor_details: setup_cursor_details(),
      server_start_timestamp: init.server_start_timestamp,
      colors: array.from_list([
        "#000000", "#ffffff", "#006400", "#bdb76b", "#00008b", "#48d1cc",
        "#ff0000", "#ffa500", "#ffff00", "#00ff00", "#00fa9a", "#0000ff",
        "#ff00ff", "#6495ed", "#ff1493", "#ffb6c1",
      ]),
    )
  #(
    model,
    effect.batch([
      effect.after_paint(fn(dispatch, _) { dispatch(Reset) }),
      effect.from(fn(dispatch) { add_key_listener(keybinds_handler(dispatch)) }),
    ]),
  )
}

@external(javascript, "./drawing.ffi.mjs", "add_key_listener")
fn add_key_listener(callback: fn(String, Bool, Bool) -> Nil) -> Nil

fn keybinds_handler(dispatch) {
  fn(key, shift_key, meta_key) {
    case key {
      "u" -> dispatch(BackHistory)
      "z" if meta_key && !shift_key -> dispatch(BackHistory)
      "r" -> dispatch(ForwardHistory)
      "z" if meta_key && shift_key -> dispatch(ForwardHistory)
      "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> {
        let assert Ok(index) = int.parse(key)
        dispatch(SetColorIndex(index - 1))
      }
      "[" -> dispatch(SizeLower)
      "{" -> dispatch(SetSize(pen_size_1))
      "]" -> dispatch(SizeIncrease)
      "}" -> dispatch(SetSize(pen_size_4))
      _ -> Nil
    }
  }
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  MouseMoved(x: Int, y: Int)
  StartDrawing(x: Int, y: Int)
  SetColor(color: String)
  SetColorIndex(index: Int)
  SetSize(size: Int)
  StopDrawing
  BackHistory
  ForwardHistory
  MouseLeave
  Reset
  ChatMessage(chat.Msg)
  EndDrawing
  ToggleReady
  MouseEnter(mouse_down: Bool, x: Int, y: Int)
  EmptyMsg
  SizeLower
  SizeIncrease
}

@external(javascript, "./drawing.ffi.mjs", "draw_at_other_canvas")
fn draw_at_other_canvas(
  canvas_name: String,
  pen_settings: PenSettings,
  strokes: List(#(Int, Int)),
) -> Nil

pub fn handle_drawing_sent(
  model: Model,
  history: List(HistoryItem),
  pen_settings: PenSettings,
  direction: history.Direction,
) -> Model {
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
          top: list.append([PenUp, ..history], [
            Color(pen_settings.color),
            Size(pen_settings.size),
            ..past_history
          ]),
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
          left: list.append([PenUp, ..history], [
            Color(pen_settings.color),
            Size(pen_settings.size),
            ..past_history
          ]),
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
          bottom: list.append([PenUp, ..history], [
            Color(pen_settings.color),
            Size(pen_settings.size),
            ..past_history
          ]),
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
          right: list.append([PenUp, ..history], [
            Color(pen_settings.color),
            Size(pen_settings.size),
            ..past_history
          ]),
          right_history_index: 0,
        ),
      )
    }
  }
  draw_at_other_canvas(
    canvas_name <> "-canvas",
    pen_settings,
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
  |> follow_history_for_other_canvas(
    canvas_name,
    [],
    PenSettings(color: default_color, size: default_size),
  )

  Model(..model, other_sides_history:)
}

pub fn follow_history_for_other_canvas(
  history: List(HistoryItem),
  canvas_name: String,
  to_draw: List(#(Int, Int)),
  pen_settings: PenSettings,
) -> Nil {
  case history {
    [] -> Nil
    [PenUp, ..rest] -> {
      draw_at_other_canvas(canvas_name, pen_settings, to_draw)
      follow_history_for_other_canvas(rest, canvas_name, [], pen_settings)
    }
    [Point(x, y), ..rest] ->
      follow_history_for_other_canvas(
        rest,
        canvas_name,
        [#(x, y), ..to_draw],
        pen_settings,
      )
    [Color(color), ..rest] ->
      follow_history_for_other_canvas(
        rest,
        canvas_name,
        to_draw,
        PenSettings(..pen_settings, color:),
      )
    [Size(size), ..rest] -> {
      follow_history_for_other_canvas(
        rest,
        canvas_name,
        to_draw,
        PenSettings(..pen_settings, size:),
      )
    }
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
      start_drawing(model, x:, y:)
    }
    StopDrawing | MouseLeave -> {
      stop_drawing(model)
    }
    MouseEnter(mouse_down:, x:, y:) -> {
      case model.is_drawing, mouse_down {
        True, False -> stop_drawing(model)
        False, True -> start_drawing(model, x:, y:)
        _, _ -> #(model, effect.none())
      }
    }
    Reset -> {
      clear()
      model.history |> list.reverse() |> follow_history()
      canvas_set_color(model.pen_settings.color)
      canvas_set_size(model.pen_settings.size)
      set_cursor(
        model.cursor_details,
        model.pen_settings.size,
        model.pen_settings.color,
      )
      setup_canvas(model.canvas_details)
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

      canvas_set_color(model.pen_settings.color)
      canvas_set_size(model.pen_settings.size)

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

          canvas_set_color(model.pen_settings.color)
          canvas_set_size(model.pen_settings.size)

          #(Model(..model, history_pos:), messages)
        }
      }
    }
    SetColor(color) -> {
      update_color(model, color)
    }
    SetColorIndex(index) -> {
      let color =
        model.colors |> array.get(index) |> result.unwrap(default_color)
      update_color(model, color)
    }
    SizeLower -> {
      let new_size = case model.pen_settings.size {
        s if s == pen_size_2 -> pen_size_1
        s if s == pen_size_3 -> pen_size_2
        s if s == pen_size_4 -> pen_size_3
        size -> size
      }
      update_size(model, new_size)
    }
    SizeIncrease -> {
      let new_size = case model.pen_settings.size {
        s if s == pen_size_1 -> pen_size_2
        s if s == pen_size_2 -> pen_size_3
        s if s == pen_size_3 -> pen_size_4
        size -> size
      }
      update_size(model, new_size)
    }
    SetSize(size) -> {
      update_size(model, size)
    }
    ChatMessage(chat_msg) -> {
      let #(chat, effect) = chat.update(model.party.chat, chat_msg, model.ws)
      #(
        Model(..model, party: party.SharedParty(..model.party, chat:)),
        effect |> effect.map(ChatMessage),
      )
    }
    EndDrawing -> {
      let assert Some(ws) = model.ws

      let final_history = case model.history_pos {
        0 -> model.history
        _ -> take_history(model.history, model.history_pos + 1)
      }

      #(
        model,
        ws.send(
          ws,
          messages.EndDrawing(final_history)
            |> messages.encode_client_message(),
        ),
      )
    }
    ToggleReady -> {
      let assert Some(ws) = model.ws

      #(
        Model(..model, is_ready: !model.is_ready),
        ws.send(
          ws,
          messages.ToggleReady
            |> messages.encode_client_message(),
        ),
      )
    }
    EmptyMsg -> #(model, effect.none())
  }
}

fn update_size(model: Model, size: Int) -> #(Model, effect.Effect(Msg)) {
  canvas_set_size(size)
  set_cursor(model.cursor_details, size, model.pen_settings.color)
  #(
    Model(
      ..model,
      pen_settings: PenSettings(..model.pen_settings, size:),
      history: [Size(size), ..model.history],
    ),
    effect.none(),
  )
}

fn update_color(model: Model, color: String) -> #(Model, effect.Effect(Msg)) {
  canvas_set_color(color)
  set_cursor(model.cursor_details, model.pen_settings.size, color)
  #(
    Model(
      ..model,
      pen_settings: PenSettings(..model.pen_settings, color:),
      history: [Color(color), ..model.history],
    ),
    effect.none(),
  )
}

fn start_drawing(
  model: Model,
  x x: Int,
  y y: Int,
) -> #(Model, effect.Effect(Msg)) {
  draw_point(x, y)
  let new_history = case model.history_pos {
    0 -> model.history
    _ -> take_history(model.history, model.history_pos + 1)
  }
  #(
    Model(
      ..model,
      is_drawing: True,
      history: [
        Point(x, y),
        Size(model.pen_settings.size),
        Color(model.pen_settings.color),
        ..new_history
      ],
      history_pos: 0,
      max_history_pos: model.max_history_pos - model.history_pos,
    ),
    effect.none(),
  )
}

pub fn take_history(history: List(HistoryItem), pos: Int) -> List(HistoryItem) {
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
      Size(size) -> int.to_string(size)
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
      canvas_set_color(color)
      follow_history(rest)
    }
    [Size(size), ..rest] -> {
      canvas_set_size(size)
      follow_history(rest)
    }
  }
}

@external(javascript, "./drawing.ffi.mjs", "setup_canvas")
pub fn setup_canvas(canvas_details: CanvasDetails) -> Nil

@external(javascript, "./drawing.ffi.mjs", "draw_point")
fn draw_point(x: Int, y: Int) -> Nil

@external(javascript, "./drawing.ffi.mjs", "end_drawing")
fn end_drawing() -> Nil

@external(javascript, "./drawing.ffi.mjs", "clear")
fn clear() -> Nil

@external(javascript, "./drawing.ffi.mjs", "clear_alternate_canvas")
fn clear_alternate_canvas(name: String) -> Nil

@external(javascript, "./drawing.ffi.mjs", "set_color")
fn canvas_set_color(color: String) -> Nil

@external(javascript, "./drawing.ffi.mjs", "set_size")
fn canvas_set_size(size: Int) -> Nil

pub type CursorDetails

@external(javascript, "./drawing.ffi.mjs", "setup_cursor")
fn setup_cursor_details() -> CursorDetails

@external(javascript, "./drawing.ffi.mjs", "set_cursor")
fn set_cursor(cursor_details: CursorDetails, size: Int, color: String) -> Nil

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

  let on_mouseenter =
    event.on("mouseenter", {
      use x <- decode.field("offsetX", decode.int)
      use y <- decode.field("offsetY", decode.int)
      use buttons <- decode.field("buttons", decode.int)

      decode.success(MouseEnter(mouse_down: buttons == 1, x:, y:))
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
        on_mouseenter,
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

  let #(ready_button_class, ready_button_text) = case model.is_ready {
    True -> #("bg-gray-200", "unready")
    False -> #("bg-green-200", "ready")
  }

  let end_button = case model.party.id == 0 && model.is_ready {
    True ->
      html.button(
        [
          attribute.class("p-1 mt-1 text-2xl bg-rose-200 rounded-lg"),
          event.on_click(EndDrawing),
        ],
        [element.text("end early")],
      )
    False -> element.none()
  }

  let timer = case model.party.info.duration {
    Some(duration) ->
      countdown_timer.element(duration, model.server_start_timestamp)
    None -> element.none()
  }

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
canvas =
  document.getElementById('drawing-canvas');
ctx =
  canvas.getContext('2d');

    ",
      ),
      html.div([attribute.class("flex w-full gap-8 px-8 items-center")], [
        chat.view(model.party.chat, model.party.id) |> element.map(ChatMessage),
        html.div([], [
          timer,
          view_drawing_ui(model),
          canvas,
          html.div([], [
            html.button(
              [
                event.on_click(ToggleReady),
                attribute.class(
                  "p-1 mt-1 mr-2 text-2xl rounded-lg " <> ready_button_class,
                ),
              ],
              [element.text(ready_button_text)],
            ),
            end_button,
          ]),
        ]),
      ]),
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

fn view_drawing_ui(model: Model) -> Element(Msg) {
  let color_buttons =
    model.colors
    |> array.map(fn(color) {
      let outline = case color == model.pen_settings.color {
        True -> "border-2 border-slate-600"
        False -> "border border-slate-300"
      }
      html.button(
        [
          attribute.class("w-6 h-6 rounded-full " <> outline),
          attribute.style("background-color", color),
          event.on_click(SetColor(color)),
        ],
        [],
      )
    })
    |> array.to_list()

  let size_buttons =
    pen_sizes
    |> list.index_map(fn(size, i) {
      let outline = case size == model.pen_settings.size {
        True -> "bg-slate-600"
        False -> "border border-slate-300"
      }
      let icon_size = i * 4 + 9
      html.button(
        [
          attribute.class("rounded-full " <> outline),
          attribute.style("width", int.to_string(icon_size) <> "px"),
          attribute.style("height", int.to_string(icon_size) <> "px"),
          event.on_click(SetSize(size)),
        ],
        [],
      )
    })

  let undo_enabled = model.history_pos < model.max_history_pos
  let undo_button =
    html.button(
      [
        attribute.class(
          "bg-slate-200 rounded-lg cursor-pointer disabled:cursor-not-allowed",
        ),
        event.on_click(BackHistory),
        attribute.disabled(!undo_enabled),
      ],
      [icons.undo(undo_enabled)],
    )

  let redo_enabled = case model.history_pos {
    0 -> False
    _ -> True
  }

  let redo_button =
    html.button(
      [
        attribute.class(
          "bg-slate-200 rounded-lg cursor-pointer disabled:cursor-not-allowed",
        ),
        event.on_click(ForwardHistory),
        attribute.disabled(!redo_enabled),
      ],
      [icons.redo(redo_enabled)],
    )

  html.div([attribute.class("flex p-2")], [
    html.div(
      [
        attribute.class(
          "flex justify-center items-center gap-1 p-2 rounded-lg shadow-sm bg-slate-100",
        ),
      ],
      list.flatten([
        color_buttons,
        [html.div([attribute.class("ml-6")], [])],
        size_buttons,
        [html.div([attribute.class("ml-6")], [])],
        [undo_button, redo_button],
      ]),
    ),
  ])
}

fn stop_drawing(model: Model) {
  end_drawing()

  let no_changes = case model.history {
    [PenUp, ..] -> True
    _ -> False
  }

  use <- bool.guard(when: no_changes, return: #(model, effect.none()))

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
          let pen_edge = model.pen_settings.size / 2
          let #(top, left, bottom, right) = acc
          let top = case y {
            y if y < model.canvas_details.edge + pen_edge -> [item, ..top]
            _ -> top
          }
          let left = case x {
            x if x < model.canvas_details.edge + pen_edge -> [item, ..left]
            _ -> left
          }
          let bottom_border =
            model.canvas_details.height - model.canvas_details.edge
          let bottom = case y {
            y if y > bottom_border - pen_edge -> [
              Point(x, y - bottom_border),
              ..bottom
            ]
            _ -> bottom
          }
          let right_border =
            model.canvas_details.width - model.canvas_details.edge
          let right = case x {
            x if x > right_border - pen_edge -> [
              Point(x - right_border, y),
              ..right
            ]
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
        messages.SendDrawing(history, model.pen_settings, direction)
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
      max_history_pos: model.max_history_pos + 1,
    ),
    effect.batch(messages),
  )
}
