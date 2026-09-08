class_name StructureView
extends Node2D
## Draws everything the player has built, plus the build-mode ghost.
##
## Readability first: a wall is a slab in its material's colour, damage shows
## as a bar and a darkening, and anything that does a job — a gate, a turret,
## a generator, a trap — shows whether it is doing it.

const COLORS := {
	"barricade": "#8a6a3c", "woodWall": "#a3763f", "stoneWall": "#8f8a80",
	"reinforcedWall": "#9a8256", "metalWall": "#9aa2ab", "gate": "#b08a5a",
	"spike": "#8a8078", "workbench": "#b08a5a", "stash": "#a3763f",
	"chest": "#8a6a3c", "locker": "#9aa2ab", "bedroll": "#6f7a52",
	"bunk": "#6f7a52", "watchtower": "#a3763f", "generator": "#71787f",
	"turret": "#5e6a72", "floodlight": "#c9a227",
}

var sim: GameSim
var build_bar: BuildBar


func _init(sim_: GameSim) -> void:
	sim = sim_


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl := inv * Vector2.ZERO - Vector2(64, 64)
	var br := inv * get_viewport_rect().size + Vector2(64, 64)
	var half := Config.TILE * 0.5

	for s in sim.structs.list:
		if s.destroyed:
			continue
		var pos: Vector2 = s.pos
		if pos.x < tl.x or pos.y < tl.y or pos.x > br.x or pos.y > br.y:
			continue
		var frac: float = s.hp / s.max_hp
		var base := Color(COLORS.get(s.type, "#8a8f84"))
		# Damage darkens the whole piece, so a wall about to fall reads at a
		# glance rather than only in its health bar.
		var body := base.lerp(Color("#2a251c"), (1.0 - frac) * 0.55)
		if s.flash > 0.0:
			body = body.lerp(Color.WHITE, 0.6)

		match s.type:
			"gate":
				if s.open:
					# Swung open: two posts and a gap you can walk through.
					draw_rect(Rect2(pos - Vector2(half, half), Vector2(5, Config.TILE)), body)
					draw_rect(Rect2(pos + Vector2(half - 5, -half), Vector2(5, Config.TILE)), body)
				else:
					draw_rect(Rect2(pos - Vector2(half, half), Vector2(Config.TILE, Config.TILE)), body)
					draw_line(pos + Vector2(-half, -half), pos + Vector2(half, half), Color(0, 0, 0, 0.35), 2.0)
			"spike":
				for i in range(4):
					var x: float = pos.x - half + 5 + i * 7
					draw_polygon([Vector2(x, pos.y + 8), Vector2(x + 5, pos.y + 8), Vector2(x + 2.5, pos.y - 9)],
						PackedColorArray([body, body, body]))
			"bedroll":
				draw_rect(Rect2(pos - Vector2(half - 3, half - 6), Vector2(Config.TILE - 6, Config.TILE - 12)), body)
				if s.active:
					draw_arc(pos, 14.0, 0.0, TAU, 20, Color("#9fd0ff", 0.8), 1.5)
			"floodlight":
				draw_circle(pos, 8.0, body)
				if s.powered:
					draw_arc(pos, s.def.light_radius * 0.25, 0.0, TAU, 28, Color("#ffe6a8", 0.25), 2.0)
			"turret":
				draw_rect(Rect2(pos - Vector2(half - 2, half - 2), Vector2(Config.TILE - 4, Config.TILE - 4)), body)
				var barrel: float = s.aim
				draw_line(pos, pos + Vector2.from_angle(barrel) * 20.0, Color("#cfd6dd") if s.powered else Color("#5a5f58"), 3.0)
				if s.starved:
					draw_string(font, pos + Vector2(-30, -18), "NO 9MM", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color("#c96a5a"))
				elif not s.powered:
					draw_string(font, pos + Vector2(-30, -18), "NO POWER", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color("#c96a5a"))
			"generator":
				draw_rect(Rect2(pos - Vector2(half - 2, half - 2), Vector2(Config.TILE - 4, Config.TILE - 4)), body)
				if s.running:
					draw_arc(pos, 10.0 + sin(sim.time * 6.0) * 1.5, 0.0, TAU, 16, Color("#d2762c", 0.5), 2.0)
					draw_arc(pos, s.def.power_radius, 0.0, TAU, 48, Color("#59b8c4", 0.07), 1.0)
			_:
				var inset: float = 1.0 if s.def.get("wall", false) else 3.0
				draw_rect(Rect2(pos - Vector2(half - inset, half - inset), Vector2(Config.TILE - inset * 2, Config.TILE - inset * 2)), body)
				if s.store != null:
					draw_rect(Rect2(pos - Vector2(half - 7, half - 7), Vector2(Config.TILE - 14, Config.TILE - 14)), Color(0, 0, 0, 0.3))
				if s.type == "workbench" and s.tier >= 2:
					draw_string(font, pos + Vector2(-16, -12), "II", HORIZONTAL_ALIGNMENT_CENTER, 32, 10, Color("#59b8c4"))

		if frac < 0.999:
			var w := Config.TILE - 6.0
			draw_rect(Rect2(pos.x - w / 2.0, pos.y - half - 6.0, w, 3.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(pos.x - w / 2.0, pos.y - half - 6.0, w * frac, 3.0),
				Color("#9fd07a") if frac > 0.5 else Color("#e05a4a"))

	_draw_ghost()


## The tile under the cursor in build mode: green where the piece can go, red
## where it cannot, and the reason is on the bar.
func _draw_ghost() -> void:
	if build_bar == null or not build_bar.open:
		return
	var t := build_bar.hover_tile
	var at := Vector2(t.x * Config.TILE, t.y * Config.TILE)
	var ok: bool = build_bar.check.ok
	var col := Color("#9fd07a", 0.35) if ok else Color("#c96a5a", 0.3)
	draw_rect(Rect2(at, Vector2(Config.TILE, Config.TILE)), col)
	draw_rect(Rect2(at, Vector2(Config.TILE, Config.TILE)), Color(col.r, col.g, col.b, 0.9), false, 2.0)
	# The reach a piece may be placed within, so "Too far" is visible before
	# it is a refusal.
	var p := sim.players[0]
	draw_arc(p.pos, Config.BUILD.range, 0.0, TAU, 64, Color("#d8e8c0", 0.12), 1.0)
