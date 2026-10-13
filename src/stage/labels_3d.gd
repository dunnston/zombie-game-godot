class_name Labels3D
extends Node2D
## Every word and bar over the 3D stage: names and health over people, what
## a car or a piece is doing, what a pile on the ground is, the door's
## title, the reach ring in build mode. The 2D views drew these on the
## canvas beside the body; here the body is in the world and the words stay
## on the screen, at the point the camera puts the top of that body.
## Sizes are the 2D sizes scaled by what the 2D zoom gave them at 1080p.

const SCALE := 1.6

var sim: GameSim
var stage: Stage3D
var local: PlayerSim
var build_bar: BuildBar


func _init(sim_: GameSim, stage_: Stage3D) -> void:
	sim = sim_
	stage = stage_


func _draw() -> void:
	var font := ThemeDB.fallback_font
	_players(font)
	_enemies(font)
	_survivors(font)
	_vehicles(font)
	_pickups(font)
	_structures(font)
	_doors(font)
	_build_reach()


func _bar(at: Vector2, w: float, frac: float, fill: Color) -> void:
	draw_rect(Rect2(at.x - w / 2.0, at.y, w, 4.0), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(at.x - w / 2.0, at.y, w * clampf(frac, 0.0, 1.0), 4.0), fill)


func _text(font: Font, at: Vector2, s: String, size: int, color: Color, width := 160.0) -> void:
	var px := roundi(size * SCALE)
	draw_string(font, at + Vector2(-width / 2.0 + 1, 1), s, HORIZONTAL_ALIGNMENT_CENTER, width, px, Color(0, 0, 0, color.a * 0.7))
	draw_string(font, at + Vector2(-width / 2.0, 0), s, HORIZONTAL_ALIGNMENT_CENTER, width, px, color)


func _players(font: Font) -> void:
	for p in sim.players:
		if p.away:
			continue
		var c := Util.render_pos(p.prev_pos, p.pos)
		var head := stage.to_screen_h(c, 1.95)
		var ring := Color(Config.PLAYER.colors[p.seat % Config.PLAYER.colors.size()])
		var is_local := p == local
		if p.dead:
			continue
		if p.downed:
			var who := "YOU" if is_local else p.display_name
			_text(font, head, "%s — DOWN" % who, 10, Color("#e05a4a"))
			_bar(head + Vector2(0, 18), 40.0, p.down_t / Config.PLAYER.downed_time, Color("#e05a4a"))
			continue
		var y := head.y
		if not is_local:
			_text(font, Vector2(head.x, y - 16), p.display_name, 10, ring)
			if p.hp < p.max_hp:
				_bar(Vector2(head.x, y), 44.0, p.hp / p.max_hp, Color("#c8423a"))
		if not p.reloading.is_empty():
			_bar(Vector2(head.x, y + 8), 44.0, p.reloading.t / p.reloading.dur, Color("#ffe6a8"))
		elif not p.using.is_empty():
			_bar(Vector2(head.x, y + 8), 44.0, p.using.t / p.using.dur, Color("#7ce08a"))
		elif not p.reviving.is_empty():
			_bar(Vector2(head.x, y + 8), 44.0, p.reviving.t / p.reviving.dur, Color("#9fd0ff"))


func _enemies(_font: Font) -> void:
	for e in sim.enemies.list:
		if e.dead:
			continue
		var c := Util.render_pos(e.prev_pos, e.pos)
		if not _on_screen(c):
			continue
		var h := clampf(Units.m(e.r) * 4.2, 1.2, 2.6) + 0.25
		var head := stage.to_screen_h(c, h)
		if e.raid:
			draw_circle(head + Vector2(0, -8), 3.0, Color("#e05a4a"))
		if e.hp < e.max_hp:
			_bar(head, maxf(28.0, e.r * 2.6), e.hp / e.max_hp, Color("#c8423a"))


func _survivors(font: Font) -> void:
	var R := float(Config.SURVIVOR.r)
	for rescue in sim.crew.rescues:
		var at: Vector2 = rescue.pos
		if _on_screen(at):
			_text(font, stage.to_screen_h(at, 1.9), String(rescue.name), 10, Color("#b7e08a"))
	for s in sim.crew.list:
		if s.dead:
			continue
		var c := Util.render_pos(s.prev_pos, s.pos)
		if not _on_screen(c):
			continue
		var head := stage.to_screen_h(c, 1.95)
		var job: Dictionary = Config.JOBS.get(s.job, Config.JOBS.guard)
		var ring := Color(String(job.color))
		if s.downed:
			_text(font, head, "%s — help" % s.display_name, 10, Color("#e05a4a"))
			_bar(head + Vector2(0, 18), 40.0, s.down_t / Config.SURVIVOR.revive_time, Color("#e05a4a"))
			continue
		if s.hp < s.max_hp:
			_bar(head, 40.0, s.hp / s.max_hp, Color("#7ec46a"))
		var tag := String(job.short)
		if s.posted:
			tag += "*"
		if s.out_of_ammo:
			tag += " !"
		var feet := stage.to_screen(c + Vector2(0, R))
		_text(font, feet + Vector2(0, 4), tag, 9, Color(ring, 0.85))
		if not s.carrying.is_empty() or not s.carry_items.is_empty():
			_text(font, feet + Vector2(0, 18), "hauling", 8, Color("#e8c86a", 0.7))


func _vehicles(font: Font) -> void:
	var C := Config.CAR
	for v in sim.cars.list:
		var c: Vector2 = Util.render_pos(v.prev_pos, v.pos)
		if not _on_screen(c):
			continue
		var top := stage.to_screen_h(c, 1.5)
		if v.destroyed:
			_text(font, top, "WRECK", 9, Color("#8a8f84"))
			continue
		if v.locked and not v.hotwired:
			_text(font, top, "LOCKED", 9, Color("#c96a5a", 0.8))
		elif v.fuel <= 0.5:
			_text(font, top, "EMPTY", 9, Color("#d9c46a", 0.7))
		if v.engine_on:
			_bar(stage.to_screen(c) + Vector2(0, 20), 48.0, v.fuel / C.fuel_max, Color("#d2762c"))
		if v.hp < v.max_hp:
			_bar(top + Vector2(0, 16), 48.0, v.hp / v.max_hp, Color("#7ec46a"))


func _pickups(font: Font) -> void:
	for it in sim.pickups:
		var pos: Vector2 = it.pos
		if not _on_screen(pos):
			continue
		var pip: bool = it.kind == "res" or it.kind == "item"
		var at := stage.to_screen_h(pos, 0.55)
		if pip and it.n > 1:
			_text(font, at, "x%d" % it.n, 9, Color(1, 1, 1, 0.85))
		elif not pip:
			_text(font, at, Items.name_of(it.id), 9, Color("#ffe08a"))
	for pack in sim.backpacks:
		if _on_screen(pack.pos):
			_text(font, stage.to_screen_h(pack.pos, 0.9), "YOUR PACK", 10, Color("#c9a227"))


func _structures(font: Font) -> void:
	for s in sim.structs.list:
		if s.destroyed:
			continue
		var pos: Vector2 = s.pos
		if not _on_screen(pos):
			continue
		var h := float(Structures3D.HEIGHTS.wall) if s.def.get("wall", false) else float(Structures3D.HEIGHTS.get(s.type, Structures3D.HEIGHTS.default))
		var top := stage.to_screen_h(pos, h + 0.3)
		var frac: float = s.hp / s.max_hp
		if frac < 0.999:
			_bar(top, 36.0, frac, Color("#9fd07a") if frac > 0.5 else Color("#e05a4a"))
		match s.type:
			"turret":
				if s.starved:
					_text(font, top + Vector2(0, -16), "NO 9MM", 9, Color("#c96a5a"))
				elif not s.powered:
					_text(font, top + Vector2(0, -16), "NO POWER", 9, Color("#c96a5a"))
			"workbench":
				if s.tier >= 2:
					_text(font, top + Vector2(0, -16), Config.bench_numeral(int(s.tier)), 10, Color("#59b8c4"))
			_:
				if Farming.is_bed(s) and Farming.ready(s):
					_text(font, top + Vector2(0, -16), "READY", 9, Color("#9fd07a"))


func _doors(font: Font) -> void:
	for f in sim.world.features:
		var kind := String(f.kind)
		var r := InstanceView._rect(f)
		var centre := r.get_center()
		if not _on_screen(centre):
			continue
		match kind:
			"instance_door":
				_text(font, stage.to_screen_h(centre, 0.6), Instance.title(String(f.id)).to_upper(), 12, Color("#d8c98a"), 240.0)
				if sim.cleared.has(f.id) and int(sim.cleared[f.id]) == sim.clock.day:
					_chains(r)
			"chained":
				if not f.open:
					_chains(r)
			"exit":
				if sim.instance != null and sim.instance.state == "cleared":
					_text(font, stage.to_screen_h(centre, 0.6), "EXIT", 12, Color("#9fe8a0"))
			"range_exit":
				_text(font, stage.to_screen_h(centre, 0.6), "EXIT", 12, Color("#9fe8a0"))


func _chains(r: Rect2) -> void:
	var grey := Color("#9aa0a6")
	draw_line(stage.to_screen_h(r.position, 0.2), stage.to_screen_h(r.end, 0.2), grey, 3.0)
	draw_line(stage.to_screen_h(Vector2(r.end.x, r.position.y), 0.2), stage.to_screen_h(Vector2(r.position.x, r.end.y), 0.2), grey, 3.0)


## The reach a piece may be placed within, so "Too far" is visible before
## it is a refusal.
func _build_reach() -> void:
	if build_bar == null or not build_bar.placing():
		return
	var p: PlayerSim = local if local != null else sim.players[0]
	var pts := PackedVector2Array()
	for i in range(65):
		pts.append(stage.to_screen(p.pos + Vector2.from_angle(TAU * i / 64.0) * float(Config.BUILD.range)))
	draw_polyline(pts, Color("#d8e8c0", 0.18), 1.5)


## Whether a world point is anywhere near the camera's ground: the labels
## are drawn each frame for everything, so the far side of town is skipped
## before a projection is paid for.
func _on_screen(at: Vector2) -> bool:
	return at.distance_squared_to(stage.focus) < stage.label_reach * stage.label_reach
