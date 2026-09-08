class_name Sound
## Noise, and the zombies it brings. (Named Sound because Godot already
## owns the class name Noise.) One function; every source goes
## through it, so a stealth perk quietens a car and a turret the same way it
## quietens a pistol.


## Pulls everything within `radius` of the point toward it: an alert window
## and a destination, and deliberately NOT aggro. Aggro means "hunting a
## player" and outranks the noise branch in the AI, so a noise that set it
## sent zombies at the nearest player instead of at the sound (measured in
## the prototype: a group 420px from a bang walked 304px the other way). If
## they can also sense a player the sight check sets aggro on its own and
## the hunt wins, which is right. Returns how many heard it.
static func make_noise(sim: GameSim, x: float, y: float, radius: float, actor: PlayerSim = null) -> int:
	var r := radius * (actor.noise_mul if actor != null else 1.0)
	if r <= 0.0:
		return 0
	var r2 := r * r
	var heard := 0
	var at := Vector2(x, y)
	for e in sim.enemies.list:
		if e.dead:
			continue
		if e.pos.distance_squared_to(at) >= r2:
			continue
		e.alert_t = maxf(e.alert_t, Config.NOISE.alert_time)
		e.has_noise = true
		e.noise_at = at
		heard += 1
	return heard
