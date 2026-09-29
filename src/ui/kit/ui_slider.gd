class_name UiSlider
extends Control
## A drag-anywhere bar: the flat, bordered track `UiMeter` draws, plus a grip
## and a value you can set by clicking or dragging anywhere along it — a
## volume control has no room for a mouse-precision drag past its own edges,
## so clicking a point sets the value to that point outright.

## Fired on every change, drag included, for a live preview.
signal changed(value: float)
## Fired once, when the mouse comes back up — the moment to write the value
## down rather than to a disk write per pixel dragged.
signal released(value: float)

var value := 1.0
var fill := Ui.ACCENT
var _dragging := false


func _init(height := 20.0, fill_color := Ui.ACCENT) -> void:
	custom_minimum_size = Vector2(0, height)
	fill = fill_color
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_NONE


func set_value(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_set_from_x(event.position.x)
		elif _dragging:
			_dragging = false
			released.emit(value)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_set_from_x(event.position.x)
		accept_event()


func _set_from_x(x: float) -> void:
	var v := clampf(x / maxf(1.0, size.x), 0.0, 1.0)
	if is_equal_approx(v, value):
		return
	value = v
	queue_redraw()
	changed.emit(v)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Ui.VOID)
	var inner := r.grow(-1.0)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * value, inner.size.y)), fill)
	draw_rect(r, Ui.LINE_SOFT, false, 1.0)
	var gx := clampf(inner.position.x + inner.size.x * value, inner.position.x + 1.5, inner.position.x + inner.size.x - 1.5)
	draw_rect(Rect2(gx - 1.5, inner.position.y - 2.0, 3.0, inner.size.y + 4.0), Ui.TEXT_HIGH)
