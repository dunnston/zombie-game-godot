class_name QuietField
extends RefCounted
## Local pressure relief: the reason clearing ground is worth doing.
##
## The spawner keeps a standing population near the player, refilled every
## 0.6s, so on its own there is never a lull to build in. Killing things
## buys quiet, locally and temporarily. A coarse field over the map holds how
## thoroughly each patch has been cleared; the spawner reads it and thins
## out, and stops entirely above `suppress_at`. Quiet decays over a few
## minutes: a breather you earned, not a safe zone you own. Raids ignore it.

const Q := Config.QUIET

var w := 0
var h := 0
var a := PackedFloat32Array()


func _init() -> void:
	w = ceili(Config.WORLD_SIZE / Q.cell)
	h = w
	a.resize(w * h)


func _cell(cx: int, cy: int) -> float:
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return 0.0
	return a[cy * w + cx]


## Raw quiet at a point, sampled bilinearly across the four nearest cells.
## Reading the containing cell made the same kills worth forty seconds of
## calm or none depending on where in a 256px square you stood.
func quiet_at(px: float, py: float) -> float:
	var fx := px / Q.cell - 0.5
	var fy := py / Q.cell - 0.5
	var cx := floori(fx)
	var cy := floori(fy)
	var tx := fx - cx
	var ty := fy - cy
	var q00 := _cell(cx, cy)
	var q10 := _cell(cx + 1, cy)
	var q01 := _cell(cx, cy + 1)
	var q11 := _cell(cx + 1, cy + 1)
	return (q00 * (1.0 - tx) + q10 * tx) * (1.0 - ty) + (q01 * (1.0 - tx) + q11 * tx) * ty


## Quiet including the standing contribution of anything built nearby.
## Structures arrive in Phase 3; until then this is quiet_at.
func total_quiet_at(px: float, py: float) -> float:
	return minf(Q.max, quiet_at(px, py))


## Multiplier on the population the spawner wants: 1 on untouched ground,
## down to the floor where it has been thoroughly cleared.
func density_mul(px: float, py: float) -> float:
	return 1.0 - (1.0 - Q.floor) * minf(1.0, total_quiet_at(px, py) / Q.max)


## True where the ground is quiet enough that nothing new should walk in.
func suppressed(px: float, py: float) -> bool:
	return total_quiet_at(px, py) >= Q.suppress_at


## A kill quietens where it fell and the ground around it, weighted by true
## distance to each cell centre so the payoff does not depend on where in a
## cell you were standing.
func add_quiet(px: float, py: float, amount: float = Q.per_kill) -> void:
	var cx := floori(px / Q.cell)
	var cy := floori(py / Q.cell)
	var reach: float = Q.kernel_reach * Q.cell
	for j in range(-2, 3):
		for i in range(-2, 3):
			var x := cx + i
			var y := cy + j
			if x < 0 or y < 0 or x >= w or y >= h:
				continue
			var d := Vector2((x + 0.5) * Q.cell - px, (y + 0.5) * Q.cell - py).length()
			var share := 1.0 - d / reach
			if share <= 0.0:
				continue
			var k := y * w + x
			a[k] = minf(Q.max, a[k] + amount * share)


## Bleeds the whole field back toward dangerous. A 40x40 field is cheap.
func tick(dt: float) -> void:
	var d: float = Q.decay_per_sec * dt
	for i in range(a.size()):
		if a[i] > 0.0:
			a[i] = maxf(0.0, a[i] - d)
