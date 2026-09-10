class_name PickupView
extends Node2D
## Piles on the ground and the packs the dead leave behind. Small, bobbing
## and coloured by what they are, so a street after a fight reads at a glance.

var sim: GameSim


func _init(sim_: GameSim) -> void:
	sim = sim_


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl := inv * Vector2.ZERO - Vector2(48, 48)
	var br := inv * get_viewport_rect().size + Vector2(48, 48)

	for it in sim.pickups:
		var pos: Vector2 = it.pos
		if pos.x < tl.x or pos.y < tl.y or pos.x > br.x or pos.y > br.y:
			continue
		var bob := sin(it.t * 3.4 + it.bob) * 2.0
		var at := pos + Vector2(0, bob)
		var color := Color(Items.color_of(it.id))
		draw_circle(pos + Vector2(0, 3), 4.0, Color(0, 0, 0, 0.22))
		# A resource is a small pip; a weapon or a piece of gear is a crate,
		# because it is worth crossing the road for. Either gives way to real
		# art when the item has some (`Items.icon_of`).
		var pip: bool = it.kind == "res" or it.kind == "item"
		var tex := Items.icon_of(it.id, "ground")
		if tex != null:
			draw_texture_rect(tex, Items.art_rect(tex, Rect2(at - Vector2(8, 8), Vector2(16, 16))), false)
		elif pip:
			draw_circle(at, 4.0, color)
			draw_arc(at, 5.5, 0.0, TAU, 12, Color(0, 0, 0, 0.5), 1.0)
		else:
			var r := Rect2(at - Vector2(6, 5), Vector2(12, 10))
			draw_rect(r, color)
			draw_rect(r, Color(0, 0, 0, 0.6), false, 1.0)
		if pip and it.n > 1:
			draw_string(font, at + Vector2(-12, -7), "x%d" % it.n, HORIZONTAL_ALIGNMENT_CENTER, 24, 9, Color(1, 1, 1, 0.85))
		elif not pip:
			draw_string(font, at + Vector2(-40, -10), Items.name_of(it.id), HORIZONTAL_ALIGNMENT_CENTER, 80, 9, Color("#ffe08a"))

	for pack in sim.backpacks:
		var pos: Vector2 = pack.pos
		if pos.x < tl.x or pos.y < tl.y or pos.x > br.x or pos.y > br.y:
			continue
		draw_circle(pos + Vector2(0, 4), 7.0, Color(0, 0, 0, 0.25))
		draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), Color("#6b4a2f"))
		draw_rect(Rect2(pos - Vector2(8, 8), Vector2(16, 16)), Color("#c9a227"), false, 1.5)
		draw_string(font, pos + Vector2(-40, -14), "YOUR PACK", HORIZONTAL_ALIGNMENT_CENTER, 80, 10, Color("#c9a227"))
