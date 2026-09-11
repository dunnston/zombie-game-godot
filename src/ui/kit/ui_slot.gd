class_name UiSlot
extends Control
## One item cell: 56x56, radius 2, the swatch (or the item's art) inset 6px,
## the count bottom-right in mono, the condition sliver along the bottom.
##
## Selection grows the border inward to 2px and the swatch inset shrinks by one
## to match, so the box itself never moves. Drawn rather than composed, because
## a pack is forty of these and a frame is sixteen milliseconds.

## What the owner knows this cell by: {kind, index, slot}.
var info := {}
## {id, n, wear, lv} or empty.
var stack := {}
var selected := false
var dim := false
## Condition as a fraction, or < 0 when there is nothing to say.
var wear := -1.0
## The hotbar number, top-left; "" for none.
var number := ""
## A label under the swatch for body slots and such; drawn by the owner.
var hovered := false


func _init(cell_info := {}, px := Ui.SLOT_SIZE) -> void:
	info = cell_info
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		hovered = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		hovered = false
		queue_redraw())


## Sets what the cell shows; redraws only when something actually changed.
func show_stack(s: Dictionary, sel := false, w := -1.0, num := "", dimmed := false) -> void:
	if s == stack and sel == selected and is_equal_approx(w, wear) and num == number and dimmed == dim:
		return
	stack = s
	selected = sel
	wear = w
	number = num
	dim = dimmed
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var empty := stack.is_empty()
	var sb: StyleBoxFlat
	if selected:
		sb = Ui.box(Ui.SELECTED, Ui.ACCENT_HI, 2, 2)
	elif hovered and not empty:
		sb = Ui.box(Ui.HOVER, Ui.LINE_STRONG, 1, 2)
	elif empty:
		sb = Ui.box(Ui.SLOT_EMPTY, Ui.LINE_STRONG if hovered else Ui.LINE_SOFT, 1, 2)
	else:
		sb = Ui.box(Ui.SLOT, Ui.LINE, 1, 2)
	sb.draw(get_canvas_item(), r)

	var mono := Ui.font("mono", 500)
	if not number.is_empty():
		draw_string(mono, Vector2(4, 13), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
	if empty:
		return
	var id := String(stack.id)
	var inset := 5.0 if selected else 6.0
	var sw := r.grow(-inset)
	var alpha := 0.45 if dim else 1.0
	var tex := Items.icon_of(id)
	if tex != null:
		draw_texture_rect(tex, Items.art_rect(tex, sw), false, Color(1, 1, 1, alpha))
	else:
		draw_rect(sw, Color(Color(Items.color_of(id)), alpha))
	var lv := Upgrade.level_in(stack)
	if lv > 1:
		draw_string(mono, Vector2(0, 13), "L%d" % lv, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, Ui.WAIT)
	if int(stack.get("n", 1)) > 1:
		draw_string(mono, Vector2(0, size.y - 4), str(int(stack.n)), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4, 12, Ui.INK)
	if wear >= 0.0:
		var bar := Rect2(5, size.y - 7, size.x - 10, 3)
		draw_rect(bar, Ui.VOID)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(wear, 0.0, 1.0), 3)), Ui.wear_color(wear))
