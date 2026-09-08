class_name SaveGame
extends RefCounted
## Saving and loading. Payload version 3.
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

const VERSION := 3
const DIR := "user://saves"

## Fields of a structure that are worth remembering. Everything else is
## rebuilt from its `Config.STRUCTURES` row on load.
const STRUCT_FIELDS := ["hp", "max_hp", "open", "tier", "fuel", "ammo", "on", "arm"]


static func slot_path(slot: int) -> String:
	return "%s/slot%d.json" % [DIR, slot]


# ------------------------------------------------------------------ saving --

static func to_dict(sim: GameSim) -> Dictionary:
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
		players.append({
			"seat": p.seat, "name": p.display_name,
			"x": p.pos.x, "y": p.pos.y, "hp": p.hp, "stam": p.stam,
			# The build, and only the build: level, what has been spent and what
			# it was spent on. Every derived stat is rebuilt on load by the same
			# recompute that produced it, so a save can never carry a stale one.
			"xp": p.xp, "level": p.level, "xp_next": p.xp_next,
			"skill_points": p.skill_points, "attrs": p.attrs.duplicate(), "perks": p.perks.duplicate(),
			"second_wind_cd": p.second_wind_cd,
			"slot": p.slot, "bag": p.bag.to_record(), "hotbar": p.hotbar.to_record(),
			"equip": p.equip.duplicate(), "mag": p.mag.duplicate(),
			"light_on": p.light_on, "light_fuel": p.light_fuel, "light_id": p.light_id,
			"light_charge": p.light_charge.duplicate(),
			"spawn_tx": p.spawn_tile.x, "spawn_ty": p.spawn_tile.y,
		})

	var piles: Array = []
	for it in sim.pickups:
		piles.append({"x": it.pos.x, "y": it.pos.y, "kind": it.kind, "id": it.id, "n": it.n})
	var packs: Array = []
	for b in sim.backpacks:
		packs.append({"x": b.pos.x, "y": b.pos.y, "held": b.held.duplicate(), "mag": b.mag.duplicate(), "seat": b.seat})

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
		"raids_done": sim.raids_done,
		"threat": sim.threat.value,
		"bench_tier": sim.structs.bench_tier,
		"stats": sim.stats.duplicate(),
		"players": players,
		"looted": looted,
		"chopped": sim.world.chopped_keys(),
		"structures": structures,
		"stash": sim.stash.to_record() if sim.stash != null else [],
		"pickups": piles,
		"backpacks": packs,
	}


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
static func apply(sim: GameSim, data: Dictionary) -> Dictionary:
	var world_seed := int(data.get("world_seed", 20240917))
	var world := World.new(world_seed)
	if int(data.get("fingerprint", 0)) != world.fingerprint():
		return {"ok": false, "reason": "This save was made by a different world generator (fingerprint mismatch); it cannot be loaded"}

	sim.start(world, int(data.get("run_seed", 1)))
	sim.time = float(data.get("time", 0.0))
	sim.clock.t = clampf(float(data.get("day_t", Config.DAY_START)), 0.0, 0.999999)
	sim.clock.day = maxi(1, int(data.get("day", 1)))
	# Set directly rather than through tick(), so loading into dusk does not
	# announce dusk again at the player who was already standing in it.
	sim.clock.phase = String(DayNight.phase_at(sim.clock.t).id)
	sim.raids_done = int(data.get("raids_done", 0))
	sim.threat.value = float(data.get("threat", 0.0))
	sim.threat.tier = Threat.tier_of(sim.threat.value)
	sim.structs.bench_tier = int(data.get("bench_tier", 0))
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

	sim.players.clear()
	for rec in data.get("players", []):
		var p := PlayerSim.new()
		p.seat = int(rec.get("seat", 0))
		p.display_name = String(rec.get("name", Config.PLAYER.names[0]))
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
		p.spawn_tile = Vector2i(int(rec.get("spawn_tx", -1)), int(rec.get("spawn_ty", -1)))
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
		Loot.spawn_pickup(sim, Vector2(float(rec.x), float(rec.y)), String(rec.kind), String(rec.id), int(rec.n))
	sim.backpacks.clear()
	for rec in data.get("backpacks", []):
		var held := {}
		for k in rec.get("held", {}):
			held[k] = int(rec.held[k])
		var mag := {}
		for k in rec.get("mag", {}):
			mag[k] = int(rec.mag[k])
		sim.backpacks.append({"pos": Vector2(float(rec.x), float(rec.y)), "held": held, "mag": mag, "t": 0.0, "seat": int(rec.get("seat", 0))})

	sim.events.clear()
	return {"ok": true, "reason": ""}


static func load_from(sim: GameSim, slot: int) -> Dictionary:
	var read := read_slot(slot)
	if not read.ok:
		return read
	return apply(sim, read.data)
