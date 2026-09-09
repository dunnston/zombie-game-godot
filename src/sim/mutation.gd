class_name Mutation
extends RefCounted
## The Mutation meter: the one status the player manages, and the only thing
## allowed to write it.
##
## You were bitten before the first frame and there is no cure. Brain matter
## suppresses the change, so the supply line that keeps you human runs through
## the horde — which is why food and drink are buffs here and nothing else.
##
## Two rules hold this together:
##
## 1. **Every change to `PlayerSim.mutation` comes through `add`.** The band is
##    derived from the value in exactly one place, and a band change is the
##    only thing that asks for a recompute, so the meter drifting a tenth of a
##    point costs nothing.
## 2. **The band reaches the stats through `recompute_stats` and nowhere else**
##    (invariant 4). This file never writes a modifier; it writes `mut_band`
##    and lets the one door open.


## Points per second with nothing else acting on it.
static func rate_per_sec() -> float:
	var M := Config.MUTATION
	return float(M.max) / (float(M.days_to_full) * Config.DAY_LENGTH)


## Which band a value falls in. The table is low to high, so the last band
## whose threshold has been passed wins.
static func band_index(v: float) -> int:
	var bands: Array = Config.MUTATION.bands
	var idx := 0
	for i in range(bands.size()):
		if v >= float(bands[i].at):
			idx = i
	return idx


static func band_at(i: int) -> Dictionary:
	var bands: Array = Config.MUTATION.bands
	return bands[clampi(i, 0, bands.size() - 1)]


static func band_of(p: PlayerSim) -> Dictionary:
	return band_at(p.mut_band)


## What the meter reads as a fraction, for a bar.
static func fraction(p: PlayerSim) -> float:
	return clampf(p.mutation / float(Config.MUTATION.max), 0.0, 1.0)


# -------------------------------------------------------------- the meter --

## The one writer. `amount` may be negative — that is what a suppressant is.
## Returns how much actually landed, which is not what was asked for at either
## end of the bar.
static func add(sim: GameSim, p: PlayerSim, amount: float, why := "") -> float:
	if p == null or amount == 0.0:
		return 0.0
	var M := Config.MUTATION
	var before := p.mutation
	p.mutation = clampf(p.mutation + amount, 0.0, float(M.max))
	var moved := p.mutation - before
	# Turning is checked here rather than in the tick, so the bite that fills
	# the bar finishes you on that bite and not up to a frame later.
	if p.mutation >= float(M.max) and not p.dead:
		turn(sim, p)
		return moved
	_settle_band(sim, p, moved > 0.0, why)
	return moved


## Suppression, said the way the items say it: a positive number of points
## taken off. Returns what it actually took.
static func suppress(sim: GameSim, p: PlayerSim, amount: float) -> float:
	return -add(sim, p, -absf(amount), "suppressed")


## The band, after the value moved. The recompute is here and only here, so
## there is one answer to "when does mutation touch my stats".
static func _settle_band(sim: GameSim, p: PlayerSim, rising: bool, _why := "") -> void:
	var idx := band_index(p.mutation)
	if idx == p.mut_band:
		return
	p.mut_band = idx
	Equipment.recompute_stats(p)
	if sim == null:
		return
	var b := band_at(idx)
	sim.emit({"t": "mut_rise" if rising else "mut_fall", "seat": p.seat,
		"x": p.pos.x, "y": p.pos.y, "band": String(b.id)})
	sim.notify("%s — %s" % [String(b.name), String(b.desc)], String(b.color), true)


## Called after `mutation` is set from outside the simulation — a save being
## loaded, a snapshot landing on a guest — where there is no event to emit and
## no notice to give, only stats to bring into line.
static func sync_band(p: PlayerSim) -> void:
	var idx := band_index(p.mutation)
	if idx == p.mut_band:
		return
	p.mut_band = idx
	Equipment.recompute_stats(p)


# ------------------------------------------------------------------- tick --

## The ambient climb, plus the effect clocks. Called from the player's own
## tick after death is handled and before being downed is: bleeding out on the
## ground is exactly when the change gets on with it.
static func tick(sim: GameSim, p: PlayerSim, dt: float) -> void:
	if p.dead or p.away:
		return
	tick_effects(sim, p, dt)
	tick_lurch(sim, p, dt)
	add(sim, p, rate_per_sec() * rate_multiplier(sim, p) * dt)


## Everything acting on the base rate right now: the ground under you, the
## dark, and whatever you have taken. Separated out because the tests measure
## it directly, and because a rate nobody can inspect is a rate nobody can
## tune.
static func rate_multiplier(sim: GameSim, p: PlayerSim) -> float:
	var M := Config.MUTATION
	var muls: Array = M.tier_mul
	var tier := 0
	if sim != null and sim.world != null:
		tier = sim.world.danger_at_px(p.pos.x, p.pos.y)
	var m := float(muls[clampi(tier, 0, muls.size() - 1)])
	if sim != null and sim.clock != null:
		var k := clampf(float(sim.clock.darkness().alpha) / Config.DARKNESS_FULL, 0.0, 1.0)
		m *= lerpf(1.0, float(M.night_mul), k)
	return m * p.mut_rate_mul


# ------------------------------------------------------------- the lurch --

## At the top band your legs occasionally stop being yours. Rolled on the
## host's stream like everything else, and mirrored to guests as a flag — a
## guest that predicted its own footsteps through one would fight the host for
## a second and a half and lose, so `NetGuest` hands the body back for the
## duration the same way it does while you are driving.
static func tick_lurch(sim: GameSim, p: PlayerSim, dt: float) -> void:
	var L: Dictionary = Config.MUTATION.lurch
	if p.mut_band < int(L.band):
		# Dropping out of the band disarms it: coming back should not fire one
		# instantly off a clock that ran while you were human.
		p.lurch_t = 0.0
		p.lurch_cd = 0.0
		return
	if p.lurch_t > 0.0:
		p.lurch_t = maxf(0.0, p.lurch_t - dt)
		if p.lurch_t <= 0.0:
			p.lurch_cd = sim.rng.frange(float(L.every_min), float(L.every_max))
			sim.notify("You have your legs back", "#b07ad0")
		return
	if p.lurch_cd <= 0.0:
		p.lurch_cd = sim.rng.frange(float(L.every_min), float(L.every_max))
		return
	p.lurch_cd -= dt
	if p.lurch_cd > 0.0:
		return
	p.lurch_t = sim.rng.frange(float(L.dur_min), float(L.dur_max))
	p.using = {}
	p.searching = {}
	p.reviving = {}
	sim.emit({"t": "lurch", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	sim.notify("SOMETHING ELSE IS DRIVING", "#b07ad0", true)


## What a lurching player wants, which is not what they pressed. Rewrites the
## intent rather than guarding twenty branches: "the intent is taken off you"
## is the rule, and this is the one place it is true.
static func hijack_intent(sim: GameSim, p: PlayerSim) -> void:
	var it := p.intent
	it.fire = false
	it.fire_pressed = false
	it.reload = false
	it.interact = false
	it.interact_held = false
	it.use = false
	it.suppress = false
	it.eat = false
	it.sneak = false
	it.sprint = true                    # it runs
	it.build_action = ""
	it.slot = -1
	it.wheel = 0
	# Toward the nearest living thing that is not you. Nothing in reach and it
	# just runs the way it was already facing, which reads as worse rather
	# than better.
	var reach: float = float(Config.MUTATION.lurch.reach)
	var best: Vector2 = p.pos + Vector2.from_angle(p.angle) * 100.0
	var bd := reach * reach
	for e in sim.enemies.list:
		if e.dead:
			continue
		var d := e.pos.distance_squared_to(p.pos)
		if d < bd:
			bd = d
			best = e.pos
	var dir := (best - p.pos).normalized()
	it.mx = dir.x
	it.my = dir.y
	it.aim = best


# -------------------------------------------------------------- the price --

## What a hit does to the meter. A zombie's melee is a bite `bite_chance` of
## the time — every hit counting would make this a second health bar — and any
## big enough blow moves it whether or not it broke the skin.
static func on_damage(sim: GameSim, p: PlayerSim, dealt: float, bite: bool) -> void:
	var M := Config.MUTATION
	if bite and sim.rng.chance(float(M.bite_chance)):
		add(sim, p, float(M.per_bite), "bitten")
		sim.emit({"t": "bitten", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
		sim.notify("BITTEN — it is spreading", "#c07f9a", true)
	elif dealt >= float(M.heavy_damage):
		add(sim, p, float(M.per_heavy), "hurt")


static func on_down(sim: GameSim, p: PlayerSim) -> void:
	add(sim, p, float(Config.MUTATION.per_down), "down")


## The end of the meter. Death, with its own banner, and you wake up part of
## the way along rather than clean: letting the bar fill must never become the
## cheapest way to empty it.
static func turn(sim: GameSim, p: PlayerSim) -> void:
	if p.dead:
		return
	p.mutation = float(Config.MUTATION.after_turn)
	p.mut_band = band_index(p.mutation)
	p.effects.clear()
	Equipment.recompute_stats(p)
	sim.emit({"t": "turned", "seat": p.seat, "x": p.pos.x, "y": p.pos.y})
	# The banner is `kill_player`'s, so there is one death path and one place
	# that says what happened.
	Damage.kill_player(sim, p, "turned")


# ------------------------------------------------------------------ doses --

## Whether an item is something you take for the meter. A `tool` never is:
## Neural Tissue is an ingredient, not a dose.
static func is_suppressant(id: String) -> bool:
	var c: Dictionary = Config.CONSUMABLES.get(id, {})
	return float(c.get("mut", 0.0)) > 0.0 and not c.get("tool", false)


## What to reach for: the strongest dose that does not overshoot by more than
## `overshoot`, and the gentlest one there is when everything overshoots. The
## rule is written against the table rather than against three item ids, so
## the Refined and Experimental doses will need no change here.
static func pick_suppressant(p: PlayerSim) -> String:
	var over: float = float(Config.MUTATION.overshoot)
	var best := ""
	var best_mut := 0.0
	var gentlest := ""
	var gentlest_mut := INF
	for id in Config.CONSUMABLES:
		if not is_suppressant(id) or p.count_carried(id) <= 0:
			continue
		var m := float(Config.CONSUMABLES[id].mut)
		if m < gentlest_mut:
			gentlest_mut = m
			gentlest = id
		if m <= p.mutation + over and m > best_mut:
			best_mut = m
			best = id
	return best if not best.is_empty() else gentlest


## One dose landing, from the end of the use channel. Spending the item is the
## caller's job; this is what the dose does.
static func take_dose(sim: GameSim, p: PlayerSim, id: String) -> void:
	var c: Dictionary = Config.CONSUMABLES.get(id, {})
	if c.is_empty():
		return
	var took := suppress(sim, p, float(c.get("mut", 0.0)))
	if c.has("effect"):
		give_effect(sim, p, String(c.effect), float(c.get("effect_mul", 1.0)))
	# The gamble. An Experimental dose is three quarters of the bar and ninety
	# seconds of Surge, and one time in four it costs you a Fever — which is
	# on the same axis as the reward, because a Fever turns you faster. That
	# is what stops it being a free win.
	if c.has("risk") and sim != null and sim.rng.chance(float(c.risk.chance)):
		give_effect(sim, p, String(c.risk.effect))
		sim.notify("It fought back", "#c96a5a", true)
	sim.emit({"t": "dosed", "seat": p.seat, "x": p.pos.x, "y": p.pos.y, "id": id})
	sim.notify("%s  −%d Mutation" % [String(c.name), roundi(took)], "#8fd08a")


# ---------------------------------------------------------------- effects --

## Buffs and debuffs. They refresh rather than stack: a second raw brain while
## the first is still turning your stomach resets the clock and does not
## double the misery.
static func give_effect(sim: GameSim, p: PlayerSim, id: String, mul := 1.0) -> void:
	var e: Dictionary = Config.EFFECTS.get(id, {})
	if e.is_empty():
		return
	p.effects[id] = maxf(float(p.effects.get(id, 0.0)), float(e.dur) * mul)
	Equipment.recompute_stats(p)
	if sim != null:
		sim.notify(String(e.name), String(e.color))


static func tick_effects(sim: GameSim, p: PlayerSim, dt: float) -> void:
	if p.effects.is_empty():
		return
	var expired := false
	for id in p.effects.keys():
		var left := float(p.effects[id]) - dt
		if left <= 0.0:
			p.effects.erase(id)
			expired = true
		else:
			p.effects[id] = left
	if expired:
		Equipment.recompute_stats(p)


## The active effects as one small string, for the wire: "nausea:12.3".
static func pack_effects(p: PlayerSim) -> String:
	if p.effects.is_empty():
		return ""
	var parts := PackedStringArray()
	for id in p.effects:
		parts.append("%s:%.1f" % [id, float(p.effects[id])])
	return ",".join(parts)


## The other end of `pack_effects`, on a guest. Recomputes only when the *set*
## of effects changed rather than every snapshot: a clock ticking down is not
## a reason to rebuild every stat twenty times a second.
static func unpack_effects(p: PlayerSim, s: String) -> void:
	var was := p.effects.keys()
	was.sort()
	p.effects.clear()
	if not s.is_empty():
		for part in s.split(",", false):
			var bits := part.split(":")
			if bits.size() == 2 and Config.EFFECTS.has(bits[0]):
				p.effects[String(bits[0])] = float(bits[1])
	var now := p.effects.keys()
	now.sort()
	if was != now:
		Equipment.recompute_stats(p)
