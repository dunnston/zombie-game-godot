class_name UiSwatch
extends Control
## A square of an item's colour, or its art when it has some — the chips in a
## bill, the icon tile on a card, the big one on a detail panel. A `frame`
## draws the void tile with a border around it, the way the cards show an icon.

var id := ""
var color := Color.WHITE
var alpha := 1.0
var frame := false
var frame_color := Ui.LINE
## Inner size when framed.
var inner := 0.0
## Draw `color` with no item behind it: a structure, which has no art.
var solid := false


static func of_color(c: Color, px := 8, framed := false, inner_px := 0.0) -> UiSwatch:
	var s := UiSwatch.new("", px, framed, inner_px)
	s.color = c
	s.solid = true
	return s


func _init(item_id := "", px := 8, framed := false, inner_px := 0.0) -> void:
	id = item_id
	color = Color(Items.color_of(item_id)) if not item_id.is_empty() else Ui.LINE
	custom_minimum_size = Vector2(px, px)
	frame = framed
	inner = inner_px if inner_px > 0.0 else px * 0.6
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_item(item_id: String, a := 1.0, edge: Variant = null) -> void:
	var fc: Color = frame_color if edge == null else edge
	if item_id == id and is_equal_approx(a, alpha) and fc == frame_color:
		return
	id = item_id
	color = Color(Items.color_of(item_id)) if not item_id.is_empty() else Ui.LINE
	alpha = a
	frame_color = fc
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var sw := r
	if frame:
		draw_rect(r, Ui.VOID)
		draw_rect(r, frame_color, false, 1.0)
		sw = Rect2((size - Vector2(inner, inner)) / 2.0, Vector2(inner, inner))
	if id.is_empty():
		if solid:
			draw_rect(sw, Color(color, alpha))
		return
	var tex := Items.icon_of(id)
	if tex != null:
		draw_texture_rect(tex, Items.art_rect(tex, sw), false, Color(1, 1, 1, alpha))
	else:
		draw_rect(sw, Color(color, alpha))
