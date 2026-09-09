class_name SfxView
extends RefCounted
## Turns simulation events into sounds. The other half of `Sfx`, and the only
## place that knows which event means which cue.
##
## The simulation stays deaf and silent: it emits what happened and this
## decides what that sounds like, exactly as `FxView` decides what it looks
## like and `LightView` decides what it lights. That is what lets the whole
## game run headless with no audio device and no change to a single sim file.
##
## Distance is the one thing here the prototype did not have. Web audio gave
## every sound the same volume wherever it happened, so a turret across town
## was as loud as the gun in your hand. Here a cue fades with how far away it
## was and stops entirely past `Config.SFX_RANGE` — which is also what keeps a
## raid on the far side of the map from being a wall of noise.

var sim: GameSim

## The pitch spread on a horde's growls, so one buffer is a dozen throats.
const GROWL_SPREAD := 0.35

## Sim event -> cue, for the ones that are a straight swap. Anything needing a
## decision (which gun, what hit what) is in `on_event` instead.
const DIRECT := {
	"dryfire": "dryfire",
	"reload": "reload",
	"reload_done": "reload_done",
	"swing": "swing",
	"bullet_wall": "hit_wall",
	"kill": "zombie_die",
	"growl": "growl",
	"player_hit": "player_hurt",
	"player_died": "player_die",
	"heal": "heal",
	"picked_up": "pickup",
	"loot": "loot",
	"built": "build",
	"crafted": "craft",
	"chop": "chop",
	"harvest": "chop",
	"deny": "deny",
	"level_up": "level_up",
	"raid_warn": "raid_warn",
	"struct_hit": "struct_hit",
	"struct_down": "struct_break",
	"car_wrecked": "car_wreck",
	"enter_car": "engine_start",
	"exit_car": "engine_stop",
	"pick_snap": "deny",
	"second_wind": "level_up",
	"recruited": "level_up",
	"discovered": "pickup",
	"survivor_level": "pickup",
	"survivor_down": "player_hurt",
	"survivor_died": "zombie_die",
	"refuel": "ui",
	"spend": "ui",
}


func _init(sim_: GameSim) -> void:
	sim = sim_


func on_event(ev: Dictionary) -> void:
	var t := String(ev.t)
	match t:
		"muzzle":
			# The cue is on the muzzle flash, not on the bullet: a shotgun
			# spawns eight pellets and fires once, and eight bangs for one
			# trigger pull is exactly what the rate limit exists to prevent.
			var w := String(ev.get("w", "pistol"))
			_at(w if Sfx.has(w) else "pistol", ev)
		"hit":
			_at("melee_hit" if String(ev.get("kind", "bullet")) == "melee" else "bullet_hit", ev)
		"growl":
			# One recording, a horde of voices.
			_at("growl", ev, 1.0 + (randf() - 0.5) * GROWL_SPREAD)
		"raid_end":
			if bool(ev.get("repelled", false)):
				Sfx.play("raid_win")
		_:
			if DIRECT.has(t):
				_at(DIRECT[t], ev)


## Plays a cue where it happened. An event with no position — a raid warning
## belongs to the whole town — is played at full volume.
func _at(cue: String, ev: Dictionary, pitch := 1.0) -> void:
	if not ev.has("x"):
		Sfx.play(cue, pitch)
		return
	var g := gain_at(Vector2(ev.x, ev.y))
	if g <= 0.0:
		return
	Sfx.play(cue, pitch, g)


## How loud something is from where you are standing: full up close, silent
## past the range, and squared in between so the fall-off sounds like distance
## rather than like a dimmer switch.
func gain_at(at: Vector2) -> float:
	if sim.players.is_empty():
		return 1.0
	var d := sim.players[0].pos.distance_to(at)
	var near: float = Config.SFX_NEAR
	var far: float = Config.SFX_RANGE
	if d <= near:
		return 1.0
	if d >= far:
		return 0.0
	var k := 1.0 - (d - near) / (far - near)
	return k * k
