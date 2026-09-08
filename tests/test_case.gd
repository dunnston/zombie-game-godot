class_name TestCase
extends RefCounted
## Base class for headless tests. Subclass, name methods `test_*`, use the
## assertions below. Failures are recorded, not thrown, so one test reports
## every broken assertion instead of stopping at the first.

var _failures: Array[String] = []
var _asserts := 0

static var _shared_world: World

## One generated world for the whole run. Never mutate it in a test that
## another test could follow; fell trees on a private World.new() instead.
static func world() -> World:
	if _shared_world == null:
		_shared_world = World.new()
	return _shared_world

## A fresh simulation on the shared world, with the spawner's opening
## crowd cleared so a test starts from exactly what it plants.
static func new_sim(run_seed := 1) -> GameSim:
	var sim := GameSim.new()
	sim.start(world(), run_seed)
	sim.enemies.list.clear()
	sim.events.clear()
	return sim

## Centre tile of a clear (2n+1)-tile square of open ground, searched from
## the town outward, at danger tier 2 or below. A test arena needs the whole
## corridor open, not just the centre: one tree stops a walker and the
## assertion fails for a reason unrelated to what it measures.
static func clear_plot(n: int) -> Vector2i:
	var w := world()
	var W := Config.WORLD_TILES
	var lo := W / 4 + 8
	var hi := 3 * W / 4 - 8
	for band: Array in [[lo, hi], [8, W - 8]]:
		for ty in range(band[0], band[1], 2):
			for tx in range(band[0], band[1], 2):
				if w.danger[ty * W + tx] > 2:
					continue
				var clear := true
				for j in range(-n, n + 1):
					for i in range(-n, n + 1):
						var x: int = tx + i
						var y: int = ty + j
						if x < 2 or y < 2 or x >= W - 2 or y >= W - 2 or w.blocked[y * W + x]:
							clear = false
							break
					if not clear:
						break
				if clear:
					return Vector2i(tx, ty)
	return Vector2i(160, 160)

static func tile_centre(t: Vector2i) -> Vector2:
	return Vector2(t.x * Config.TILE + 16, t.y * Config.TILE + 16)

## Steps the whole simulation for `seconds` at 60Hz.
static func run(sim: GameSim, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in range(int(round(seconds / dt))):
		sim.tick(dt)

## Every event of one kind that the sim has emitted so far.
static func events_of(sim: GameSim, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev in sim.events:
		if ev.t == kind:
			out.append(ev)
	return out

func before_each() -> void:
	pass

func after_each() -> void:
	pass

func _fail(msg: String) -> void:
	var where := ""
	for frame in get_stack():
		var src: String = frame.get("source", "")
		if src.ends_with("_test.gd"):
			where = "%s:%d " % [src.get_file(), frame.get("line", 0)]
			break
	_failures.append(where + msg)

func ok(cond: bool, msg := "") -> void:
	_asserts += 1
	if not cond:
		_fail("expected true" + ("" if msg.is_empty() else ": " + msg))

func eq(actual, expected, msg := "") -> void:
	_asserts += 1
	if actual != expected:
		_fail("expected %s, got %s%s" % [str(expected), str(actual), "" if msg.is_empty() else " (" + msg + ")"])

func ne(actual, unexpected, msg := "") -> void:
	_asserts += 1
	if actual == unexpected:
		_fail("expected something other than %s%s" % [str(unexpected), "" if msg.is_empty() else " (" + msg + ")"])

func near(actual: float, expected: float, tol := 1e-6, msg := "") -> void:
	_asserts += 1
	if absf(actual - expected) > tol:
		_fail("expected %f ± %f, got %f%s" % [expected, tol, actual, "" if msg.is_empty() else " (" + msg + ")"])

func gt(actual, floor_value, msg := "") -> void:
	_asserts += 1
	if not (actual > floor_value):
		_fail("expected > %s, got %s%s" % [str(floor_value), str(actual), "" if msg.is_empty() else " (" + msg + ")"])

func has(container, item, msg := "") -> void:
	_asserts += 1
	if not container.has(item):
		_fail("expected %s to contain %s%s" % [str(container), str(item), "" if msg.is_empty() else " (" + msg + ")"])

# ------------------------------------------------------------ raid harness --

## A competent defender with `weapon` and a full pack plays raid `index`
## through to the end, aiming at the nearest raider and holding fire. Shared
## because both the open-field and the compound harnesses run it.
##
## The twelve-second warning is skipped: it has its own test, and every
## harness sitting through it is simulation that measures nothing.
static func play_raid(sim: GameSim, p: PlayerSim, index: int, weapon := "rifle", max_seconds := 300.0) -> Dictionary:
	sim.raids_done = index
	p.god_mode = true
	p.select_slot(p.hotbar_index(weapon))
	p.add_res(Config.WEAPONS[weapon].ammo, 400)
	sim.threat.value = 100.0
	sim.tick(1.0 / 60.0)
	if sim.raid != null:
		sim.raid.timer = 0.05
	run(sim, 0.2)
	var t0 := sim.time
	for i in range(int(max_seconds * 60)):
		var best: EnemySim = null
		var bd := INF
		for e in sim.enemies.list:
			if e.dead or not e.raid:
				continue
			var d := e.pos.distance_squared_to(p.pos)
			if d < bd:
				bd = d
				best = e
		if best != null:
			p.intent.aim = best.pos
			p.intent.fire = true
			p.intent.fire_pressed = i % 30 == 0
		else:
			p.intent.fire = false
		sim.tick(1.0 / 60.0)
		if sim.raid == null:
			break
	return {"seconds": sim.time - t0, "done": sim.raid == null, "kills": sim.stats.kills,
		"repelled": sim.raids_done == index + 1 and events_of(sim, "raid_end").back().repelled,
		"reward": p.count_res("scrap")}


## The standard compound the prototype measured raids against: an 11x11
## perimeter of wood north and south and reinforced east and west, four
## gates, spikes on the north approach, and the workshop inside. Fixed at
## roughly first-raid strength whatever index is thrown at it — high indices
## are meant to flatten it.
static func build_compound(sim: GameSim, p: PlayerSim) -> Dictionary:
	p.bag = Slots.new(400)
	p.carry_cap = 1000000.0
	for id in ["wood", "stone", "sticks", "scrap", "cloth", "elec", "parts", "mil", "fuel"]:
		p.bag.add(id, 900)
	sim.structs.bench_tier = 2
	var tx := floori(p.pos.x / Config.TILE)
	var ty := floori(p.pos.y / Config.TILE)
	# Placement is range-limited, so the builder walks its own perimeter.
	var put := func(type: String, x: int, y: int) -> Dictionary:
		p.pos = Vector2(x * Config.TILE + 16, y * Config.TILE + 16) + Vector2(0, Config.TILE * 2)
		return sim.structs.place(sim, type, x, y, p)
	for i in range(-5, 6):
		if i != 0:
			put.call("woodWall", tx + i, ty - 5)
			put.call("woodWall", tx + i, ty + 5)
	for j in range(-4, 5):
		if j != 0:
			put.call("reinforcedWall", tx - 5, ty + j)
			put.call("reinforcedWall", tx + 5, ty + j)
	put.call("gate", tx, ty - 5)
	put.call("gate", tx, ty + 5)
	put.call("gate", tx - 5, ty)
	put.call("gate", tx + 5, ty)
	for i in range(-2, 3):
		put.call("spike", tx + i, ty - 6)
	put.call("workbench", tx - 3, ty - 2)
	put.call("stash", tx - 3, ty + 2)
	put.call("bedroll", tx + 3, ty + 3)
	var gen: Dictionary = put.call("generator", tx + 3, ty - 3)
	put.call("turret", tx + 2, ty - 1)
	put.call("turret", tx - 2, ty + 1)
	if not gen.is_empty():
		gen.fuel = gen.def.fuel_max
	if sim.stash != null:
		sim.stash.add("ammoP", 600)
	p.pos = tile_centre(Vector2i(tx, ty))
	return {"tx": tx, "ty": ty, "built": sim.structs.count(), "hp": sim.structs.hp_total()}


## What a raid left of it: pieces gone, and the health of the walls still up.
static func compound_report(sim: GameSim, before: Dictionary) -> Dictionary:
	var walls_hp := 0.0
	var walls_max := 0.0
	for s in sim.structs.list:
		if s.destroyed or not s.def.get("wall", false):
			continue
		walls_hp += s.hp
		walls_max += s.max_hp
	return {"lost": int(before.built) - sim.structs.count(),
		"walls_pct": roundi(walls_hp / maxf(1.0, walls_max) * 100.0)}
