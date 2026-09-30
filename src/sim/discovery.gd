class_name Discovery
extends RefCounted
## What the player knows how to make, and how they came to know it.
##
## Progression step B (`tasks/progression-plan.md`): a recipe or a buildable
## appears when the game has a reason to show it, and never more than about
## eight at once. The reasons are *facts about the run* — what has been held,
## what has been made, how far the bench has climbed, how big a raid has come
## — kept on `GameSim.known` and saved. What is known is **derived** from
## those facts every time they change, never stored, so a save can no more
## carry a stale list than it can a stale stat (invariant 4's shape again).
##
## The rule, per rung of the ladder (`Config.BENCH_TIERS`) and per `wave` on
## the row (`data/recipes.json`, `data/structures.json`):
##
##   by hand   any material in the bill has been held
##   1 Foothold the bench has been reached (tier 1: always)
##   2 Kit      the tier's Kit trigger (`Config.WAVES`): a material first held
##   3 Set      anything from the tier's Kit has been made or built
##   4 Second   the tier's second material first held
##   5 Defence  a raid as big as the tier's ceiling has been warned about
##   station    a structure with that station has been built
##
## `tick` finds new holdings by looking in every present player's pockets,
## so no path an item can take into a pack — loot, craft, harvest, chest,
## backpack, trade — has to remember to say so.

const WAVE_FOOTHOLD := 1
const WAVE_KIT := 2
const WAVE_SET := 3
const WAVE_SECOND := 4
const WAVE_DEFENCE := 5


## A fresh run knows nothing but what its hands can do.
static func fresh() -> Dictionary:
	return {"held": {}, "crafted": {}, "built": {}, "raid_max": -1, "bench_max": 0, "ids": {}, "dirty": true}


# -------------------------------------------------------------------- facts --

## Something is in a pocket. Cheap: a dictionary lookup per stack per step.
static func tick(sim: GameSim) -> void:
	var k: Dictionary = sim.known
	for p in sim.present_players():
		for cont: Slots in [p.bag, p.hotbar, p.haul]:
			if cont == null:
				continue
			for i in range(cont.size()):
				var id: String = cont.id_at(i)
				if not id.is_empty() and not k.held.has(id):
					k.held[id] = true
					k.dirty = true
		for slot in p.equip:
			var id: String = p.equip[slot]
			if not id.is_empty() and not k.held.has(id):
				k.held[id] = true
				k.dirty = true
	if k.dirty:
		_refresh(sim)


static func note_crafted(sim: GameSim, recipe_id: String) -> void:
	if not sim.known.crafted.has(recipe_id):
		sim.known.crafted[recipe_id] = true
		sim.known.dirty = true


static func note_built(sim: GameSim, type: String) -> void:
	if not sim.known.built.has(type):
		sim.known.built[type] = true
		sim.known.dirty = true


static func note_raid(sim: GameSim, index: int) -> void:
	if index > int(sim.known.raid_max):
		sim.known.raid_max = index
		sim.known.dirty = true


static func note_bench(sim: GameSim, tier: int) -> void:
	if tier > int(sim.known.bench_max):
		sim.known.bench_max = tier
		sim.known.dirty = true


## Debug and the smoke run: every fact at once.
static func reveal_all(sim: GameSim) -> void:
	var k: Dictionary = sim.known
	for id in Config.RES:
		k.held[id] = true
	for id in Config.CONSUMABLES:
		k.held[id] = true
	for r in Config.RECIPES:
		k.crafted[String(r.id)] = true
	for id in Config.STRUCTURES:
		k.built[id] = true
	k.raid_max = Config.RAIDS.size() - 1
	k.bench_max = Config.MAX_BENCH
	k.dirty = true
	_refresh(sim)


# -------------------------------------------------------------------- rules --

## The key a thing is known under: a recipe by its id, a buildable as
## "build:<type>".
static func build_key(type: String) -> String:
	return "build:" + type


static func recipe_known(sim: GameSim, r: Dictionary) -> bool:
	if sim.known.dirty:
		_refresh(sim)
	return sim.known.ids.has(String(r.id))


static func structure_known(sim: GameSim, type: String) -> bool:
	if sim.known.dirty:
		_refresh(sim)
	return sim.known.ids.has(build_key(type))


## Every known key, for the wire and the tests.
static func known_keys(sim: GameSim) -> Array:
	if sim.known.dirty:
		_refresh(sim)
	var out: Array = sim.known.ids.keys()
	out.sort()
	return out


## A guest is told what is known rather than why (the facts are the host's);
## it keeps the list and says what is new, as the host's own refresh does.
static func apply_keys(sim: GameSim, keys: Array) -> void:
	var fresh_ids := {}
	for key in keys:
		fresh_ids[String(key)] = true
	_announce(sim, fresh_ids)
	sim.known.ids = fresh_ids
	sim.known.dirty = false


## Whether one row would be known, from the facts alone. Pure, so the data
## test can ask it about every row under every trigger.
static func row_known(k: Dictionary, tier: int, wave: int, cost: Dictionary, station: String) -> bool:
	if not station.is_empty():
		for type in k.built:
			if String(Config.STRUCTURES.get(type, {}).get("station", "")) == station:
				return true
		return false
	if tier <= 0:
		for id in cost:
			if k.held.has(id):
				return true
		return false
	if tier > 1 and int(k.bench_max) < tier:
		return false
	match wave:
		WAVE_FOOTHOLD:
			return true
		WAVE_KIT:
			return _trigger(k, Config.WAVES.get(tier, {}).get("kit", {}), tier)
		WAVE_SET:
			return _kit_made(k, tier)
		WAVE_SECOND:
			return _trigger(k, Config.WAVES.get(tier, {}).get("second", {}), tier)
		WAVE_DEFENCE:
			return int(k.raid_max) >= int(Config.BENCH_TIERS[clampi(tier, 1, Config.MAX_BENCH)].raid_cap)
	return false


static func _trigger(k: Dictionary, spec: Dictionary, tier: int) -> bool:
	if spec.has("bench"):
		return int(k.bench_max) >= int(spec.bench)
	if spec.has("held"):
		for id in spec.held:
			if k.held.has(id):
				return true
		return false
	# No trigger written down: the rung itself is the trigger.
	return int(k.bench_max) >= tier


## Anything from the tier's Kit made or built.
static func _kit_made(k: Dictionary, tier: int) -> bool:
	for r in Config.RECIPES:
		if int(r.bench) == tier and int(r.get("wave", WAVE_KIT)) == WAVE_KIT and k.crafted.has(String(r.id)):
			return true
	for type in Config.STRUCTURES:
		var def: Dictionary = Config.STRUCTURES[type]
		if int(def.get("tier", 1)) == tier and int(def.get("wave", WAVE_KIT)) == WAVE_KIT and k.built.has(type):
			return true
	return false


## Rebuild the known set from the facts, and say what is new.
static func _refresh(sim: GameSim) -> void:
	var k: Dictionary = sim.known
	var fresh_ids := {}
	for r in Config.RECIPES:
		if row_known(k, int(r.bench), int(r.get("wave", WAVE_KIT)), r.cost, String(r.get("station", ""))):
			fresh_ids[String(r.id)] = true
	for type in Config.STRUCTURES:
		var def: Dictionary = Config.STRUCTURES[type]
		if row_known(k, int(def.get("tier", 1)), int(def.get("wave", WAVE_KIT)), def.cost, ""):
			fresh_ids[build_key(type)] = true
	_announce(sim, fresh_ids)
	k.ids = fresh_ids
	k.dirty = false


## One line for everything that arrived together, and an event the screens
## can mark. Nothing is said on a fresh run's first look or on a load: the
## first bench-0 recipes and a save's whole list are not news.
static func _announce(sim: GameSim, fresh_ids: Dictionary) -> void:
	var was: Dictionary = sim.known.ids
	if was.is_empty():
		return
	var names: Array[String] = []
	var keys: Array = []
	for key in fresh_ids:
		if was.has(key):
			continue
		keys.append(key)
		names.append(display_name(String(key)))
	if keys.is_empty():
		return
	names.sort()
	sim.emit({"t": "known", "keys": keys})
	var shown := names.slice(0, 4)
	var text := ", ".join(shown) + (" and %d more" % (names.size() - 4) if names.size() > 4 else "")
	sim.notify("New at the bench: " + text if not keys[0].begins_with("build:") or keys.size() > 1 else "New to build: " + text, "#59b8c4")


static func display_name(key: String) -> String:
	if key.begins_with("build:"):
		return String(Config.STRUCTURES.get(key.trim_prefix("build:"), {}).get("name", key))
	var r := Crafting.recipe(key)
	return String(r.get("name", key)) if not r.is_empty() else key
