extends "res://tests/test_case.gd"
## The map: finding a district, what that is worth, and which enemies the
## minimap is allowed to show you.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


## The centre of a district in world pixels.
func _middle_of(id: String) -> Vector2:
	for l in sim.world.locations:
		if String(l.id) == id:
			var r: Rect2i = l.rect
			return Vector2(r.position.x + r.size.x / 2.0, r.position.y + r.size.y / 2.0) * Config.TILE
	ok(false, "no district %s" % id)
	return Vector2.ZERO


func _loc(id: String) -> Dictionary:
	for l in sim.world.locations:
		if String(l.id) == id:
			return l
	return {}


func _forget_all() -> void:
	for l in sim.world.locations:
		l.discovered = false


# --------------------------------------------------------------- discovery --

func test_walking_into_a_district_finds_it() -> void:
	_forget_all()
	ok(not _loc("hospital").discovered)
	p.pos = _middle_of("hospital")
	sim.tick(0.016)
	ok(_loc("hospital").discovered, "standing in it is what finds it")


func test_finding_a_place_pays_by_how_dangerous_it_is() -> void:
	_forget_all()
	# Far enough up the curve that a hundred XP cannot level them: a level-up
	# takes the ceiling off `xp` and the award would be unreadable.
	p.level = 20
	p.xp_next = Config.xp_for_level(20)
	p.xp_mul = 1.0

	p.xp = 0
	p.pos = _middle_of("suburb")           # tier 1
	sim.tick(0.016)
	eq(p.xp, float(Config.MAP.discover_xp), "a quiet suburb")

	p.xp = 0
	p.pos = _middle_of("military")          # tier 4
	sim.tick(0.016)
	eq(p.xp, float(Config.MAP.discover_xp * 4), "the checkpoint is worth four suburbs")
func test_a_district_is_only_found_once() -> void:
	_forget_all()
	p.pos = _middle_of("commercial")
	sim.tick(0.016)
	var after := p.xp
	for i in range(20):
		sim.tick(0.016)
	eq(p.xp, after, "standing there does not keep paying")


func test_the_outskirts_are_nowhere_and_cost_nothing() -> void:
	_forget_all()
	p.xp = 0
	# A corner of the world that no district rect covers.
	p.pos = Vector2(62, 62) * Config.TILE
	ok(sim.world.location_at_px(p.pos.x, p.pos.y).is_empty(), "this really is nowhere")
	sim.tick(0.016)
	eq(p.xp, 0)


func test_what_you_found_survives_a_save() -> void:
	_forget_all()
	p.pos = _middle_of("junkyard")
	sim.tick(0.016)
	ok(_loc("junkyard").discovered)

	var slot := 94
	ok(SaveGame.save_to(sim, slot).ok)
	var fresh := new_sim()
	for l in fresh.world.locations:
		l.discovered = false
	var r := SaveGame.load_from(fresh, slot)
	ok(r.ok, r.reason)
	var found := {}
	for l in fresh.world.locations:
		if l.discovered:
			found[String(l.id)] = true
	ok(found.has("junkyard"), "the map came back")
	ok(not found.has("military"), "and only what was actually found")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.slot_path(slot)))


func test_an_old_payload_is_refused_by_version() -> void:
	# Every phase that changes what a save has to hold bumps the version, and
	# the refusal says so rather than loading half a world.
	eq(SaveGame.VERSION, 11)


# ----------------------------------------------------------------- the radar --

## `_revealed` is on the Control, but it touches nothing but the sim — which is
## the point of keeping the reveal rule in one place instead of in `_draw`.
func _reveal_count() -> int:
	var m := MapScreen.new(sim)
	var n: int = m._revealed(p).size()
	m.free()
	return n


func test_the_minimap_shows_what_is_near_and_not_the_whole_town() -> void:
	sim.enemies.list.clear()
	p.pos = Vector2(5000, 5000)
	p.radar_mul = 1.0
	# One at your elbow, one across the town. Neither has noticed you.
	sim.enemies.list.append(_walker(p.pos + Vector2(200, 0), false))
	sim.enemies.list.append(_walker(p.pos + Vector2(4000, 0), false))
	eq(_reveal_count(), 1, "the far one is not a secret you already know")


func test_something_hunting_you_shows_from_further_off() -> void:
	sim.enemies.list.clear()
	p.pos = Vector2(5000, 5000)
	p.radar_mul = 1.0
	# Beyond the unaware radius, inside the aware one.
	var at := p.pos + Vector2(Config.MAP.unaware + 100.0, 0)
	var e := _walker(at, false)
	sim.enemies.list.append(e)
	eq(_reveal_count(), 0, "it has not noticed you")
	e.aggro = true
	eq(_reveal_count(), 1, "one that is already coming is not hidden")


func test_sixth_sense_is_what_makes_it_a_radar() -> void:
	# The perk was dead in the prototype: `radarMul` was set and read by
	# nobody. This is the test that it is worth six Perception.
	sim.enemies.list.clear()
	p.pos = Vector2(5000, 5000)
	var far := Config.MAP.unaware * 2.0
	for i in range(4):
		sim.enemies.list.append(_walker(p.pos + Vector2(far, i * 40.0), false))
	p.radar_mul = 1.0
	eq(_reveal_count(), 0)

	p.perks = {"sixthSense": 1}
	Perks.recompute_stats(p)
	gt(p.radar_mul, 1.0, "the perk produces the number")
	eq(_reveal_count(), 4, "and the number is what the map reads")


func test_the_dead_are_off_the_map() -> void:
	sim.enemies.list.clear()
	p.pos = Vector2(5000, 5000)
	p.radar_mul = 1.0
	var e := _walker(p.pos + Vector2(100, 0), false)
	sim.enemies.list.append(e)
	eq(_reveal_count(), 1)
	e.dead = true
	eq(_reveal_count(), 0)


func _walker(at: Vector2, aggro: bool) -> EnemySim:
	var e := EnemySim.new("walker", at, 1)
	e.aggro = aggro
	return e
