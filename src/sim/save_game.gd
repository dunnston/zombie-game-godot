class_name SaveGame
extends RefCounted
## Saving and loading. Payload version 11.
##
## **Containers are identified by tile position, never by ordinal index**
## (invariant 7). The prototype keyed them by their position in an array,
## and every change to world generation silently invalidated every save —
## twice. Props that were chopped down are recorded the same way, as tile
## keys replayed against a world rebuilt from the seed.
##
## A world fingerprint guards the whole scheme: if generation changes, the
## tile keys no longer describe the same map, and the save is refused with
## the version and the reason rather than loaded into a world that has moved
## underneath it.

const VERSION := 11
const DIR := "user://saves"

## Fields of a structure that are worth remembering. Everything else is
## rebuilt from its `Config.STRUCTURES` row on load — a Raised Bed's *stage*
## included, because it is derived from `grow` and a stored one could go
## stale (v11). The load path guards each field with `has`, so a v10 save
## comes back with empty beds rather than being refused.
const STRUCT_FIELDS := ["hp", "max_hp", "open", "tier", "fuel", "ammo", "on", "arm",
	"seed", "fert", "water", "grow"]


static func slot_path(slot: int) -> String:
	return "%s/slot%d.json" % [DIR, slot]


# ------------------------------------------------------------------ saving --

static func to_dict(sim: GameSim) -> Dictionary:
	# From inside an instance the game is written as though the party had just
	# walked out: the town, everyone at its door, what they found gone. A run
	# is never saved (§7). The town is swapped in to be written and back out.
	var inst := sim.instance
	if inst != null:
		inst.swap(sim)
	var out := _town_dict(sim, inst)
	if inst != null:
		inst.swap(sim)
	return out


static func _town_dict(sim: GameSim, inst: Instance) -> Dictionary:
	var looted: Array[String] = []
	for c in sim.world.containers:
		if c.looted:
			looted.append("%d,%d" % [c.tx, c.ty])

	var structures: Array = []
	for s in sim.structs.list:
		if s.destroyed:
			continue
		var rec := {"type": s.type, "tx": s.tx, "ty": s.ty}
		for f in STRUCT_FIELDS:
			rec[f] = s[f]
		# A Supply Stash aliases the shared pile, which is saved once below.
		if s.store != null and s.type != "stash":
			rec["store"] = s.store.to_record()
		structures.append(rec)

	var players: Array = []
	for p in sim.players:
		var rec := {
			"seat": p.seat, "name": p.display_name,
			# Who the character belongs to and whether they are here. The
			# host's save keeps every player by identity (v7), so a guest who
			# comes back next week gets their character, level and pack.
			"identity": p.identity, "away": p.away,
			"x": p.pos.x, "y": p.pos.y,
			# Somebody on the ground when the game was written down gets up
			# when it is read back: a save is not a bleed-out clock.
			"hp": p.hp if not p.downed else maxf(1.0, p.max_hp * Config.PLAYER.revive_hp_frac),
			"stam": p.stam,
			# The build, and only the build: level, what has been spent and what
			# it was spent on. Every derived stat is rebuilt on load by the same
			# recompute that produced it, so a save can never carry a stale one.
			"xp": p.xp, "level": p.level, "xp_next": p.xp_next,
			"skill_points": p.skill_points, "attrs": p.attrs.duplicate(), "perks": p.perks.duplicate(),
			"second_wind_cd": p.second_wind_cd,
			# The meter, and whatever is still working through you (v8). The
			# band is not stored: it is derived from the value on load, the
			# same way it is derived from it in play.
			"mutation": p.mutation, "effects": p.effects.duplicate(),
			"slot": p.slot, "bag": p.bag.to_record(), "hotbar": p.hotbar.to_record(),
			"equip": p.equip.duplicate(), "mag": p.mag.duplicate(),
			"light_on": p.light_on, "light_fuel": p.light_fuel, "light_id": p.light_id,
			"light_doused": p.light_doused, "light_charge": p.light_charge.duplicate(),
			"spawn_tx": p.spawn_tile.x, "spawn_ty": p.spawn_tile.y,
			"driving_id": p.driving_id, "car_keys": p.car_keys.duplicate(),
		}
		# Everyone who went in, here or dropped: nobody is written down inside
		# a map that a save never keeps.
		if inst != null and inst.party.has(p.seat):
			rec.merge(inst.walked_out_record(p), true)
		players.append(rec)

	var piles: Array = []
	for it in sim.pickups:
		piles.append({"x": it.pos.x, "y": it.pos.y, "kind": it.kind, "id": it.id, "n": it.n,
			"w": int(it.get("w", -1)), "lv": int(it.get("lv", 0))})
	var packs: Array = []
	for b in sim.backpacks:
		packs.append({"x": b.pos.x, "y": b.pos.y, "held": b.held.duplicate(), "mag": b.mag.duplicate(),
			"wear": b.wear.duplicate(), "lv": b.get("lv", {}).duplicate(), "seat": b.seat})

	return {
		"version": VERSION,
		"fingerprint": sim.world.fingerprint(),
		"world_seed": sim.world.world_seed,
		"run_seed": sim.run_seed,
		"time": sim.time,
		# Two numbers are the whole clock; everything else about the sky is
		# derived from them, so nothing can come back out of step. Fires are
		# deliberately not saved: they burn out in seconds and a prop that
		# burned away is already in `chopped`.
		"day_t": sim.clock.t,
		"day": sim.clock.day,
		"crew": _crew_record(sim),
		"rescues": _rescue_record(sim),
		"ration_debt": sim.crew.debt,
		"cars": _car_record(sim),
		"raids_done": sim.raids_done, "human_raids_done": sim.human_raids_done,
		"threat": sim.threat.value,
		"bench_tier": sim.structs.bench_tier,
		"stats": sim.stats.duplicate(),
		"players": players,
		"looted": looted,
		"chopped": sim.world.chopped_keys(),
		# The districts you have stood in. Only the ids: the rects are `Config`,
		# so a save cannot carry a stale map of a town that has been re-laid.
		"discovered": _discovered(sim),
		# Which instances were cleared, and on which day. Absent in an older
		# save, which is what "never cleared" looks like, so no version bump.
		"cleared": sim.cleared.duplicate(),
		"structures": structures,
		"stash": sim.stash.to_record() if sim.stash != null else [],
		"pickups": piles,
		"backpacks": packs,
	}


## Just the ids, in `Config.LOCATIONS` order.
static func _discovered(sim: GameSim) -> Array:
	var out: Array = []
	for l in sim.world.locations:
		if l.discovered:
			out.append(String(l.id))
	return out


static func save_to(sim: GameSim, slot: int) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "reason": "Cannot write to %s" % slot_path(slot)}
	f.store_string(JSON.stringify(to_dict(sim)))
	f.close()
	return {"ok": true, "reason": ""}


# ----------------------------------------------------------------- loading --

## Reads a slot and says why it cannot be used, rather than quietly starting
## a new world.
static func read_slot(slot: int) -> Dictionary:
	if not FileAccess.file_exists(slot_path(slot)):
		return {"ok": false, "reason": "Slot %d is empty" % slot}
	var f := FileAccess.open(slot_path(slot), FileAccess.READ)
	if f == null:
		return {"ok": false, "reason": "Cannot read slot %d" % slot}
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "Slot %d is not a save file" % slot}
	if int(data.get("version", 0)) != VERSION:
		return {"ok": false, "reason": "Save is version %s; this build reads version %d" % [str(data.get("version", "?")), VERSION]}
	return {"ok": true, "reason": "", "data": data}


## Rebuilds `sim` from a payload. The world is regenerated from its seed and
## then walked back to the state that was saved: containers marked looted by
## tile, chopped props removed by tile, structures re-placed.
##
## `reuse` is a world already generated from the same seed — the tests hand
## one in because generating one costs a third of a second per guest join.
## It is walked back to the payload's state like a fresh one would be, but
## nothing un-fells a tree: a reused world is only right for a run that has
## not changed it, which is what a test guarantees and a game never does.
static func apply(sim: GameSim, data: Dictionary, reuse: World = null) -> Dictionary:
	var world_seed := int(data.get("world_seed", 20240917))
	var world := reuse if reuse != null and reuse.world_seed == world_seed else World.new(world_seed)
	# `accepts_fingerprint` also takes the town from before the School was
	# stamped on it, so a save from last week still loads (see World).
	if not world.accepts_fingerprint(int(data.get("fingerprint", 0))):
		return {"ok": false, "reason": "This save was made by a different world generator (fingerprint mismatch); it cannot be loaded"}

	sim.start(world, int(data.get("run_seed", 1)))
	sim.time = float(data.get("time", 0.0))
	sim.clock.t = clampf(float(data.get("day_t", Config.DAY_START)), 0.0, 0.999999)
	sim.clock.day = maxi(1, int(data.get("day", 1)))
	# Set directly rather than through tick(), so loading into dusk does not
	# announce dusk again at the player who was already standing in it.
	sim.clock.phase = String(DayNight.phase_at(sim.clock.t).id)
	sim.raids_done = int(data.get("raids_done", 0))
	sim.human_raids_done = int(data.get("human_raids_done", 0))
	sim.threat.value = float(data.get("threat", 0.0))
	sim.threat.tier = Threat.tier_of(sim.threat.value)
	sim.structs.bench_tier = int(data.get("bench_tier", 0))
	for k in data.get("cleared", {}):
		sim.cleared[String(k)] = int(data.cleared[k])
	for k in data.get("stats", {}):
		sim.stats[k] = data.stats[k]
	sim.enemies.list.clear()

	var by_tile := {}
	for c in world.containers:
		by_tile["%d,%d" % [c.tx, c.ty]] = c
	for key in data.get("looted", []):
		var c: Dictionary = by_tile.get(key, {})
		if not c.is_empty():
			c.looted = true

	var found := {}
	for id in data.get("discovered", []):
		found[String(id)] = true
	for l in world.locations:
		l.discovered = found.has(String(l.id))

	for key in data.get("chopped", []):
		var parts: PackedStringArray = String(key).split(",")
		if parts.size() == 2:
			var prop := world.prop_at_tile(int(parts[0]), int(parts[1]))
			if not prop.is_empty():
				world.remove_prop(prop)

	if not data.get("stash", []).is_empty():
		sim.stash = Slots.new(Config.STASH_SLOTS)
		sim.stash.from_record(data.stash)
	for rec in data.get("structures", []):
		if not Config.STRUCTURES.has(rec.type):
			continue
		var s := sim.structs.make(sim, rec.type, int(rec.tx), int(rec.ty))
		for f in STRUCT_FIELDS:
			if rec.has(f):
				s[f] = rec[f]
		if s.store != null and rec.has("store") and rec.type != "stash":
			s.store.from_record(rec.store)

	# Before the players: a driver's `driving_id` has to point at a car that
	# already exists and is where the save left it.
	_load_cars(sim, data)

	sim.players.clear()
	for rec in data.get("players", []):
		var p := PlayerSim.new()
		p.seat = int(rec.get("seat", 0))
		p.display_name = String(rec.get("name", Config.PLAYER.names[0]))
		p.identity = String(rec.get("identity", ""))
		# A guest's character loads parked, whatever it was doing when the
		# game was saved: the person is not here until they connect. The
		# host's own (seat 0) is never away — somebody is at this keyboard.
		p.away = p.seat != 0
		p.pos = Vector2(float(rec.x), float(rec.y))
		p.intent.aim = p.pos + Vector2.RIGHT
		p.xp = float(rec.xp)
		p.level = int(rec.get("level", 1))
		p.xp_next = int(rec.get("xp_next", Config.xp_for_level(p.level)))
		p.skill_points = int(rec.get("skill_points", 0))
		# JSON gives back a plain Dictionary of floats; the ranks are counts.
		for k in rec.get("attrs", {}):
			p.attrs[k] = int(rec.attrs[k])
		for k in rec.get("perks", {}):
			p.perks[k] = int(rec.perks[k])
		p.second_wind_cd = float(rec.get("second_wind_cd", 0.0))
		p.slot = int(rec.slot)
		p.bag.from_record(rec.bag)
		p.hotbar.from_record(rec.hotbar)
		for k in rec.get("equip", {}):
			p.equip[k] = String(rec.equip[k])
		for k in rec.get("mag", {}):
			p.mag[k] = int(rec.mag[k])
		p.light_id = String(rec.get("light_id", ""))
		p.light_fuel = float(rec.get("light_fuel", 0.0))
		for k in rec.get("light_charge", {}):
			p.light_charge[k] = float(rec.light_charge[k])
		p.light_on = bool(rec.get("light_on", false))
		# An older save has no answer to this and false is the right one: a torch
		# loaded into the dark lights itself, which is what it would have done.
		p.light_doused = bool(rec.get("light_doused", false))
		p.spawn_tile = Vector2i(int(rec.get("spawn_tx", -1)), int(rec.get("spawn_ty", -1)))
		p.driving_id = int(rec.get("driving_id", 0))
		for k in rec.get("car_keys", []):
			p.car_keys.append(String(k))
		# Before the recompute: the band is one of the things the recompute
		# reads, so setting it afterwards would load a Feral character with a
		# human's stats until the meter next moved.
		p.mutation = clampf(float(rec.get("mutation", 0.0)), 0.0, float(Config.MUTATION.max))
		p.mut_band = Mutation.band_index(p.mutation)
		p.effects.clear()
		for k in rec.get("effects", {}):
			if Config.EFFECTS.has(k):
				p.effects[String(k)] = float(rec.effects[k])
		Equipment.recompute_stats(p)
		# After the recompute, never before: the ceiling has to exist before
		# what is standing under it is restored, or a Constitution build loads
		# clamped back down to the base 112.
		p.hp = minf(float(rec.hp), p.max_hp)
		p.stam = minf(float(rec.stam), p.max_stam)
		p.lit = p.light_on
		sim.players.append(p)
	if sim.players.is_empty():
		return {"ok": false, "reason": "Save has no players in it"}

	# After the players exist: a bedroll is only "active" if one of them
	# names its tile.
	sim.structs.refresh_bedrolls(sim)

	sim.pickups.clear()
	for rec in data.get("pickups", []):
		Loot.spawn_pickup(sim, Vector2(float(rec.x), float(rec.y)), String(rec.kind), String(rec.id),
			int(rec.n), null, int(rec.get("w", -1)), int(rec.get("lv", 0)))
	sim.backpacks.clear()
	for rec in data.get("backpacks", []):
		var held := {}
		for k in rec.get("held", {}):
			held[k] = int(rec.held[k])
		var mag := {}
		for k in rec.get("mag", {}):
			mag[k] = int(rec.mag[k])
		var wear := {}
		for k in rec.get("wear", {}):
			wear[k] = int(rec.wear[k])
		var lv := {}
		for k in rec.get("lv", {}):
			lv[k] = int(rec.lv[k])
		sim.backpacks.append({"pos": Vector2(float(rec.x), float(rec.y)), "held": held, "mag": mag,
			"wear": wear, "lv": lv, "t": 0.0, "seat": int(rec.get("seat", 0))})

	# Last, after the structures: a sniper needs their tower to exist before
	# they can be pointed at it.
	_load_crew(sim, data)

	sim.events.clear()
	return {"ok": true, "reason": ""}


static func load_from(sim: GameSim, slot: int) -> Dictionary:
	var read := read_slot(slot)
	if not read.ok:
		return read
	return apply(sim, read.data)


## The crew. Like the player's build, only the *inputs* are stored: level and
## job produce the combat numbers on load through `SurvivorSim.refresh`, so a
## Charisma perk bought after the save still reaches everyone in it.
##
## A sniper's tower is stored by tile, not by index into the structure list —
## invariant 7, the same rule that keeps container identity out of ordinals.
static func _crew_record(sim: GameSim) -> Array:
	var out: Array = []
	for s in sim.crew.list:
		if s.dead:
			continue
		out.append({
			"id": s.id, "name": s.display_name, "level": s.level, "xp": s.xp,
			"x": s.pos.x, "y": s.pos.y, "hp": s.hp,
			"job": s.job, "kills": s.kills, "hungry": s.hungry,
			"downed": s.downed, "down_t": s.down_t, "tint": s.tint,
			"tower_tx": int(s.tower.tx) if not s.tower.is_empty() else -1,
			"tower_ty": int(s.tower.ty) if not s.tower.is_empty() else -1,
			# A haul came out of a real container, so it survives a save the
			# same way it survives a reassignment.
			"carrying": s.carrying.duplicate(),
			"carry_items": s.carry_items.duplicate(true),
		})
	return out


static func _rescue_record(sim: GameSim) -> Array:
	var out: Array = []
	for r in sim.crew.rescues:
		out.append({"x": r.pos.x, "y": r.pos.y, "name": r.name, "level": int(r.level)})
	return out


## Rebuilds the crew. Runs after the structures, because a sniper's tower has
## to exist before it can be pointed at.
static func _load_crew(sim: GameSim, data: Dictionary) -> void:
	sim.crew.list.clear()
	sim.crew.rescues.clear()
	sim.crew.seq = 0
	sim.crew.debt = float(data.get("ration_debt", 0.0))

	for rec in data.get("rescues", []):
		sim.crew.rescues.append({
			"pos": Vector2(float(rec.x), float(rec.y)),
			"name": String(rec.get("name", "Survivor")),
			"level": int(rec.get("level", 1)),
		})

	for rec in data.get("crew", []):
		var s := SurvivorSim.new(Vector2(float(rec.x), float(rec.y)),
			String(rec.get("name", "Survivor")), int(rec.get("level", 1)))
		s.id = int(rec.get("id", 0))
		sim.crew.seq = maxi(sim.crew.seq, s.id)
		s.xp = float(rec.get("xp", 0.0))
		s.job = String(rec.get("job", "guard"))
		s.kills = int(rec.get("kills", 0))
		s.hungry = bool(rec.get("hungry", false))
		s.downed = bool(rec.get("downed", false))
		s.down_t = float(rec.get("down_t", 0.0))
		s.tint = String(rec.get("tint", Config.SURVIVOR_TINTS[0]))
		for k in rec.get("carrying", {}):
			s.carrying[k] = int(rec.carrying[k])
		for e in rec.get("carry_items", []):
			s.carry_items.append({"id": String(e.id), "n": int(e.n)})
		var tx := int(rec.get("tower_tx", -1))
		var ty := int(rec.get("tower_ty", -1))
		if tx >= 0:
			s.tower = sim.structs.at_tile(tx, ty)
		# A sniper whose tower did not come back is a guard, not a crash.
		if s.job == "sniper" and s.tower.is_empty():
			s.job = "guard"
		# After the level and the job, never before: the ceiling has to exist
		# before what is standing under it is restored.
		s.refresh(sim.host())
		s.hp = minf(float(rec.get("hp", s.max_hp)), s.max_hp)
		sim.crew.list.append(s)


## Cars. The generator makes the same thirty in the same places from the seed,
## so what a save carries is only what a *run* changed about them: what is
## broken, what is open, what is in the boot, and where the driven one ended
## up. `si` and the spawn position come back from the world.
static func _car_record(sim: GameSim) -> Array:
	var out: Array = []
	for v in sim.cars.list:
		out.append({
			"id": v.id, "x": v.pos.x, "y": v.pos.y, "angle": v.angle,
			"hp": v.hp, "fuel": v.fuel, "locked": v.locked, "hotwired": v.hotwired,
			"key_id": v.key_id, "destroyed": v.destroyed,
			"trunk": v.trunk.to_record(),
			# The tiles this car is blocking right now. Recomputing them on
			# load would be wrong for a car parked somewhere it was not made.
			"tiles": _tiles_record(v.tiles),
		})
	return out


static func _tiles_record(tiles: Array) -> Array:
	var out: Array = []
	for t: Vector2i in tiles:
		out.append([t.x, t.y])
	return out


## Rebuilds the cars over the freshly generated ones. Runs before the players,
## because a driver's `driving_id` has to point at something that exists.
static func _load_cars(sim: GameSim, data: Dictionary) -> void:
	var by_id := {}
	for v in sim.cars.list:
		by_id[int(v.id)] = v

	# A salvaged car has no record, and the fleet was just regenerated from the
	# seed — so anything the save does not mention was stripped and must go, or
	# salvage-save-reload is an endless scrap mine.
	var kept := {}
	for rec in data.get("cars", []):
		kept[int(rec.id)] = true
	for i in range(sim.cars.list.size() - 1, -1, -1):
		var gone: Dictionary = sim.cars.list[i]
		if not kept.has(int(gone.id)):
			sim.cars.release_tiles(sim, gone)
			sim.cars.list.remove_at(i)

	for rec in data.get("cars", []):
		var v: Dictionary = by_id.get(int(rec.id), {})
		if v.is_empty():
			continue
		# The generator already blocked this car's tiles. Release them before
		# moving it, or a car that was driven somewhere leaves a permanent
		# invisible wall where it was parked at generation.
		sim.cars.release_tiles(sim, v)
		v.pos = Vector2(float(rec.x), float(rec.y))
		v.prev_pos = v.pos
		v.angle = float(rec.angle)
		v.speed = 0.0
		v.engine_on = false
		v.hp = float(rec.hp)
		v.fuel = float(rec.fuel)
		v.locked = bool(rec.locked)
		v.hotwired = bool(rec.hotwired)
		v.key_id = String(rec.get("key_id", ""))
		v.destroyed = bool(rec.get("destroyed", false))
		v.trunk.from_record(rec.get("trunk", []))
		var tiles: Array[Vector2i] = []
		for t in rec.get("tiles", []):
			tiles.append(Vector2i(int(t[0]), int(t[1])))
		v.tiles = tiles
		for t in tiles:
			if World.in_bounds(t.x, t.y):
				sim.world.blocked[t.y * Config.WORLD_TILES + t.x] = 1
	# The key markers live on containers, which a load rebuilds from the seed,
	# so without this every locked car comes back keyless.
	sim.cars.plant_keys(sim)
	sim.world_version += 1
