class_name BuildingPlan
extends RefCounted
## What the building kit dresses, read off the world's tiles: every run of
## WALL tiles is a building (the generator makes rectangles of them with
## doorway gaps, `World._building`), and each gets a rectangle, a style, a
## siding panel on every outward face, windows in a rhythm along each side,
## trim in the reveals beside a doorway, a corner board at each corner and a
## canopy over each doorway. The roof is the stage's to build from the
## rectangle. Nothing here is a node: a test reads it headless.
##
## Directions index `DIRS`: south, east, north, west — the yaw a piece modelled
## facing south (+z) is turned by, in quarter turns.

const T = Config.T
const W := Config.WORLD_TILES
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
## Windows sit every this many tiles along a side.
const WINDOW_EVERY := 3

var rects: Array[Rect2i] = []
var styles: PackedInt32Array = PackedInt32Array()
## Every standing wall tile, with its building.
var cores: Array[Dictionary] = []     # {tile, rect}
## {tile, dir, kind ("facade", "facade_window", "jamb"), rect}
var faces: Array[Dictionary] = []
## {at: Vector2i (the tile corner point), rect}
var corners: Array[Dictionary] = []
## {at: Vector2 (the gap's centre on the face line, tiles), dir, width, rect}
var porches: Array[Dictionary] = []
var _rect_of := {}   # tile index -> rect index


func build(world: World) -> void:
	rects.clear()
	styles.clear()
	cores.clear()
	faces.clear()
	corners.clear()
	porches.clear()
	_rect_of.clear()
	_components(world)
	for ri in range(rects.size()):
		_dress(world, ri)


## The building the tile stands in, or -1: inside its rectangle, walls and
## doorway included, which is when its roof comes off.
func inside(tile: Vector2i) -> int:
	for ri in range(rects.size()):
		if rects[ri].has_point(tile):
			return ri
	return -1


## Flood every WALL tile into its building (eight-connected: a partition
## wall meets the ring at a corner) and take the bounding rectangle. A wall
## chewed through is rubble now, but it still joins the ring it was part
## of (`world.breached`), or a breach beside a doorway would cut a house in
## two and give the stub a roof of its own.
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
	for start in range(W * W):
		if ring[start] == 0 or seen[start] == 1:
			continue
		var stack: Array[int] = [start]
		seen[start] = 1
		var members: Array[int] = []
		var lo := Vector2i(W, W)
		var hi := Vector2i(-1, -1)
		while not stack.is_empty():
			var i: int = stack.pop_back()
			members.append(i)
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
		var ri := rects.size()
		rects.append(Rect2i(lo, hi - lo + Vector2i.ONE))
		styles.append(int(Util.hash2(lo.x * 13, lo.y * 7) * FacadeArt.STYLES.size()))
		for i in members:
			_rect_of[i] = ri
			if tiles[i] == T.WALL:
				cores.append({"tile": Vector2i(i % W, i / W), "rect": ri})


func _dress(world: World, ri: int) -> void:
	var r := rects[ri]
	# Each side in turn: its outward direction, and the perimeter tiles
	# along it, corner to corner.
	for d in range(4):
		var dir := DIRS[d]
		var line: Array[Vector2i] = _side(r, d)
		var windows := _window_slots(world, line)
		for k in range(line.size()):
			var t := line[k]
			if world.tile(t.x, t.y) != T.WALL:
				continue
			var kind := "facade_window" if windows[k] else "facade"
			faces.append({"tile": t, "dir": d, "kind": kind, "rect": ri})
			# A reveal: this wall's face along the side, toward a doorway.
			for step: int in [-1, 1]:
				var j := k + step
				if j < 0 or j >= line.size():
					continue
				var g := line[j]
				var gt := world.tile(g.x, g.y)
				if gt != T.WALL and gt != T.RUBBLE:
					var toward := g - t
					faces.append({"tile": t, "dir": DIRS.find(toward), "kind": "jamb", "rect": ri})
		# Canopies: each run of non-wall tiles along the side that is a way in.
		var k := 0
		while k < line.size():
			var gt := world.tile(line[k].x, line[k].y)
			if gt == T.WALL or gt == T.RUBBLE:
				k += 1
				continue
			var k0 := k
			while k < line.size() and world.tile(line[k].x, line[k].y) != T.WALL and world.tile(line[k].x, line[k].y) != T.RUBBLE:
				k += 1
			var a := Vector2(line[k0]) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
			var b := Vector2(line[k - 1]) + Vector2(0.5, 0.5) + Vector2(dir) * 0.5
			porches.append({"at": (a + b) * 0.5, "dir": d, "width": k - k0, "rect": ri})
	# Corner boards where two outward faces meet: the four corners of the
	# rectangle, while the corner tile still stands.
	for c: Vector2i in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
		if world.tile(c.x, c.y) != T.WALL:
			continue
		var px := c.x + (1 if c.x == r.end.x - 1 else 0)
		var py := c.y + (1 if c.y == r.end.y - 1 else 0)
		corners.append({"at": Vector2i(px, py), "rect": ri})


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


## Which tiles along a side get a window: never a corner, never beside a
## doorway, and otherwise one every `WINDOW_EVERY`, centred on the side.
static func _window_slots(world: World, line: Array[Vector2i]) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(line.size())
	var m := line.size() - 2
	if m < 1:
		return out
	var k := (m + 1) / WINDOW_EVERY
	if k < 1:
		return out
	var span := WINDOW_EVERY * (k - 1) + 1
	var offset := (m - span) / 2
	for j in range(k):
		var i := 1 + offset + WINDOW_EVERY * j
		if i < 1 or i > line.size() - 2:
			continue
		var clear := true
		for n in range(i - 1, i + 2):
			if world.tile(line[n].x, line[n].y) != T.WALL:
				clear = false
		if clear:
			out[i] = 1
	return out
