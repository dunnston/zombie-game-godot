class_name Sound
## Noise, and the zombies it brings. (Named Sound because Godot already
## owns the class name Noise.) Every source goes through `make_noise`, so a
## stealth perk quietens a car and a turret the same way it quietens a
## pistol.


## How far a weapon carries, as a radius. Guns and melee both keep it in
## WEAPONS, so one number answers "how loud is this thing" for every source
## that holds one: firing it, swinging it, and working with it.
##
## A row with no `noise` of its own falls back rather than going silent. A
## weapon nobody can hear is not a stealth weapon, it is a bug that looks
## like one, and a new row in the content editor should be quiet by default,
## never inaudible by accident.
## The noise lens (F2 in a dev build). Off by default, and set from the view
## layer — the sim never reads a key, it only agrees to describe itself.
static var debug := false


static func weapon_radius(w: Dictionary) -> float:
	return float(w.get("noise", Config.NOISE.melee))


## Pulls everything within `radius` of the point toward it: an alert window
## and a destination, and deliberately NOT aggro. Aggro means "hunting a
## player" and outranks the noise branch in the AI, so a noise that set it
## sent zombies at the nearest player instead of at the sound (measured in
## the prototype: a group 420px from a bang walked 304px the other way). If
## they can also sense a player the sight check sets aggro on its own and
## the hunt wins, which is right. Returns how many heard it.
static func make_noise(sim: GameSim, x: float, y: float, radius: float, actor: PlayerSim = null, src := "world") -> int:
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
	# Nothing is emitted unless somebody is looking. A noise fires on every
	# swing and every round of automatic fire, and `_relay_events` sends any
	# positioned event to every guest reliably — so an always-on debug event
	# would be a co-op bandwidth cost for a lens nobody had opened.
	if debug:
		sim.emit({"t": "noise", "x": at.x, "y": at.y, "r": r, "src": src, "heard": heard})
	return heard
