extends "res://tests/test_case.gd"
## `BuildingPlan`: the town's buildings read off the tiles for the parts.
## The starter house at (150, 150) is the generator's 8×7 with one 2-tile
## doorway, the military compound is a 28×28 ring with two buildings in
## it, and the hardware store has a room divider cut off by its own gaps:
## one of each kind, so every rule below has a case.

const T = Config.T

var plan: BuildingPlan
var house := -1


func before_each() -> void:
	plan = BuildingPlan.new()
	plan.build(world())
	house = _rect_at(Vector2i(150, 150))


func _rect_at(pos: Vector2i) -> int:
	for ri in range(plan.rects.size()):
		if plan.rects[ri].position == pos:
			return ri
	return -1


func _parts(ri: int, part := "") -> Array:
	var out := []
	for p in plan.parts:
		if p.rect == ri and (part.is_empty() or p.part == part):
			out.append(p)
	return out


func test_the_starter_house_is_a_building_dressed_whole() -> void:
	ok(house >= 0, "the 8×7 house at (150, 150) is a component")
	eq(plan.rects[house], Rect2i(150, 150, 8, 7))
	eq(plan.kinds[house], BuildingPlan.BUILDING)
	ok(plan.styles[house] >= 0 and plan.styles[house] < FacadeArt.HOUSE_STYLES, "a house style")
	# 30 outward faces, 2 of them the doorway: every other one is a panel,
	# a window panel covering two.
	var plain := _parts(house, "wall_1m").size()
	var windows := _parts(house, "wall_window_2m").size()
	eq(plain + 2 * windows, 28)
	ok(windows >= 3, "a house this size has windows on three sides at least, has %d" % windows)
	eq(_parts(house, "wall_doorway_2m").size(), 1)
	eq(_parts(house, "door_open").size(), 1)
	eq(_parts(house, "porch_roof_2m").size(), 1)
	eq(_parts(house, "corner_post").size(), 4)
	eq(_parts(house, "wall_interior_1m").size(), 0)
	# Clean corners (the owner's deal, 2026-10-14): each post is turned to
	# put its two boarded faces outward, and the panel either side of it
	# stops a wall's thickness short of the vertex, shifted the other way.
	var dirs := []
	for p in _parts(house, "corner_post"):
		dirs.append(int(p.dir))
	dirs.sort()
	eq(dirs, [0, 1, 2, 3])
	var short := 0
	for p in _parts(house, "wall_1m"):
		if is_equal_approx(float(p.sx), 0.75):
			short += 1
			var nearest := INF
			for c in _parts(house, "corner_post"):
				nearest = minf(nearest, (p.at as Vector2).distance_to(c.at))
			near(nearest, 0.625, 1e-6, "a short panel spans 0.25..1.0 from its vertex, so its centre is 0.625 off, at %s" % p.at)
		else:
			eq(float(p.sx), 1.0)
	eq(short, 8, "two short panels at each of four corners")
	ok(house in plan.roofed(), "a building gets a roof")
	ok(plan.rects.size() > 40, "the town has dozens of components, found %d" % plan.rects.size())


func test_windows_sit_in_pairs_away_from_corners_and_doorways() -> void:
	var r := plan.rects[house]
	for w in _parts(house, "wall_window_2m"):
		# The panel's origin is on the edge two wall tiles share; both
		# tiles and their outer neighbours along the side are walls.
		var at: Vector2 = w.at
		var along := Vector2i(1, 0) if w.dir in [0, 2] else Vector2i(0, 1)
		var back := Vector2(BuildingPlan.DIRS[w.dir]) * 0.5
		var mid := at - back
		var ta := Vector2i(floori(mid.x - 0.5 * along.x), floori(mid.y - 0.5 * along.y))
		var tb := ta + along
		for t in [ta - along, ta, tb, tb + along]:
			eq(world().tile(t.x, t.y), T.WALL, "window tile %s" % t)
		for t: Vector2i in [ta, tb]:
			var corner := (t.x == r.position.x or t.x == r.end.x - 1) and (t.y == r.position.y or t.y == r.end.y - 1)
			ok(not corner, "no window on a corner %s" % t)


func test_a_compound_is_a_yard_and_its_buildings_keep_their_roofs() -> void:
	var yard := _rect_at(Vector2i(206, 206))
	ok(yard >= 0, "the military compound's ring")
	eq(plan.rects[yard].size, Vector2i(28, 28))
	eq(plan.kinds[yard], BuildingPlan.YARD)
	eq(plan.styles[yard], FacadeArt.YARD)
	ok(not (yard in plan.roofed()), "a yard has no roof")
	eq(_parts(yard, "wall_window_2m").size(), 0)
	eq(_parts(yard, "porch_roof_2m").size(), 0)
	eq(_parts(yard, "door_open").size(), 0)
	ok(_parts(yard, "wall_1m").size() > 90, "the ring is panelled")
	eq(_parts(yard, "corner_post").size(), 4)
	var hut := _rect_at(Vector2i(210, 211))
	ok(hut >= 0, "the hut inside it")
	eq(plan.kinds[hut], BuildingPlan.BUILDING)
	ok(hut in plan.roofed(), "the hut keeps its roof")
	# Standing in the hut, the hut is what you are inside, not the yard.
	eq(plan.inside(Vector2i(214, 214)), hut)
	eq(plan.inside(Vector2i(208, 208)), -1)


func test_a_divider_cut_off_by_its_gaps_belongs_to_its_building() -> void:
	# The hardware store's middle wall is split from the ring by its own
	# gaps, and two doorways cut a stub off its north-east corner. Both
	# are the store's: one building, closed, with plaster dividers inside.
	eq(_rect_at(Vector2i(205, 142)), -1)
	eq(_rect_at(Vector2i(214, 136)), -1)
	var store := _rect_at(Vector2i(196, 136))
	ok(store >= 0, "the store")
	eq(plan.kinds[store], BuildingPlan.BUILDING)
	ok(store in plan.roofed(), "one roof over the store")
	ok(_parts(store, "wall_interior_arm").size() >= 20, "its dividers are plaster arms, %d of them" % _parts(store, "wall_interior_arm").size())
	# A divider is a post with an arm toward each wall it joins (never a
	# full panel poking past the other), and the arm that meets the ring
	# is the long one, buried in the outer wall's plaster.
	var posts := _parts(store, "wall_interior_post")
	ok(posts.size() >= 8, "posts at the dividers' tiles, %d" % posts.size())
	ok(_parts(store, "wall_interior_arm_long").size() >= 2, "a divider reaches the outer wall")
	for a in _parts(store, "wall_interior_arm") + _parts(store, "wall_interior_arm_long"):
		var on_post := false
		for p in posts:
			if is_equal_approx((a.at as Vector2).distance_to(p.at), 0.125):
				on_post = true
		ok(on_post, "an arm starts at a post's face, %s" % a.at)
	eq(_parts(store, "wall_doorway_2m").size(), 2)
	eq(plan.inside(Vector2i(206, 143)), store)
	# Nothing in the town is roofed inside something else that is roofed.
	for a in plan.roofed():
		for b in plan.roofed():
			ok(a == b or not plan.rects[a].grow(-1).encloses(plan.rects[b]), "roof %s over roof %s" % [plan.rects[a], plan.rects[b]])


func test_inside_counts_the_walls_and_the_doorway() -> void:
	eq(plan.inside(Vector2i(153, 153)), house)
	eq(plan.inside(Vector2i(150, 150)), house)
	eq(plan.inside(Vector2i(157, 156)), house)
	ok(plan.inside(Vector2i(149, 150)) != house, "the street is outside")


func test_a_broken_wall_is_a_gap_in_the_same_house() -> void:
	var w := World.new()
	var p := BuildingPlan.new()
	p.build(w)
	var ri := -1
	for i in range(p.rects.size()):
		if p.rects[i].position == Vector2i(150, 150):
			ri = i
	ok(ri >= 0, "the house is in a fresh world too")
	# A mid-wall tile on the north side whose neighbours both stand.
	var target := Vector2i(-1, -1)
	for x in range(152, 156):
		if w.tile(x, 150) == T.WALL and w.tile(x - 1, 150) == T.WALL and w.tile(x + 1, 150) == T.WALL:
			target = Vector2i(x, 150)
			break
	ok(target.x >= 0, "a mid-wall tile on the north side")
	var before := p.rects.size()
	w.break_wall(target.x, target.y)
	p.build(w)
	eq(p.rects.size(), before)
	eq(p.rects[ri], Rect2i(150, 150, 8, 7))
	eq(p.kinds[ri], BuildingPlan.BUILDING)
	for part in p.parts:
		if part.rect != ri:
			continue
		var at: Vector2 = part.at
		if part.part == "wall_1m" and part.dir == 2:
			ok(absf(at.x - (target.x + 0.5)) > 0.01, "the broken tile has no panel")
		ok(part.part != "porch_roof_2m" or at.y > 152.0, "rubble gets no canopy")


## Every building the generator stamped is drawn as one building, whatever
## its doorways cut (2026-10-14): two doorways and a divider's gap split a
## ring into arcs, and a flood of the walls alone called each arc a
## partition, so seven houses stood with no siding and no roof.
func test_every_generator_building_is_one_dressed_building() -> void:
	var by_rect := {}
	for i in range(plan.rects.size()):
		by_rect[plan.rects[i]] = plan.kinds[i]
	var bare := []
	for b in world().buildings:
		if by_rect.get(b.rect, "") != BuildingPlan.BUILDING:
			bare.append("%s %s -> %s" % [b.use, b.rect, by_rect.get(b.rect, "no rect")])
	eq(bare, [], "generator buildings the plan did not dress whole")
