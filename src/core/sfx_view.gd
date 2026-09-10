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
## Whose ears these are.
var player: PlayerSim = null

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
	"stagger": "stagger",
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
	"mut_rise": "mutate_up",
	"mut_fall": "mutate_down",
	"dosed": "heal",
	"ate": "heal",
	"lurch": "lurch",
	"bitten": "player_hurt",
	"turned": "turned",
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


## Turns one event into one sound, and **returns the cue it chose** — or "" for
## an event that makes no noise.
##
## The return value exists for the tests. Three times now a feature has shipped
## built-but-not-connected because the test asserted on the thing feeding the
## code rather than on what the code decided: asserting that a bow emits a
## `shot` event proves nothing about whether the bow makes a sound. This is the
## seam that lets a headless test ask the real question.
func on_event(ev: Dictionary) -> String:
	var t := String(ev.t)
	match t:
		"shot":
			# On the *shot*, not the muzzle flash. `spawn_bullet` already puts
			# the weapon id on the first pellet only and leaves it empty on the
			# rest — `combat.gd` even says "one sound per shot, not per pellet"
			# beside it — so this is the field asking to be used, and it is the
			# only one that reaches a bow: a bow emits no muzzle flash, because
			# a flash is a light source and a bow that lit up the treeline
			# would give away the one thing it is for.
			var w := String(ev.get("w", ""))
			if w.is_empty():
				return ""                   # pellets two through eight
			return _at(w if Sfx.has(w) else "pistol", ev)
		"hit":
			return _at("melee_hit" if String(ev.get("kind", "bullet")) == "melee" else "bullet_hit", ev)
		"growl":
			# One recording, a horde of voices.
			return _at("growl", ev, 1.0 + (randf() - 0.5) * GROWL_SPREAD)
		"raid_end":
			if bool(ev.get("repelled", false)):
				Sfx.play("raid_win")
				return "raid_win"
			return ""
		_:
			if DIRECT.has(t):
				return _at(DIRECT[t], ev)
	return ""


## Plays a cue where it happened, and names it. An event with no position — a
## raid warning belongs to the whole town — is played at full volume. A cue too
## far away to hear is still the cue that was chosen, so it is still named: the
## decision and the volume are different questions.
func _at(cue: String, ev: Dictionary, pitch := 1.0) -> String:
	if not ev.has("x"):
		Sfx.play(cue, pitch)
		return cue
	var g := gain_at(Vector2(ev.x, ev.y))
	if g > 0.0:
		Sfx.play(cue, pitch, g)
	return cue
## How loud something is from where you are standing: full up close, silent
## past the range, and squared in between so the fall-off sounds like distance
## rather than like a dimmer switch.
func gain_at(at: Vector2) -> float:
	if sim.players.is_empty():
		return 1.0
	var d := (player if player != null else sim.players[0]).pos.distance_to(at)
	var near: float = Config.SFX_NEAR
	var far: float = Config.SFX_RANGE
	if d <= near:
		return 1.0
	if d >= far:
		return 0.0
	var k := 1.0 - (d - near) / (far - near)
	return k * k
