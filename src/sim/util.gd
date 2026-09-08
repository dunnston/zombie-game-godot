class_name Util
## Small pure helpers shared by the simulation and the renderers.


## Deterministic hash of two integers -> [0, 1). Used for stable world detail,
## and matches the prototype's so the same tile gets the same variant.
static func hash2(x: int, y: int) -> float:
	var h := (x * 374761393 + y * 668265263) & 0xFFFFFFFF
	h = (h ^ (h >> 13)) & 0xFFFFFFFF
	h = (h * 1274126177) & 0xFFFFFFFF
	return float((h ^ (h >> 16)) & 0xFFFFFFFF) / 4294967296.0


## Frame-rate independent lerp factor: `a += (b - a) * smooth(rate, dt)`.
static func smooth(rate: float, dt: float) -> float:
	return 1.0 - exp(-rate * dt)


## Where a thing should be drawn *this frame*.
##
## The simulation steps at 60Hz and the view draws at the monitor's rate, so
## on a 144Hz screen two or three frames in a row would otherwise show the
## identical position and then jump — which reads as judder even though the
## simulation is perfectly smooth. Every entity captures where it was at the
## top of its tick; this blends between that and where it is now, by how far
## through the current physics step the renderer has got.
##
## Sim code must never call this. It is a presentation detail and using it in
## a rule would make the rule depend on the frame rate.
## A teleport is not movement and must not be smeared across the gap: a
## respawn, a load, or an entity drawn before its first tick would otherwise
## slide in from wherever it used to be — or from the origin. Nothing walks
## this far in one 60Hz step (the fastest thing in the game covers about six
## pixels), so anything past it is a jump and snaps.
const RENDER_SNAP := 40.0


static func render_pos(prev: Vector2, cur: Vector2) -> Vector2:
	if prev.distance_squared_to(cur) > RENDER_SNAP * RENDER_SNAP:
		return cur
	return prev.lerp(cur, Engine.get_physics_interpolation_fraction())
