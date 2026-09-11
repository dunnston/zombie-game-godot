class_name UiMeter
extends Control
## A progress bar: a void track with a 1px soft border, radius 0, a flat fill,
## band ticks in white at 35%, and optional text laid over it.
##
## Heights are 20 (the HUD's status bars), 14 (status), 12, 8 (secondary) and
## 4 (a sliver). The fill never animates: a meter that eases is a meter you
## misread in a fight.

var frac := 0.0
var fill := Ui.OK
## Fractions along the bar at which to draw a tick.
var ticks: Array = []
var tick_color := Color(1, 1, 1, 0.35)
var left := ""
var right := ""
var text_color := Color.WHITE
var right_color: Variant = null


func _init(height := 8.0, fill_color := Ui.OK) -> void:
	custom_minimum_size = Vector2(0, height)
	fill = fill_color
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_value(f: float, c: Variant = null, l := "", r := "") -> void:
	f = clampf(f, 0.0, 1.0)
	var col: Color = fill if c == null else c
	if is_equal_approx(f, frac) and col == fill and l == left and r == right:
		return
	frac = f
	fill = col
	left = l
	right = r
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Ui.VOID)
	var inner := r.grow(-1.0)
	draw_rect(Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y)), fill)
	for t in ticks:
		var x := floorf(inner.position.x + inner.size.x * float(t))
		draw_rect(Rect2(x, inner.position.y, 1, inner.size.y), tick_color)
	draw_rect(r, Ui.LINE_SOFT, false, 1.0)
	if size.y < 12.0 or (left.is_empty() and right.is_empty()):
		return
	var fs := 13 if size.y >= 18.0 else 12
	var base := (size.y + fs * 0.72) / 2.0
	if not left.is_empty():
		draw_string(Ui.font("ui", 600, 1), Vector2(8, base), left.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 16, fs, text_color)
	if not right.is_empty():
		draw_string(Ui.font("mono", 500), Vector2(0, base), right, HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - 8, fs, text_color if right_color == null else right_color)
