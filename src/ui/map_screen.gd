class_name MapScreen
extends Control
## The minimap in the corner and the town map behind `M`, drawn from one place.
##
## They are the same picture at two sizes with two levels of detail, so they
## are one Control and one `_draw`: a marker that appears on one and not the
## other is a bug, and having two functions is how you get one.
##
## The ground is a 320x320 image — one pixel per tile — built once per world
## and cached against the generator's fingerprint. Rebuilding it every frame
## would be a hundred thousand pixels of GDScript; rebuilding it never would
## leave the old town on screen after a load.

const PAD := 16.0
## Danger tiers 1-4, matching the HUD.
const TIER_COLORS := [Color("#8fae6a"), Color("#8fae6a"), Color("#d9c46a"), Color("#d98a4a"), Color("#e05a4a")]

var sim: GameSim
## Whose map this is: the local player, whatever seat they hold.
var player: PlayerSim = null
## Full screen rather than the corner.
var open := false

var _tex: ImageTexture = null
var _tex_for := 0


func _init(sim_: GameSim) -> void:
	sim = sim_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The corner map is scenery; the open map is a wall. Neither is clickable,
	# so neither takes the mouse away from the gun.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_dt: float) -> void:
	queue_redraw()


func toggle() -> void:
	open = not open
	queue_redraw()


# ------------------------------------------------------------------ ground --

## One pixel per tile, tinted by danger so the map itself says where not to go,
## and darkened where the ground is solid so the water and the walls read as
## shape rather than colour. Cached on the world's fingerprint: a new game or a
## load rebuilds it, a thousand frames do not. Measured at 41ms — one dropped
## frame inside the boot or the load it already belongs to, and never again.
func _ground() -> ImageTexture:
	var fp := sim.world.gen_fingerprint
	if _tex != null and _tex_for == fp:
		return _tex
	var w := World.W
	var h := World.W
	var data := PackedByteArray()
	data.resize(w * h * 3)
	var tint: float = Config.MAP.danger_tint
	var shade: float = Config.MAP.blocked_shade
	for i in range(w * h):
		var pal: Dictionary = Config.TERRAIN.get(sim.world.tiles[i], Config.TERRAIN[Config.T.GRASS])
		var c: Color = pal.a
		var r := c.r * 255.0
		var g := c.g * 255.0
		var b := c.b * 255.0
		var d := int(sim.world.danger[i])
		if d > 1:
			r = minf(255.0, r + (d - 1) * tint)
			g = maxf(0.0, g - (d - 1) * tint * 0.31)
			b = maxf(0.0, b - (d - 1) * tint * 0.31)
		if sim.world.blocked[i] != 0 and sim.world.tiles[i] != Config.T.WALL:
			r *= shade
			g *= shade
			b *= shade
		data[i * 3] = int(r)
		data[i * 3 + 1] = int(g)
		data[i * 3 + 2] = int(b)
	_tex = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGB8, data))
	_tex_for = fp
	return _tex


# ------------------------------------------------------------------- draw --

func _draw() -> void:
	if sim == null or sim.players.is_empty():
		return
	var vp := get_viewport_rect().size
	var rect: Rect2
	if open:
		var size := minf(vp.x - 120.0, vp.y - 140.0)
		rect = Rect2((vp.x - size) / 2.0, (vp.y - size) / 2.0, size, size)
		draw_rect(Rect2(Vector2.ZERO, vp), Color("#060805", 0.86))
	else:
		var size: float = Config.MAP.corner
		rect = Rect2(vp.x - size - PAD, vp.y - size - PAD, size, size)

	draw_rect(rect.grow(4.0), Color("#0a0e08", 0.85))
	draw_rect(rect.grow(3.5), Color("#3a4433"), false, 2.0)
	draw_texture_rect(_ground(), rect, false, Color(1, 1, 1, 0.9 if not open else 1.0))

	var scale := rect.size.x / Config.WORLD_SIZE
	_draw_markers(rect, scale)
	if open:
		_draw_districts(rect, scale)

	var font := ThemeDB.fallback_font
	if open:
		draw_string(font, rect.position + Vector2(0, -14), "TOWN MAP  —  %s to close" % KeyBinds.primary_label("map"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("#ebe6d6"))
	else:
		draw_string(font, rect.position + Vector2(0, -6), "%s — MAP" % KeyBinds.primary_label("map"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#8a8f84"))


## Everything that moves. Drawn in the order things matter when they overlap:
## the ground truth of what you built, then what is lying about, then people,
## then the things trying to kill you, then you.
func _draw_markers(rect: Rect2, scale: float) -> void:
	var p: PlayerSim = player if player != null else sim.players[0]
	var big := 1.0 if open else 0.0
	var to := func(v: Vector2) -> Vector2: return rect.position + v * scale

	for s in sim.structs.list:
		if s.destroyed:
			continue
		var c := Color("#59b8c4") if s.def.get("protect", false) else Color("#b7e08a")
		draw_rect(Rect2(to.call(s.pos) - Vector2.ONE * (1.0 + big * 0.5), Vector2.ONE * (2.0 + big)), c)

	for b in sim.backpacks:
		draw_circle(to.call(b.pos), 3.0 + big * 2.0, Color("#e8c86a"))

	for s in sim.crew.list:
		if s.dead:
			continue
		draw_circle(to.call(s.pos), 2.4 + big, Color("#c96a5a") if s.downed else Color("#9fd0ff"))

	for e in _revealed(p):
		var c := Color("#ff5a4a") if e.raid else (Color("#d9705a") if e.aggro else Color("#8a5a4a"))
		draw_rect(Rect2(to.call(e.pos) - Vector2.ONE * (1.0 + big * 0.5), Vector2.ONE * (2.0 + big)), c)

	# The raid, pulsing, so a horde on its way to your base is the loudest
	# thing on the map.
	if sim.raid != null and sim.raid.has_base:
		draw_arc(to.call(sim.raid.centre), 8.0 + sin(sim.time * 4.0) * 3.0, 0.0, TAU, 24, Color("#ff5a4a"), 1.0)

	# Teammates in their ring colours, then you in white on top.
	for q in sim.players:
		if q == p or q.away or q.dead:
			continue
		var at: Vector2 = to.call(q.pos)
		draw_circle(at, 2.6 + big, Color(Config.PLAYER.colors[q.seat % Config.PLAYER.colors.size()]))
		if open:
			draw_string(ThemeDB.fallback_font, at + Vector2(-40, -6), q.display_name, HORIZONTAL_ALIGNMENT_CENTER, 80, 9,
				Color(Config.PLAYER.colors[q.seat % Config.PLAYER.colors.size()]))
	var me: Vector2 = to.call(p.pos)
	draw_circle(me, 2.6 + big, Color.WHITE)
	draw_line(me, me + Vector2.from_angle(p.angle) * (8.0 + big * 4.0), Color(1, 1, 1, 0.67), 1.4)


## The enemies the map is allowed to show. Near ones, further out for the ones
## that have already noticed you, and the whole thing scaled by `radar_mul` —
## which is Sixth Sense, and the only reason that perk is worth six Perception.
func _revealed(p: PlayerSim) -> Array:
	var aware: float = Config.MAP.aware * p.radar_mul
	var unaware: float = Config.MAP.unaware * p.radar_mul
	var aware2 := aware * aware
	var unaware2 := unaware * unaware
	var out: Array = []
	for e in sim.enemies.list:
		if e.dead:
			continue
		var d := p.pos.distance_squared_to(e.pos)
		if d <= (aware2 if (e.aggro or e.raid) else unaware2):
			out.append(e)
	return out


## The districts, named once you have stood in one. An undiscovered rect is
## still drawn — you can see there is *somewhere* there — but not what it is or
## what it costs to walk in, which is the whole reason to go and look.
func _draw_districts(rect: Rect2, scale: float) -> void:
	var font := ThemeDB.fallback_font
	for l in sim.world.locations:
		var r: Rect2i = l.rect
		var box := Rect2(rect.position + Vector2(r.position) * Config.TILE * scale,
			Vector2(r.size) * Config.TILE * scale)
		draw_rect(box, Color(0.71, 0.82, 0.59, 0.5) if l.discovered else Color(0.47, 0.51, 0.43, 0.28), false, 1.0)
		var at: Vector2i = l.get("label", Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2))
		var c := rect.position + Vector2(at) * Config.TILE * scale
		var tier := int(l.tier)
		draw_string(font, c - Vector2(70, 0), String(l.name) if l.discovered else "? ? ?",
			HORIZONTAL_ALIGNMENT_CENTER, 140, 11,
			TIER_COLORS[tier] if l.discovered else Color(0.55, 0.59, 0.51, 0.55))
		if l.discovered:
			draw_string(font, c - Vector2(70, -12), "DANGER " + "▲".repeat(tier),
				HORIZONTAL_ALIGNMENT_CENTER, 140, 9, Color(0.78, 0.82, 0.71, 0.55))
