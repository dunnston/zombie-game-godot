class_name Farming
extends RefCounted
## Raised beds: what is planted, what it is fed, how wet it is, and what comes
## out. A `RefCounted` with nothing but static functions and no state of its
## own — the state lives on the structure, beside `fuel` and `ammo`
## (invariant 1: no nodes, no `Input`, nothing but the sim).
##
## **Why a water meter is not a chore.** Pillar 1 is "survival without survival
## chores" and §7 spent the whole project refusing thirst, hunger and sleep. A
## bed earns its place on three rules, and every function here is written to
## keep them true:
##
## 1. **A plant never dies.** Dry soil stops the growth clock (`tick`); nothing
##    anywhere kills a planting for want of water. Forgetting a bed costs you
##    time and never the crop, so the meter is a throttle rather than a threat.
## 2. **Nothing is ever required.** What comes out is buffs and cooking inputs,
##    exactly like the rest of the food table. There is no hunger bar under any
##    of this and there is not going to be one.
## 3. **It is delegable.** `water`, `harvest` and `plant` each take the player
##    who is doing it, so the Farmer job is four calls rather than a rewrite.
##
## The bed's four fields are `seed`, `fert`, `water` and `grow`. **The stage is
## never stored** — it is derived from `grow` every time it is asked for, so
## nothing can save, send or draw a stale one.

const F := Config.FARM


# ---------------------------------------------------------------- queries --

static func is_bed(s: Dictionary) -> bool:
	return not s.is_empty() and not s.destroyed and s.def.get("plot", false)


static func planted(s: Dictionary) -> bool:
	return is_bed(s) and not String(s.seed).is_empty()


## The row from `CROPS` for what is in the ground, or empty.
static func crop_of(s: Dictionary) -> Dictionary:
	return Config.CROPS.get(String(s.seed), {}) if planted(s) else {}


## The row from `FERTILIZER` for what has been dug in, or empty.
static func fert_of(s: Dictionary) -> Dictionary:
	return Config.FERTILIZER.get(String(s.fert), {}) if is_bed(s) else {}


## How long this planting takes, in seconds, fertilizer included.
static func grow_time(s: Dictionary) -> float:
	var crop := crop_of(s)
	if crop.is_empty():
		return 0.0
	var speed: float = float(fert_of(s).get("speed_mul", 1.0))
	return float(crop.days) * Config.DAY_LENGTH * speed


## How far along, 0..1. The one number the stage, the bar and the drawing all
## read, so they cannot disagree about what is in the ground.
static func progress(s: Dictionary) -> float:
	var total := grow_time(s)
	return 0.0 if total <= 0.0 else clampf(float(s.grow) / total, 0.0, 1.0)


## 0 seeded, 1 sprouting, 2 growing, 3 ready.
static func stage(s: Dictionary) -> int:
	if not planted(s):
		return -1
	var p := progress(s)
	var at: Array = F.stage_at
	var n := 0
	for i in range(at.size()):
		if p >= float(at[i]) and p < 1.0:
			n = i
	return at.size() - 1 if p >= 1.0 else n


static func stage_name(s: Dictionary) -> String:
	var i := stage(s)
	return "" if i < 0 else String(F.stage_names[i])


static func ready(s: Dictionary) -> bool:
	return planted(s) and progress(s) >= 1.0


static func water_frac(s: Dictionary) -> float:
	return clampf(float(s.water) / float(F.water_max), 0.0, 1.0)


## How fast a full bed empties: the whole tank over `dry_days` of game time.
static func drain_per_sec() -> float:
	return float(F.water_max) / (float(F.dry_days) * Config.DAY_LENGTH)


## The bed on a tile, if this player is close enough to be working it, else
## empty. Range-checked here rather than in the screen, for the reason
## `Structures.reachable_store` gives: the rule has to hold for a guest's
## command too, and a guest that could name any tile in the world could
## harvest the whole town from its bedroll.
static func reachable_bed(sim: GameSim, p: PlayerSim, tx: int, ty: int) -> Dictionary:
	var s := sim.structs.at_tile(tx, ty)
	if not is_bed(s):
		return {}
	var r: float = Config.PLAYER.interact_range + Config.BUILD.store_reach_bonus
	return s if p.pos.distance_squared_to(s.pos) <= r * r else {}


## Every seed and every fertilizer, for the screen's "what fits here" test.
static func accepts(slot: String, id: String) -> bool:
	if slot == "seed":
		return Config.CROPS.has(id)
	return Config.FERTILIZER.has(id) if slot == "fert" else false


## What the interact key is offering at this bed. One string, built here, so
## the prompt on screen and the thing the key does can never drift apart.
static func prompt(s: Dictionary) -> String:
	if ready(s):
		return "Harvest %s" % Items.name_of(String(crop_of(s).crop))
	if not planted(s):
		return "Plant something in the Raised Bed"
	var dry := " · dry" if float(s.water) <= 0.0 else " · %d%% water" % roundi(water_frac(s) * 100.0)
	return "Tend %s  (%s %d%%%s)" % [
		Items.name_of(String(crop_of(s).crop)), stage_name(s), roundi(progress(s) * 100.0), dry]


# ------------------------------------------------------------------- work --

## Everything below spends out of the pack and then the shared stash, through
## `PlayerSim.can_afford` and `spend` — the same pair a wall, a repair and a
## recipe already use.
##
## **The stash is reachable from anywhere in the world, and always has been.**
## `total_res` adds `sim.stash` with no distance test at all, so a Steel Wall
## has always been payable from a stash on the far side of town; farming
## inherits that rather than introducing it. An earlier version of this
## comment claimed a field bed was "a thing you carry water to", which the
## code has never done (Codex, PR #24). Range-checking the stash is a change
## to the whole economy and every system that spends, not a farming rule —
## making this the one place that checked would be a surprise, not a fix. It
## is on the roadmap as its own card.

static func plant(sim: GameSim, p: PlayerSim, s: Dictionary, seed_id: String) -> bool:
	if not is_bed(s):
		return false
	if not Config.CROPS.has(seed_id):
		sim.notify("That is not a seed", "#c96a5a")
		return false
	if planted(s):
		sim.notify("Something is already growing there", "#8a8f84")
		return false
	var cost := {seed_id: 1}
	if not p.can_afford(sim, cost):
		sim.notify("No %s to plant" % Items.name_of(seed_id), "#c96a5a")
		return false
	p.spend(sim, cost)
	s.seed = seed_id
	s.grow = 0.0
	var crop: Dictionary = Config.CROPS[seed_id]
	sim.notify("Planted %s — %s in %.1f days" % [
		Items.name_of(seed_id), Items.name_of(String(crop.crop)), float(crop.days)], "#b7e08a")
	sim.emit({"t": "planted", "x": s.pos.x, "y": s.pos.y, "seed": seed_id})
	Progression.add_xp(sim, p, int(F.xp_plant), "PLANT")
	return true


static func fertilize(sim: GameSim, p: PlayerSim, s: Dictionary, fert_id: String) -> bool:
	if not is_bed(s):
		return false
	if not Config.FERTILIZER.has(fert_id):
		sim.notify("That is not fertilizer", "#c96a5a")
		return false
	if not String(s.fert).is_empty():
		sim.notify("This bed has already been fed", "#8a8f84")
		return false
	var cost := {fert_id: 1}
	if not p.can_afford(sim, cost):
		sim.notify("No %s" % Items.name_of(fert_id), "#c96a5a")
		return false
	p.spend(sim, cost)
	s.fert = fert_id
	var f: Dictionary = Config.FERTILIZER[fert_id]
	sim.notify("%s dug in — %s" % [Items.name_of(fert_id), String(f.desc)], "#b7e08a")
	return true


## One bottle of Clean Water. Deliberately the same bottle that buys the
## Hydrated buff: drink it or grow with it is the decision the bed exists to
## pose, and giving farming a water source of its own would throw that away.
static func water(sim: GameSim, p: PlayerSim, s: Dictionary) -> bool:
	if not is_bed(s):
		return false
	if float(s.water) >= float(F.water_max) - 0.001:
		sim.notify("That bed is already soaked", "#8a8f84")
		return false
	var cost := {"water": 1}
	if not p.can_afford(sim, cost):
		sim.notify("No Clean Water — find some, or you are only waiting", "#c96a5a")
		return false
	p.spend(sim, cost)
	s.water = minf(float(F.water_max), float(s.water) + float(F.water_per_bottle))
	sim.notify("Watered — %d%%" % roundi(water_frac(s) * 100.0), "#6ad0c4")
	sim.emit({"t": "watered", "x": s.pos.x, "y": s.pos.y})
	Progression.add_xp(sim, p, int(F.xp_water), "WATER")
	return true


## What comes up. The fertilizer is spent here rather than at planting, so
## feeding a bed you planted yesterday still counts — which is forgiving in
## the way pillar 1 asks for, and costs nothing to allow.
##
## A seed of the same kind always comes back, and sometimes two. Without that
## a farm dead-ends the first time the loot tables stop offering seed, and a
## dead end is a worse outcome than an economy that grows slowly.
static func harvest(sim: GameSim, p: PlayerSim, s: Dictionary) -> int:
	if not planted(s):
		return 0
	if not ready(s):
		sim.notify("Not ready — %s, %d%%" % [stage_name(s), roundi(progress(s) * 100.0)], "#8a8f84")
		return 0
	var crop: Dictionary = crop_of(s)
	var seed_id := String(s.seed)
	# Fertilizer is the *only* multiplier on a harvest, and the panel prints
	# the band it produces. `p.loot_mul` used to be in here as well, which
	# made the panel promise 3-5 and pay 4-6 to anyone with a rank of
	# Scrounger (Codex, PR #24). Taking it out rather than printing it: the
	# perk's own description is "+35% resources **from containers**", a crop
	# you grew is nearer to a craft than to a find, and crafting has never
	# scaled with a loot perk. It also keeps the feed slot the one dial the
	# whole system is built around, instead of a number quietly stacked on by
	# a Perception build.
	var mul: float = float(fert_of(s).get("yield_mul", 1.0))
	var base: int = sim.rng.irange(int(crop.min), int(crop.max))
	var n := maxi(1, floori(base * mul))

	var seeds: int = int(F.seed_back)
	if sim.rng.chance(float(F.seed_back_bonus)):
		seeds += 1

	# The bed is cleared before anything is handed out: a harvest that
	# overflowed onto the ground and left the crop standing would be a way to
	# farm one bed for ever.
	s.seed = ""
	s.fert = ""
	s.grow = 0.0

	var crop_id := String(crop.crop)
	Loot.give_res_or_drop(sim, p, crop_id, n, s.pos)
	Loot.give_res_or_drop(sim, p, seed_id, seeds, s.pos)
	sim.emit({"t": "harvest", "x": s.pos.x, "y": s.pos.y, "res": crop_id, "n": n,
		"label": Items.name_of(crop_id).to_upper()})
	# "1 Potato Eyes back" reads as a bug. The seed's own name is already
	# plural, so the count goes on the word "seed" instead.
	sim.notify("Harvested %d %s  ·  %d seed%s back" % [
		n, Items.name_of(crop_id), seeds, "" if seeds == 1 else "s"], "#b7e08a", true)
	Progression.add_xp(sim, p, int(F.xp_harvest), "HARVEST")
	return n


## A bed leaving the map. **Destruction loses the planting and salvage returns
## it**, which is the same line `destroy` and `demolish` already draw
## everywhere else: a brute flattening your garden mid-raid is a real loss, and
## deciding to move a bed is not.
static func on_removed(sim: GameSim, s: Dictionary, refund: bool) -> void:
	if not s.def.get("plot", false):
		return
	if refund:
		if not String(s.seed).is_empty():
			Loot.stash_or_drop(sim, String(s.seed), 1, s.pos)
		if not String(s.fert).is_empty():
			Loot.stash_or_drop(sim, String(s.fert), 1, s.pos)
	s.seed = ""
	s.fert = ""
	s.grow = 0.0
	s.water = 0.0


# ------------------------------------------------------------------- step --

## Water drains whether or not anything is planted — an empty bed dries out
## like any other soil — but **growth only advances while there is water in
## it**, and running dry never kills what is in the ground. That single `if`
## is the whole reason a garden is allowed to exist in this game.
static func tick(sim: GameSim, dt: float) -> void:
	var drain := drain_per_sec() * dt
	for s in sim.structs.list:
		if s.destroyed or not s.def.get("plot", false):
			continue
		var wet: float = float(s.water)
		if wet > 0.0:
			s.water = maxf(0.0, wet - drain)
			if not String(s.seed).is_empty() and float(s.grow) < grow_time(s):
				s.grow = float(s.grow) + dt
				if float(s.grow) >= grow_time(s):
					sim.notify("%s is ready to harvest" % Items.name_of(String(crop_of(s).crop)), "#b7e08a")
