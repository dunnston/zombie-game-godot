class_name SpatialHash
extends RefCounted
## Enemies bucketed into 96px cells, rebuilt every step. Separation, melee
## arcs and bullets ask "who is near this point" a few hundred times a
## step; with a horde that is the difference between a frame and a stall.

const CELL := 96.0
const STRIDE := 4096

var _map := {}


func clear() -> void:
	_map.clear()


func insert(e: EnemySim) -> void:
	var k := int(e.pos.x / CELL) * STRIDE + int(e.pos.y / CELL)
	var b = _map.get(k)
	if b == null:
		b = []
		_map[k] = b
	b.append(e)


## Everything in the cells overlapping the circle, into `out` (cleared first).
## Callers do their own exact distance test.
func query(x: float, y: float, r: float, out: Array) -> Array:
	out.clear()
	var x0 := int((x - r) / CELL)
	var x1 := int((x + r) / CELL)
	var y0 := int((y - r) / CELL)
	var y1 := int((y + r) / CELL)
	for cx in range(x0, x1 + 1):
		for cy in range(y0, y1 + 1):
			var b = _map.get(cx * STRIDE + cy)
			if b != null:
				out.append_array(b)
	return out
