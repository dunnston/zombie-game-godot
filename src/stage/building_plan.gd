class_name BuildingPlan
extends RefCounted
## What the building parts dress, read off the world's tiles. Every
## eight-connected run of WALL tiles is a component with a bounding
## rectangle, and is one of three things:
##
## - a **building**: its rectangle's edge is a closed ring of its own tiles
##   with doorway gaps of at most three. It gets siding panels on every
##   outward face, 2 m window panels in a rhythm along each side, a doorway
##   panel with an open door and a canopy over each gap, a corner post at
##   each corner, and a roof (the stage builds that from the rectangle);
## - a **yard**: a closed ring with another closed ring inside it (the
##   military compound, the junkyard). Plain concrete panels, posts, no
##   windows, no roof: nothing goes over the buildings in it;
## - a **partition**: anything that does not close — the room dividers
##   inside a house, a line cut off by its own gaps. Plaster, no roof.
##
## Nothing here is a node; a test reads it headless. A wall chewed through
## is rubble that still joins its ring (`world.breached`), so a breach
## beside a doorway cannot cut a house in two.
##
## A part is placed by its origin on the ground (`at`, in tiles), its
## facing (`dir`, quarter turns from south = +z) and a width scale. Parts
## are modelled facing south with their body behind the face plane
## (`tools/build_kit.py`).

const T = Config.T
const W := Config.WORLD_TILES
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
## A window panel is two tiles wide and comes every this many tiles.
const WINDOW_EVERY := 4
## A doorway wider than this is not a doorway: the ring is open.
const GAP_MAX := 4

const BUILDING := "building"
const YARD := "yard"
const PARTITION := "partition"

var rects: Array[Rect2i] = []
var kinds: PackedStringArray = PackedStringArray()
var styles: PackedInt32Array = PackedInt32Array()
## {part, at: Vector2, dir, sx, rect}
var parts: Array[Dictionary] = []
var _members: Array = []    # per rect: Dictionary tile index -> true


func build(world: World) -> void:
	rects.clear()
	kinds.clear()
	styles.clear()
	parts.clear()
	_members.clear()
	_components(world)
	_merge_enclosed()
	_classify()
	for ri in range(rects.size()):
		match kinds[ri]:
			BUILDING:
				_dress(world, ri, true)
			YARD:
				_dress(world, ri, false)
			PARTITION:
				_partition(world, ri)


## Which buildings get a roof: every building, by rect index.
func roofed() -> PackedInt32Array:
	var out := PackedInt32Array()
	for ri in range(rects.size()):
		if kinds[ri] == BUILDING:
			out.append(ri)
	return out


## The smallest building the tile stands in, or -1: inside its rectangle,
## walls and doorway included, which is when its roof comes off.
func inside(tile: Vector2i) -> int:
	var best := -1
	var area := 0
	for ri in range(rects.size()):
		if kinds[ri] != BUILDING or not rects[ri].has_point(tile):
			continue
		var a := rects[ri].get_area()
		if best < 0 or a < area:
			best = ri
			area = a
	return best


func count(part: String, rect := -1) -> int:
	var n := 0
	for p in parts:
		if p.part == part and (rect < 0 or p.rect == rect):
			n += 1
	return n


func _components(world: World) -> void:
	var tiles := world.tiles
	var ring := PackedByteArray()
	ring.resize(W * W)
	for i in range(W * W):
		ring[i] = 1 if tiles[i] == T.WALL else 0
	for i in world.breached:
		if tiles[i] == T.RUBBLE:
			ring[i] = 1
	var seen := PackedByteArray()
	seen.resize(W * W)
	# The generator's buildings first, each one component whatever its
	# doorways cut (2026-10-14): two doorways and a divider's gap can split
	# a ring into arcs that never touch, and a flood called each arc a
	# partition and dressed the house with no facades and no roof. Seven of
	# the town's seventy-two were drawn that way, and every house in the
	# layout lab. Everything else (an instance's rooms, a fence of walls)
	# is still found by the flood below.
	for b in world.buildings:
		var r: Rect2i = b.rect
		var members := {}
		var lo := Vector2i(W, W)
		var hi := Vector2i(-1, -1)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var i := y * W + x
				if ring[i] == 0 or seen[i] == 1:
					continue
				seen[i] = 1
				members[i] = true
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if members.is_empty():
			continue
		rects.append(Rect2i(lo, hi - lo + Vector2i.ONE))
		styles.append(int(Util.hash2(lo.x * 13, lo.y * 7) * FacadeArt.HOUSE_STYLES))
		_members.append(members)
	for start in range(W * W):
		if ring[start] == 0 or seen[start] == 1:
			continue
		var stack: Array[int] = [start]
		seen[start] = 1
		var members := {}
		var lo := Vector2i(W, W)
		var hi := Vector2i(-1, -1)
		while not stack.is_empty():
			var i: int = stack.pop_back()
			members[i] = true
			var x := i % W
			var y := i / W
			lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
			hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx < 0 or ny < 0 or nx >= W or ny >= W:
						continue
					var n := ny * W + nx
					if ring[n] == 1 and seen[n] == 0:
						seen[n] = 1
						stack.append(n)
		rects.append(Rect2i(lo, hi - lo + Vector2i.ONE))
		styles.append(int(Util.hash2(lo.x * 13, lo.y * 7) * FacadeArt.HOUSE_STYLES))
		_members.append(members)


func _is_member(ri: int, t: Vector2i) -> bool:
	return _members[ri].has(t.y * W + t.x)


## A run that does not close and lies inside another component's rectangle
## is that component's: a room divider cut off by its own gaps, or the stub
## of a ring two doorways cut off at a corner (the hardware store's). A
## closed ring inside another is a building in a yard and stays its own.
func _merge_enclosed() -> void:
	var gone := PackedByteArray()
	gone.resize(rects.size())
	var changed := true
	while changed:
		changed = false
		for i in range(rects.size()):
			if gone[i] == 1 or _closed(i):
				continue
			var best := -1
			for j in range(rects.size()):
				if j == i or gone[j] == 1 or not rects[j].encloses(rects[i]):
					continue
				if best < 0 or rects[j].get_area() < rects[best].get_area():
					best = j
			if best < 0:
				continue
			(_members[best] as Dictionary).merge(_members[i])
			gone[i] = 1
			changed = true
	var rects2: Array[Rect2i] = []
	var styles2 := PackedInt32Array()
	var members2 := []
	for i in range(rects.size()):
		if gone[i] == 0:
			rects2.append(rects[i])
			styles2.append(styles[i])
			members2.append(_members[i])
	rects = rects2
	styles = styles2
	_members = members2


## A closed ring: every edge tile is the component's, bar doorway gaps of
## at most `GAP_MAX` that never take a corner.
func _closed(ri: int) -> bool:
	var r := rects[ri]
	if r.size.x < 3 or r.size.y < 3:
		return false
	for d in range(4):
		var line := _side(r, d)
		var run := 0
		for k in range(line.size()):
			if _is_member(ri, line[k]):
				run = 0
				continue
			if k == 0 or k == line.size() - 1:
				return false
			run += 1
			if run > GAP_MAX:
				return false
	return true


func _classify() -> void:
	kinds.resize(rects.size())
	var closed := PackedByteArray()
	closed.resize(rects.size())
	for ri in range(rects.size()):
		closed[ri] = 1 if _closed(ri) else 0
	for ri in range(rects.size()):
		if closed[ri] == 0:
			kinds[ri] = PARTITION
			continue
		kinds[ri] = BUILDING
		var inner := rects[ri].grow(-1)
		for rj in range(rects.size()):
			if rj != ri and closed[rj] == 1 and inner.encloses(rects[rj]):
				kinds[ri] = YARD
				styles[ri] = FacadeArt.YARD
				break


func _dress(world: World, ri: int, house: bool) -> void:
	var r := rects[ri]
	for d in range(4):
		var dir := DIRS[d]
		var line := _side(r, d)
		var windows := _window_pairs(ri, line) if house else PackedByteArray()
		var k := 0
		while k < line.size():
			var t := line[k]
			if _is_member(ri, t) and world.tile(t.x, t.y) == T.WALL:
				var at := Vector2(t) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
				if windows.size() > k and windows[k] == 1:
					# The pair k, k+1: the panel's origin on their shared edge.
					var t2 := line[k + 1]
					var mid := (Vector2(t) + Vector2(t2)) * 0.5 + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
					parts.append({"part": "wall_window_2m", "at": mid, "dir": d, "sx": 1.0, "rect": ri})
					parts.append({"part": "window_single", "at": mid, "dir": d, "sx": 1.0, "rect": ri})
					k += 2
					continue
				# A corner tile's panel stops a wall's thickness short of the
				# corner: the post fills that square, flush with both faces.
				var sx := 1.0
				if k == 0 or k == line.size() - 1:
					var v := Vector2(t.x + (1 if t.x == r.end.x - 1 else 0), t.y + (1 if t.y == r.end.y - 1 else 0))
					at += (at - v).normalized() * 0.125
					sx = 0.75
				parts.append({"part": "wall_1m", "at": at, "dir": d, "sx": sx, "rect": ri})
				k += 1
				continue
			if _is_member(ri, t):
				# Rubble where a wall was: open air, nothing to dress.
				k += 1
				continue
			# A doorway: the run of gap tiles, one panel across it with the
			# door hung on its left post and a canopy over it.
			var k0 := k
			while k < line.size() and not _is_member(ri, line[k]):
				k += 1
			var a := Vector2(line[k0]) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
			var b := Vector2(line[k - 1]) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
			var width := k - k0
			var centre := (a + b) * 0.5
			parts.append({"part": "wall_doorway_2m", "at": centre, "dir": d, "sx": width / 2.0, "rect": ri})
			if house:
				# Along the face, left is the panel's -x: a quarter turn back.
				var left := Vector2(DIRS[(d + 3) % 4])
				var hinge := centre + left * (width / 2.0 - 0.06 - 0.5)
				parts.append({"part": "door_open", "at": hinge, "dir": d, "sx": 1.0, "rect": ri})
				parts.append({"part": "porch_roof_2m", "at": centre, "dir": d, "sx": width / 2.0, "rect": ri})
	# The post's own faces are the -x and +z ones (west and south, unturned),
	# so it is turned to put them outward at each corner: 3 NW, 2 NE, 0 SW, 1 SE.
	var corners: Array = [[r.position, 3], [Vector2i(r.end.x - 1, r.position.y), 2], [Vector2i(r.position.x, r.end.y - 1), 0], [r.end - Vector2i.ONE, 1]]
	for cd: Array in corners:
		var c: Vector2i = cd[0]
		if world.tile(c.x, c.y) != T.WALL:
			continue
		var px := c.x + (1 if c.x == r.end.x - 1 else 0)
		var py := c.y + (1 if c.y == r.end.y - 1 else 0)
		parts.append({"part": "corner_post", "at": Vector2(px, py), "dir": int(cd[1]), "sx": 1.0, "rect": ri})
	# Room dividers inside a house are the house's own tiles off its ring.
	for i in _members[ri]:
		var t := Vector2i(i % W, i / W)
		if world.tile(t.x, t.y) != T.WALL:
			continue
		if t.x == r.position.x or t.x == r.end.x - 1 or t.y == r.position.y or t.y == r.end.y - 1:
			continue
		_divider(world, ri, t)


func _partition(world: World, ri: int) -> void:
	for i in _members[ri]:
		var t := Vector2i(i % W, i / W)
		if world.tile(t.x, t.y) == T.WALL:
			_divider(world, ri, t)


## A plaster wall through the middle of its tile, run the way its
## neighbours go.
## A room divider tile: a post at its centre and an arm toward each wall it
## joins, to the tile's edge where the next divider's arm meets it, or
## through a ring tile into the outer wall's plaster. Two runs meeting make
## a clean corner with nothing poking past the other (the owner's deal,
## 2026-10-14). A tile with no wall beside it is one plain panel across.
func _divider(world: World, ri: int, t: Vector2i) -> void:
	var c := Vector2(t) + Vector2(0.5, 0.5)
	var r := rects[ri]
	var arms: Array = []
	for d in range(4):
		var n: Vector2i = t + DIRS[d]
		if world.tile(n.x, n.y) != T.WALL:
			continue
		var ring := n.x == r.position.x or n.x == r.end.x - 1 or n.y == r.position.y or n.y == r.end.y - 1
		arms.append([d, ring])
	if arms.is_empty():
		parts.append({"part": "wall_interior_1m", "at": c + Vector2(0.0, 0.125), "dir": 0, "sx": 1.0, "rect": ri})
		return
	parts.append({"part": "wall_interior_post", "at": c, "dir": 0, "sx": 1.0, "rect": ri})
	for a: Array in arms:
		var d: int = a[0]
		# The arm's +x runs out from the post: a quarter turn back from `d`
		# (facing 0 points +x east; DIRS[1] is east).
		parts.append({"part": "wall_interior_arm_long" if a[1] else "wall_interior_arm", "at": c + Vector2(DIRS[d]) * 0.125, "dir": (d + 3) % 4, "sx": 1.0, "rect": ri})


## The perimeter tiles along side `d` of `r`, in order.
static func _side(r: Rect2i, d: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match d:
		0:
			for x in range(r.position.x, r.end.x):
				out.append(Vector2i(x, r.end.y - 1))
		1:
			for y in range(r.position.y, r.end.y):
				out.append(Vector2i(r.end.x - 1, y))
		2:
			for x in range(r.position.x, r.end.x):
				out.append(Vector2i(x, r.position.y))
		3:
			for y in range(r.position.y, r.end.y):
				out.append(Vector2i(r.position.x, y))
	return out


## Which tiles start a two-tile window panel along a side: never a corner,
## never beside a doorway, one pair every `WINDOW_EVERY`, centred.
func _window_pairs(ri: int, line: Array[Vector2i]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(line.size())
	var m := line.size() - 2
	if m < 2:
		return out
	var k := (m + 2) / WINDOW_EVERY
	if k < 1:
		return out
	var span := WINDOW_EVERY * (k - 1) + 2
	var offset := (m - span) / 2
	for j in range(k):
		var i := 1 + offset + WINDOW_EVERY * j
		if i < 1 or i + 1 > line.size() - 2:
			continue
		var clear := true
		for n in range(i - 1, i + 3):
			if not _is_member(ri, line[n]):
				clear = false
		if clear:
			out[i] = 1
	return out
