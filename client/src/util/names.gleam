import components/icons
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute
import lustre/element
import lustre/element/html

const artist_descriptions = [
  "Awful", "Horrid", "Bad", "Terrible", "Miserable", "Dreadful", "Atrocious",
  "Abysmal", "Unpleasant", "Disgusting", "Frightful", "Appalling", "Horrific",
]

const artist_names = [
  "Artist", "Painter", "Designer", "Sketcher", "Illustrator", "Craftsman",
  "Cartoonist", "Drawer", "Creator", "Artisan", "Producer", "Sculptor",
  "Originator",
]

pub fn new() -> String {
  [
    list.sample(artist_descriptions, 1),
    list.sample(artist_names, 1),
    [int.random(100) |> int.to_string()],
  ]
  |> list.flatten()
  |> string.concat()
}

pub fn get_styling_by_id(id: Int, personal_id: Int) {
  let color = case id % 4 {
    0 -> "text-violet-300"
    1 -> "text-teal-400"
    2 -> "text-rose-300"
    _ -> "text-amber-500"
  }

  let icon_wrapper = fn(icon) {
    html.span([attribute.class("whitespace-pre inline-flex items-center gap-[1px] select-none")], [
      element.text(" ("),
      icon,
      element.text(")"),
    ])
  }

  let symbol = case id {
    0 -> icon_wrapper(icons.crown())
    id if id == personal_id -> icon_wrapper(icons.person())
    _ -> element.none()
  }
  #(color, symbol)
}
