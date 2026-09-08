extends "res://tests/test_case.gd"
## The map: deterministic, consistent, and every district and container
## reachable from the camp. One world is built and shared across tests.

const T = Config.T
const W := Config.WORLD_TILES

static var _world: World
static var _reached := PackedByteArray()


static func world() -> World:
	if _world == null:
		_world = World.new()
	return _world


## Flood fill over unblocked tiles from the camp crossroads.
static func reached() -> PackedByteArray:
	if not _reached.is_empty():
		return _reached
	var w := world()
	_reached.resize(W * W)
	var queue := PackedInt32Array()
	var start := 160 * W + 160
	queue.append(start)
	_reached[start] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % W
		var y := i / W
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + off.x
			var ny := y + off.y
			if nx < 0 or ny < 0 or nx >= W or ny >= W:
				continue
			var ni := ny * W + nx
			if _reached[ni] or w.blocked[ni]:
				continue
			_reached[ni] = 1
			queue.append(ni)
	return _reached


func test_deterministic() -> void:
	var a := world()
	var b := World.new()
	ok(a.tiles == b.tiles, "tiles differ between two builds of the same seed")
	ok(a.blocked == b.blocked, "collision differs")
	eq(b.props.size(), a.props.size(), "prop count")
	eq(b.containers.size(), a.containers.size(), "container count")


func test_solid_tiles_are_blocked() -> void:
	var w := world()
	var bad := 0
	for i in range(W * W):
		if Config.SOLID_BY_TILE[w.tiles[i]] == 1 and w.blocked[i] == 0:
			bad += 1
	eq(bad, 0, "solid tiles that are not blocked")


func test_landmarks() -> void:
	var w := world()
	eq(w.tile(150, 150), T.WALL, "camp shack corner")
	eq(w.tile(154, 153), T.FLOOR_WOOD, "camp shack floor")
	eq(w.tile(100, 160), T.ROAD, "the highway")
	eq(w.tile(67, 20), T.WATER, "the river")
	eq(w.tile(67, 160), T.ROAD, "the highway bridge")
	eq(w.tile(10, 130), T.FIELD, "a farm field")
	ok(w.containers.size() > 400, "containers: %d" % w.containers.size())
	ok(w.props.size() > 10000, "props: %d" % w.props.size())
	ok(w.vehicle_spawns.size() > 30, "cars: %d" % w.vehicle_spawns.size())


func test_spawn_tiles_are_safe_open_ground() -> void:
	var w := world()
	ok(w.spawn_tiles.size() > 100, "spawn tiles: %d" % w.spawn_tiles.size())
	var bad := 0
	for t in w.spawn_tiles:
		var i := t.y * W + t.x
		if w.blocked[i] or w.danger[i] != 1:
			bad += 1
	eq(bad, 0, "spawn tiles that are blocked or not tier 1")


func test_every_district_reachable_from_camp() -> void:
	var w := world()
	var r := reached()
	for loc in w.locations:
		var rect: Rect2i = loc.rect
		var n := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if r[y * W + x]:
					n += 1
		ok(n > 0, "%s unreachable from the camp" % loc.id)


## A corner cabinet is searched from the diagonal tile: interact range is 76px
## and a diagonal neighbour is 45px away, so eight neighbours count.
func test_every_container_reachable() -> void:
	var w := world()
	var r := reached()
	var stranded := 0
	for c in w.containers:
		var open := false
		for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var x: int = c.tx + off.x
			var y: int = c.ty + off.y
			if World.in_bounds(x, y) and r[y * W + x]:
				open = true
				break
		if not open:
			stranded += 1
	eq(stranded, 0, "containers with no reachable neighbour")


func test_starter_cache_near_camp() -> void:
	var w := world()
	var min_units := {"sticks": 2, "fiber": 2, "stone": 1}
	var have := {"sticks": 0, "fiber": 0, "stone": 0}
	for y in range(160 - 12, 160 + 13):
		for x in range(160 - 12, 160 + 13):
			var p := w.prop_at_tile(x, y)
			if p.is_empty() or not p.get("hand", false):
				continue
			var res: String = p.get("res", "fiber" if p.harvest == "fiber" else "stone")
			have[res] += min_units[res]
	ok(have.sticks >= 14, "sticks near camp: %d" % have.sticks)
	ok(have.fiber >= 14, "fiber near camp: %d" % have.fiber)
	ok(have.stone >= 12, "stone near camp: %d" % have.stone)


func test_location_lookup() -> void:
	var w := world()
	eq(w.location_at_px(160 * 32, 160 * 32).id, "camp")
	eq(w.location_at_px(270 * 32, 160 * 32).id, "downtown")
	eq(w.location_at_px(150 * 32, 30 * 32).id, "forest")
	eq(w.location_at_px(100 * 32, 30 * 32).id, "lumber", "named places inside the forest win")
	ok(w.location_at_px(60 * 32, 300 * 32).is_empty(), "the outskirts have no name")
	eq(w.danger_at_px(270 * 32, 160 * 32), 4)
	eq(w.danger_at_px(160 * 32, 160 * 32), 1)
