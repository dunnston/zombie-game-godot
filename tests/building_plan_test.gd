extends "res://tests/test_case.gd"
## `BuildingPlan`: the town's buildings read off the tiles for the building
## kit. The starter house at (150, 150) is the generator's 8×7 with one
## 2-tile doorway (`World._gen_*`), which makes every count below exact.

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


func _of(list: Array, ri: int, kind := "") -> Array:
	var out := []
	for e in list:
		if e.rect == ri and (kind.is_empty() or e.get("kind", "") == kind):
			out.append(e)
	return out


func test_the_starter_house_is_found_whole() -> void:
	ok(house >= 0, "the 8×7 house at (150, 150) is a building")
	eq(plan.rects[house], Rect2i(150, 150, 8, 7))
	# Its ring is 26 wall tiles less the 2-tile doorway.
	eq(_of(plan.cores, house).size(), 24)
	ok(plan.styles[house] >= 0 and plan.styles[house] < FacadeArt.STYLES.size(), "a style from the table")
	ok(plan.rects.size() > 40, "the town has dozens of buildings, found %d" % plan.rects.size())


func test_every_outward_face_is_dressed_and_the_doorway_gets_its_trim() -> void:
	# 30 perimeter faces, 2 of them the doorway's gap.
	var panels := _of(plan.faces, house, "facade").size() + _of(plan.faces, house, "facade_window").size()
	eq(panels, 28)
	eq(_of(plan.faces, house, "jamb").size(), 2)
	eq(_of(plan.corners, house).size(), 4)
	var porches := _of(plan.porches, house)
	eq(porches.size(), 1)
	eq(int(porches[0].width), 2)
	# Every jamb faces along its side, at a tile that is not a wall.
	for j in _of(plan.faces, house, "jamb"):
		var g: Vector2i = j.tile + BuildingPlan.DIRS[j.dir]
		ok(world().tile(g.x, g.y) != T.WALL, "a jamb faces the doorway")


func test_windows_sit_in_a_rhythm_away_from_corners_and_doorways() -> void:
	var r := plan.rects[house]
	var windows := _of(plan.faces, house, "facade_window")
	ok(windows.size() >= 6, "a house this size has at least six windows, has %d" % windows.size())
	for w in windows:
		var t: Vector2i = w.tile
		var on_x_edge := t.x == r.position.x or t.x == r.end.x - 1
		var on_y_edge := t.y == r.position.y or t.y == r.end.y - 1
		ok(not (on_x_edge and on_y_edge), "no window on a corner tile %s" % t)
		# Its neighbours along the wall are walls: never beside the doorway.
		var along := Vector2i(1, 0) if w.dir in [0, 2] else Vector2i(0, 1)
		for s in [-1, 1]:
			var n: Vector2i = t + along * s
			eq(world().tile(n.x, n.y), T.WALL)
	# A side without a doorway, 8 or 7 long, carries two windows.
	for d in range(4):
		var side := BuildingPlan._side(r, d)
		var gaps := 0
		for t in side:
			if world().tile(t.x, t.y) != T.WALL:
				gaps += 1
		var n := 0
		for w in windows:
			if w.dir == d:
				n += 1
		if gaps == 0:
			eq(n, 2)


func test_inside_counts_the_walls_and_the_doorway() -> void:
	eq(plan.inside(Vector2i(153, 153)), house)
	eq(plan.inside(Vector2i(150, 150)), house)
	eq(plan.inside(Vector2i(157, 156)), house)
	ok(plan.inside(Vector2i(149, 150)) != house, "the street is outside")
	ok(plan.inside(Vector2i(150, 157)) != house, "the next row south is outside")


func test_a_broken_wall_is_a_gap_without_trim() -> void:
	var w := World.new()
	var p := BuildingPlan.new()
	p.build(w)
	var ri := -1
	for i in range(p.rects.size()):
		if p.rects[i].position == Vector2i(150, 150):
			ri = i
	ok(ri >= 0, "the house is in a fresh world too")
	# A plain panel whose neighbours along the wall both stand.
	var target := Vector2i(-1, -1)
	for f in _of(p.faces, ri, "facade"):
		var t: Vector2i = f.tile
		if t.x > 150 and t.x < 157 and t.y == 150 and w.tile(t.x - 1, t.y) == T.WALL and w.tile(t.x + 1, t.y) == T.WALL:
			target = t
			break
	ok(target.x >= 0, "a mid-wall panel on the north side")
	w.break_wall(target.x, target.y)
	p.build(w)
	for c in _of(p.cores, ri):
		ok(c.tile != target, "a broken wall has no core")
	for f in _of(p.faces, ri):
		ok(f.tile != target, "a broken wall has no face")
		if f.kind == "jamb":
			ok(f.tile + BuildingPlan.DIRS[f.dir] != target, "rubble gets no door trim")
	eq(_of(p.cores, ri).size(), 23)
