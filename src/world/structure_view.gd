class_name StructureView
extends Node2D
## Draws everything the player has built, plus the build-mode ghost.
##
## A piece with a picture in `art/world/` is drawn as that picture; one
## without is drawn in code, a slab in its material's colour. Either way the
## street keeps showing what the piece is doing on top — readability first:
## damage darkens it and shows as a bar, and anything that does a job — a
## gate, a turret, a generator, a bed — shows whether it is doing it.

const COLORS := {
	"barricade": "#8a6a3c", "woodWall": "#a3763f", "stoneWall": "#8f8a80",
	"reinforcedWall": "#9a8256", "metalWall": "#9aa2ab", "gate": "#b08a5a",
	"spike": "#8a8078", "workbench": "#b08a5a", "stash": "#a3763f",
	"chest": "#8a6a3c", "locker": "#9aa2ab", "bedroll": "#6f7a52",
	"bunk": "#6f7a52", "watchtower": "#a3763f", "generator": "#71787f",
	"turret": "#5e6a72", "floodlight": "#c9a227", "raisedBed": "#5a4632",
	"longBed": "#5a4632",
}

## What a crop is drawn in, by stage. A garden has to be readable from the
## other side of the compound — the whole point of walking over is knowing
## before you set off whether anything is ready.
const CROP_TINT := {"potato": "#9fd07a", "corn": "#e0c24a", "herbs": "#8fd08a"}

## What damage darkens a piece toward, at most `DAMAGE_DARKEN` of the way.
const DAMAGE_TINT := Color("#2a251c")
const DAMAGE_DARKEN := 0.55

## The turret's head, as a multiple of the tile: its body sits inside the
## mount and the barrel reaches past the tile's edge, where the code-drawn
## barrel always reached.
const TURRET_HEAD := 1.4

var sim: GameSim
## Whose reach the build ring shows.
var player: PlayerSim = null
var build_bar: BuildBar


func _init(sim_: GameSim) -> void:
	sim = sim_
	# The pictures are 128px and a tile is 32: the same shrink the icons get.
	texture_filter = Items.ART_FILTER


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl := inv * Vector2.ZERO - Vector2(96, 96)
	var br := inv * get_viewport_rect().size + Vector2(96, 96)

	for s in sim.structs.list:
		if s.destroyed:
			continue
		var pos: Vector2 = s.pos
		if pos.x < tl.x or pos.y < tl.y or pos.x > br.x or pos.y > br.y:
			continue
		var rect := footprint_rect(s)
		var frac: float = s.hp / s.max_hp
		# Damage darkens the whole piece, so a wall about to fall reads at a
		# glance rather than only in its health bar.
		var dark := (1.0 - frac) * DAMAGE_DARKEN
		var pic := picture_of(s)
		if pic != null:
			var tint := Color.WHITE.lerp(DAMAGE_TINT, dark)
			if s.flash > 0.0:
				# Past white, so a hit lights the picture up the way it lights a slab.
				tint = tint.lerp(Color(2.4, 2.4, 2.4), 0.6)
			_draw_picture(pic, rect, int(s.get("rot", 0)), tint)
		else:
			var body := Color(COLORS.get(s.type, "#8a8f84")).lerp(DAMAGE_TINT, dark)
			if s.flash > 0.0:
				body = body.lerp(Color.WHITE, 0.6)
			_draw_shape(s, rect, body)
		_draw_state(s, rect, pic != null, font)

		if frac < 0.999:
			var w := rect.size.x - 6.0
			draw_rect(Rect2(pos.x - w / 2.0, rect.position.y - 6.0, w, 3.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(pos.x - w / 2.0, rect.position.y - 6.0, w * frac, 3.0),
				Color("#9fd07a") if frac > 0.5 else Color("#e05a4a"))

	_draw_ghost()


## The tiles a piece stands on, in world pixels.
static func footprint_rect(s: Dictionary) -> Rect2:
	var f := Structures.footprint(s.type, int(s.get("rot", 0)))
	return Rect2(Vector2(s.tx, s.ty) * Config.TILE, Vector2(f) * Config.TILE)


## The picture a piece is drawn as right now, or null to draw it in code.
static func picture_of(s: Dictionary) -> Texture2D:
	if s.type == "gate" and s.open:
		return Structures.world_art_of("gate", "open")
	return Structures.world_art_of(s.type)


## A picture fitted inside its tiles without stretching. A turned piece's
## picture is the lying-flat one, drawn a quarter turn round.
func _draw_picture(tex: Texture2D, rect: Rect2, rot: int, tint: Color) -> void:
	if rot % 2 == 0:
		draw_texture_rect(tex, Items.art_rect(tex, rect), false, tint)
		return
	var flat := Rect2(-Vector2(rect.size.y, rect.size.x) / 2.0, Vector2(rect.size.y, rect.size.x))
	draw_set_transform(rect.get_center(), PI / 2.0)
	draw_texture_rect(tex, Items.art_rect(tex, flat), false, tint)
	draw_set_transform(Vector2.ZERO)


## A piece with no picture: shapes in its colour, as the street always drew it.
func _draw_shape(s: Dictionary, rect: Rect2, body: Color) -> void:
	var pos: Vector2 = s.pos
	var half := Config.TILE * 0.5
	match s.type:
		"gate":
			if s.open:
				# Swung open: two posts and a gap you can walk through.
				draw_rect(Rect2(pos - Vector2(half, half), Vector2(5, Config.TILE)), body)
				draw_rect(Rect2(pos + Vector2(half - 5, -half), Vector2(5, Config.TILE)), body)
			else:
				draw_rect(rect, body)
				draw_line(pos + Vector2(-half, -half), pos + Vector2(half, half), Color(0, 0, 0, 0.35), 2.0)
		"spike":
			for i in range(4):
				var x: float = pos.x - half + 5 + i * 7
				draw_polygon([Vector2(x, pos.y + 8), Vector2(x + 5, pos.y + 8), Vector2(x + 2.5, pos.y - 9)],
					PackedColorArray([body, body, body]))
		"bedroll":
			draw_rect(Rect2(pos - Vector2(half - 3, half - 6), Vector2(Config.TILE - 6, Config.TILE - 12)), body)
		"floodlight":
			draw_circle(pos, 8.0, body)
		"turret", "generator":
			draw_rect(rect.grow(-2.0), body)
		_:
			if Farming.is_bed(s):
				# A frame of boards and soil that darkens when it is wet.
				draw_rect(rect.grow(-1.0), body)
				draw_rect(rect.grow(-5.0), Color("#3a2c1c").lerp(Color("#241a10"), Farming.water_frac(s)))
				return
			var inset: float = 1.0 if s.def.get("wall", false) else 3.0
			draw_rect(rect.grow(-inset), body)
			if s.store != null:
				draw_rect(rect.grow(-7.0), Color(0, 0, 0, 0.3))


## What a piece is doing, drawn over whichever of the two it looks like.
func _draw_state(s: Dictionary, rect: Rect2, pictured: bool, font: Font) -> void:
	var pos: Vector2 = s.pos
	if Farming.is_bed(s):
		_draw_crop(s, rect, pictured)
		return
	match s.type:
		"bedroll":
			if s.active:
				draw_arc(pos, 14.0, 0.0, TAU, 20, Color("#9fd0ff", 0.8), 1.5)
		"floodlight":
			if s.powered:
				draw_arc(pos, s.def.light_radius * 0.25, 0.0, TAU, 28, Color("#ffe6a8", 0.25), 2.0)
		"turret":
			var head := Structures.world_art_of("turret", "head") if pictured else null
			if head != null:
				# The mount stands still and the head turns to where it aims.
				# An unpowered head goes grey, as the drawn barrel did.
				var side := Config.TILE * TURRET_HEAD
				draw_set_transform(pos, s.aim)
				draw_texture_rect(head, Rect2(-Vector2(side, side) / 2.0, Vector2(side, side)), false,
					Color.WHITE if s.powered else Color(0.55, 0.55, 0.55))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_line(pos, pos + Vector2.from_angle(s.aim) * 20.0, Color("#cfd6dd") if s.powered else Color("#5a5f58"), 3.0)
			if s.starved:
				draw_string(font, pos + Vector2(-30, -18), "NO 9MM", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color("#c96a5a"))
			elif not s.powered:
				draw_string(font, pos + Vector2(-30, -18), "NO POWER", HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color("#c96a5a"))
		"generator":
			if s.running:
				draw_arc(pos, 10.0 + sin(sim.time * 6.0) * 1.5, 0.0, TAU, 16, Color("#d2762c", 0.5), 2.0)
				draw_arc(pos, s.def.power_radius, 0.0, TAU, 48, Color("#59b8c4", 0.07), 1.0)
		"workbench":
			if s.tier >= 2:
				draw_string(font, pos + Vector2(-16, -12), "II", HORIZONTAL_ALIGNMENT_CENTER, 32, 10, Color("#59b8c4"))


## A bed's crop, growing out of the soil in four steps: three shoots per tile,
## each taller by stage, so a row of beds reads as a progress bar without
## carrying one. Ready gets a ring, the way an active bedroll does, because
## "is anything ready" is the question you ask the garden from across the base.
func _draw_crop(s: Dictionary, rect: Rect2, pictured: bool) -> void:
	var pos: Vector2 = s.pos
	if pictured:
		# The picture's soil is dry soil; water darkens it, as it does the
		# drawn soil. Inside the frame boards only.
		var wet := Farming.water_frac(s)
		if wet > 0.0:
			var frame := minf(rect.size.x, rect.size.y) * 0.16
			draw_rect(rect.grow(-frame), Color(0.08, 0.05, 0.02, 0.45 * wet))
	if not Farming.planted(s):
		return
	var crop: Dictionary = Farming.crop_of(s)
	var tint := Color(CROP_TINT.get(String(crop.crop), "#9fd07a"))
	var st := Farming.stage(s)
	var h: float = 2.0 + st * 3.6
	var along := rect.size.x >= rect.size.y
	var length := rect.size.x if along else rect.size.y
	var count := 3 * roundi(length / Config.TILE)
	# Down a turned bed the shoots grow along the row, so the row is shorter
	# by a shoot's height or the top one stands out of the frame.
	var step := (length - (18.0 if along else 24.0)) / maxf(1.0, count - 1)
	for i in range(count):
		var off := -step * (count - 1) / 2.0 + i * step
		# And they zigzag, or each would stand in the last.
		var base := pos + (Vector2(off, 8.0) if along else Vector2(-4.0 if i % 2 == 0 else 4.0, off + h / 2.0))
		draw_line(base, base - Vector2(0, h), tint.darkened(0.35 - st * 0.1), 2.0)
		# A tip at every stage, not only the last two: a bed sown this morning
		# has to look different from one standing empty, or the row lies about
		# what is in it.
		draw_circle(base - Vector2(0, h), 1.2 + st * 0.8, tint)
	if Farming.ready(s):
		draw_arc(pos, 15.0 * maxf(rect.size.x, rect.size.y) / Config.TILE, 0.0, TAU, 28, Color(tint, 0.75), 1.5)


## The tiles under the cursor in build mode: green where the piece can go, red
## where it cannot, and the reason is on the bar. A piece with a picture shows
## it, faintly, lying the way it will be built.
func _draw_ghost() -> void:
	if build_bar == null or not build_bar.placing():
		return
	var t := build_bar.hover_tile
	# A faint grid round the cursor, so where a piece lands reads as a tile
	# rather than as wherever the mouse happens to be.
	var tile := Vector2(Config.TILE, Config.TILE)
	for dy in range(-2, 3):
		for dx in range(-3, 4):
			draw_rect(Rect2(Vector2((t.x + dx) * Config.TILE, (t.y + dy) * Config.TILE), tile), Color("#d8e8c0", 0.18), false, 1.0)
	var card := build_bar.selected_card()
	var rot := build_bar.rot_for(card)
	var area := Rect2(Vector2(t) * Config.TILE, tile)
	if Config.STRUCTURES.has(card):
		area.size = Vector2(Structures.footprint(card, rot)) * Config.TILE
	var ok: bool = build_bar.check.ok
	var edge := Color("#9fd07a") if ok else Color("#c8423a")
	draw_rect(area, Color(edge, 0.28))
	var pic := Structures.world_art_of(card) if Config.STRUCTURES.has(card) else null
	if pic != null:
		_draw_picture(pic, area, rot, Color(1, 1, 1, 0.55))
	draw_rect(area.grow(-1.0), edge, false, 2.0)
	# The reach a piece may be placed within, so "Too far" is visible before
	# it is a refusal.
	var p: PlayerSim = player if player != null else sim.players[0]
	draw_arc(p.pos, Config.BUILD.range, 0.0, TAU, 64, Color("#d8e8c0", 0.12), 1.0)
