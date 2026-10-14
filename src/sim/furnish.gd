class_name Furnish
extends RefCounted
## Dresses the town: what stands in a room, around a house and across a
## field (2026-10-14). The generator stamps a building and says what it is
## for; this decides, room by room, that the kitchen has a fridge against
## one wall and a table in the middle, and that a swing set stands in the
## yard and not in the doorway. Everything it places is a prop or a
## container in `World` — solid things block their tiles — so a guest
## builds the same rooms from the seed and a save finds every cabinet by
## its tile. How a piece looks is the stage's business (`PropModels`).
##
## The recipes are `Config.ROOMS`, `Config.DECOR` and `Config.YARD`. A
## piece is placed against a wall facing in, free in the middle with open
## floor around it, or hung on a wall; and the one rule that keeps the
## game playable is that a piece which would cut a room's floor in two, or
## leave a cabinet with no tile to search it from, is not placed.

const T = Config.T
const W := Config.WORLD_TILES
## Facings, in quarter turns from south: 0 south, 1 east, 2 north, 3 west.
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const FLOORS := [T.FLOOR_WOOD, T.FLOOR_TILE, T.DIRT, T.GRAVEL]
## Yard pieces stand this far out from the house at most.
const YARD_REACH := 4


# ------------------------------------------------------------------ houses --

## A home, room by room: the rooms are read off the building's partitions,
## given roles by where the door is and how big they are, and furnished
## from `Config.ROOMS`. `b` is a `World.buildings` record.
static func house(world: World, b: Dictionary) -> void:
	var rooms := rooms_of(b)
	var roles := roles_for(b, rooms)
	var set := _index(b.interior)
	for i in range(rooms.size()):
		var cells: Array[Vector2i] = []
		for c in b.interior:
			if rooms[i].has_point(c):
				cells.append(c)
		var recipe: Array = Config.ROOMS.get(roles[i], [])
		_apply(world, cells, set, recipe)


## The interior rectangles between a building's partition lines, floor only.
static func rooms_of(b: Dictionary) -> Array[Rect2i]:
	var r: Rect2i = b.rect
	var xs: Array[int] = [r.position.x]
	xs.append_array(b.vs)
	xs.append(r.end.x - 1)
	var ys: Array[int] = [r.position.y]
	ys.append_array(b.hs)
	ys.append(r.end.y - 1)
	var out: Array[Rect2i] = []
	for j in range(1, ys.size()):
		for i in range(1, xs.size()):
			var room := Rect2i(xs[i - 1] + 1, ys[j - 1] + 1, xs[i] - xs[i - 1] - 1, ys[j] - ys[j - 1] - 1)
			if room.size.x > 0 and room.size.y > 0:
				out.append(room)
	return out


## A role per room. One room is a studio (a shack's) or a cabin; two are
## the room with the door, which cooks and sits, and the one behind it,
## which sleeps and washes; three or more give the smallest the bathroom,
## the door its living room, the next a kitchen and the rest bedrooms. An
## apartment floor's lattice cycles through the four.
static func roles_for(b: Dictionary, rooms: Array[Rect2i]) -> PackedStringArray:
	var use := String(b.get("use", "house"))
	var out := PackedStringArray()
	out.resize(rooms.size())
	if rooms.size() == 1:
		out[0] = "cabin" if use == "cabin" else "studio"
		return out
	var entry := _door_room(b, rooms)
	if rooms.size() == 2:
		out[entry] = "living_kitchen"
		out[1 - entry] = "bedroom_bath"
		return out
	if use == "apartment" or rooms.size() > 4:
		var cycle := ["bedroom", "kitchen", "living", "bathroom"]
		for i in range(rooms.size()):
			out[i] = cycle[i % cycle.size()]
		out[entry] = "living"
		return out
	var order: Array[int] = []
	for i in range(rooms.size()):
		order.append(i)
	order.sort_custom(func(a: int, c: int) -> bool: return rooms[a].get_area() < rooms[c].get_area())
	out[entry] = "living"
	var bath := -1
	for i in order:
		if i != entry:
			bath = i
			break
	out[bath] = "bathroom"
	var kitchen := -1
	for i in range(rooms.size()):
		if i != entry and i != bath:
			if kitchen < 0:
				kitchen = i
				out[i] = "kitchen"
			else:
				out[i] = "bedroom"
	return out


## The room a doorway opens into: the one with a floor tile beside a door
## tile, or the first.
static func _door_room(b: Dictionary, rooms: Array[Rect2i]) -> int:
	for d: Vector2i in b.doors:
		for off in DIRS:
			var t: Vector2i = d + off
			for i in range(rooms.size()):
				if rooms[i].has_point(t):
					return i
	return 0


# --------------------------------------------------------------- the rest --

## Loose pieces across `cells` (a building's furnishable floor, or a room
## of an instance) from a `Config.DECOR` recipe: what an office or a shop
## has besides its cabinets.
static func dress(world: World, cells: Array[Vector2i], recipe: Array) -> void:
	_apply(world, cells, _index(cells), recipe)


## A classroom: desks in two rows across the front half facing the board,
## every other tile so there is an aisle between each, the back half left
## open; the board on the wall they face.
static func classroom(world: World, cells: Array[Vector2i], r: Rect2i) -> void:
	var set := _index(cells)
	for row in range(2):
		var y := r.position.y + 2 + row * 2
		var x := r.position.x + 2
		while x < r.end.x - 2:
			var t := Vector2i(x, y)
			if set.has(_i(t)) and not world.blocked[_i(t)] and not world.dressed.has(_i(t)):
				world.add_thing("furniture", "school_desk", t, 1, 1, 2, true)
			x += 2
	# The board: the wall tile nearest the middle of the front wall (the
	# middle itself may be the doorway).
	var mid := r.position.x + r.size.x / 2
	for k in range(0, r.size.x / 2):
		for x in [mid - k, mid + k]:
			var board := Vector2i(x, r.position.y)
			if x > r.position.x and x < r.end.x - 1 and world.tile(board.x, board.y) == T.WALL and not world.dressed.has(_i(board)):
				world.add_thing("wall", "chalkboard", board, 1, 1, 0, false, {"outer": true})
				return


## Rows of corn across a field, every other row, with the odd gap.
static func corn(world: World, r: Rect2i) -> void:
	var y := r.position.y + 1
	while y < r.end.y - 1:
		for x in range(r.position.x + 1, r.end.x - 1):
			var i := y * W + x
			if world.tiles[i] != T.FIELD or world.blocked[i] or world.dressed.has(i):
				continue
			if world.rng.chance(0.88):
				world.add_thing("corn", "corn", Vector2i(x, y), 1, 1, world.rng.irange(0, 3), false)
		y += 2


## What stands on the lot around a house: a few pieces from `Config.YARD`
## on the grass within reach of its walls, never on the way from a door,
## never touching anything else that stands, so the lawn stays a lawn you
## can cross.
static func yard(world: World, b: Dictionary, table: Array, n: int) -> void:
	var r: Rect2i = b.rect
	var keep := {}
	for d: Vector2i in b.doors:
		var out := Vector2i.ZERO
		if d.x == r.position.x:
			out = Vector2i(-1, 0)
		elif d.x == r.end.x - 1:
			out = Vector2i(1, 0)
		elif d.y == r.position.y:
			out = Vector2i(0, -1)
		else:
			out = Vector2i(0, 1)
		for k in range(1, 4):
			keep[_i(d + out * k)] = true
		var side := Vector2i(out.y, out.x)
		keep[_i(d + out + side)] = true
		keep[_i(d + out - side)] = true
	var lot := r.grow(YARD_REACH)
	var placed := 0
	var guard := 0
	while placed < n and guard < n * 12:
		guard += 1
		var piece: Dictionary = _weighted(world.rng, table)
		var dir := world.rng.irange(0, 3)
		var foot := _footprint(piece, dir)
		var spots: Array[Vector2i] = []
		for y in range(lot.position.y, lot.end.y - foot.y + 1):
			for x in range(lot.position.x, lot.end.x - foot.x + 1):
				var o := Vector2i(x, y)
				if Rect2i(o, foot).intersects(r):
					continue
				if _lawn_fits(world, o, foot, keep):
					spots.append(o)
		if spots.is_empty():
			continue
		var at: Vector2i = world.rng.pick(spots)
		world.add_thing("yard", String(piece.what), at, int(piece.get("w", 1)), int(piece.get("h", 1)), dir, bool(piece.get("solid", true)))
		placed += 1


static func _lawn_fits(world: World, o: Vector2i, foot: Vector2i, keep: Dictionary) -> bool:
	for j in range(-1, foot.y + 1):
		for i in range(-1, foot.x + 1):
			var t := o + Vector2i(i, j)
			if not World.in_bounds(t.x, t.y):
				return false
			var idx := _i(t)
			var ring := i < 0 or j < 0 or i >= foot.x or j >= foot.y
			if ring:
				# Nothing standing beside it but the house itself.
				if world.blocked[idx] and world.tiles[idx] != T.WALL:
					return false
				continue
			var tile: int = world.tiles[idx]
			if tile != T.GRASS and tile != T.DIRT:
				return false
			if world.blocked[idx] or world.dressed.has(idx) or world.prop_grid.has(idx) or world.no_tree(t.x, t.y) or keep.has(idx):
				return false
	return true


# ---------------------------------------------------------------- engine --

## Runs a recipe over a room. An entry is placed once, `n` times, or on a
## `chance`; `one_of` takes the first of its list that fits.
static func _apply(world: World, cells: Array[Vector2i], set: Dictionary, recipe: Array) -> void:
	for entry in recipe:
		_entry(world, cells, set, entry)


static func _entry(world: World, cells: Array[Vector2i], set: Dictionary, entry: Dictionary) -> bool:
	if entry.has("chance") and not world.rng.chance(float(entry.chance)):
		return false
	if entry.has("one_of"):
		for alt in entry.one_of:
			if _entry(world, cells, set, alt):
				return true
		return false
	var n := 1
	if entry.has("n"):
		n = world.rng.irange(int(entry.n[0]), int(entry.n[1]))
	var any := false
	for k in range(n):
		if _place(world, cells, set, entry):
			any = true
	return any


## One piece, somewhere it fits. Returns false when nowhere does.
static func _place(world: World, cells: Array[Vector2i], set: Dictionary, piece: Dictionary) -> bool:
	if piece.get("wall", false):
		return _hang(world, cells, set, piece)
	var solid := bool(piece.get("solid", true))
	var free := bool(piece.get("free", false))
	var run := 1
	if piece.has("run"):
		run = world.rng.irange(int(piece.run[0]), int(piece.run[1]))
	var spots: Array = []
	for d in range(4):
		var w := int(piece.get("w", 1)) * run
		var h := int(piece.get("h", 1))
		for c in cells:
			if _fits(world, set, c, d, w, h, free, solid):
				spots.append([c, d])
	while not spots.is_empty():
		var pick: Array = spots[world.rng.irange(0, spots.size() - 1)]
		spots.erase(pick)
		var c: Vector2i = pick[0]
		var d: int = pick[1]
		var w := int(piece.get("w", 1))
		var h := int(piece.get("h", 1))
		var made: Array[Dictionary] = []
		for k in range(run):
			var o: Vector2i = c + DIRS[(d + 1) % 4] * (k * w)
			var origin := _origin(o, d, w, h)
			if piece.has("container"):
				var cont := world._add_container(origin.x, origin.y, String(piece.container))
				if cont.is_empty():
					break
				cont["dir"] = d
				cont["si"] = world.rng.irange(0, 3)
				made.append(cont)
			else:
				made.append(world.add_thing(String(piece.get("kind", "furniture")), String(piece.what), origin, w, h, d, solid))
		if made.size() < run:
			for m in made:
				world.remove_thing(m)
			continue
		if not solid or still_open(world, cells, set):
			return true
		for m in made:
			world.remove_thing(m)
	return false


## Whether a piece `w` across and `h` deep, facing `d`, fits with its
## origin cell at `c`: against a wall (its back row on the wall) or free
## (open floor all round), on furnishable cells nothing stands on.
static func _fits(world: World, set: Dictionary, c: Vector2i, d: int, w: int, h: int, free: bool, solid: bool) -> bool:
	var fwd := DIRS[d]
	var side := DIRS[(d + 1) % 4]
	for i in range(w):
		for j in range(h):
			var t: Vector2i = c + side * i + fwd * j
			var idx := _i(t)
			if not set.has(idx) or world.blocked[idx] or world.dressed.has(idx):
				return false
			if free:
				for off in DIRS:
					var n: Vector2i = t + off
					var ni := _i(n)
					if not World.in_bounds(n.x, n.y) or world.tiles[ni] == T.WALL:
						return false
					if solid and world.blocked[ni]:
						return false
			elif j == 0:
				var back: Vector2i = t - fwd
				if not World.in_bounds(back.x, back.y) or world.tiles[_i(back)] != T.WALL:
					return false
	return true


## The top-left tile of a piece's footprint from its origin cell and facing.
static func _origin(c: Vector2i, d: int, w: int, h: int) -> Vector2i:
	var fwd := DIRS[d]
	var side := DIRS[(d + 1) % 4]
	var far: Vector2i = c + side * (w - 1) + fwd * (h - 1)
	return Vector2i(mini(c.x, far.x), mini(c.y, far.y))


## The tiles a piece covers when it faces `d`: its width runs along the
## wall it backs onto.
static func _footprint(piece: Dictionary, d: int) -> Vector2i:
	var w := int(piece.get("w", 1))
	var h := int(piece.get("h", 1))
	return Vector2i(w, h) if d % 2 == 0 else Vector2i(h, w)


## A piece on a wall: a wall tile beside the room, facing in.
static func _hang(world: World, cells: Array[Vector2i], set: Dictionary, piece: Dictionary) -> bool:
	var spots: Array = []
	var outer := {}
	for c in cells:
		for d in range(4):
			var wall: Vector2i = c - DIRS[d]
			var idx := _i(wall)
			if world.tiles[idx] != T.WALL or world.dressed.has(idx):
				continue
			spots.append([wall, d])
			# An outer wall has the outdoors behind it; a divider, another
			# room's floor. The stage hangs the piece on the panel's face.
			var beyond: Vector2i = wall - DIRS[d]
			outer[idx] = not World.in_bounds(beyond.x, beyond.y) or not (world.tiles[_i(beyond)] in FLOORS)
	if spots.is_empty():
		return false
	var pick: Array = spots[world.rng.irange(0, spots.size() - 1)]
	world.add_thing("wall", String(piece.what), pick[0], 1, 1, pick[1], false, {"outer": outer[_i(pick[0])]})
	return true


## The rule: every free floor tile of the room still reaches every other,
## and everything solid in it can be reached from a free tile beside it
## (a corner cabinet from the diagonal, as the interact range allows).
## `World._stock` asks it of every cabinet too.
static func still_open(world: World, cells: Array[Vector2i], set: Dictionary) -> bool:
	var r := _bounds(cells)
	var seen := {}
	var start := Vector2i(-1, -1)
	var free_n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var i := y * W + x
			if world.tiles[i] != T.WALL and not world.blocked[i]:
				free_n += 1
				if start.x < 0:
					start = Vector2i(x, y)
	if start.x < 0:
		return false
	var stack: Array[Vector2i] = [start]
	seen[_i(start)] = true
	while not stack.is_empty():
		var t: Vector2i = stack.pop_back()
		for off in DIRS:
			var n: Vector2i = t + off
			if not r.has_point(n):
				continue
			var ni := _i(n)
			if seen.has(ni) or world.tiles[ni] == T.WALL or world.blocked[ni]:
				continue
			seen[ni] = true
			stack.append(n)
	if seen.size() < free_n:
		return false
	for c in cells:
		var ci := _i(c)
		if not world.blocked[ci]:
			continue
		var beside := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := c + Vector2i(dx, dy)
				var ni := _i(n)
				if World.in_bounds(n.x, n.y) and world.tiles[ni] != T.WALL and not world.blocked[ni]:
					beside = true
		if not beside:
			return false
	return true


## The tiles the cells span, every one of them inside (`Rect2i.expand` would
## leave the last row and column on the edge, and a corner cell unchecked).
static func _bounds(cells: Array[Vector2i]) -> Rect2i:
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


static func _index(cells: Array[Vector2i]) -> Dictionary:
	var out := {}
	for c in cells:
		out[_i(c)] = true
	return out


static func _i(t: Vector2i) -> int:
	return t.y * W + t.x


static func _weighted(rng: Rng, table: Array) -> Dictionary:
	var total := 0.0
	for e in table:
		total += float(e.get("weight", 1))
	var r := rng.next() * total
	for e in table:
		r -= float(e.get("weight", 1))
		if r <= 0.0:
			return e
	return table[0]
