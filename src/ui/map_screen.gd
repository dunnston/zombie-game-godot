class_name MapScreen
extends Control
## The minimap in the corner and the town map behind `M`, drawn from one place.
##
## They are the same picture at two sizes with two levels of detail — one
## `MapView` class, so a marker that appears on one and not the other is a bug
## rather than a second function drifting. The open map sits in the same
## frame as every other full screen, with a legend, where you are and the
## districts found, and nothing on the map itself is clickable: it never takes
## the mouse away from the gun.
##
## The ground is a 320x320 image — one pixel per tile — built once per world
## and cached against the generator's fingerprint. Rebuilding it every frame
## would be a hundred thousand pixels of GDScript; rebuilding it never would
## leave the old town on screen after a load.

signal navigate(to: String)

## What the map draws everything in. Structures that guard, walls and traps,
## a dropped pack, the crew, and the three kinds of enemy.
const C_PROTECT := Color("#59b8c4")
const C_BUILT := Color("#b7e08a")
const C_PACK := Color("#e8c86a")
const C_CREW := Color("#c48fd0")
const C_CREW_DOWN := Color("#c96a5a")
const C_WANDER := Color("#8a5a4a")
const C_AWARE := Color("#d9705a")
const C_RAID := Color("#ff5a4a")

var sim: GameSim
## Whose map this is: the local player, whatever seat they hold.
var player: PlayerSim = null
## Full screen rather than the corner.
var open := false

var corner: MapView
var _page: Control = null
var _page_sig := ""
var _refreshers: Array[Callable] = []
var _tex: ImageTexture = null
var _tex_for := 0


func _init(sim_: GameSim) -> void:
	sim = sim_
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Ui.theme()
	corner = MapView.new(self, false)
	var s: float = Config.MAP.corner
	corner.custom_minimum_size = Vector2(s, s)
	add_child(corner)
	# Anchored to the bottom-right corner by explicit offsets: a 260px square
	# 24px in from both edges, whatever size the window is.
	corner.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	corner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	corner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	corner.offset_left = -(s + Ui.MARGIN)
	corner.offset_top = -(s + Ui.MARGIN)
	corner.offset_right = -Ui.MARGIN
	corner.offset_bottom = -Ui.MARGIN


func _process(_dt: float) -> void:
	if sim == null or sim.players.is_empty():
		return
	corner.visible = not open
	corner.queue_redraw()
	if open:
		_refresh_page()


func toggle() -> void:
	open = not open
	if not open and _page != null:
		_page.queue_free()
		_page = null
		_page_sig = ""


func me() -> PlayerSim:
	return player if player != null else sim.players[0]


# ------------------------------------------------------------------ ground --

## One pixel per tile, tinted by danger so the map itself says where not to go,
## and darkened where the ground is solid so the water and the walls read as
## shape rather than colour. Cached on the world's fingerprint: a new game or a
## load rebuilds it, a thousand frames do not.
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


# -------------------------------------------------------------------- page --

func _refresh_page() -> void:
	var found := 0
	for l in sim.world.locations:
		if l.discovered:
			found += 1
	var sig := "%d|%d|%s" % [found, sim.world.locations.size(), KeyBinds.primary_label("map")]
	if _page == null or sig != _page_sig:
		_page_sig = sig
		if _page != null:
			_page.queue_free()
		_build_page(found)
	for r in _refreshers:
		r.call()


func _build_page(found: int) -> void:
	_refreshers.clear()
	_page = Control.new()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)
	var col := Chrome.root(_page, Color("#060805"))
	var key := KeyBinds.primary_label("map")

	var clock := Ui.label("", "Mono", Ui.TEXT_HIGH)
	var phase := Ui.label("", "Caps", Ui.NIGHT)
	var readout := Ui.vbox(3, [clock, phase])
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_refreshers.append(func() -> void:
		Ui.set_text(clock, "DAY %d  ·  %s" % [sim.clock.day, sim.clock.clock_string()])
		Ui.set_text(phase, sim.clock.phase_name()))
	col.add_child(Chrome.tab_bar("map", Chrome.TABS, [readout, Ui.keycap(key, "Close")],
		func(id: String) -> void: navigate.emit(id)))

	var body := Chrome.body(24)
	col.add_child(Chrome.body_margin(body))

	# The map, as big a square as the column allows.
	var total := sim.world.locations.size()
	var left := Ui.vbox(14, [Ui.hbox(16, [Ui.label("Town map", "PanelTitle"),
		Ui.label("%d districts  ·  %d discovered  ·  the ground itself is tinted by danger" % [total, found], "Body14", Ui.TEXT_DIM)])])
	(left.get_child(0).get_child(1) as Control).size_flags_vertical = Control.SIZE_SHRINK_END
	var view := MapView.new(self, true)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(view)
	Ui.expand(left, true, true)
	body.add_child(left)
	_refreshers.append(func() -> void: view.queue_redraw())

	var right := Ui.vbox(16, [_here_panel(), _legend_panel(), _districts_panel()])
	var rs := Ui.scroller(right)
	rs.custom_minimum_size.x = 420
	rs.size_flags_horizontal = Control.SIZE_FILL
	body.add_child(rs)

	col.add_child(Chrome.footer([],
		"The map is a readout, not a tool — nothing here is clickable, so it never takes the mouse away from the gun."))
	(col.get_child(col.get_child_count() - 1).get_child(0) as HBoxContainer).add_child(Ui.hint(key, "Close"))


func _here_panel() -> PanelContainer:
	var name_l := Ui.label("", "PanelTitle")
	var pips := UiPips.new(4, Vector2(9, 9), Ui.TIER_COLORS[1], Color(1, 1, 1, 0.18), 5)
	pips.diamond = true
	pips._resize()
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var tier_l := Ui.label("", "Mono")
	var built := Ui.label("", "Mono14", Ui.TEXT_HIGH)
	var boxes := Ui.label("", "Mono14", Ui.TEXT_HIGH)
	var out := Ui.label("", "Mono14", Ui.TEXT_HIGH)
	var row := func(t: String, v: Label) -> HBoxContainer:
		return Ui.hbox(8, [Ui.expand(Ui.label(t, "Body14")), v])
	var content := Ui.vbox(10, [name_l, Ui.hbox(10, [Ui.label("Danger", "Caps"), pips, tier_l]), Ui.rule(),
		row.call("Your structures", built), row.call("Containers left here", boxes), row.call("Crew out of the base", out)])
	_refreshers.append(func() -> void:
		var p := me()
		var loc := sim.world.location_at_px(p.pos.x, p.pos.y)
		var tier := sim.world.danger_at_px(p.pos.x, p.pos.y)
		Ui.set_text(name_l, String(loc.name) if not loc.is_empty() else "The Outskirts")
		pips.set_filled(tier, Ui.TIER_COLORS[clampi(tier, 1, 4)])
		Ui.set_text(tier_l, "TIER %d" % tier)
		Ui.set_color(tier_l, Ui.TIER_COLORS[clampi(tier, 1, 4)])
		var n := 0
		for s in sim.structs.list:
			if not s.destroyed:
				n += 1
		Ui.set_text(built, str(n))
		var left := 0
		if not loc.is_empty():
			var r: Rect2i = loc.rect
			for c in sim.world.containers:
				if not c.looted and r.has_point(Vector2i(int(c.tx), int(c.ty))):
					left += 1
		Ui.set_text(boxes, str(left) if not loc.is_empty() else "—")
		var away := 0
		for s in sim.crew.alive():
			if not sim.structs.in_base(s.pos):
				away += 1
		Ui.set_text(out, str(away)))
	return Ui.panel("Pane", Ui.vbox(0, [Ui.head("You are here"), Ui.pad(content, 18, 16, 18, 16)]))


func _legend_panel() -> PanelContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	var mate: Color = Color(Config.PLAYER.colors[1 % Config.PLAYER.colors.size()])
	for e in [[Color.WHITE, "You", true], [mate, "Teammate", true], [C_CREW, "Crew", true], [C_CREW_DOWN, "Crew down", true],
			[C_PROTECT, "Bench, stash, tower", false], [C_BUILT, "Wall or trap", false], [C_PACK, "Dropped pack", true],
			[C_WANDER, "Wandering dead", false], [C_AWARE, "Has noticed you", false], [C_RAID, "Raid", false]]:
		var dot := Legend.new(e[0], e[2])
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var cell := Ui.hbox(10, [dot, Ui.label(String(e[1]), "Small", Ui.TEXT_BODY)])
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(cell)
	var note := Ui.para("The map shows the dead you are close to, further out once they have noticed you. Sixth Sense widens both.",
		"Small", Color(1, 1, 1, 0.4))
	return Ui.panel("Pane", Ui.vbox(0, [Ui.head("Legend"), Ui.pad(Ui.vbox(14, [grid, note]), 18, 16, 18, 16)]))


func _districts_panel() -> PanelContainer:
	var list := Ui.vbox(8)
	var known: Array = []
	var unseen := 0
	for l in sim.world.locations:
		if l.discovered:
			known.append(l)
		else:
			unseen += 1
	known.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.tier) < int(b.tier))
	for l in known:
		var tier := int(l.tier)
		list.add_child(Ui.hbox(12, [Ui.rect(Ui.TIER_COLORS[clampi(tier, 1, 4)], 10, 10),
			Ui.expand(Ui.label(String(l.name), "Body14")), Ui.label("TIER %d" % tier, "Mono12")]))
	if unseen > 0:
		var row := Ui.hbox(12, [Ui.rect(Ui.TEXT_OFF, 10, 10),
			Ui.expand(Ui.label("%d district%s unseen" % [unseen, "" if unseen == 1 else "s"], "Body14", Ui.TEXT_DIM)),
			Ui.label("? ? ?", "Mono12", Ui.TEXT_OFF)])
		row.modulate.a = 0.5
		list.add_child(row)
	for r in list.get_children():
		(r.get_child(0) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return Ui.panel("Inset", Ui.vbox(10, [Ui.label("Districts", "Caps"), list]))


## One swatch in the legend: a dot for people and packs, a square for things.
class Legend extends Control:
	var c: Color
	var round_ := false

	func _init(col: Color, is_round: bool) -> void:
		c = col
		round_ = is_round
		custom_minimum_size = Vector2(9, 9)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if round_:
			draw_circle(size / 2.0, 4.5, c)
		else:
			draw_rect(Rect2(Vector2(0.5, 0.5), Vector2(8, 8)), c)


## The picture itself, at either size. Big draws the districts and names; both
## draw every marker, in the order things matter when they overlap.
class MapView extends Control:
	var owner_: MapScreen
	var big := false

	func _init(o: MapScreen, is_big: bool) -> void:
		owner_ = o
		big = is_big
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var sim := owner_.sim
		if sim == null or sim.players.is_empty():
			return
		var side := minf(size.x, size.y)
		var rect := Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side))
		if big:
			rect = rect.grow(-2.0)
		draw_rect(rect.grow(2.0), Color("#0a0e08"))
		draw_texture_rect(owner_._ground(), rect, false, Color(1, 1, 1, 1.0 if big else 0.9))
		draw_rect(rect.grow(1.0), Color("#3a4433"), false, 2.0)
		var scale := rect.size.x / Config.WORLD_SIZE
		if big:
			_districts(rect, scale)
		_markers(rect, scale)
		var f := Ui.font("mono", 500)
		if not big:
			var txt := "%s — MAP" % KeyBinds.primary_label("map")
			draw_rect(Rect2(rect.position + Vector2(4, rect.size.y - 22), Vector2(f.get_string_size(txt, 0, -1, 12).x + 8, 18)),
				Color(Ui.VOID, 0.7))
			draw_string(f, rect.position + Vector2(8, rect.size.y - 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.TEXT_DIM)
		else:
			var note := "GROUND IMAGE — ONE PIXEL PER TILE, BUILT FROM THE WORLD GENERATOR"
			var w := f.get_string_size(note, 0, -1, 12).x + 20
			var at := rect.position + Vector2(16, rect.size.y - 42)
			Ui.box(Color(Ui.VOID, 0.82), Ui.LINE, 1, 0).draw(get_canvas_item(), Rect2(at, Vector2(w, 26)))
			draw_string(f, at + Vector2(10, 17), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Ui.TEXT_DIM)

	func _markers(rect: Rect2, scale: float) -> void:
		var sim := owner_.sim
		var p := owner_.me()
		var k := 1.0 if big else 0.0
		var to := func(v: Vector2) -> Vector2: return rect.position + v * scale

		for s in sim.structs.list:
			if s.destroyed:
				continue
			var c := MapScreen.C_PROTECT if s.def.get("protect", false) else MapScreen.C_BUILT
			draw_rect(Rect2(to.call(s.pos) - Vector2.ONE * (1.0 + k * 1.5), Vector2.ONE * (2.0 + k * 3.0)), c)
		for b in sim.backpacks:
			draw_circle(to.call(b.pos), 3.0 + k * 2.0, MapScreen.C_PACK)
		for s in sim.crew.list:
			if s.dead:
				continue
			draw_circle(to.call(s.pos), 2.4 + k * 1.6, MapScreen.C_CREW_DOWN if s.downed else MapScreen.C_CREW)
		for e in owner_._revealed(p):
			var c := MapScreen.C_RAID if e.raid else (MapScreen.C_AWARE if e.aggro else MapScreen.C_WANDER)
			draw_rect(Rect2(to.call(e.pos) - Vector2.ONE * (1.0 + k * 1.5), Vector2.ONE * (2.0 + k * 3.0)), c)
		# The raid, pulsing, so a horde on its way to your base is the loudest
		# thing on the map.
		if sim.raid != null and sim.raid.has_base:
			var at: Vector2 = to.call(sim.raid.centre)
			var r := (8.0 + sin(sim.time * 4.0) * 3.0) * (1.0 + k * 3.0)
			draw_arc(at, r, 0.0, TAU, 32, Color(MapScreen.C_RAID, 0.55 if big else 1.0), 2.0 if big else 1.0)
			if big:
				draw_string(Ui.font("ui", 600, 1), at + Vector2(-r, -r - 8), "HORDE  ·  HEADING FOR THE BASE",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MapScreen.C_RAID)
		for q in sim.players:
			if q == p or q.away or q.dead:
				continue
			var at: Vector2 = to.call(q.pos)
			var qc := Color(Config.PLAYER.colors[q.seat % Config.PLAYER.colors.size()])
			draw_circle(at, 2.6 + k * 1.4, qc)
			if big:
				draw_string(Ui.font("mono", 500), at + Vector2(-60, -8), q.display_name.to_upper(),
					HORIZONTAL_ALIGNMENT_CENTER, 120, 12, qc)
		var me: Vector2 = to.call(p.pos)
		draw_circle(me, 2.6 + k * 2.0, Color.WHITE)
		draw_line(me, me + Vector2.from_angle(p.angle) * (8.0 + k * 6.0), Color(1, 1, 1, 0.67), 1.4)

	## The districts, named once you have stood in one. An undiscovered rect is
	## still drawn — you can see there is somewhere there — but not what it is.
	func _districts(rect: Rect2, scale: float) -> void:
		var sim := owner_.sim
		var name_f := Ui.font("display", 500, 1)
		var mono := Ui.font("mono", 500)
		var caps := Ui.font("ui", 600, 1)
		var base: Dictionary = sim.structs.base_centre()
		for l in sim.world.locations:
			var r: Rect2i = l.rect
			var box := Rect2(rect.position + Vector2(r.position) * Config.TILE * scale,
				Vector2(r.size) * Config.TILE * scale)
			draw_rect(box, Color(0.71, 0.82, 0.59, 0.5) if l.discovered else Color(0.47, 0.51, 0.43, 0.28), false, 1.0)
			var tier := int(l.tier)
			var at := box.position + Vector2(8, 18)
			var w := maxf(40.0, box.size.x - 12.0)
			if l.discovered:
				draw_string(name_f, at, String(l.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w, 15, Ui.TIER_COLORS[clampi(tier, 1, 4)])
				draw_string(mono, at + Vector2(0, 16), "DANGER " + "▲".repeat(tier), HORIZONTAL_ALIGNMENT_LEFT, w, 12,
					Color(0.78, 0.82, 0.71, 0.6))
				if not base.is_empty() and box.has_point(rect.position + Vector2(base.get("pos", Vector2.ZERO)) * scale):
					draw_string(caps, at + Vector2(0, 32), "YOUR BASE", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Ui.ACCENT)
			else:
				draw_string(name_f, at, "? ? ?", HORIZONTAL_ALIGNMENT_LEFT, w, 15, Color(0.55, 0.59, 0.51, 0.55))
				draw_string(mono, at + Vector2(0, 16), "UNDISCOVERED", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(0.55, 0.59, 0.51, 0.45))
