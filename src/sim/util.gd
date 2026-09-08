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
