class_name World
extends RefCounted
## Builds and holds the map. The layout is authored (fixed seed + hand-placed
## districts) so the player can learn the town, while the small details are
## procedural. A faithful port of the prototype's createWorld: the same seed
## gives the same map, because the RNG is consumed in the same order.
##
## The world is 320 tiles square. The original 160-tile town sits in the
## middle (offset by TOWN_X/TOWN_Y) and the country wraps around it:
##
##              forest · lumber camp · lake · (forest)
##     farms |                                     | Crown Heights
##     river |               THE TOWN              | Downtown
##     ranch |                                     | Galleria Mall
##              orchard · outskirts · junkyard
##
## All static collision is tile-based: `blocked[i] == 1` stops players and
## enemies. Bullets ask SHOOT_OVER (water, fences) before stopping. Player-
## built structures live in a separate, destructible map (Phase 3).

const W := Config.WORLD_TILES
const TILE := Config.TILE
const T = Config.T

## Where the original town's (0,0) landed. Town coordinates are already shifted.
const TOWN_X := 80
const TOWN_Y := 80
const TOWN_W := 160

var world_seed: int
var tiles := PackedByteArray()
var blocked := PackedByteArray()
var mark := PackedByteArray()        # road centre lines: 1 horizontal, 2 vertical
var danger := PackedByteArray()      # 1..4 per tile
var props: Array[Dictionary] = []
var prop_grid := {}                  # tile index -> harvestable prop
var chopped: Array[int] = []         # tile indices harvested this run, for the save
var containers: Array[Dictionary] = []
var vehicle_spawns: Array[Dictionary] = []
var locations: Array[Dictionary] = []
var spawn_tiles: Array[Vector2i] = []
var rng: Rng

var _no_tree := PackedByteArray()    # tiles the woodland pass must leave alone


func _init(seed_value: int = 20240917) -> void:
	world_seed = seed_value
	rng = Rng.new(seed_value)
	var n := W * W
	tiles.resize(n)
	tiles.fill(T.GRASS)
	blocked.resize(n)
	mark.resize(n)
	danger.resize(n)
	danger.fill(1)
	_no_tree.resize(n)
	for l in Config.LOCATIONS:
		var d: Dictionary = l.duplicate()
		d["discovered"] = false
		locations.append(d)
	_generate()


# ---------------------------------------------------------------- helpers --

static func idx(x: int, y: int) -> int:
	return y * W + x


static func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < W


func tile(x: int, y: int) -> int:
	return tiles[y * W + x] if in_bounds(x, y) else T.WALL


func _put(x: int, y: int, t: int) -> void:
	if not in_bounds(x, y):
		return
	var i := y * W + x
	tiles[i] = t
	blocked[i] = Config.SOLID_BY_TILE[t]


func _block(x: int, y: int, v: int = 1) -> void:
	if in_bounds(x, y):
		blocked[y * W + x] = v


func _fill(x: int, y: int, w: int, h: int, t: int) -> void:
	for j in range(y, y + h):
		for i in range(x, x + w):
			_put(i, j, t)


func _clearing(x: int, y: int, w: int, h: int) -> void:
	for j in range(y, y + h):
		for i in range(x, x + w):
			if in_bounds(i, j):
				_no_tree[j * W + i] = 1


static func _is_ground(t: int) -> bool:
	return t == T.GRASS or t == T.DIRT or t == T.GRAVEL


# ------------------------------------------------------------------ water --

## An elliptical body of water with a sandy shore, slightly wobbled.
func _lake(cx: float, cy: float, rx: float, ry: float, wobble := 0.12) -> void:
	for y in range(floori(cy - ry - 3), floori(cy + ry + 3) + 1):
		for x in range(floori(cx - rx - 3), floori(cx + rx + 3) + 1):
			var a := atan2(y - cy, x - cx)
			var k := 1.0 + sin(a * 3 + cx) * wobble + cos(a * 5 + cy) * wobble * 0.5
			var dx := (x - cx) / (rx * k)
			var dy := (y - cy) / (ry * k)
			var d := dx * dx + dy * dy
			if d < 1:
				_put(x, y, T.WATER)
			elif d < 1.45 and _is_ground(tile(x, y)):
				_put(x, y, T.SAND)


## The Marrow: a meandering river down the west side of the map.
func river_centre(y: float) -> float:
	return 66 + 5 * sin(y * 0.05) + 2.5 * sin(y * 0.13 + 1.7)


func _river_half(y: float) -> float:
	return 3.2 + 0.9 * sin(y * 0.08 + 0.5)


# ------------------------------------------------------------------ roads --

func _road_h(y: int, thickness: int, x0 := 0, x1 := W) -> void:
	_fill(x0, y - 1, x1 - x0, thickness + 2, T.SIDEWALK)
	_fill(x0, y, x1 - x0, thickness, T.ROAD)
	var cy := y + (thickness >> 1)
	for x in range(x0, x1):
		mark[cy * W + x] = 1


func _road_v(x: int, thickness: int, y0 := 0, y1 := W) -> void:
	_fill(x - 1, y0, thickness + 2, y1 - y0, T.SIDEWALK)
	_fill(x, y0, thickness, y1 - y0, T.ROAD)
	var cx := x + (thickness >> 1)
	for y in range(y0, y1):
		mark[y * W + cx] = 2


## Unpaved: a gravel lane or a dirt track, no sidewalk, kept clear of trees.
func _lane(x: int, y: int, w: int, h: int, t: int = T.GRAVEL) -> void:
	_fill(x, y, w, h, t)
	_clearing(x - 1, y - 1, w + 2, h + 2)


## A dirt footpath between waypoints, two tiles wide.
func _trail(points: Array) -> void:
	for i in range(1, points.size()):
		var x: int = points[i - 1][0]
		var y: int = points[i - 1][1]
		var tx: int = points[i][0]
		var ty: int = points[i][1]
		var guard := 0
		while (x != tx or y != ty) and guard < 600:
			guard += 1
			if x != tx and (y == ty or rng.chance(0.5)):
				x += signi(tx - x)
			else:
				y += signi(ty - y)
			for off: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var px := x + off.x
				var py := y + off.y
				var t := tile(px, py)
				if _is_ground(t) or t == T.SAND:
					_put(px, py, T.DIRT)
				if in_bounds(px, py):
					_no_tree[py * W + px] = 1


# -------------------------------------------------------------- buildings --

## Stamps a rectangular building: solid perimeter, floor inside, doorway
## gaps, optional partitions. Returns the furnishable interior tiles.
## opts: floor, doors, door_sides, door_width, rooms, grid
func _building(bx: int, by: int, bw: int, bh: int, opts: Dictionary = {}) -> Array[Vector2i]:
	var floor_t: int = opts.get("floor", T.FLOOR_WOOD)
	_fill(bx, by, bw, bh, floor_t)
	for x in range(bx, bx + bw):
		_put(x, by, T.WALL)
		_put(x, by + bh - 1, T.WALL)
	for y in range(by, by + bh):
		_put(bx, y, T.WALL)
		_put(bx + bw - 1, y, T.WALL)

	# Doorways — at least one, always on an outer wall.
	var doors: int = opts.get("doors", 1)
	var door_sides: Array = opts.get("door_sides", [])
	var width: int = opts.get("door_width", 2)
	for d in range(doors):
		var side: int = door_sides[d % door_sides.size()] if door_sides.size() > 0 else rng.irange(0, 3)
		if side == 0:
			var x := bx + rng.irange(1, maxi(1, bw - width - 1))
			for i in range(width):
				_put(x + i, by, floor_t)
		elif side == 1:
			var x := bx + rng.irange(1, maxi(1, bw - width - 1))
			for i in range(width):
				_put(x + i, by + bh - 1, floor_t)
		elif side == 2:
			var y := by + rng.irange(1, maxi(1, bh - width - 1))
			for i in range(width):
				_put(bx, y + i, floor_t)
		elif side == 3:
			var y := by + rng.irange(1, maxi(1, bh - width - 1))
			for i in range(width):
				_put(bx + bw - 1, y + i, floor_t)

	# Partition lines: their gap tiles are the only way between rooms, so the
	# furnishing pass must never put a wardrobe in one.
	var vs: Array[int] = []
	var hs: Array[int] = []
	var grid = opts.get("grid", null)
	if grid != null and bw > 13 and bh > 13:
		# A tower floor: a lattice of rooms off a corridor, every wall with a
		# gap. No line closer than five tiles to the far wall.
		var step: int = 7 if grid is bool else grid
		var vx := bx + step
		while vx < bx + bw - 5:
			vs.append(vx)
			vx += step
		var hy := by + step
		while hy < by + bh - 5:
			hs.append(hy)
			hy += step
		for v in vs:
			for y in range(by + 1, by + bh - 1):
				_put(v, y, T.WALL)
		for h in hs:
			for x in range(bx + 1, bx + bw - 1):
				_put(x, h, T.WALL)
		var xs: Array[int] = [bx]
		xs.append_array(vs)
		xs.append(bx + bw - 1)
		var ys: Array[int] = [by]
		ys.append_array(hs)
		ys.append(by + bh - 1)
		for v in vs:
			for k in range(1, ys.size()):
				var y0 := ys[k - 1] + 1
				var y1 := ys[k] - 1
				if y1 - y0 >= 2:
					var g := rng.irange(y0, y1 - 1)
					_put(v, g, floor_t)
					_put(v, g + 1, floor_t)
		for h in hs:
			for k in range(1, xs.size()):
				var x0 := xs[k - 1] + 1
				var x1 := xs[k] - 1
				if x1 - x0 >= 2:
					var g := rng.irange(x0, x1 - 1)
					_put(g, h, floor_t)
					_put(g + 1, h, floor_t)
	elif opts.get("rooms", false) and bw > 9 and bh > 7:
		var vx := bx + floori(bw / 2.0) + rng.irange(-1, 1)
		vs.append(vx)
		for y in range(by + 1, by + bh - 1):
			_put(vx, y, T.WALL)
		if bh > 11:
			# Four rooms: every one of them gets a way into a neighbour.
			var hy := by + floori(bh / 2.0)
			hs.append(hy)
			for x in range(bx + 1, bx + bw - 1):
				if x != vx:
					_put(x, hy, T.WALL)
			var g0 := by + rng.irange(1, maxi(1, hy - by - 3))
			_put(vx, g0, floor_t)
			_put(vx, g0 + 1, floor_t)
			var g1 := hy + rng.irange(1, maxi(1, by + bh - hy - 4))
			_put(vx, g1, floor_t)
			_put(vx, g1 + 1, floor_t)
			var g2 := bx + rng.irange(1, maxi(1, vx - bx - 3))
			_put(g2, hy, floor_t)
			_put(g2 + 1, hy, floor_t)
			var g3 := vx + rng.irange(1, maxi(1, bx + bw - vx - 4))
			_put(g3, hy, floor_t)
			_put(g3 + 1, hy, floor_t)
		else:
			var gap := by + rng.irange(2, bh - 4)
			_put(vx, gap, floor_t)
			_put(vx, gap + 1, floor_t)

	# The furnishable interior: floor tiles not on a wall line and not beside
	# an opening in one. Two cabinets either side of a doorway would wall it
	# off as surely as bricks.
	var interior: Array[Vector2i] = []
	for y in range(by + 1, by + bh - 1):
		for x in range(bx + 1, bx + bw - 1):
			if _on_line(x, y, bx, by, bw, bh, vs, hs) or tiles[y * W + x] != floor_t:
				continue
			if _opening(x - 1, y, bx, by, bw, bh, vs, hs, floor_t) \
				or _opening(x + 1, y, bx, by, bw, bh, vs, hs, floor_t) \
				or _opening(x, y - 1, bx, by, bw, bh, vs, hs, floor_t) \
				or _opening(x, y + 1, bx, by, bw, bh, vs, hs, floor_t):
				continue
			interior.append(Vector2i(x, y))
	return interior


func _on_line(x: int, y: int, bx: int, by: int, bw: int, bh: int, vs: Array[int], hs: Array[int]) -> bool:
	return x == bx or x == bx + bw - 1 or y == by or y == by + bh - 1 or vs.has(x) or hs.has(y)


func _opening(x: int, y: int, bx: int, by: int, bw: int, bh: int, vs: Array[int], hs: Array[int], floor_t: int) -> bool:
	return _on_line(x, y, bx, by, bw, bh, vs, hs) and tiles[y * W + x] == floor_t


## A rail fence around a rectangle, with the listed tiles left open as gates.
func _fence_rect(fx: int, fy: int, fw: int, fh: int, gates: Array = []) -> void:
	var open := {}
	for g in gates:
		open[Vector2i(g[0], g[1])] = true
	for x in range(fx, fx + fw):
		_post(x, fy, open)
		_post(x, fy + fh - 1, open)
	for y in range(fy, fy + fh):
		_post(fx, y, open)
		_post(fx + fw - 1, y, open)


func _post(x: int, y: int, open: Dictionary) -> void:
	if not open.has(Vector2i(x, y)) and _is_ground(tile(x, y)):
		_put(x, y, T.FENCE)


## Tilled ground in rows. Walkable, buildable, and nothing grows on it.
func _field(x: int, y: int, w: int, h: int) -> void:
	_fill(x, y, w, h, T.FIELD)


func _add_container(tx: int, ty: int, kind: String) -> Dictionary:
	if not in_bounds(tx, ty) or blocked[ty * W + tx]:
		return {}
	if not Config.CONTAINERS.has(kind):
		return {}
	var def: Dictionary = Config.CONTAINERS[kind]
	var c := {
		"id": containers.size(), "kind": kind,
		"x": tx * TILE + TILE / 2.0, "y": ty * TILE + TILE / 2.0,
		"tx": tx, "ty": ty, "looted": false,
		"sprite": def.sprite, "label": def.label, "rolls": def.rolls, "table": def.table,
	}
	containers.append(c)
	_block(tx, ty, 1)
	return c


## Furnishes a building's interior. `kinds` is either a list of container
## kinds or a FURNISHING key, in which case fittings are drawn from that
## building type's weighted table. Furniture goes against walls.
func _stock(interior: Array[Vector2i], kinds, n: int) -> void:
	var table: Array = Config.FURNISHING[kinds] if kinds is String else []
	var list: Array = [] if kinds is String else kinds
	var near_wall: Array[Vector2i] = []
	for c in interior:
		if blocked[c.y * W + c.x - 1] or blocked[c.y * W + c.x + 1] \
			or blocked[(c.y - 1) * W + c.x] or blocked[(c.y + 1) * W + c.x]:
			near_wall.append(c)
	var pool := near_wall if near_wall.size() > n else interior
	var used := {}
	var placed := 0
	var guard := 0
	while placed < n and guard < n * 25 and pool.size() > 0:
		guard += 1
		var cell: Vector2i = rng.pick(pool)
		if used.has(cell):
			continue
		used[cell] = true
		var kind: String = _pick_kind(list, table)
		if not _add_container(cell.x, cell.y, kind).is_empty():
			placed += 1


func _pick_kind(list: Array, table: Array) -> String:
	if not list.is_empty():
		return rng.pick(list)
	var total := 0
	for e in table:
		total += e[1]
	var r := rng.next() * total
	for e in table:
		r -= e[1]
		if r <= 0:
			return e[0]
	return table[0][0]


# ---------------------------------------------------------- cars and props --

## Cars are spawned as vehicle definitions rather than scenery, because they
## can be driven away. `tiles` records which ones this car claimed.
func _add_car(tx: int, ty: int, rot: int) -> void:
	if not in_bounds(tx, ty):
		return
	var horizontal := rot == 0
	var tw := 2 if horizontal else 1
	var th := 1 if horizontal else 2
	for j in range(th):
		for i in range(tw):
			if not in_bounds(tx + i, ty + j) or blocked[(ty + j) * W + tx + i]:
				return
	var claimed: Array[Vector2i] = []
	for j in range(th):
		for i in range(tw):
			_block(tx + i, ty + j, 1)
			claimed.append(Vector2i(tx + i, ty + j))
	vehicle_spawns.append({
		"x": (tx + tw / 2.0) * TILE, "y": (ty + th / 2.0) * TILE,
		"rot": 0.0 if horizontal else PI / 2,
		"si": rng.irange(0, 3), "tiles": claimed, "seed": rng.irange(1, 0x7fffffff),
	})


func _add_wreck(tx: int, ty: int) -> void:
	if not in_bounds(tx, ty) or not in_bounds(tx + 1, ty):
		return
	if blocked[ty * W + tx] or blocked[ty * W + tx + 1]:
		return
	_block(tx, ty, 1)
	_block(tx + 1, ty, 1)
	props.append({"kind": "wreck", "si": rng.irange(0, 1), "rot": 0.0, "x": (tx + 1) * TILE, "y": (ty + 0.5) * TILE})


## A choppable tree on one tile. 470hp is six swings of the stone Hatchet at
## starting stats, and three of the Fire Axe.
func _plant_tree(x: int, y: int, pine := false) -> Dictionary:
	if not in_bounds(x, y) or blocked[y * W + x]:
		return {}
	var t := tiles[y * W + x]
	if t != T.GRASS and t != T.DIRT:
		return {}
	_block(x, y, 1)
	var tree := {
		"kind": "pine" if pine else "tree", "si": rng.irange(0, 3), "rot": 0.0, "tx": x, "ty": y,
		"x": (x + 0.5) * TILE, "y": (y + 0.5) * TILE,
		"hp": 470.0, "max_hp": 470.0, "harvest": "wood", "solid": true, "flash": 0.0,
	}
	props.append(tree)
	prop_grid[y * W + x] = tree
	return tree


## Ground litter: sticks, a loose stone, dry grass. Non-blocking, picked up
## with the interact key. The bottom of the gathering ladder.
func _plant_litter(x: int, y: int, res: String) -> Dictionary:
	if not in_bounds(x, y):
		return {}
	var i := y * W + x
	if blocked[i] or prop_grid.has(i):
		return {}
	var t := tiles[i]
	if t == T.WATER or t == T.WALL:
		return {}
	var prop := {
		"kind": "litter", "res": res, "si": rng.irange(0, 2), "rot": rng.frange(0, 6.28), "tx": x, "ty": y,
		"x": (x + 0.5) * TILE, "y": (y + 0.5) * TILE,
		"harvest": "litter_" + res, "hand": true, "solid": false, "flash": 0.0,
		"hp": 1.0, "max_hp": 1.0,
	}
	props.append(prop)
	prop_grid[i] = prop
	return prop


## Solid scenery that is not harvestable: hay bales (1 tile), silos (2x2).
func _add_scenery(kind: String, tx: int, ty: int, w := 1, h := 1) -> Dictionary:
	for j in range(h):
		for i in range(w):
			if not in_bounds(tx + i, ty + j) or blocked[(ty + j) * W + tx + i]:
				return {}
	for j in range(h):
		for i in range(w):
			_block(tx + i, ty + j, 1)
	var p := {"kind": kind, "si": rng.irange(0, 2), "rot": 0.0, "x": (tx + w / 2.0) * TILE, "y": (ty + h / 2.0) * TILE, "w": w, "h": h}
	props.append(p)
	return p


func _hay(tx: int, ty: int) -> void:
	_add_scenery("hay", tx, ty)


func _silo(tx: int, ty: int) -> void:
	_add_scenery("silo", tx, ty, 2, 2)


## A bush or a rock: walk-through scenery you break for fiber or stone.
func _plant_scenery(x: int, y: int) -> Dictionary:
	var i := y * W + x
	if prop_grid.has(i):
		return {}
	var bush := rng.chance(0.7)
	var prop := {
		"kind": "bush" if bush else "rock", "si": rng.irange(0, 2), "rot": rng.frange(0, 6.28), "tx": x, "ty": y,
		"x": (x + 0.5) * TILE, "y": (y + 0.5) * TILE,
		"hp": 24.0 if bush else 45.0, "max_hp": 24.0 if bush else 45.0, "harvest": "fiber" if bush else "stone",
		"hand": true, "solid": false, "flash": 0.0,
	}
	props.append(prop)
	prop_grid[i] = prop
	return prop


## The big stuff: a boulder needs a pickaxe, a thicket needs a scythe. A
## boulder blocks; a thicket does not — standing in one is how you use it.
func _plant_big(x: int, y: int, kind: String) -> Dictionary:
	if not in_bounds(x, y):
		return {}
	var i := y * W + x
	if blocked[i] or prop_grid.has(i):
		return {}
	var t := tiles[i]
	if t != T.GRASS and t != T.DIRT and t != T.GRAVEL and t != T.SAND:
		return {}
	var boulder := kind == "boulder"
	var si := rng.irange(0, 2)
	var rot := 0.0 if boulder else rng.frange(0, 6.28)
	var prop := {
		"kind": kind, "si": si, "rot": rot, "tx": x, "ty": y,
		"x": (x + 0.5) * TILE, "y": (y + 0.5) * TILE,
		"hp": 380.0 if boulder else 90.0, "max_hp": 380.0 if boulder else 90.0,
		"harvest": "boulder" if boulder else "thicket", "solid": boulder, "flash": 0.0,
	}
	if boulder:
		_block(x, y, 1)
	props.append(prop)
	prop_grid[i] = prop
	return prop


## How likely a random tile is to grow something, by where it is.
func _growth(x: int, y: int) -> float:
	if _no_tree[y * W + x]:
		return 0.0
	if y < 62:
		return 0.85                                   # the forest
	if x >= 240 and y < 272:
		return 0.03                                   # the city: a street tree
	if x < 56 and y < 260:
		return 0.05                                   # farmland
	if x >= TOWN_X and y >= TOWN_Y and x < TOWN_X + TOWN_W and y < TOWN_Y + TOWN_W:
		# Wooded at the edges, thinner in the middle — but never bare.
		var edge := mini(mini(x - TOWN_X, y - TOWN_Y), mini(TOWN_X + TOWN_W - 1 - x, TOWN_Y + TOWN_W - 1 - y))
		return clampf(0.62 - edge / 130.0, 0.18, 0.62)
	var border := mini(mini(x, y), mini(W - 1 - x, W - 1 - y))
	return 0.7 if border < 12 else 0.4                # the outskirts


func _grow(x: int, y: int) -> void:
	var i := y * W + x
	var t := tiles[i]
	if t != T.GRASS and t != T.DIRT:
		return
	if blocked[i] or prop_grid.has(i):
		return
	var p := _growth(x, y)
	if p <= 0 or not rng.chance(p):
		return
	if rng.chance(0.72):
		var pine := rng.chance(0.7 if y < 62 else 0.15)
		_plant_tree(x, y, pine)
	else:
		_plant_scenery(x, y)


# --------------------------------------------------------------- generate --

func _generate() -> void:
	# Grass variation: patches of dirt and rough ground.
	for y in range(W):
		for x in range(W):
			var n := sin(x * 0.09) * cos(y * 0.11) + sin((x + y) * 0.05) * 0.7
			if n > 1.1:
				_put(x, y, T.DIRT)
			elif n < -1.25:
				_put(x, y, T.GRAVEL)

	# The river.
	for y in range(W):
		var xc := river_centre(y)
		var hw := _river_half(y)
		for x in range(floori(xc - hw - 3), floori(xc + hw + 3) + 1):
			var d := absf(x + 0.5 - xc)
			if d < hw:
				_put(x, y, T.WATER)
			elif d < hw + 1.6 and _is_ground(tile(x, y)):
				_put(x, y, T.SAND)

	_lake(197, 28, 22, 14)          # Loon Lake, in the forest north of town
	_lake(150, 95, 6, 5, 0.18)      # the town pond, beside the suburbs
	_lake(14, 118, 5, 4, 0.2)       # a farm pond
	_lake(28, 238, 4, 3, 0.2)       # the ranch's stock pond

	# Roads are laid over the river, which is what makes a bridge.
	_road_h(158, 5)                       # the highway: farms — bridge — town — downtown
	_road_h(106, 4, 26, W)                # north road: farm lane — bridge — town — Crown Heights
	_road_h(194, 4, 82, 240)              # south road: ends at the riverbank
	_road_v(158, 5)                       # main street: forest — town — junkyard — south
	_road_v(106, 4, 44, 250)              # west street: lumber yard down to the orchard
	_road_v(194, 4, 52, 248)              # east street: the lake lodge down to the junkyard gate
	_road_v(262, 4, 60, 222)
	_road_v(290, 4, 60, 272)
	_road_h(84, 4, 240, W)
	_road_h(130, 4, 240, W)
	_road_h(184, 4, 240, W)
	_road_h(218, 4, 196, W)               # the checkpoint slip road runs on into the mall district
	_fill(218, 196, 4, 40, T.ROAD)        # ...and its spur up to the compound gate
	_lane(28, 66, 3, 190)                 # the farm lane, north farm down to the ranch
	_lane(20, 78, 8, 3)
	_lane(20, 174, 8, 3)
	_lane(20, 216, 8, 3)
	_lane(31, 76, 6, 3)
	_lane(31, 172, 6, 3)
	_lane(31, 212, 4, 3)

	_gen_town()
	_gen_country()
	_gen_forest()
	_gen_city()
	_gen_junkyard()

	# Roadside wrecks on the main arteries — cover and obstacles.
	for i in range(70):
		var along := rng.irange(4, W - 6)
		var r := rng.next()
		if r < 0.3:
			_add_wreck(along, 159)
		elif r < 0.5:
			_add_wreck(maxi(28, along), 107)
		elif r < 0.8:
			_add_wreck(159, along)
		else:
			_add_wreck(195, clampi(along, 54, 246))

	_gen_woodland()
	_gen_litter()
	_gen_danger_and_spawns()


func _gen_town() -> void:
	# camp: a couple of shacks, a wreck, and easy pickings.
	_stock(_building(150, 150, 8, 7, {"doors": 1}), "house", 4)
	_stock(_building(164, 164, 7, 6, {"doors": 1}), "house", 4)
	_stock(_building(148, 166, 9, 6, {"doors": 2}), "house", 5)

	# suburbs
	for lot in [
		[90, 90, 13, 10], [108, 88, 12, 9], [126, 90, 14, 11],
		[90, 110, 12, 10], [110, 110, 15, 11], [130, 112, 12, 9],
		[92, 128, 14, 11], [114, 130, 13, 10], [132, 130, 12, 9],
		[88, 146, 12, 9], [120, 146, 11, 8],
	]:
		var doors := rng.irange(1, 2)
		var interior := _building(lot[0], lot[1], lot[2], lot[3], {"doors": doors, "rooms": true})
		var n := rng.irange(5, 8)
		_stock(interior, "house", n)
		_fill(lot[0] + 2, lot[1] + lot[3], 3, 3, T.GRAVEL)
		if rng.chance(0.55):
			_add_car(lot[0] + 2, lot[1] + lot[3] + 1, 0)

	# east homes
	for lot in [
		[178, 88, 14, 11], [198, 88, 13, 10], [216, 90, 13, 11],
		[178, 106, 12, 10], [198, 106, 14, 11], [216, 108, 13, 10],
		[180, 122, 15, 8], [202, 122, 14, 8], [220, 122, 10, 8],
	]:
		var doors := rng.irange(1, 2)
		var interior := _building(lot[0], lot[1], lot[2], lot[3], {"doors": doors, "rooms": true})
		var n := rng.irange(6, 9)
		_stock(interior, "house", n)
		if rng.chance(0.5):
			_add_car(lot[0] + 3, lot[1] + lot[3] + 1, 0)

	# market row
	var conv := _building(174, 138, 16, 12, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 2]})
	_stock(conv, "store", 11)
	_fill(174, 151, 16, 4, T.LOT)
	var hard := _building(196, 136, 20, 14, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 3], "rooms": true})
	_stock(hard, "hardware", 14)
	_fill(196, 151, 20, 5, T.LOT)
	_add_car(200, 152, 0)
	_add_car(208, 152, 0)
	var pawn := _building(220, 138, 12, 11, {"floor": T.FLOOR_TILE, "doors": 1})
	_stock(pawn, "pawn", 8)
	_fill(172, 162, 60, 6, T.LOT)
	for i in range(7):
		_add_car(174 + i * 8, 163, 0)

	# fuel stop
	var shop := _building(110, 164, 11, 8, {"floor": T.FLOOR_TILE, "doors": 1, "door_sides": [1]})
	_stock(shop, "store", 7)
	_fill(110, 173, 24, 8, T.LOT)
	for i in range(4):
		_add_container(114 + i * 4, 176, "fuelPump")
	_add_car(124, 174, 0)
	_add_car(128, 179, 0)
	_add_wreck(120, 179)

	# police
	var main := _building(180, 178, 24, 18, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 2], "rooms": true})
	_stock(main, "police", 14)
	var arm := _building(206, 180, 10, 9, {"floor": T.FLOOR_TILE, "doors": 1, "door_sides": [2]})
	_stock(arm, ["gunSafe", "gunSafe", "policeLocker", "footlocker"], 6)
	_fill(180, 198, 30, 6, T.LOT)
	for i in range(5):
		_add_car(182 + i * 6, 199, 0)
	for x in range(180, 204):
		if x % 5 != 0:
			_put(x, 176, T.RUBBLE)

	# hospital
	var hosp := _building(94, 192, 30, 22, {"floor": T.FLOOR_TILE, "doors": 3, "door_sides": [0, 2, 3], "rooms": true})
	_stock(hosp, ["pharmacy", "hospitalCrate"], 4)   # the dispensary, guaranteed
	_stock(hosp, "hospital", 14)
	var wing := _building(96, 218, 20, 10, {"floor": T.FLOOR_TILE, "doors": 1})
	_stock(wing, "hospital", 8)
	_fill(126, 196, 10, 18, T.LOT)
	_add_wreck(128, 200)
	_add_car(128, 208, 0)

	# industrial
	var warehouse := _building(144, 200, 26, 20, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 3]})
	_stock(warehouse, "industrial", 15)
	for y in range(206, 216, 4):
		for x in range(148, 166):
			if x % 7 != 0:
				_put(x, y, T.RUBBLE)
	_fill(144, 222, 26, 8, T.LOT)
	_add_wreck(148, 224)
	_add_car(156, 224, 0)
	_add_wreck(164, 225)

	# military: fenced compound with a single vehicle gate.
	var cx := 206
	var cy := 206
	var cw := 28
	var ch := 28
	for x in range(cx, cx + cw):
		_put(x, cy, T.WALL)
		_put(x, cy + ch - 1, T.WALL)
	for y in range(cy, cy + ch):
		_put(cx, y, T.WALL)
		_put(cx + cw - 1, y, T.WALL)
	_fill(cx + 1, cy + 1, cw - 2, ch - 2, T.GRAVEL)
	for i in range(4):
		_put(cx + 12 + i, cy, T.GRAVEL)
	var hut := _building(cx + 4, cy + 5, 10, 8, {"floor": T.FLOOR_TILE, "doors": 1, "door_sides": [1]})
	_stock(hut, "military", 7)
	var bar := _building(cx + 16, cy + 16, 10, 9, {"floor": T.FLOOR_TILE, "doors": 1, "door_sides": [0]})
	_stock(bar, "military", 7)
	for i in range(7):
		_add_container(cx + 4 + i * 3, cy + 21, "militaryCrate")
	for i in range(4):
		_add_container(cx + 18 + i * 2, cy + 4, "militaryCrate")
	for x in range(cx + 3, cx + 25):
		if x % 4 != 0:
			_put(x, cy + 2, T.RUBBLE)
	_add_wreck(cx + 17, cy + 9)
	_add_wreck(cx + 21, cy + 11)


func _gen_country() -> void:
	# farms: north farmstead, above the north road.
	var h := _building(8, 74, 12, 9, {"doors": 1, "door_sides": [3], "rooms": true})
	_stock(h, "house", 7)
	var b := _building(34, 72, 14, 10, {"floor": T.DIRT, "doors": 1, "door_sides": [2], "door_width": 3})
	_stock(b, "barn", 8)
	_silo(49, 73)
	for i in range(5):
		var hx := 36 + i * 2 + rng.irange(0, 1)
		var hy := 84 + rng.irange(0, 1)
		_hay(hx, hy)
	_add_car(22, 84, 0)                       # the farm truck
	_field(6, 88, 20, 12)
	_field(34, 88, 16, 12)
	# Windbreak between the north fields and the middle ones.
	for x in range(6, 52, 2):
		if x < 27 or x > 31:
			var pine := rng.chance(0.4)
			_plant_tree(x, 102, pine)
	_fence_rect(34, 106, 16, 9, [[41, 106], [42, 106]])
	for i in range(4):
		_hay(37 + i * 3, 110)
	_field(4, 126, 22, 14)
	_field(34, 118, 16, 24)
	var feed := _building(34, 146, 14, 9, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [1, 2]})
	_stock(feed, "farmstore", 9)
	_fill(32, 155, 18, 2, T.LOT)
	_add_container(49, 148, "fuelDrum")
	_add_container(49, 150, "fuelDrum")
	_add_car(36, 155, 0)
	_add_car(44, 155, 0)
	# South farmstead, below the highway.
	h = _building(8, 170, 11, 8, {"doors": 1, "door_sides": [3], "rooms": true})
	_stock(h, "house", 6)
	b = _building(36, 168, 12, 9, {"floor": T.DIRT, "doors": 1, "door_sides": [2], "door_width": 3})
	_stock(b, "barn", 7)
	_silo(49, 169)
	var coop := _building(22, 170, 5, 4, {"doors": 1, "door_sides": [1]})
	_stock(coop, ["cabinet", "crate"], 1)
	_field(4, 182, 22, 14)
	_field(32, 182, 18, 12)
	for i in range(4):
		_hay(34 + i * 3, 196)
	for x in range(6, 52, 2):
		if x < 27 or x > 31:
			var pine := rng.chance(0.4)
			_plant_tree(x, 200, pine)

	# ranch
	var rh := _building(8, 212, 12, 8, {"doors": 1, "door_sides": [3], "rooms": true})
	_stock(rh, "house", 6)
	var stable := _building(32, 208, 16, 8, {"floor": T.DIRT, "doors": 2, "door_sides": [1, 2], "door_width": 3})
	_stock(stable, "barn", 8)
	_add_car(22, 220, 0)
	_fence_rect(6, 224, 44, 28, [[28, 224], [29, 224], [30, 224], [6, 236], [6, 237]])
	for i in range(7):
		var hx := 9 + rng.irange(0, 38)
		var hy := 228 + rng.irange(0, 21)
		_hay(hx, hy)
	_clearing(6, 224, 44, 28)

	# the orchard: rows of fruit trees south of the hospital.
	_clearing(86, 246, 50, 28)
	for y in range(250, 272, 4):
		for x in range(88, 134, 4):
			if x >= 104 and x <= 111:
				continue                          # the west street runs through
			var ox := x + rng.irange(0, 1)
			var oy := y + rng.irange(0, 1)
			_plant_tree(ox, oy, false)
	var shed := _building(114, 246, 8, 5, {"floor": T.DIRT, "doors": 1, "door_sides": [1]})
	_stock(shed, ["logPile", "toolbox", "crate"], 2)


func _gen_forest() -> void:
	# lumber camp
	_lane(94, 22, 32, 26, T.DIRT)          # the yard
	var mill := _building(96, 24, 14, 9, {"floor": T.FLOOR_WOOD, "doors": 1, "door_sides": [1], "door_width": 3})
	_stock(mill, "lumber", 8)
	var bunk := _building(114, 26, 10, 7, {"doors": 1, "door_sides": [1]})
	_stock(bunk, "cabin", 5)
	for i in range(8):
		_add_container(96 + i * 2, 38, "logPile")
	for i in range(7):
		_add_container(97 + i * 2, 41, "logPile")
	_add_container(124, 40, "fuelDrum")
	_add_container(124, 42, "fuelDrum")
	_add_car(114, 44, 0)                    # the log truck
	_add_wreck(120, 46)

	# lake: the lodge and its boathouse on the south shore.
	var lodge := _building(174, 44, 13, 8, {"doors": 2, "door_sides": [0, 1], "rooms": true})
	_stock(lodge, "cabin", 8)
	var boat := _building(206, 43, 7, 5, {"floor": T.FLOOR_WOOD, "doors": 1, "door_sides": [0]})
	_stock(boat, ["crate", "toolbox", "footlocker"], 2)
	_lane(188, 50, 12, 4)
	_add_car(190, 51, 0)
	_add_wreck(196, 52)
	for y in range(43, 34, -1):              # a plank jetty out over the water
		_put(197, y, T.FLOOR_WOOD)
		_put(198, y, T.FLOOR_WOOD)
	_clearing(172, 42, 44, 12)

	# hunting cabins + trails
	for c in [[24, 20, 7, 6], [140, 12, 7, 6], [228, 30, 7, 6], [46, 46, 6, 5]]:
		var cabin := _building(c[0], c[1], c[2], c[3], {"doors": 1})
		_stock(cabin, "cabin", 3)
		_clearing(c[0] - 2, c[1] - 2, c[2] + 4, c[3] + 4)
	_trail([[27, 27], [27, 66]])
	_trail([[49, 52], [49, 66]])
	_trail([[143, 19], [143, 30], [156, 30]])
	_trail([[231, 37], [231, 60], [239, 60]])
	_trail([[110, 52], [110, 44]])
	_trail([[176, 52], [176, 60], [193, 60]])


func _gen_city() -> void:
	# heights
	for blk in [
		[242, 64, 18, 16], [266, 64, 22, 16], [294, 64, 22, 16],
		[242, 90, 18, 14], [266, 90, 22, 14], [294, 90, 22, 14],
		[242, 112, 18, 14], [294, 112, 22, 14],
	]:
		var s0 := rng.irange(0, 1)
		var s1 := rng.irange(2, 3)
		var interior := _building(blk[0], blk[1], blk[2], blk[3], {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [s0, s1], "grid": 6})
		var n := rng.irange(9, 13)
		_stock(interior, "apartment", n)
	var corner := _building(266, 112, 22, 14, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [1, 3]})
	_stock(corner, "store", 9)
	for y in [83, 109, 129]:
		for x in range(244, 316, 9):
			if rng.chance(0.55):
				_add_car(x, y, 0)
			else:
				_add_wreck(x, y)

	# downtown
	var t := _building(242, 134, 18, 20, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [1, 3], "grid": 6})
	_stock(t, "office", 12)
	var bank := _building(266, 136, 22, 18, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [1, 2], "rooms": true})
	_stock(bank, ["safe", "safe", "safe", "gunSafe"], 4)   # the vault, guaranteed
	_stock(bank, "bank", 9)
	t = _building(294, 134, 24, 20, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [1, 2], "grid": 7})
	_stock(t, "office", 13)
	for y in range(157, 164):
		if y != 160:
			_put(247, y, T.RUBBLE)
	_add_container(249, 156, "militaryCrate")
	_add_container(249, 164, "militaryCrate")
	_add_container(251, 157, "militaryCrate")
	_add_wreck(252, 160)
	_add_wreck(258, 158)
	_add_wreck(244, 162)
	# Plaza: paving, a dead fountain, and the last vending machines in town.
	_fill(242, 164, 20, 19, T.LOT)
	for y in range(170, 177):
		for x in range(248, 256):
			var dx := (x - 251.5) / 3.5
			var dy := (y - 173) / 3.0
			if dx * dx + dy * dy < 1:
				_put(x, y, T.WATER)
	_add_container(243, 165, "vending")
	_add_container(260, 165, "vending")
	_add_container(243, 181, "vending")
	for i in range(6):
		var rx := 244 + rng.irange(0, 16)
		var ry := 165 + rng.irange(0, 17)
		_put(rx, ry, T.RUBBLE)
	t = _building(266, 164, 22, 18, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 1], "grid": 6})
	_stock(t, "office", 12)
	_fill(294, 164, 26, 19, T.LOT)
	for y in range(166, 182, 4):
		for x in range(296, 316, 5):
			if rng.chance(0.5):
				_add_car(x, y, 0)
			elif rng.chance(0.6):
				_add_wreck(x, y)
	t = _building(242, 188, 18, 24, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 3], "grid": 6})
	_stock(t, "office", 14)
	var hall := _building(266, 190, 22, 24, {"floor": T.FLOOR_TILE, "doors": 3, "door_sides": [0, 2, 3], "grid": 7})
	_stock(hall, "office", 15)
	t = _building(294, 190, 24, 24, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [0, 2], "grid": 7})
	_stock(t, "office", 14)
	for i in range(18):
		var wx := rng.irange(242, 316)
		var wy: int = rng.pick([131, 132, 159, 160, 161, 185, 186])
		_add_wreck(wx, wy)
	for y in [137, 150, 168, 178, 196, 206]:
		if rng.chance(0.7):
			_add_wreck(290 + rng.irange(0, 2), y)

	# mall
	var mall := _building(242, 224, 46, 20, {"floor": T.FLOOR_TILE, "doors": 4, "door_sides": [0, 1, 2, 3], "door_width": 3, "grid": 8})
	_stock(mall, "mall", 22)
	_fill(242, 246, 46, 20, T.LOT)
	for y in range(248, 264, 4):
		for x in range(244, 286, 5):
			if rng.chance(0.45):
				_add_car(x, y, 0)
			elif rng.chance(0.5):
				_add_wreck(x, y)
	var drug := _building(294, 226, 22, 12, {"floor": T.FLOOR_TILE, "doors": 2, "door_sides": [1, 2]})
	_stock(drug, "drugstore", 9)
	var guns := _building(294, 244, 22, 12, {"floor": T.FLOOR_TILE, "doors": 1, "door_sides": [2]})
	_stock(guns, "gunshop", 9)
	_fill(294, 258, 22, 6, T.LOT)
	_add_car(296, 259, 0)
	_add_wreck(304, 260)
	_add_car(310, 259, 0)


func _gen_junkyard() -> void:
	var cx := 166
	var cy := 250
	var cw := 48
	var ch := 42
	for x in range(cx, cx + cw):
		_put(x, cy, T.WALL)
		_put(x, cy + ch - 1, T.WALL)
	for y in range(cy, cy + ch):
		_put(cx, y, T.WALL)
		_put(cx + cw - 1, y, T.WALL)
	_fill(cx + 1, cy + 1, cw - 2, ch - 2, T.GRAVEL)
	for i in range(4):
		_put(194 + i, cy, T.GRAVEL)
	var crusher := _building(cx + 4, cy + 4, 12, 8, {"floor": T.GRAVEL, "doors": 1, "door_sides": [3]})
	_stock(crusher, "junk", 6)
	var office := _building(cx + 34, cy + 4, 10, 7, {"floor": T.FLOOR_WOOD, "doors": 1, "door_sides": [2]})
	_stock(office, "junk", 4)
	for y in range(cy + 14, cy + ch - 4, 5):
		for x in range(cx + 3, cx + cw - 4, 4):
			if rng.chance(0.78):
				_add_wreck(x, y)
			elif rng.chance(0.5):
				var kind: String = rng.pick(["toolbox", "fuelDrum", "crate", "electronics"])
				_add_container(x, y, kind)
	_add_car(cx + 20, cy + 6, 0)


func _gen_woodland() -> void:
	for i in range(26000):
		var x := rng.irange(1, W - 2)
		var y := rng.irange(1, W - 2)
		_grow(x, y)
	# A second pass over the forest so it is thicker than any town edge.
	for i in range(2600):
		var x := rng.irange(1, W - 2)
		var y := rng.irange(1, 60)
		_grow(x, y)

	# Boulders: rocky ground first — gravel, riverbanks, the forest floor.
	for i in range(5200):
		var x := rng.irange(2, W - 3)
		var y := rng.irange(2, W - 3)
		if _no_tree[y * W + x]:
			continue
		var t := tiles[y * W + x]
		var rocky := t == T.GRAVEL or t == T.SAND
		var wild := y < 62 or x < 56 or (x > 236 and y > 272) or mini(mini(x, y), mini(W - 1 - x, W - 1 - y)) < 20
		var p := 0.34 if rocky else (0.07 if wild else 0.02)
		if rng.chance(p):
			_plant_big(x, y, "boulder")
	# Thickets: the wet and the wild. Not in the town, where someone used to mow.
	for i in range(5200):
		var x := rng.irange(2, W - 3)
		var y := rng.irange(2, W - 3)
		if _no_tree[y * W + x]:
			continue
		var t := tiles[y * W + x]
		var damp := t == T.SAND or absf(x - river_centre(y)) < 12
		var wild := y < 62 or x < 56 or mini(mini(x, y), mini(W - 1 - x, W - 1 - y)) < 20
		var p := 0.26 if damp else (0.09 if wild else 0.015)
		if rng.chance(p):
			_plant_big(x, y, "thicket")


func _gen_litter() -> void:
	# Litter, everywhere you can walk. Weighted to sticks and fiber because
	# they are what the first tools cost most of.
	for i in range(90000):
		var x := rng.irange(1, W - 2)
		var y := rng.irange(1, W - 2)
		var ti := y * W + x
		if blocked[ti] or prop_grid.has(ti):
			continue
		var t := tiles[ti]
		var p: float
		if t == T.GRASS or t == T.DIRT:
			p = 0.045
		elif t == T.GRAVEL or t == T.SAND or t == T.FIELD:
			p = 0.03
		elif t == T.ROAD or t == T.SIDEWALK or t == T.LOT or t == T.RUBBLE:
			p = 0.01
		else:
			continue                                   # not indoors
		if not rng.chance(p):
			continue
		var r := rng.next()
		_plant_litter(x, y, "sticks" if r < 0.42 else ("fiber" if r < 0.78 else "stone"))

	# The starter cache: enough material within a short walk of where the
	# player wakes up to make the first tool, topping up only what the
	# map-wide odds above did not happen to provide.
	var camp: Rect2i = locations[0].rect
	var cx := roundi(camp.position.x + camp.size.x / 2.0)
	var cy := roundi(camp.position.y + camp.size.y / 2.0)
	var R := 12
	var min_units := {"sticks": 2, "fiber": 2, "stone": 1}
	var quota := {"sticks": 14, "fiber": 14, "stone": 12}
	var have := {"sticks": 0, "fiber": 0, "stone": 0}
	for y in range(cy - R, cy + R + 1):
		for x in range(cx - R, cx + R + 1):
			if not in_bounds(x, y):
				continue
			var prop: Dictionary = prop_grid.get(y * W + x, {})
			if prop.is_empty() or not prop.get("hand", false):
				continue
			var res: String = prop.get("res", "fiber" if prop.harvest == "fiber" else "stone")
			if have.has(res):
				have[res] += min_units[res]
	for res in ["sticks", "fiber", "stone"]:
		var tries := 0
		while tries < 400 and have[res] < quota[res]:
			tries += 1
			var x := cx + rng.irange(-R, R)
			var y := cy + rng.irange(-R, R)
			if not in_bounds(x, y):
				continue
			if not _plant_litter(x, y, res).is_empty():
				have[res] += min_units[res]

	# Reeds along every shore: scenery, not an obstacle.
	for y in range(1, W - 1):
		for x in range(1, W - 1):
			var i := y * W + x
			if tiles[i] != T.SAND or blocked[i]:
				continue
			if not rng.chance(0.16):
				continue
			props.append({"kind": "reed", "si": rng.irange(0, 2), "rot": 0.0, "x": (x + 0.5) * TILE, "y": (y + 0.5) * TILE})


func _gen_danger_and_spawns() -> void:
	for loc in locations:
		var r: Rect2i = loc.rect
		var pad := 6
		for y in range(r.position.y - pad, r.end.y + pad):
			for x in range(r.position.x - pad, r.end.x + pad):
				if not in_bounds(x, y):
					continue
				var inside := x >= r.position.x and y >= r.position.y and x < r.end.x and y < r.end.y
				var t: int = loc.tier if inside else maxi(1, loc.tier - 1)
				var i := y * W + x
				if t > danger[i]:
					danger[i] = t

	# Open outdoor tiles in tier-1 land, away from walls — the random start
	# and respawns before a bedroll exists.
	for y in range(4, W - 4, 2):
		for x in range(4, W - 4, 2):
			var i := y * W + x
			if blocked[i] or danger[i] > 1:
				continue
			var t := tiles[i]
			if t != T.GRASS and t != T.DIRT and t != T.GRAVEL and t != T.ROAD and t != T.SIDEWALK and t != T.FIELD:
				continue
			var clear := true
			for j in range(-2, 3):
				if not clear:
					break
				for i2 in range(-2, 3):
					if blocked[clampi(y + j, 0, W - 1) * W + clampi(x + i2, 0, W - 1)]:
						clear = false
						break
			if clear:
				spawn_tiles.append(Vector2i(x, y))


# -------------------------------------------------------------- accessors --

func tile_at_px(px: float, py: float) -> int:
	return tile(floori(px / TILE), floori(py / TILE))


func is_blocked_tile(tx: int, ty: int) -> bool:
	if tx < 0 or ty < 0 or tx >= W or ty >= W:
		return true
	return blocked[ty * W + tx] == 1


func is_blocked_px(px: float, py: float) -> bool:
	return is_blocked_tile(floori(px / TILE), floori(py / TILE))


func danger_at_px(px: float, py: float) -> int:
	var x := clampi(floori(px / TILE), 0, W - 1)
	var y := clampi(floori(py / TILE), 0, W - 1)
	return danger[y * W + x]


## The first location whose rect contains the point, or an empty Dictionary.
func location_at_px(px: float, py: float) -> Dictionary:
	var tx := px / TILE
	var ty := py / TILE
	for l in locations:
		var r: Rect2i = l.rect
		if tx >= r.position.x and ty >= r.position.y and tx < r.end.x and ty < r.end.y:
			return l
	return {}


## The harvestable prop occupying a tile, or an empty Dictionary.
func prop_at_tile(tx: int, ty: int) -> Dictionary:
	return prop_grid.get(ty * W + tx, {})


## Removes a harvested prop and frees the tile if this prop was what blocked
## it. `solid` is set by whatever planted it, never inferred from kind.
func remove_prop(prop: Dictionary) -> void:
	var i := props.find(prop)
	if i >= 0:
		props.remove_at(i)
	var ti: int = prop.ty * W + prop.tx
	prop_grid.erase(ti)
	chopped.append(ti)
	if prop.solid and in_bounds(prop.tx, prop.ty):
		blocked[ti] = 0


# --------------------------------------------------------------- movement --

## Circle-vs-tilemap test over the tiles the circle touches.
func circle_hits_solid(cx: float, cy: float, r: float) -> bool:
	var min_x := floori((cx - r) / TILE)
	var max_x := floori((cx + r) / TILE)
	var min_y := floori((cy - r) / TILE)
	var max_y := floori((cy + r) / TILE)
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			if not is_blocked_tile(tx, ty):
				continue
			var rx := tx * TILE
			var ry := ty * TILE
			var nx := clampf(cx, rx, rx + TILE)
			var ny := clampf(cy, ry, ry + TILE)
			var ddx := cx - nx
			var ddy := cy - ny
			if ddx * ddx + ddy * ddy < r * r:
				return true
	return false


## Slide-along-walls circle movement. Resolves X and Y independently so an
## entity brushing a wall keeps its remaining momentum instead of sticking.
func move_circle(pos: Vector2, d: Vector2, r: float) -> Vector2:
	var x := pos.x
	var y := pos.y
	if d.x != 0.0:
		var nx := x + d.x
		if not circle_hits_solid(nx, y, r):
			x = nx
		else:
			var step := signf(d.x)
			var probe := x
			for i in range(4):
				var t := probe + step * (absf(d.x) / 4.0)
				if circle_hits_solid(t, y, r):
					break
				probe = t
			x = probe
	if d.y != 0.0:
		var ny := y + d.y
		if not circle_hits_solid(x, ny, r):
			y = ny
		else:
			var step := signf(d.y)
			var probe := y
			for i in range(4):
				var t := probe + step * (absf(d.y) / 4.0)
				if circle_hits_solid(x, t, r):
					break
				probe = t
			y = probe
	var lim := W * TILE - r - 1.0
	return Vector2(clampf(x, r + 1.0, lim), clampf(y, r + 1.0, lim))


## What stops a round: everything that stops a foot except water and fences.
## A river is a barrier you can shoot across; a farm fence is knee high.
func bullet_blocks_px(px: float, py: float) -> bool:
	var tx := floori(px / TILE)
	var ty := floori(py / TILE)
	if not is_blocked_tile(tx, ty):
		return false
	if tx < 0 or ty < 0 or tx >= W or ty >= W:
		return true
	return Config.SHOOT_OVER_BY_TILE[tiles[ty * W + tx]] == 0


## Sight: nothing solid to feet between the two points. Trees and boulders
## block it, so an enemy cannot track you through a building.
func has_line_of_sight(a: Vector2, b: Vector2, step := 12.0) -> bool:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return true
	var n := ceili(len / step)
	for i in range(1, n + 1):
		var t := float(i) / n
		if is_blocked_px(a.x + d.x * t, a.y + d.y * t):
			return false
	return true


## The same rule bullets use, so a turret never locks onto something behind
## a tree and empties its magazine into the trunk.
func has_terrain_line_of_sight(a: Vector2, b: Vector2, step := 14.0) -> bool:
	var d := b - a
	var len := d.length()
	if len < 1e-4:
		return true
	var n := ceili(len / step)
	for i in range(1, n + 1):
		var t := float(i) / n
		if bullet_blocks_px(a.x + d.x * t, a.y + d.y * t):
			return false
	return true


## An unblocked point on a ring around a centre, inside the map, or
## Vector2.INF after `tries` misses.
func find_open_spot(rng_: Rng, centre: Vector2, min_r: float, max_r: float, tries := 26) -> Vector2:
	var lim := W * TILE - TILE * 2
	for i in range(tries):
		var a := rng_.frange(0.0, TAU)
		var r := rng_.frange(min_r, max_r)
		var x := centre.x + cos(a) * r
		var y := centre.y + sin(a) * r
		if x < TILE * 2 or y < TILE * 2 or x > lim or y > lim:
			continue
		if is_blocked_px(x, y):
			continue
		return Vector2(x, y)
	return Vector2.INF


## Ejects an entity that has ended up inside geometry. Cheap no-op normally.
func unstick(pos: Vector2, r: float) -> Vector2:
	if not circle_hits_solid(pos.x, pos.y, r):
		return pos
	for ring in range(1, 9):
		var step := TILE * 0.55 * ring
		for i in range(12):
			var a := (i / 12.0) * TAU
			var nx := pos.x + cos(a) * step
			var ny := pos.y + sin(a) * step
			if not circle_hits_solid(nx, ny, r):
				return Vector2(nx, ny)
	return pos
