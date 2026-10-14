extends "res://tests/test_case.gd"
## The furnishing pass (2026-10-14, `Furnish`): homes have kitchens,
## bathrooms and bedrooms with the right things in them, the other
## buildings have what they are for, yards stay off the path from the
## door, corn grows on fields, and nothing anywhere seals a room or
## strands a cabinet. One world, shared with every other test.

const T = Config.T
const W := Config.WORLD_TILES
const HOMES := ["house", "farm", "shack", "cabin", "apartment"]
const BEDS := ["bed_single", "bed_double", "bunk_bed"]


func _inside(r: Rect2i, kind: String, what := "") -> Array:
	var out := []
	for p in world().props:
		if p.get("kind", "") != kind or not p.has("tx"):
			continue
		if not what.is_empty() and p.get("what", "") != what:
			continue
		if r.has_point(Vector2i(int(p.tx), int(p.ty))):
			out.append(p)
	return out


func _containers_in(r: Rect2i, kind := "") -> Array:
	var out := []
	for c in world().containers:
		if r.has_point(Vector2i(int(c.tx), int(c.ty))) and (kind.is_empty() or c.kind == kind):
			out.append(c)
	return out


func _homes() -> Array:
	var out := []
	for b in world().buildings:
		if b.use in HOMES:
			out.append(b)
	return out


func test_the_generator_records_every_building() -> void:
	var w := world()
	ok(w.buildings.size() > 60, "buildings recorded: %d" % w.buildings.size())
	ok(_homes().size() > 30, "homes: %d" % _homes().size())
	for b in w.buildings:
		ok(not b.doors.is_empty(), "a building at %s has a door" % b.rect.position)
		for d: Vector2i in b.doors:
			ok(w.tile(d.x, d.y) != T.WALL, "a door tile is not a wall")


func test_every_home_has_a_bed_and_a_house_its_rooms() -> void:
	for b in _homes():
		var r: Rect2i = b.rect
		var beds := 0
		for what in BEDS:
			beds += _inside(r, "furniture", what).size()
		ok(beds >= 1, "%s at %s sleeps somewhere (%d beds)" % [b.use, r.position, beds])
		var rooms := Furnish.rooms_of(b)
		if rooms.size() < 3 or b.use == "apartment":
			continue
		ok(_inside(r, "furniture", "toilet").size() >= 1, "a %d-room house at %s has a toilet" % [rooms.size(), r.position])
		ok(_inside(r, "furniture", "stove").size() >= 1, "...and a stove")
		ok(_containers_in(r, "fridge").size() >= 1, "...and a fridge to search")
		ok(_containers_in(r, "kitchen").size() >= 1, "...and kitchen cabinets")


func test_the_fridge_is_in_the_kitchen_and_the_toilet_in_the_bathroom() -> void:
	var checked := 0
	for b in _homes():
		var rooms := Furnish.rooms_of(b)
		if rooms.size() < 3 or b.use == "apartment":
			continue
		var roles := Furnish.roles_for(b, rooms)
		for i in range(rooms.size()):
			match roles[i]:
				"kitchen":
					ok(_containers_in(rooms[i], "fridge").size() >= 1, "the kitchen at %s has the fridge" % rooms[i].position)
					eq(_inside(rooms[i], "furniture", "toilet").size(), 0, "no toilet in the kitchen")
					checked += 1
				"bathroom":
					ok(_inside(rooms[i], "furniture", "toilet").size() >= 1, "the bathroom at %s has the toilet" % rooms[i].position)
					eq(_containers_in(rooms[i], "fridge").size(), 0, "no fridge in the bathroom")
				"bedroom":
					var beds := 0
					for what in BEDS:
						beds += _inside(rooms[i], "furniture", what).size()
					ok(beds >= 1, "the bedroom at %s has a bed" % rooms[i].position)
	ok(checked >= 10, "houses with rooms checked: %d" % checked)


func test_the_room_with_the_door_is_the_living_room() -> void:
	var b := {"rect": Rect2i(0, 0, 13, 13), "use": "house", "vs": [6], "hs": [6], "doors": [Vector2i(0, 9)], "interior": []}
	var rooms := Furnish.rooms_of(b)
	eq(rooms.size(), 4)
	var roles := Furnish.roles_for(b, rooms)
	# The door at (0, 9) opens into the south-west room: rooms are listed
	# row by row, so that is the third.
	eq(roles[2], "living")
	var counts := {}
	for r in roles:
		counts[r] = counts.get(r, 0) + 1
	eq(counts.get("bathroom", 0), 1)
	eq(counts.get("kitchen", 0), 1)
	eq(counts.get("bedroom", 0), 1)


func test_every_floor_tile_of_every_building_reaches_its_door() -> void:
	var w := world()
	var sealed := 0
	for b in w.buildings:
		var r: Rect2i = b.rect
		var seen := {}
		var stack: Array[Vector2i] = []
		for d: Vector2i in b.doors:
			stack.append(d)
			seen[d] = true
		while not stack.is_empty():
			var t: Vector2i = stack.pop_back()
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := t + off
				if not r.has_point(n) or seen.has(n):
					continue
				if w.tile(n.x, n.y) == T.WALL or w.blocked[n.y * W + n.x]:
					continue
				seen[n] = true
				stack.append(n)
		for y in range(r.position.y + 1, r.end.y - 1):
			for x in range(r.position.x + 1, r.end.x - 1):
				if w.tile(x, y) != T.WALL and not w.blocked[y * W + x] and not seen.has(Vector2i(x, y)):
					sealed += 1
	eq(sealed, 0, "floor tiles no door reaches")


func test_nothing_stands_in_a_doorway_or_just_inside_it() -> void:
	var w := world()
	var bad := 0
	for b in w.buildings:
		var r: Rect2i = b.rect
		for d: Vector2i in b.doors:
			if w.blocked[d.y * W + d.x]:
				bad += 1
			# (A door may open onto the end of a room divider — the generator
			# has always allowed that, and the door's other tile is clear.)
			for off: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n := d + off
				if r.grow(-1).has_point(n) and w.blocked[n.y * W + n.x] and w.tile(n.x, n.y) != T.WALL:
					bad += 1
	eq(bad, 0, "things in or just inside a doorway")


func test_what_was_stood_against_a_wall_has_the_wall_at_its_back() -> void:
	var w := world()
	var checked := 0
	var wrong := 0
	for c in w.containers:
		if not c.has("dir"):
			continue
		var back := Vector2i(int(c.tx), int(c.ty)) - Furnish.DIRS[int(c.dir)]
		checked += 1
		if w.tile(back.x, back.y) != T.WALL:
			wrong += 1
	ok(checked > 100, "containers the furnisher placed: %d" % checked)
	eq(wrong, 0, "containers whose back is not to a wall")


func test_yards_are_on_the_grass_and_off_the_path_from_the_door() -> void:
	var w := world()
	var yard := _inside(Rect2i(0, 0, W, W), "yard")
	ok(yard.size() > 40, "yard pieces: %d" % yard.size())
	var keep := {}
	for b in w.buildings:
		var r: Rect2i = b.rect
		for d: Vector2i in b.doors:
			var out := Vector2i(-1 if d.x == r.position.x else (1 if d.x == r.end.x - 1 else 0), -1 if d.y == r.position.y else (1 if d.y == r.end.y - 1 else 0))
			for k in range(1, 4):
				keep[d + out * k] = true
	var bad := 0
	for p in yard:
		var foot := World.footprint_of(int(p.w), int(p.h), int(p.dir))
		for j in range(foot.y):
			for i in range(foot.x):
				var t := Vector2i(int(p.tx) + i, int(p.ty) + j)
				var tile := w.tile(t.x, t.y)
				if tile != T.GRASS and tile != T.DIRT:
					bad += 1
				if keep.has(t):
					bad += 1
				if p.solid != (w.blocked[t.y * W + t.x] == 1):
					bad += 1
	eq(bad, 0, "yard tiles off the grass, on the path, or wrongly blocked")


func test_the_farms_have_corn_and_tractors() -> void:
	var w := world()
	var corn := _inside(Rect2i(0, 0, W, W), "corn")
	ok(corn.size() > 150, "corn stalks: %d" % corn.size())
	var bad := 0
	for p in corn:
		if w.tile(int(p.tx), int(p.ty)) != T.FIELD or p.solid or w.blocked[int(p.ty) * W + int(p.tx)]:
			bad += 1
	eq(bad, 0, "corn off a field or blocking it")
	var tractors := 0
	for p in w.props:
		if p.get("kind", "") == "tractor":
			tractors += 1
			ok(w.blocked[int(p.ty) * W + int(p.tx)] == 1 and w.blocked[int(p.ty) * W + int(p.tx) + 1] == 1, "a tractor blocks both its tiles")
	eq(tractors, 3, "a tractor at each farmstead and the ranch")


func test_stumps_and_logs_lie_among_the_trees() -> void:
	var w := world()
	var stumps := 0
	var logs := 0
	for p in w.props:
		var kind := String(p.get("kind", ""))
		if kind == "stump" or kind == "log":
			if kind == "stump":
				stumps += 1
			else:
				logs += 1
			ok(w.blocked[int(p.ty) * W + int(p.tx)] == 1, "a %s is solid" % kind)
	ok(stumps > 100, "stumps: %d" % stumps)
	ok(logs > 50, "logs: %d" % logs)


func test_the_other_buildings_have_what_they_are_for() -> void:
	var w := world()
	var all := Rect2i(0, 0, W, W)
	ok(_inside(all, "furniture", "grocery_shelf").size() >= 6, "the shops have aisles")
	ok(_inside(all, "furniture", "bunk_bed").size() >= 1, "the barracks have bunks")
	ok(_inside(all, "wall").size() > 40, "pictures and clocks on the walls: %d" % _inside(all, "wall").size())
	for p in _inside(all, "wall"):
		var back := Vector2i(int(p.tx), int(p.ty))
		eq(w.tile(back.x, back.y), T.WALL, "a wall piece hangs on a wall tile")
		ok(not p.solid, "and blocks nothing")
	# What a thing can be walked through does not block.
	for p in _inside(all, "furniture"):
		eq(w.blocked[int(p.ty) * W + int(p.tx)] == 1, bool(p.solid), "%s blocks iff solid" % p.what)


func test_classrooms_have_desks_facing_the_board() -> void:
	var w := World.new(7, "school")
	var desks := 0
	var boards := 0
	for p in w.props:
		if p.get("what", "") == "school_desk":
			desks += 1
			eq(int(p.dir), 2, "a desk faces north, to the board")
		elif p.get("what", "") == "chalkboard":
			boards += 1
	ok(desks >= 45, "school desks: %d" % desks)
	eq(boards, 9, "a board in every classroom")
	ok(w.enemy_spots.size() > 20, "the rooms still have room to stand in: %d spots" % w.enemy_spots.size())


func test_the_town_still_builds_in_time() -> void:
	var t0 := Time.get_ticks_msec()
	World.new()
	var ms := Time.get_ticks_msec() - t0
	ok(ms < 2500, "the town built in %d ms" % ms)
