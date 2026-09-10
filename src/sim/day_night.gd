class_name DayNight
extends RefCounted
## The clock, and what the dark is worth to everything else.
##
## Night is the pressure valve of the whole game: the map gets darker and
## smaller, the infected get bolder, and Threat climbs faster. Everything you
## built during the day decides whether you enjoy that or dread it.
##
## Two numbers are the whole state — `t`, the fraction of the day elapsed, and
## `day`, which one it is. Everything else is derived, so a save stores those
## two and nothing can come back out of step.

## Fraction of the current day elapsed, 0..1.
var t := Config.DAY_START
var day := 1
## The phase id the clock was in last tick, so a crossing can be announced
## exactly once rather than every frame it is still true.
var phase := "day"


func _init() -> void:
	phase = String(phase_at(t).id)


func tick(sim: GameSim, dt: float) -> void:
	t += dt / Config.DAY_LENGTH
	if t >= 1.0:
		t -= 1.0
		day += 1
		if sim != null:
			sim.notify("DAY %d" % day, "#d0c46a", true)
	var now := phase_at(t)
	if now.id != phase:
		phase = String(now.id)
		if sim != null:
			_announce(sim, phase)


## The notices are the whole tutorial for night: the first time dusk lands on
## a player with no walls and no torch, this is what tells them why.
static func _announce(sim: GameSim, id: String) -> void:
	match id:
		"dusk":
			sim.notify("The light is going. Get behind something.", "#d98a4a", true)
		"night":
			sim.notify("NIGHT — they can hear you a long way off", "#8f9ad0", true)
		"dawn":
			sim.notify("First light. You made it.", "#d0c46a", true)


static func phase_at(at: float) -> Dictionary:
	for p in Config.PHASES:
		if at >= p.from and at < p.to:
			return p
	return Config.PHASES[Config.PHASES.size() - 1]


func phase_name() -> String:
	return String(phase_at(t).name)


## How dark it is, and what colour the dark is, blended along
## `Config.DARKNESS_KEYS` so dusk creeps in rather than snapping between
## phases. Returns `{alpha, color}`, the colour as a `Color`.
##
## The colour is interpolated like the alpha. It used to step to whichever
## key was nearer, which was invisible while the tint only tinted — now that
## `LightView` multiplies the canvas by it, a step is a step in how much of
## the map you can see, and the deep-night keys are far apart.
static func darkness_at(at: float) -> Dictionary:
	var keys: Array = Config.DARKNESS_KEYS
	for i in range(keys.size() - 1):
		var a: Dictionary = keys[i]
		var b: Dictionary = keys[i + 1]
		if at >= a.t and at <= b.t:
			var k: float = (at - a.t) / maxf(1e-6, b.t - a.t)
			return {"alpha": lerpf(a.a, b.a, k),
				"color": Color(String(a.c)).lerp(Color(String(b.c)), k)}
	return {"alpha": 0.0, "color": Color("#0a0c09")}


func darkness() -> Dictionary:
	return darkness_at(t)


## What the whole canvas is multiplied by at `at`: `LightView` sets exactly
## this on its `CanvasModulate` and nothing else darkens the world, so this
## is "how much of the map you can see" as a number a test can hold. 1 is
## noon and near-black is night. Real lights add on top of it.
static func canvas_tint_at(at: float) -> Color:
	var d := darkness_at(at)
	return Color.WHITE.lerp(d.color, float(d.alpha))


func canvas_tint() -> Color:
	return canvas_tint_at(t)


func is_night() -> bool:
	return phase == "night"


## Dark enough that a light is worth carrying.
func is_dark() -> bool:
	return float(darkness().alpha) > Config.DARK_ENOUGH


## The multipliers the rest of the simulation reads off the clock. Every one
## of these already had a caller before the clock existed — the spawner, the
## sense check, the walk speed and `Threat.add` — so turning the sky dark is
## the only thing that had to change.
static func factors_at(at: float) -> Dictionary:
	var d: float = darkness_at(at).alpha
	var k := clampf(d / Config.DARKNESS_FULL, 0.0, 1.0)
	var n := Config.NIGHT
	return {
		"density": 1.0 + k * n.density,
		"sense": 1.0 + k * n.sense,
		"speed": 1.0 + k * n.speed,
		"threat": 1.0 + k * n.threat,
		"darkness": d,
	}


func factors() -> Dictionary:
	return factors_at(t)


## 24-hour clock for the HUD. Dawn sits at 06:00 so the numbers agree with
## what the screen is doing.
func clock_string() -> String:
	var hours: float = fmod(t * 24.0 + 6.0, 24.0)
	var h := floori(hours)
	var m := floori((hours - h) * 60.0)
	return "%02d:%02d" % [h, m]
