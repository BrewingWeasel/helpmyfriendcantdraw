import lustre/attribute
import lustre/element/html

pub fn view(reason: String) {
  html.div(
    [
      attribute.class(
        "flex flex-col w-screen h-screen justify-center items-center text-2xl",
      ),
      attribute.style("font-family", "Caveat Brush"),
    ],
    [
      html.p([attribute.class("text-5xl text-center")], [
        html.text("Disconnected"),
      ]),
      html.p([attribute.class("text-3xl text-center")], [html.text(reason)]),
    ],
  )
}
