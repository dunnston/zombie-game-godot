class_name Layout
extends RefCounted
## A building the owner laid out by hand (2026-10-14): `Config.LAYOUTS`,
## one row per layout, is a tile map and a list of things. The map is
## text, one character a tile — `#` wall, `.` floor, `+` a doorway in the
## outer wall, `-` an opening in a partition, a space for nothing (grass
## left as it is). A thing is `{what, x, y, d}` plus `w`, `h` (tiles,
## across its face and deep), `kind` ("furniture" unless said; "wall" for
## a piece hung on a wall tile), `container` (a searchable kind, which
## makes it a container rather than a prop) and `solid`. `x`, `y` are the
## top-left tile of its footprint inside the map, `d` the way it faces in
## quarter turns from south (0 south, 1 east, 2 north, 3 west), like
## everything `Furnish` stands.
##
## `stamp` puts one on the world exactly as written, so what the lab shows
## (`tools\lab.cmd`) is what the town will get. `problems` says what is
## wrong with a row before anything is stamped; `playable` is Furnish's
## rule asked of the whole house afterwards. Nothing here rolls a die:
## the only randomness is a thing's variant.

const T = Config.T
const W := Config.WORLD_TILES
const DIRS := Furnish.DIRS

const WALL := "#"
const FLOOR := "."
const DOOR := "+"
const GAP := "-"
const OUT := " "
const LEGEND := [WALL, FLOOR, DOOR, GAP, OUT]

const FLOOR_TILES := {"wood": T.FLOOR_WOOD, "tile": T.FLOOR_TILE, "dirt": T.DIRT, "gravel": T.GRAVEL}


## The map's size in tiles.
static func size(row: Dictionary) -> Vector2i:
	var map: Array = row.get("map", [])
	if map.is_empty():
		return Vector2i.ZERO
	return Vector2i(String(map[0]).length(), map.size())


## The tile character at a map position, a space outside the map.
static func at(row: Dictionary, x: int, y: int) -> String:
	var map: Array = row.get("map", [])
	if y < 0 or y >= map.size():
		return OUT
	var line := String(map[y])
	if x < 0 or x >= line.length():
		return OUT
	return line[x]


static func is_floor(ch: String) -> bool:
	return ch == FLOOR or ch == DOOR or ch == GAP


## How many tiles a thing covers: across its face and deep, from the
## model it draws as (`PropModels`, the box in metres is the tiles), or
## one by one. A container is always one tile.
static func size_of(what: String, container := "") -> Vector2i:
	if not container.is_empty():
		return Vector2i.ONE
	var parts := PropModels.resolve(PropModels.THINGS.get(what, null), 0)
	if parts.is_empty():
		return Vector2i.ONE
	var box: Vector3 = parts[0].box
	return Vector2i(maxi(1, roundi(box.x)), maxi(1, roundi(box.z)))


## The tiles a thing covers in the map, top-left and size, facing `d`.
static func footprint(t: Dictionary) -> Rect2i:
	var w := int(t.get("w", 1))
	var h := int(t.get("h", 1))
	var across := int(t.get("d", 0)) % 2 == 0
	return Rect2i(int(t.x), int(t.y), w if across else h, h if across else w)


## Puts layout `id` on the world with its map's top-left at (bx, by):
## tiles, then things. Records the building like `World._building` does
## (rect, floor, use, doors, interior) so the yards and the rest of the
## generator treat it as one of theirs. Returns the record.
static func stamp(world: World, bx: int, by: int, id: String) -> Dictionary:
	var row: Dictionary = Config.LAYOUTS[id]
	var sz := size(row)
	var floor_t: int = FLOOR_TILES.get(String(row.get("floor", "wood")), T.FLOOR_WOOD)
	var doors: Array[Vector2i] = []
	var interior: Array[Vector2i] = []
	for y in range(sz.y):
		for x in range(sz.x):
			var ch := at(row, x, y)
			var t := Vector2i(bx + x, by + y)
			match ch:
				WALL:
					world._put(t.x, t.y, T.WALL)
				FLOOR, GAP:
					world._put(t.x, t.y, floor_t)
				DOOR:
					world._put(t.x, t.y, floor_t)
					doors.append(t)
			if ch == FLOOR:
				interior.append(t)
	for thing in row.get("things", []):
		place(world, bx, by, thing)
	# Nothing grows against the walls or in front of a door (`_building`).
	world._clearing(bx - 1, by - 1, sz.x + 2, sz.y + 2)
	var rect := Rect2i(bx, by, sz.x, sz.y)
	for d in doors:
		var out := outward(rect, d)
		for k in range(1, 4):
			var t := d + out * k
			if World.in_bounds(t.x, t.y):
				world._no_tree[t.y * W + t.x] = 1
	var b := {"rect": rect, "floor": floor_t, "use": String(row.get("use", "house")),
		"vs": [], "hs": [], "doors": doors, "interior": interior, "layout": id}
	world.buildings.append(b)
	return b


## One thing of a layout onto the world. A container goes through the
## world's container list (it is searchable, and a save finds it by its
## tile); a hung piece carries whether its wall is an outer one, which is
## where the stage hangs it; everything else is a prop.
static func place(world: World, bx: int, by: int, t: Dictionary) -> Dictionary:
	var at_ := Vector2i(bx + int(t.x), by + int(t.y))
	var d := int(t.get("d", 0))
	if t.has("container"):
		var c := world._add_container(at_.x, at_.y, String(t.container))
		if not c.is_empty():
			c["dir"] = d
			c["si"] = world.rng.irange(0, 3)
		return c
	var kind := String(t.get("kind", "furniture"))
	var what := String(t.get("what", ""))
	var w := int(t.get("w", 1))
	var h := int(t.get("h", 1))
	var solid := bool(t.get("solid", kind != "wall"))
	var extra := {}
	if kind == "wall":
		# An outer wall has the outdoors behind it; a divider, another
		# room's floor (`Furnish._hang`).
		var beyond := at_ - DIRS[d]
		extra["outer"] = not (world.tile(beyond.x, beyond.y) in Furnish.FLOORS)
	return world.add_thing(kind, what, at_, w, h, d, solid, extra)


## Which way out of the building a door tile on its rectangle's edge faces.
static func outward(rect: Rect2i, d: Vector2i) -> Vector2i:
	if d.x == rect.position.x:
		return Vector2i(-1, 0)
	if d.x == rect.end.x - 1:
		return Vector2i(1, 0)
	if d.y == rect.position.y:
		return Vector2i(0, -1)
	return Vector2i(0, 1)


## What is wrong with a layout row before it is stamped: the map's shape
## and legend, a door that leads somewhere, every thing on the floor (or,
## hung, on a wall with floor before it), nothing on top of anything
## else. Empty when nothing is.
static func problems(row: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var map: Array = row.get("map", [])
	if map.is_empty():
		out.append("the map is empty")
		return out
	var sz := size(row)
	for y in range(map.size()):
		var line := String(map[y])
		if line.length() != sz.x:
			out.append("map row %d is %d wide, the first is %d" % [y, line.length(), sz.x])
		for x in range(line.length()):
			if not line[x] in LEGEND:
				out.append("map row %d has '%s', which is not in the legend" % [y, line[x]])
	if not out.is_empty():
		return out
	if not FLOOR_TILES.has(String(row.get("floor", "wood"))):
		out.append("floor '%s' is not one of %s" % [row.get("floor"), ", ".join(FLOOR_TILES.keys())])
	var doors := 0
	for y in range(sz.y):
		for x in range(sz.x):
			var ch := at(row, x, y)
			if ch == DOOR:
				doors += 1
				var floor_beside := false
				var out_beside := false
				for off in DIRS:
					var n := at(row, x + off.x, y + off.y)
					floor_beside = floor_beside or is_floor(n)
					out_beside = out_beside or n == OUT
				if not floor_beside or not out_beside:
					out.append("the doorway at %d,%d does not join the outside to the floor" % [x, y])
			elif ch == GAP:
				var floors := 0
				for off in DIRS:
					if is_floor(at(row, x + off.x, y + off.y)):
						floors += 1
				if floors < 2:
					out.append("the opening at %d,%d does not join two floors" % [x, y])
	if doors == 0:
		out.append("no doorway ('+') in the outer wall")
	var taken := {}
	var i := 0
	for t in row.get("things", []):
		var name := "thing %d (%s)" % [i, t.get("what", t.get("container", "?"))]
		i += 1
		if not t.has("x") or not t.has("y"):
			out.append("%s has no tile" % name)
			continue
		if not t.has("what") and not t.has("container"):
			out.append("%s names nothing" % name)
		var d := int(t.get("d", 0))
		if d < 0 or d > 3:
			out.append("%s faces %d, not 0..3" % [name, d])
			continue
		var f := footprint(t)
		var hung := String(t.get("kind", "")) == "wall"
		for y in range(f.position.y, f.end.y):
			for x in range(f.position.x, f.end.x):
				var ch := at(row, x, y)
				if hung:
					if ch != WALL:
						out.append("%s hangs at %d,%d, which is not a wall" % [name, x, y])
					elif not is_floor(at(row, x + DIRS[d].x, y + DIRS[d].y)):
						out.append("%s hangs at %d,%d facing %d, where there is no floor" % [name, x, y, d])
				elif ch != FLOOR:
					var what_is := "a wall" if ch == WALL else ("outside" if ch == OUT else "a doorway")
					out.append("%s covers %d,%d, which is %s" % [name, x, y, what_is])
				var key := y * 4096 + x
				if taken.has(key):
					out.append("%s covers %d,%d, where %s already is" % [name, x, y, taken[key]])
				taken[key] = name
	return out


## Furnish's rule asked of a stamped building: every free tile of it
## reaches every other, and everything solid in it can be reached from a
## free tile beside it. Checked after `stamp`, with the building it returned.
static func playable(world: World, b: Dictionary) -> bool:
	var cells: Array[Vector2i] = []
	var r: Rect2i = b.rect
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if world.tile(x, y) in Furnish.FLOORS:
				cells.append(Vector2i(x, y))
	if cells.is_empty():
		return false
	return Furnish.still_open(world, cells, Furnish._index(cells))
