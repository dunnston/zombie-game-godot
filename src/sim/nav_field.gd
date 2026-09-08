class_name NavField
extends RefCounted
## A local flow field: the walking distance, in tiles, from every tile in a
## square window to one target tile, over the collision bitmap. An enemy
## anywhere in the window asks which neighbouring tile is closer and walks
## that way, so a horde finds the door instead of pressing on the wall.
##
## The distances come from a four-neighbour breadth-first search (cheap:
## one queue, no costs); the step choice looks at all eight neighbours and
## refuses a diagonal unless both orthogonals are open, so a path never
## squeezes between two blocked corners. The window is padded with one
## blocked ring so the inner loop needs no bounds checks.
##
## The prototype had no pathfinding; every stuck-AI bug came from that.

const W := Config.WORLD_TILES

var target := Vector2i.ZERO      # the tile everything flows toward
var x0 := 0                      # window origin in world tiles (of the padded grid)
var y0 := 0
var size := 0                    # padded window side, in tiles
var dist := PackedInt32Array()   # -1 = blocked, outside, or unreachable
var built_at := 0.0
var version := 0                 # world version this was built against
var build_ms := 0.0


func build(world: World, target_tile: Vector2i, radius: int, now := 0.0, world_version := 0, structs: Structures = null) -> void:
	var t0 := Time.get_ticks_usec()
	target = target_tile
	size = radius * 2 + 3
	x0 = target_tile.x - radius - 1
	y0 = target_tile.y - radius - 1
	built_at = now
	version = world_version
	var n := size * size
	dist.resize(n)
	dist.fill(-1)

	# Which local cells are open. The outer ring stays closed.
	var open := PackedByteArray()
	open.resize(n)
	var blocked := world.blocked
	for ly in range(1, size - 1):
		var wy := y0 + ly
		if wy < 0 or wy >= W:
			continue
		var row := wy * W
		var base := ly * size
		for lx in range(1, size - 1):
			var wx := x0 + lx
			if wx >= 0 and wx < W and blocked[row + wx] == 0 and not (structs != null and structs.solid_at(wx, wy)):
				open[base + lx] = 1

	var start := (radius + 1) * size + radius + 1
	if open[start] == 0:
		build_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return
	var queue := PackedInt32Array()
	queue.resize(n)
	var head := 0
	var tail := 1
	queue[0] = start
	dist[start] = 0
	while head < tail:
		var c := queue[head]
		head += 1
		var d := dist[c] + 1
		var ni := c + 1
		if open[ni] == 1 and dist[ni] < 0:
			dist[ni] = d
			queue[tail] = ni
			tail += 1
		ni = c - 1
		if open[ni] == 1 and dist[ni] < 0:
			dist[ni] = d
			queue[tail] = ni
			tail += 1
		ni = c + size
		if open[ni] == 1 and dist[ni] < 0:
			dist[ni] = d
			queue[tail] = ni
			tail += 1
		ni = c - size
		if open[ni] == 1 and dist[ni] < 0:
			dist[ni] = d
			queue[tail] = ni
			tail += 1
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0


func covers(pos: Vector2) -> bool:
	var lx := floori(pos.x / Config.TILE) - x0
	var ly := floori(pos.y / Config.TILE) - y0
	return lx >= 1 and ly >= 1 and lx < size - 1 and ly < size - 1


## Walking distance in tiles from a world tile, or -1.
func dist_at_tile(tx: int, ty: int) -> int:
	var lx := tx - x0
	var ly := ty - y0
	if lx < 0 or ly < 0 or lx >= size or ly >= size:
		return -1
	return dist[ly * size + lx]


## Unit vector toward the neighbouring tile that is closer to the target,
## or Vector2.ZERO when there is nowhere to go: outside the window, on the
## target tile, or cut off from it.
func step_dir(pos: Vector2) -> Vector2:
	var tx := floori(pos.x / Config.TILE)
	var ty := floori(pos.y / Config.TILE)
	var lx := tx - x0
	var ly := ty - y0
	if lx < 1 or ly < 1 or lx >= size - 1 or ly >= size - 1:
		return Vector2.ZERO
	var c := ly * size + lx
	var here := dist[c]
	if here <= 0:
		return Vector2.ZERO
	var best := here
	var bx := 0
	var by := 0
	# Orthogonals first, then diagonals under the corner rule. Distances are
	# from a four-neighbour search, so a diagonal is usually two closer and
	# wins when it is open, which is what makes the walk look natural.
	var e := dist[c + 1]
	var w := dist[c - 1]
	var s := dist[c + size]
	var n := dist[c - size]
	if e >= 0 and e < best:
		best = e
		bx = 1
		by = 0
	if w >= 0 and w < best:
		best = w
		bx = -1
		by = 0
	if s >= 0 and s < best:
		best = s
		bx = 0
		by = 1
	if n >= 0 and n < best:
		best = n
		bx = 0
		by = -1
	if e >= 0 and s >= 0:
		var d := dist[c + size + 1]
		if d >= 0 and d < best:
			best = d
			bx = 1
			by = 1
	if w >= 0 and s >= 0:
		var d := dist[c + size - 1]
		if d >= 0 and d < best:
			best = d
			bx = -1
			by = 1
	if e >= 0 and n >= 0:
		var d := dist[c - size + 1]
		if d >= 0 and d < best:
			best = d
			bx = 1
			by = -1
	if w >= 0 and n >= 0:
		var d := dist[c - size - 1]
		if d >= 0 and d < best:
			best = d
			bx = -1
			by = -1
	if bx == 0 and by == 0:
		return Vector2.ZERO
	var centre := Vector2((tx + bx + 0.5) * Config.TILE, (ty + by + 0.5) * Config.TILE)
	return (centre - pos).normalized()
