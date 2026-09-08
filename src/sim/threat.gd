class_name Threat
extends RefCounted
## The Threat meter. Doing loud, powerful things attracts a horde; lying
## low bleeds it back down. Threat schedules raids, never a calendar.

const TH := Config.THREAT
const TIER_NAMES := ["LOW", "RISING", "HIGH", "CRITICAL"]
const TIER_COLORS := ["#8fae6a", "#d9c46a", "#d98a4a", "#e05a4a"]

var value := 0.0
var tier := 0


static func tier_of(v: float) -> int:
	if v >= TH.warn_at[2]:
		return 3
	if v >= TH.warn_at[1]:
		return 2
	if v >= TH.warn_at[0]:
		return 1
	return 0


func label() -> String:
	return TIER_NAMES[tier_of(value)]


func color() -> String:
	return TIER_COLORS[tier_of(value)]


## `actor` is the player whose noise this is, for their Threat perks; things
## nobody did personally read the base owner's (seat 0).
func add(sim: GameSim, amount: float, actor: PlayerSim = null) -> void:
	if sim.raid != null:
		return
	var src := actor if actor != null else (sim.players[0] if not sim.players.is_empty() else null)
	var mul := src.threat_mul if src != null else 1.0
	value = minf(TH.max, value + amount * mul * sim.night_factors().threat)
	_check_tier(sim)


func _check_tier(sim: GameSim) -> void:
	var t := tier_of(value)
	if t > tier:
		tier = t
		if t == 1:
			sim.notify("THREAT RISING — they are starting to gather", "#d9c46a", true)
		elif t == 2:
			sim.notify("THREAT HIGH — fortify now", "#d98a4a", true)
		elif t == 3:
			sim.notify("THREAT CRITICAL — a horde is forming", "#e05a4a", true)
	elif t < tier:
		tier = t


func tick(sim: GameSim, dt: float) -> void:
	if sim.raid != null:
		return
	# Once full it stays pinned until the raid launches, or decay would shave
	# it back below the threshold every frame and a raid could never fire.
	if value >= TH.max:
		return
	if value > 0.0:
		value = maxf(0.0, value - TH.decay_per_sec * dt)
		_check_tier(sim)


func raid_ready(sim: GameSim) -> bool:
	return sim.raid == null and value >= TH.max


func reset_after_raid() -> void:
	value = TH.post_raid_reset
	tier = tier_of(value)
