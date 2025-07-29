import gleam/int
import gleam/list
import gleam/string

const artist_descriptions = ["Awful", "Horrid", "Bad", "Terrible"]

const artist_names = ["Artist", "Drawer", "Painter", "Designer"]

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
  let symbol = case id {
    // 0 if personal_id == 0 -> " (L|U)"
    0 -> " (L)"
    _ if id == personal_id -> " (U)"
    _ -> ""
  }
  #(color, symbol)
}
