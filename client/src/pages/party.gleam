import components/chat
import gleam/dict
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
  Start
}

pub fn update(model: Model, msg: Msg) {
  case msg {
    // WsWrapper(event) -> {
    //   case event {
    //     ws.InvalidUrl -> panic as "invalid websocket url"
    //     ws.OnOpen(socket) -> {
    //     }
    //     ws.OnTextMessage(_message) ->
    //       panic as "should be intercepted by main handler"
    //     ws.OnBinaryMessage(_message) -> {
    //       panic as "should read all messages as utf8"
    //     }
    //     ws.OnClose(_reason) -> {
    //       let code = case model.party {
    //         KnownParty(code:, ..) -> code
    //         PartyCode(code:, ..) -> code
    //         Creating -> "????"
    //       }
    //       #(
    //         Model(..model, party: PartyCode(code, "Disconnected..."), ws: None),
    //         effect.none(),
    //       )
    //     }
    //   }
    // }
    RemovePlayer(id) -> {
      case model.ws {
        Some(ws) -> {
          let assert KnownParty(party:) = model.party
          let players = party.info.players |> dict.delete(id)
          let party = SharedParty(..party, info: party.Party(players:))

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
      let assert Model(party: KnownParty(SharedParty(chat:, ..) as party), ..) =
        model
      let #(chat, effect) = chat.update(chat, chat_msg, model.ws)
      #(
        Model(..model, party: KnownParty(SharedParty(..party, chat:))),
        effect |> effect.map(ChatMessage),
      )
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
            element.text(player.name),
            element.text(symbol),
          ])
        })

      let chat = chat.view(chat, personal_id)

      let settings =
        html.div(
          [attribute.class("grow flex p-8 justify-center bg-slate-100")],
          [
            html.button(
              [
                attribute.class("bg-rose-200 p-2 h-12 rounded-xl"),
                event.on_click(Start),
              ],
              [element.text("start")],
            ),
          ],
        )

      html.div([attribute.class("flex gap-8 w-screen mx-12")], [
        chat |> element.map(ChatMessage),
        html.div(
          [attribute.class("bg-slate-100 rounded-xl p-5 w-64 flex-none")],
          [
            html.h2([], [html.text("Players")]),
            html.ul(
              [attribute.class("list-disc list-inside text-2xl")],
              players,
            ),
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
        attribute.style("font-family", "Caveat Brush"),
        attribute.class(
          "absolute top-0 right-0 my-6 mx-12 text-center text-xl gap-0",
        ),
      ],
      [
        html.h3([], [element.text("PARTY CODE")]),
        html.h3([attribute.class("text-5xl")], [element.text(code)]),
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
