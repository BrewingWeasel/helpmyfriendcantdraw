export function draw_at_other_canvas(canvas_name, pen_settings, strokes) {
  const canvas = document.getElementById(canvas_name);
  const ctx = canvas.getContext('2d');

  ctx.beginPath();

  ctx.strokeStyle = pen_settings.color;
  ctx.lineWidth = pen_settings.size;
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

export function setup_canvas(canvas_details) {
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  const tooltip_canvas = document.getElementById('tooltip-canvas');
  const tooltip_ctx = tooltip_canvas.getContext('2d');

  tooltip_ctx.setLineDash([3, 8]);
  tooltip_ctx.lineWidth = 1;
  tooltip_ctx.strokeStyle = 'rgba(10, 10, 10, 1)';

  const drawTooltip = ([x, y], [x2, y2]) => {
    tooltip_ctx.beginPath();
    tooltip_ctx.moveTo(x, y);
    tooltip_ctx.lineTo(x2, y2);
    tooltip_ctx.stroke();
    tooltip_ctx.closePath();
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

export function setup_cursor() {
	return {
		canvas: document.createElement("canvas"),
		url: undefined,
	};
}

export function set_cursor(cursor_details, size, color, scale = window.devicePixelRatio) {
    const render_size = size * scale;
    cursor_details.canvas.width = render_size;
    cursor_details.canvas.height = render_size;

    const cursor_ctx = cursor_details.canvas.getContext("2d");

    cursor_ctx.scale(scale, scale);
    cursor_ctx.strokeStyle = color;
	cursor_ctx.lineWidth = 1.5;
	const padding = cursor_ctx.lineWidth / 2;

    cursor_ctx.beginPath();
    cursor_ctx.arc(size / 2, size / 2, size / 2 - padding, 0, Math.PI * 2);
    cursor_ctx.stroke();

    const final_canvas = document.createElement("canvas");
    final_canvas.width = size;
    final_canvas.height = size;

    const final_ctx = final_canvas.getContext("2d");
    final_ctx.drawImage(cursor_details.canvas, 0, 0, size, size);

    final_canvas.toBlob((blob) => {
        if (cursor_details.url) URL.revokeObjectURL(cursor_details.url);
        cursor_details.url = URL.createObjectURL(blob);

        canvas.style.cursor = `url(${cursor_details.url}) ${size / 2} ${size / 2}, auto`;
    });
}
