extends "res://tests/test_case.gd"
## Hand-laid buildings (2026-10-14, `Layout`, `data/layouts.json`): every
## layout in the table passes the checks the importer runs, stamps onto a
## lab world exactly as written, and is playable by Furnish's rule; the
## checks themselves catch what they are for.

const T = Config.T
const W := Config.WORLD_TILES

## A small house to stamp and to break: a doorway south, a partition
## with a gap, a bed, a fridge against the north wall, a picture on it.
const HOUSE := {
	"id": "test_house", "use": "house", "floor": "wood",
	"map": [
		"#########",
		"#...#...#",
		"#...-...#",
		"#...#...#",
		"####++###",
	],
	"things": [
		{"what": "bed_single", "x": 1, "y": 1, "w": 1, "h": 2, "d": 0},
		{"container": "fridge", "x": 5, "y": 1, "w": 1, "h": 1, "d": 0},
		{"what": "painting", "kind": "wall", "x": 7, "y": 0, "w": 1, "h": 1, "d": 0},
		{"what": "rug", "x": 5, "y": 2, "w": 2, "h": 2, "d": 0, "solid": false},
	],
}


func _lab(id: String) -> World:
	return World.new(7, "lab:" + id)


func _with(row: Dictionary) -> World:
	var was: Dictionary = Config.LAYOUTS
	var table := was.duplicate()
	table[row.id] = row
	Config.LAYOUTS = table
	var w := _lab(String(row.id))
	Config.LAYOUTS = was
	return w


func test_every_layout_in_the_table_checks_out_and_is_playable() -> void:
	gt(Config.LAYOUTS.size(), 0, "there is at least one layout")
	for id in Config.LAYOUTS:
		var row: Dictionary = Config.LAYOUTS[id]
		eq(Array(Layout.problems(row)), [], id)
		for t in row.get("things", []):
			if t.has("container"):
				ok(Config.CONTAINERS.has(t.container), "%s: container '%s' exists" % [id, t.container])
			else:
				ok(PropModels.THINGS.has(t.what), "%s: '%s' is a thing the stage knows" % [id, t.what])
		var world := _lab(id)
		eq(world.buildings.size(), 1, "%s: the lab stamps one building" % id)
		ok(Layout.playable(world, world.buildings[0]), "%s: every room reachable, every piece searchable" % id)
		gt(world.spawn_tiles.size(), 0, "%s: the party wakes outside its door" % id)
		var door: Vector2i = world.buildings[0].doors[0]
		var spawn: Vector2i = world.spawn_tiles[0]
		ok(not world.blocked[spawn.y * W + spawn.x], "%s: the spawn tile is clear" % id)
		eq(Layout.outward(world.buildings[0].rect, door), (spawn - door) / 2, "%s: the spawn is out from the door" % id)


func test_a_layout_stamps_exactly_as_written() -> void:
	var world := _with(HOUSE)
	var b: Dictionary = world.buildings[0]
	var r: Rect2i = b.rect
	eq(r.size, Vector2i(9, 5))
	eq(world.tile(r.position.x, r.position.y), T.WALL, "corner")
	eq(world.tile(r.position.x + 1, r.position.y + 1), T.FLOOR_WOOD, "floor")
	eq(world.tile(r.position.x + 4, r.position.y + 2), T.FLOOR_WOOD, "the partition's gap is floor")
	eq(world.tile(r.position.x + 4, r.position.y + 1), T.WALL, "the partition is wall")
	eq(b.doors.size(), 2, "two door tiles")
	eq(world.tile(r.position.x + 4, r.position.y + 4), T.FLOOR_WOOD, "the doorway is floor")
	var beds := world.props.filter(func(p: Dictionary) -> bool: return p.get("what", "") == "bed_single")
	eq(beds.size(), 1)
	eq(Vector2i(int(beds[0].tx), int(beds[0].ty)), r.position + Vector2i(1, 1))
	eq(int(beds[0].dir), 0)
	ok(world.blocked[(r.position.y + 2) * W + r.position.x + 1], "the bed's second tile is solid")
	var fridges := world.containers.filter(func(c: Dictionary) -> bool: return c.kind == "fridge")
	eq(fridges.size(), 1)
	eq(Vector2i(int(fridges[0].tx), int(fridges[0].ty)), r.position + Vector2i(5, 1))
	var pics := world.props.filter(func(p: Dictionary) -> bool: return p.get("what", "") == "painting")
	eq(pics.size(), 1)
	eq(pics[0].kind, "wall")
	ok(bool(pics[0].outer), "a picture on the north wall hangs on an outer wall")
	var rugs := world.props.filter(func(p: Dictionary) -> bool: return p.get("what", "") == "rug")
	eq(rugs.size(), 1)
	ok(not world.blocked[(r.position.y + 2) * W + r.position.x + 5], "a rug is not solid")
	ok(world.dressed.has((r.position.y + 2) * W + r.position.x + 5), "but nothing else lands on it")
	ok(Layout.playable(world, b))
	# The lab around it: a road south of the lot, the party at the door.
	eq(world.tile(r.position.x + 4, r.end.y + 4), T.ROAD)
	eq(world.spawn_tiles[0], b.doors[0] + Vector2i(0, 2))


func test_the_checks_catch_what_they_are_for() -> void:
	eq(Array(Layout.problems({"map": []})), ["the map is empty"])
	var ragged := HOUSE.duplicate(true)
	ragged.map[1] = "#...#..#"
	ok(Array(Layout.problems(ragged))[0].begins_with("map row 1 is 8 wide"))
	var sealed := HOUSE.duplicate(true)
	sealed.map[4] = "#########"
	has(Array(Layout.problems(sealed)), "no doorway ('+') in the outer wall")
	var on_wall := HOUSE.duplicate(true)
	on_wall.things[0] = {"what": "bed_single", "x": 0, "y": 1, "w": 1, "h": 2, "d": 0}
	ok(Array(Layout.problems(on_wall))[0].contains("which is a wall"))
	var stacked := HOUSE.duplicate(true)
	stacked.things.append({"what": "armchair", "x": 1, "y": 1, "w": 1, "h": 1, "d": 0})
	ok(Array(Layout.problems(stacked))[0].contains("where thing 0 (bed_single) already is"))
	var hung_wrong := HOUSE.duplicate(true)
	hung_wrong.things[2] = {"what": "painting", "kind": "wall", "x": 7, "y": 0, "w": 1, "h": 1, "d": 2}
	ok(Array(Layout.problems(hung_wrong))[0].contains("where there is no floor"))
	# A wardrobe across the partition's gap cuts the house in two, and a
	# cabinet boxed into a corner cannot be searched: not problems the
	# map can show, so `playable` asks the stamped world.
	var cut := HOUSE.duplicate(true)
	cut.things = [
		{"what": "bed_single", "x": 1, "y": 1, "w": 1, "h": 2, "d": 0},
		{"container": "wardrobe", "x": 5, "y": 1, "w": 1, "h": 1, "d": 3},
		{"container": "wardrobe", "x": 5, "y": 2, "w": 1, "h": 1, "d": 3},
		{"container": "wardrobe", "x": 5, "y": 3, "w": 1, "h": 1, "d": 3},
	]
	eq(Array(Layout.problems(cut)), [])
	var world := _with(cut)
	ok(not Layout.playable(world, world.buildings[0]), "a wall of wardrobes across the gap is not playable")
	var boxed := HOUSE.duplicate(true)
	boxed.things = [
		{"container": "safe", "x": 1, "y": 1, "w": 1, "h": 1, "d": 0},
		{"what": "armchair", "x": 2, "y": 1, "w": 1, "h": 1, "d": 0},
		{"what": "armchair", "x": 1, "y": 2, "w": 1, "h": 1, "d": 0},
		{"what": "armchair", "x": 2, "y": 2, "w": 1, "h": 1, "d": 0},
	]
	world = _with(boxed)
	ok(not Layout.playable(world, world.buildings[0]), "a safe boxed into a corner is not playable")


func test_the_lab_is_peaceful_and_the_party_wakes_at_the_door() -> void:
	var world := _with(HOUSE)
	var sim := GameSim.new()
	sim.start(world)
	sim.peaceful = true
	sim.enemies.list.clear()
	var p: PlayerSim = sim.players[0]
	var door: Vector2i = world.buildings[0].doors[0]
	ok(Vector2(door * Config.TILE).distance_to(p.pos) < 4.0 * Config.TILE, "woke at the door")
	run(sim, 30.0)
	eq(sim.enemies.list.size(), 0, "nobody came in thirty seconds")
	eq(sim.raid, null, "no raid")


func test_the_lab_house_is_dressed_as_one_building_with_a_roof() -> void:
	for id in Config.LAYOUTS:
		var world := _lab(id)
		var plan := BuildingPlan.new()
		plan.build(world)
		var r: Rect2i = world.buildings[0].rect
		var ri := plan.rects.find(r)
		ok(ri >= 0, "%s: the plan has the house's rectangle" % id)
		if ri < 0:
			continue
		eq(plan.kinds[ri], BuildingPlan.BUILDING, id)
		has(Array(plan.roofed()), ri, "%s: it gets a roof" % id)
		eq(plan.count("corner_post", ri), 4, id)
		ok(plan.count("wall_1m", ri) + 2 * plan.count("wall_window_2m", ri) > 20, "%s: siding all round" % id)
