// IMPORTS ---------------------------------------------------------------------

import components/chat
import components/countdown_timer
import gleam/dict
import gleam/io
import gleam/javascript/array
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre
import lustre/effect
import lustre/element.{type Element}
import pages/disconnected
import pages/drawing
import pages/home
import pages/party
import pages/results
import shared/list_changing
import shared/messages
import shared/palette
import shared/party.{Chat, SharedParty} as shared_party

import lustre_websocket as ws

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)

  let assert Ok(Nil) = countdown_timer.register()

  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(ws: Option(ws.WebSocket), page: Page)
}

type Page {
  DrawingPage(drawing.Model)
  HomePage(home.Model)
  PartyPage(party.Model)
  ResultsPage(results.Model)
  DisconnectedPage(reason: String)
}

fn init(_: a) -> #(Model, effect.Effect(Msg)) {
  #(Model(ws: None, page: HomePage(home.init().0)), ws.init("/ws", WsWrapper))
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  DrawingPageUpdate(drawing.Msg)
  HomePageUpdate(home.Msg)
  PartyPageUpdate(party.Msg)
  ResultsPageUpdate(results.Msg)
  WsWrapper(ws.WebSocketEvent)
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    DrawingPageUpdate(drawing_msg) -> {
      let assert DrawingPage(drawing_model) = model.page
      let #(new_drawing_model, effects) =
        drawing.update(drawing_model, drawing_msg)
      #(
        Model(..model, page: DrawingPage(new_drawing_model)),
        effects |> effect.map(DrawingPageUpdate),
      )
    }

    WsWrapper(ws.OnTextMessage(message)) -> {
      case messages.decode_server_message(message) {
        Ok(msg) -> server_update(model, msg)
        Error(_) -> #(model, effect.none())
      }
    }
    WsWrapper(ws.OnBinaryMessage(_)) -> panic as "text messages only"
    WsWrapper(ws.InvalidUrl) -> {
      io.println_error("Invalid WebSocket URL")
      #(model, effect.none())
    }
    WsWrapper(ws.OnOpen(ws)) -> #(
      Model(..model, ws: Some(ws)),
      ws.send(ws, "connected"),
    )

    WsWrapper(ws.OnClose(reason)) -> {
      case model.page {
        DisconnectedPage(_) -> #(model, effect.none())
        _ -> #(
          Model(..model, page: DisconnectedPage(string.inspect(reason))),
          effect.none(),
        )
      }
    }

    PartyPageUpdate(party.Start) -> {
      let assert PartyPage(party.Model(ws: Some(ws), ..)) = model.page

      #(
        model,
        ws.send(
          ws,
          messages.StartDrawing
            |> messages.encode_client_message(),
        ),
      )
    }

    PartyPageUpdate(party_msg) -> {
      let assert PartyPage(party_model) = model.page
      let #(new_party_model, effects) = party.update(party_model, party_msg)
      #(
        Model(..model, page: PartyPage(new_party_model)),
        effects |> effect.map(PartyPageUpdate),
      )
    }

    ResultsPageUpdate(results.ReturnToParty) -> {
      let assert ResultsPage(results_model) = model.page

      let id = results_model.party.id
      let name =
        dict.get(results_model.party.info.players, id)
        |> result.map(fn(player) { player.name })
        |> result.unwrap("unknown (you)")

      #(
        Model(
          ..model,
          page: PartyPage(party.Model(
            name:,
            owner: id == 0,
            ws: results_model.ws,
            party: party.KnownParty(results_model.party),
            edit_list: None,
            palettes: dict.new(),
          )),
        ),
        effect.batch([
          party.get_palettes() |> effect.map(PartyPageUpdate),
          chat.scroll_down(),
        ]),
      )
    }

    HomePageUpdate(home.JoinRoom) -> {
      let assert HomePage(home_model) = model.page

      let assert Some(ws) = model.ws

      let #(page, message) =
        party.init(code: home_model.code, name: home_model.name, ws:)
      #(
        Model(..model, page: PartyPage(page)),
        message |> effect.map(PartyPageUpdate),
      )
    }
    HomePageUpdate(home_msg) -> {
      let assert HomePage(home_model) = model.page
      let #(new_home_model, effects) = home.update(home_model, home_msg)
      #(
        Model(..model, page: HomePage(new_home_model)),
        effects |> effect.map(HomePageUpdate),
      )
    }
    ResultsPageUpdate(results_msg) -> {
      let assert ResultsPage(results_model) = model.page
      let #(new_results_model, effects) =
        results.update(results_model, results_msg)
      #(
        Model(..model, page: ResultsPage(new_results_model)),
        effects |> effect.map(ResultsPageUpdate),
      )
    }
  }
}

fn server_update(main_model: Model, message) {
  let find_shared_party = fn(update) {
    case main_model.page {
      PartyPage(party.Model(party: party.KnownParty(shared), ws:, ..) as model) -> {
        let #(new, effect) = update(shared, ws)
        #(
          Model(
            ..main_model,
            page: PartyPage(party.Model(..model, party: party.KnownParty(new))),
          ),
          effect,
        )
      }
      DrawingPage(drawing_model) -> {
        let #(new, effect) = update(drawing_model.party, drawing_model.ws)
        #(
          Model(
            ..main_model,
            page: DrawingPage(drawing.Model(..drawing_model, party: new)),
          ),
          effect,
        )
      }
      ResultsPage(results_model) -> {
        let #(new, effect) = update(results_model.party, results_model.ws)
        #(
          Model(
            ..main_model,
            page: ResultsPage(results.Model(..results_model, party: new)),
          ),
          effect,
        )
      }
      _ -> #(main_model, effect.none())
    }
  }

  io.println("Received message: " <> string.inspect(message))
  case message {
    messages.PartyCreated(code) -> {
      let assert PartyPage(model) = main_model.page

      let party =
        party.KnownParty(SharedParty(
          shared_party.new(model.name),
          code,
          Chat(
            [
              shared_party.Server(
                "Type /help to view commands available to you as room leader",
              ),
            ],
            "",
            False,
          ),
          id: 0,
        ))
      #(
        Model(..main_model, page: PartyPage(party.Model(..model, party:))),
        effect.none(),
      )
    }
    messages.UserJoined(name, id) -> {
      use party, _ws <- find_shared_party()

      let party =
        SharedParty(
          ..party,
          info: shared_party.Party(
            ..party.info,
            players: party.info.players
              |> dict.insert(id, shared_party.Player(name: name)),
          ),
        )
      #(party, effect.none())
    }
    messages.PartyInfo(party_info, id) -> {
      let assert PartyPage(
        party.Model(
          party: party.PartyCode(code, _),
          ..,
        ) as model,
      ) = main_model.page
      let party =
        party.KnownParty(SharedParty(party_info, code, Chat([], "", False), id))
      #(
        Model(..main_model, page: PartyPage(party.Model(..model, party:))),
        effect.none(),
      )
    }
    messages.UserLeft(id) -> {
      use party, _ws <- find_shared_party()

      let players = party.info.players |> dict.delete(id)
      #(
        SharedParty(..party, info: shared_party.Party(..party.info, players:)),
        effect.none(),
      )
    }
    messages.Disconnected(reason) -> {
      #(Model(..main_model, page: DisconnectedPage(reason)), effect.none())
    }
    messages.ChatMessage(message) -> {
      use party, _ws <- find_shared_party()

      let #(chat, effect) = chat.handle_chat_message(party.chat, message)
      #(SharedParty(..party, chat:), effect)
    }
    messages.DrawingInit(
      top:,
      left:,
      bottom:,
      right:,
      server_start_timestamp:,
      prompt:,
      palette:,
    ) -> {
      let init_drawing = fn(model, top, left, bottom, right) {
        Model(
          ..main_model,
          page: DrawingPage(
            drawing.Model(
              ..model,
              canvas_details: drawing.CanvasDetails(
                top:,
                left:,
                bottom:,
                right:,
                width: model.canvas_details.width,
                height: model.canvas_details.height,
                edge: model.canvas_details.edge,
              ),
              prompt:,
              colors: array.from_list(palette.colors),
              bg_color: palette.bg,
              default_color: palette.fg,
            ),
          ),
        )
      }

      case main_model.page {
        PartyPage(party.Model(ws: Some(ws), party: party.KnownParty(party), ..))
        | ResultsPage(results.Model(ws: Some(ws), party:, ..)) -> {
          let #(drawing_model, effects) =
            drawing.init(drawing.DrawingInit(
              ws:,
              party:,
              server_start_timestamp:,
              palette:,
            ))

          #(
            init_drawing(drawing_model, top, left, bottom, right),
            effects |> effect.map(DrawingPageUpdate),
          )
        }

        DrawingPage(model) -> #(
          init_drawing(model, top, left, bottom, right),
          effect.after_paint(fn(dispatch, _) {
            dispatch(DrawingPageUpdate(drawing.Reset))
          }),
        )
        _ -> panic as "DrawingInit should only be sent to DrawingPage"
      }
    }

    messages.DrawingSent(history:, pen_settings:, direction:) -> {
      let assert DrawingPage(model) = main_model.page
      let model =
        drawing.handle_drawing_sent(model, history, pen_settings, direction)
      #(Model(..main_model, page: DrawingPage(model)), effect.none())
    }
    messages.UndoSent(direction:) -> {
      let assert DrawingPage(model) = main_model.page
      #(
        Model(
          ..main_model,
          page: DrawingPage(drawing.handle_history_change_sent(
            model,
            direction,
            history_offset: 1,
          )),
        ),
        effect.none(),
      )
    }
    messages.RedoSent(direction:) -> {
      let assert DrawingPage(model) = main_model.page
      #(
        Model(
          ..main_model,
          page: DrawingPage(drawing.handle_history_change_sent(
            model,
            direction,
            history_offset: -1,
          )),
        ),
        effect.none(),
      )
    }
    messages.LayoutSet(new_layout) -> {
      use party, _ws <- find_shared_party()
      let new_party =
        SharedParty(
          ..party,
          info: shared_party.Party(..party.info, drawings_layout: new_layout),
        )
      #(new_party, effect.none())
    }
    messages.OverlapSet(overlap) -> {
      use party, _ws <- find_shared_party()
      let new_party =
        SharedParty(..party, info: shared_party.Party(..party.info, overlap:))
      #(new_party, effect.none())
    }
    messages.DurationSet(duration) -> {
      use party, _ws <- find_shared_party()
      let new_party =
        SharedParty(..party, info: shared_party.Party(..party.info, duration:))
      #(new_party, effect.none())
    }
    messages.PaletteSet(palette) -> {
      use party, _ws <- find_shared_party()
      let new_party =
        SharedParty(..party, info: shared_party.Party(..party.info, palette:))
      #(new_party, effect.none())
    }
    messages.PromptSet(selected_prompt) -> {
      use party, _ws <- find_shared_party()
      let new_party =
        SharedParty(
          ..party,
          info: shared_party.Party(..party.info, selected_prompt:),
        )
      #(new_party, effect.none())
    }
    messages.PromptListUpdated(selected_prompt, changes) -> {
      use party, _ws <- find_shared_party()
      #(
        SharedParty(
          ..party,
          info: shared_party.Party(
            ..party.info,
            prompt_options: dict.upsert(
              party.info.prompt_options,
              selected_prompt,
              fn(options) {
                list_changing.apply_batch_changes(
                  options |> option.unwrap([]),
                  changes,
                )
              },
            ),
          ),
        ),
        effect.none(),
      )
    }
    messages.RequestDrawing -> {
      let assert DrawingPage(drawing_model) = main_model.page
      let assert Some(ws) = drawing_model.ws

      let final_history = case drawing_model.history_pos {
        0 -> drawing_model.history
        _ ->
          drawing.take_history(
            drawing_model.history,
            drawing_model.history_pos + 1,
          )
      }

      #(
        main_model,
        ws.send(
          ws,
          messages.SendFinalDrawing(final_history)
            |> messages.encode_client_message(),
        ),
      )
    }
    messages.DrawingFinalized(history, x_size, y_size) -> {
      let assert DrawingPage(drawing_model) = main_model.page
      let #(model, effect) =
        results.init(
          history,
          x_size,
          y_size,
          drawing_model.ws,
          drawing_model.party,
          palette.Palette(
            fg: drawing_model.default_color,
            bg: drawing_model.bg_color,
            colors: array.to_list(drawing_model.colors),
          ),
        )
      #(
        Model(..main_model, page: ResultsPage(model)),
        effect.batch([
          effect.after_paint(fn(dispatch, _) {
            dispatch(ResultsPageUpdate(results.ShowDrawing))
          }),
          effect |> effect.map(ResultsPageUpdate),
        ]),
      )
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model.page {
    DrawingPage(drawing_model) ->
      drawing.view(drawing_model) |> element.map(DrawingPageUpdate)
    HomePage(home_model) -> home.view(home_model) |> element.map(HomePageUpdate)
    PartyPage(party_model) ->
      party.view(party_model) |> element.map(PartyPageUpdate)
    DisconnectedPage(reason) -> disconnected.view(reason)
    ResultsPage(results_model) ->
      results.view(results_model) |> element.map(ResultsPageUpdate)
  }
}
