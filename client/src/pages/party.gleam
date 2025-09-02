import components/chat
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/effect
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared/messages
import shared/party.{type SharedParty, SharedParty}
import util/names

import lustre_websocket as ws

// MODEL -----------------------------------------------------------------------
pub type Model {
  Model(name: String, ws: Option(ws.WebSocket), owner: Bool, party: PartyModel)
}

pub type PartyModel {
  KnownParty(party: SharedParty)
  PartyCode(code: String, waiting_on: String)
  Creating
}

pub fn init(
  code party_code: Option(String),
  name name: String,
  ws ws: ws.WebSocket,
) -> #(Model, effect.Effect(Msg)) {
  let name = case string.trim(name) {
    "" -> names.new()
    _ -> name
  }
  let #(owner, party, initial_message) = case party_code {
    Some(code) -> #(
      False,
      PartyCode(code, waiting_on: "Connecting.."),
      messages.JoinParty(name:, code:),
    )
    None -> #(True, Creating, messages.CreateParty(name:))
  }

  #(
    Model(name:, ws: Some(ws), owner:, party:),
    initial_message
      |> messages.encode_client_message()
      |> ws.send(ws, _),
  )
}

// UPDATE ----------------------------------------------------------------------

pub type Msg {
  RemovePlayer(id: Int)
  ChatMessage(chat.Msg)
  SetLayout(party.DrawingsLayout)
  SetOverlap(Int)
  SetDuration(Option(Int))
  Start
  CopyCode
}

@external(javascript, "./party.ffi.mjs", "write_to_clipboard")
fn write_to_clipboard(code: String) -> Nil

pub fn update(model: Model, msg: Msg) {
  let update_party_settings = fn(msg, party_updater) {
    case model.ws {
      Some(ws) -> {
        let assert KnownParty(party:) = model.party
        let party = SharedParty(..party, info: party_updater(party.info))

        #(
          Model(..model, party: KnownParty(party)),
          ws.send(
            ws,
            msg
              |> messages.encode_client_message(),
          ),
        )
      }
      None -> #(model, effect.none())
    }
  }

  case msg {
    CopyCode -> {
      case model.party {
        KnownParty(SharedParty(code:, ..)) | PartyCode(code:, ..) -> {
          write_to_clipboard(code)
          #(model, effect.none())
        }
        Creating -> #(model, effect.none())
      }
    }
    RemovePlayer(id) -> {
      case model.ws {
        Some(ws) -> {
          let assert KnownParty(party:) = model.party
          let players = party.info.players |> dict.delete(id)
          let party =
            SharedParty(..party, info: party.Party(..party.info, players:))

          #(
            Model(..model, party: KnownParty(party)),
            ws.send(
              ws,
              messages.KickUser(id:)
                |> messages.encode_client_message(),
            ),
          )
        }
        None -> #(model, effect.none())
      }
    }
    ChatMessage(chat_msg) -> {
      let assert Model(party: KnownParty(SharedParty(..) as party), ..) = model
      let #(party, effect) = chat.update(party, chat_msg, model.ws)
      #(
        Model(..model, party: KnownParty(party)),
        effect |> effect.map(ChatMessage),
      )
    }
    SetLayout(new_layout) -> {
      use party <- update_party_settings(messages.SetLayout(new_layout))
      party.Party(..party, drawings_layout: new_layout)
    }
    SetOverlap(new_overlap) -> {
      use party <- update_party_settings(messages.SetOverlap(new_overlap))
      party.Party(..party, overlap: new_overlap)
    }
    SetDuration(new_duration) -> {
      use party <- update_party_settings(messages.SetDuration(new_duration))
      party.Party(..party, duration: new_duration)
    }
    Start -> panic as "shouldn't have to handle"
  }
}

// VIEW ------------------------------------------------------------------------

pub fn view(model: Model) -> Element(Msg) {
  let code = case model.party {
    PartyCode(code, _waiting_on) -> code
    KnownParty(SharedParty(code:, ..)) -> code
    Creating -> "????"
  }

  let party_view = case model.party {
    KnownParty(SharedParty(info:, chat:, code: _, id: personal_id)) -> {
      let removing_attributes = fn(id) {
        case model.owner, id {
          False, _ | _, 0 -> []
          True, _ -> [
            event.on_click(RemovePlayer(id)),
            attribute.class("hover:line-through cursor-pointer"),
          ]
        }
      }

      let players =
        info.players
        |> dict.to_list()
        |> list.map(fn(item) {
          let #(id, player) = item
          let #(color, symbol) = names.get_styling_by_id(id, personal_id)
          html.li([attribute.class(color), ..removing_attributes(id)], [
            html.span([], [element.text(player.name), symbol]),
          ])
        })

      let chat = chat.view(chat, personal_id)

      let is_owner = personal_id == 0

      let settings =
        html.div([attribute.class("grow p-5 bg-slate-100 rounded-xl")], [
          html.h2([attribute.class("text-3xl")], [html.text("Settings")]),
          html.div([attribute.class("flex flex-col gap-2 items-center")], [
            html.table([], [
              one_of_options(
                [party.Horizontal, party.Vertical, party.Horizontal],
                "layout:",
                fn(layout) {
                  case layout {
                    party.Horizontal -> element.text("Horizontal")
                    party.Vertical -> element.text("Vertical")
                  }
                },
                info.drawings_layout,
                SetLayout,
              ),
              one_of_options(
                [30, 50, 80, 0, 30],
                "overlap:",
                fn(overlap) {
                  case overlap {
                    30 -> element.text("Small")
                    50 -> element.text("Medium")
                    80 -> element.text("Large")
                    0 -> element.text("None")
                    _ -> element.text("Custom")
                  }
                },
                info.overlap,
                SetOverlap,
              ),
              one_of_options(
                [
                  option.None,
                  option.Some(5 * 60),
                  option.Some(3 * 60),
                  option.Some(60),
                  option.Some(30),
                  option.None,
                ],
                "timer:",
                fn(timer) {
                  case timer {
                    option.None -> element.text("No timer")
                    option.Some(300) -> element.text("5:00")
                    option.Some(180) -> element.text("3:00")
                    option.Some(60) -> element.text("1:00")
                    option.Some(30) -> element.text("0:30")
                    option.Some(secs) ->
                      element.text(int.to_string(secs) <> " seconds")
                  }
                },
                info.duration,
                SetDuration,
              ),
            ]),
            html.button(
              [
                attribute.class(
                  "bg-rose-200 p-2 h-12 rounded-xl disabled:cursor-not-allowed disabled:bg-gray-200",
                ),
                attribute.disabled(!is_owner || list.length(players) < 2),
                event.on_click(Start),
              ],
              [element.text("start")],
            ),
          ]),
        ])

      html.div([attribute.class("flex gap-8 w-screen mx-12 max-h-[85vh]")], [
        chat |> element.map(ChatMessage),
        html.div(
          [attribute.class("bg-slate-100 rounded-xl p-5 w-64 flex-none")],
          [
            html.h2([attribute.class("text-3xl hidden sm:block")], [
              html.text("Players"),
            ]),
            html.h2([attribute.class("text-3xl sm:hidden text-center")], [
              html.text("Party (" <> code <> ")"),
            ]),
            html.ul([attribute.class("text-xl")], players),
          ],
        ),
        settings,
      ])
    }
    PartyCode(_, waiting_on) ->
      html.div([attribute.class("text-3xl text-center")], [
        html.text(waiting_on),
      ])
    Creating ->
      html.div([attribute.class("text-3xl text-center")], [
        html.text("Creating party..."),
      ])
  }

  element.fragment([
    html.div(
      [
        attribute.class(
          "absolute top-0 right-0 my-6 mx-12 text-center text-xl gap-0 hidden sm:block",
        ),
      ],
      [
        html.h3([], [element.text("PARTY CODE")]),
        html.h3(
          [
            attribute.class(
              "text-5xl cursor-pointer hover:scale-110 duration-200 ease-in-out",
            ),
            event.on_click(CopyCode),
          ],
          [element.text(code)],
        ),
        html.h3([], [element.text("(click to copy)")]),
      ],
    ),
    html.div(
      [
        attribute.class(
          "flex w-screen h-screen justify-center items-center text-2xl",
        ),
        attribute.style("font-family", "Caveat Brush"),
      ],
      [party_view],
    ),
  ])
}

fn one_of_options(looped_options, description, viewer, current, msg) {
  let get_pair = fn(pair) {
    let #(a, b) = pair
    case a == current {
      True -> Ok(b)
      False -> Error(Nil)
    }
  }

  let assert Ok(next) =
    looped_options
    |> list.window_by_2()
    |> list.find_map(get_pair)

  let assert Ok(previous) =
    looped_options
    |> list.reverse()
    |> list.window_by_2()
    |> list.find_map(get_pair)

  html.tr([attribute.class("align-middle")], [
    html.td([attribute.class("px-8")], [
      html.h2([attribute.class("text-2xl mx-4")], [html.text(description)]),
    ]),
    html.td([], [
      html.button(
        [
          attribute.class(
            "mx-1 text-5xl hover:scale-120 cursor-pointer duration-150 ease-in-out",
          ),
          event.on_click(msg(previous)),
        ],
        [element.text("<")],
      ),
    ]),
    html.td([attribute.class("text-center w-36")], [viewer(current)]),
    html.td([], [
      html.button(
        [
          attribute.class(
            "mx-1 text-5xl hover:scale-120 cursor-pointer duration-150 ease-in-out",
          ),
          event.on_click(msg(next)),
        ],
        [element.text(">")],
      ),
    ]),
  ])
}
