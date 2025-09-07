import lustre/attribute
import lustre/element/html

pub fn animation() {
  attribute.class(
    "cursor-pointer hover:scale-110 hover:disabled:scale-100 duration-150 ease-in-out",
  )
}

pub fn button(attributes, inner) {
  html.button(
    [
      attribute.class(
        "px-3 py-2 rounded-xl cursor-pointer disabled:cursor-not-allowed bg-accent hover:bg-accent/90 hover:disabled:disabled:bg-gray-200 disabled:bg-gray-200",
      ),
      ..attributes
    ],
    inner,
  )
}
