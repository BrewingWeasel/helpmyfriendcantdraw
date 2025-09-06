export function setup_download_button(canvas_id, download_button_id) {
	const canvas = document.getElementById(canvas_id);
	const saveButton = document.getElementById(download_button_id);
	saveButton.setAttribute("href", canvas.toDataURL("image/png").replace("image/png", "image/octet-stream"))
}

export function draw_background(canvas_id, color) {
	const canvas = document.getElementById(canvas_id);
	const ctx = canvas.getContext("2d");

	ctx.fillStyle = color;
	ctx.fillRect(0, 0, canvas.width, canvas.height);
}

