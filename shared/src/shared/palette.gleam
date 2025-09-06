import gleam/dynamic/decode
import gleam/json

pub type Palette {
  Palette(fg: String, bg: String, colors: List(String))
}

pub const default_name = "default"

pub const default = Palette(
  fg: "#1e1818",
  bg: "#dedcd3",
  colors: [
    "#1e1818", "#534c56", "#97978e", "#dedcd3", "#7ec0c2", "#416f8a", "#3f355b",
    "#7d3b55", "#b14852", "#be8162", "#d4a09d", "#e1be88", "#97b668", "#568f73",
    "#685d45", "#543734",
  ],
)

pub fn to_json(palette: Palette) -> json.Json {
  let Palette(fg:, bg:, colors:) = palette
  json.object([
    #("fg", json.string(fg)),
    #("bg", json.string(bg)),
    #("colors", json.array(colors, json.string)),
  ])
}

pub fn decoder() -> decode.Decoder(Palette) {
  use fg <- decode.field("fg", decode.string)
  use bg <- decode.field("bg", decode.string)
  use colors <- decode.field("colors", decode.list(decode.string))
  decode.success(Palette(fg:, bg:, colors:))
}
