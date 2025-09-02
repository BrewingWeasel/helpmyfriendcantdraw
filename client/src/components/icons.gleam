import lustre/attribute.{attribute}
import lustre/element/html
import lustre/element/svg

const icon_size = 36

const enabled_color = "#000000"

const disabled_color = "#7a7a7a"

// https://www.svgrepo.com/svg/506349/undo-small
pub fn undo(enabled) {
  let stroke = case enabled {
    True -> enabled_color
    False -> disabled_color
  }
  html.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("fill", "none"),
      attribute.width(icon_size),
      attribute.height(icon_size),
    ],
    [
      svg.path([
        attribute("stroke-linejoin", "round"),
        attribute("stroke-linecap", "round"),
        attribute("stroke-width", "1.5"),
        attribute("stroke", stroke),
        attribute(
          "d",
          "M18 13C17.4904 11.9961 16.6247 11.1655 15.5334 10.6333C14.442 10.1011 13.1842 9.89624 11.9494 10.0495C9.93127 10.3 8.52468 11.6116 7 12.8186M7 10V13H10",
        ),
      ]),
    ],
  )
}

// https://www.svgrepo.com/svg/506293/redo-small
pub fn redo(enabled) {
  let stroke = case enabled {
    True -> enabled_color
    False -> disabled_color
  }
  html.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute("fill", "none"),
      attribute.width(icon_size),
      attribute.height(icon_size),
    ],
    [
      svg.path([
        attribute("stroke-linejoin", "round"),
        attribute("stroke-linecap", "round"),
        attribute("stroke-width", "1.5"),
        attribute("stroke", stroke),
        attribute(
          "d",
          "M6 13C6.50963 11.9961 7.37532 11.1655 8.46665 10.6333C9.55797 10.1011 10.8158 9.89624 12.0506 10.0495C14.0687 10.3 15.4753 11.6116 17 12.8186M17 10V13H14",
        ),
      ]),
    ],
  )
}

const text_icon_size = 20

// https://www.svgrepo.com/svg/525296/crown-minimalistic
pub fn crown() {
  html.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute.class("fill-current inline"),
      attribute.width(text_icon_size),
      attribute.height(text_icon_size),
    ],
    [
      svg.path([
        attribute(
          "d",
          "M21.609 13.5616L21.8382 11.1263C22.0182 9.2137 22.1082 8.25739 21.781 7.86207C21.604 7.64823 21.3633 7.5172 21.106 7.4946C20.6303 7.45282 20.0329 8.1329 18.8381 9.49307C18.2202 10.1965 17.9113 10.5482 17.5666 10.6027C17.3757 10.6328 17.1811 10.6018 17.0047 10.5131C16.6865 10.3529 16.4743 9.91812 16.0499 9.04851L13.8131 4.46485C13.0112 2.82162 12.6102 2 12 2C11.3898 2 10.9888 2.82162 10.1869 4.46486L7.95007 9.04852C7.5257 9.91812 7.31351 10.3529 6.99526 10.5131C6.81892 10.6018 6.62434 10.6328 6.43337 10.6027C6.08872 10.5482 5.77977 10.1965 5.16187 9.49307C3.96708 8.1329 3.36968 7.45282 2.89399 7.4946C2.63666 7.5172 2.39598 7.64823 2.21899 7.86207C1.8918 8.25739 1.9818 9.2137 2.16181 11.1263L2.391 13.5616C2.76865 17.5742 2.95748 19.5805 4.14009 20.7902C5.32271 22 7.09517 22 10.6401 22H13.3599C16.9048 22 18.6773 22 19.8599 20.7902C21.0425 19.5805 21.2313 17.5742 21.609 13.5616Z",
        ),
      ]),
    ],
  )
}

pub fn person() {
  html.svg(
    [
      attribute("viewBox", "0 0 24 24"),
      attribute.class("fill-current inline"),
      attribute.width(text_icon_size),
      attribute.height(text_icon_size),
    ],
    [
      svg.path([
        attribute(
          "d",
          "M17.5 21.0001H6.5C5.11929 21.0001 4 19.8808 4 18.5001C4 14.4194 10 14.5001 12 14.5001C14 14.5001 20 14.4194 20 18.5001C20 19.8808 18.8807 21.0001 17.5 21.0001Z",
        ),
      ]),
      svg.path([
        attribute(
          "d",
          "M12 11C14.2091 11 16 9.20914 16 7C16 4.79086 14.2091 3 12 3C9.79086 3 8 4.79086 8 7C8 9.20914 9.79086 11 12 11Z",
        ),
      ]),
    ],
  )
}
