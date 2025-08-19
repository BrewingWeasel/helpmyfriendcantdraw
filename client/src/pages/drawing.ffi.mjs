export function draw_at_other_canvas(canvas_name, pen_settings, strokes) {
  const canvas = document.getElementById(canvas_name);
  const ctx = canvas.getContext('2d');

  ctx.beginPath();

  ctx.strokeStyle = pen_settings.color;
  ctx.lineWidth = pen_settings.size;;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  for (const [x, y] of strokes) {
    ctx.lineTo(
      x,
      y
    );
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(
      x,
      y
    );
  }
}


export function draw_point(x, y) {
  // ctx.lineWidth =
  //   brushSize.value;
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  ctx.lineTo(
    x,
    y
  );
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(
    x,
    y
  );
}

export function end_drawing() {
  ctx.beginPath();
}

export function clear() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
}


export function clear_alternate_canvas(canvas_name) {
  const canvas = document.getElementById(canvas_name);
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
}

export function set_color(color) {
  ctx.strokeStyle = color;
}

export function set_size(size) {
  ctx.lineWidth = size;
}

export function get_buffer(x) {
  return x.buffer;
}

export function draw_tooltips(canvas_details) {
  const canvas = document.getElementById('tooltip-canvas');
  const ctx = canvas.getContext('2d');

  ctx.setLineDash([3, 8]);
  ctx.lineWidth = 1;
  ctx.strokeStyle = 'rgba(10, 10, 10, 1)';

  const drawTooltip = ([x, y], [x2, y2]) => {
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x2, y2);
    ctx.stroke();
    ctx.closePath();
  };

  if (canvas_details.top) {
    drawTooltip([0, canvas_details.edge], [canvas_details.width, canvas_details.edge])
  }

  if (canvas_details.bottom) {
    drawTooltip([0, canvas_details.height - canvas_details.edge], [canvas_details.width, canvas_details.height - canvas_details.edge])
  }

  if (canvas_details.left) {
    drawTooltip([canvas_details.edge, 0], [canvas_details.edge, canvas_details.height])
  }

  if (canvas_details.right) {
    drawTooltip([canvas_details.width - canvas_details.edge, 0], [canvas_details.width - canvas_details.edge, canvas_details.height])
  }

}

