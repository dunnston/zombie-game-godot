class_name UiPips
extends Control
## A row of small flat blocks, some filled: bench tier pips, perk ranks, weapon
## levels. `diamond` turns each into a 9px square turned 45 degrees, which is
## how danger is counted everywhere.

var count := 3
var filled := 0
var on := Ui.ACCENT
var off := Ui.LINE_SOFT
var pip := Vector2(7, 7)
var gap := 3.0
var diamond := false


func _init(n := 3, pip_size := Vector2(7, 7), on_color := Ui.ACCENT, off_color := Ui.LINE_SOFT, spacing := 3.0) -> void:
	count = n
	pip = pip_size
	on = on_color
	off = off_color
	gap = spacing
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_resize()


func set_filled(n: int, c: Variant = null, total := -1) -> void:
	var col: Color = on if c == null else c
	var t := count if total < 0 else total
	if n == filled and col == on and t == count:
		return
	filled = n
	on = col
	count = t
	_resize()
	queue_redraw()


func _resize() -> void:
	var w := pip.x * count + gap * maxi(0, count - 1)
	custom_minimum_size = Vector2(w, pip.y) if not diamond else Vector2(w + 4, pip.y + 4)


func _draw() -> void:
	for i in range(count):
		var c := on if i < filled else off
		var x := i * (pip.x + gap)
		if diamond:
			var m := Vector2(x + pip.x / 2.0 + 2, pip.y / 2.0 + 2)
			var h := pip.x * 0.7
			draw_colored_polygon(PackedVector2Array([m + Vector2(0, -h), m + Vector2(h, 0), m + Vector2(0, h), m + Vector2(-h, 0)]), c)
		else:
			draw_rect(Rect2(x, 0, pip.x, pip.y), c)
