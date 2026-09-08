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
