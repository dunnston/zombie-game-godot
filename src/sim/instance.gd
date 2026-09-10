class_name Instance
extends RefCounted
## One run through an instanced dungeon (`tasks/instanced-dungeons.md`).
##
## Entering sets the whole town aside and hands the sim a fresh map to play on.
## `MAP_FIELDS` is everything that belongs to a map rather than to the players,
## and `swap` exchanges the town's set with the interior's. That one exchange is
## entering, leaving and saving from inside — and it is why nothing in the town
## can tick while you are in here: it is not in the sim to be ticked.
##
## The owner's rules, and where each one lives:
## - what you find goes in the haul (`Loot.give_entry`) and is tallied here;
## - only the boss lets it out (`leave` with "extracted");
## - dying, or walking out early, forfeits what you found and keeps what you
##   brought (`forfeit`), and you wake outside the door;
## - a fresh roll every entry, and one clear a day (`GameSim.cleared`).

const MAP_FIELDS := ["world", "enemies", "bullets", "pickups", "backpacks", "fire", "cars", "crew",
	"structs", "stash", "quiet", "clock", "threat", "raid"]

var kind := ""
var def: Dictionary = {}
var run_seed := 0
## Where you stand in the town when you come out.
var door := Vector2.ZERO
## "running" until the boss is down, then "cleared".
var state := "running"
## Keys the party has found, by name. Shared, because a key is a fact.
var keys := {}
## seat -> {item id: count} found in here. A tally rather than a flag on the
## items (§6.3), so stacking, spending and a find moved into the pack all come
## out right by arithmetic.
var gained := {}
var boss: EnemySim = null
## Seconds this run has taken, against the eight-to-twelve-minute budget (§6.1).
var t := 0.0
## The other map's objects: the town's, while a run is on.
var held := {}
var held_nav := {}
## A way out taken on the key, waiting for the end of the step. The map is
## only ever swapped there: leaving in the middle of a player's tick left the
## rest of the step running on the town with the sim's `instance` gone from
## under it, which the smoke run found as a SCRIPT ERROR and no test had.
var leaving := ""
## The seats that went in. Whoever went in comes out when the run ends —
## standing, down, dead or dropped (§10) — so a friend who fell at ninety per
## cent is not robbed for it, and nobody is left inside a map that has gone.
var party: Array[int] = []
## A guest's copy: built from the seed the host sent, never ticked, and never
## deciding anything. Snapshots bring the crowd; the world diff the rest.
var mirror := false


## Exchanges every map field with `held`. Entering, leaving, and the two sides
## of a save written from inside are all this.
func swap(sim: GameSim) -> void:
	for f: String in MAP_FIELDS:
		var theirs: Variant = held.get(f)
		held[f] = sim.get(f)
		sim.set(f, theirs)
	var nav: Dictionary = sim._nav
	sim._nav = held_nav
	held_nav = nav
	# Any cached flow field is about the map that just left.
	sim.world_version += 1


# -------------------------------------------------------------- the door --

static func reach() -> float:
	return float(Config.PLAYER.interact_range)


## The nearest of these kinds of feature within reach of `p`, or empty.
static func feature_near(sim: GameSim, p: PlayerSim, kinds: Array) -> Dictionary:
	var best := {}
	var bd := reach() * reach()
	for f in sim.world.features:
		if not String(f.kind) in kinds:
			continue
		var d := p.pos.distance_squared_to(Vector2(f.x, f.y))
		if d < bd:
			bd = d
			best = f
	return best


static func door_for(sim: GameSim, kind: String) -> Dictionary:
	for f in sim.world.features:
		if String(f.kind) == "instance_door" and String(f.id) == kind:
			return f
	return {}


static func title(kind: String) -> String:
	return String(Config.INSTANCES.get(kind, {}).get("name", kind)).capitalize()


## Why `p` cannot go in, or "". The prompt and the key both ask this, so they
## can never disagree.
static func refusal(sim: GameSim, p: PlayerSim, kind: String) -> String:
	if sim.instance != null:
		return "You are already inside"
	if p.driving_id > 0:
		return "Get out of the car first"
	if sim.cleared.has(kind) and int(sim.cleared[kind]) == sim.clock.day:
		return "Chained shut. You cleared it today — come back tomorrow"
	# The party goes in together or nobody does (§10): everyone here, on their
	# feet, at the door. Splitting it would mean running two maps at once.
	var f := door_for(sim, kind)
	var waiting: Array[String] = []
	for q in sim.present_players():
		if q == p:
			continue
		if q.dead or q.downed:
			return "%s has to be on their feet to go in" % q.display_name
		# Everybody, not only whoever pressed E (Codex, PR #32). Entering
		# swaps the town's cars out from under a driver without `exit`, which
		# left the car running with its tiles released — a car nothing
		# collided with — until somebody got in and out of it again.
		if q.driving_id > 0:
			return "%s has to get out of the car first" % q.display_name
		if f.is_empty() or q.pos.distance_to(f.stand) > float(Config.INSTANCE.party_reach):
			waiting.append(q.display_name)
	if not waiting.is_empty():
		return "Everyone goes in together — waiting for %s" % ", ".join(waiting)
	return ""


static func door_label(sim: GameSim, p: PlayerSim, f: Dictionary) -> String:
	var why := refusal(sim, p, String(f.id))
	return why if not why.is_empty() else "Enter %s" % title(String(f.id))


# ---------------------------------------------------------------- entering --

## ENTER on the door's panel. Everyone present goes in together, lands in the
## foyer, and the interior is populated. False, with the reason said, when the
## door would not open.
static func enter(sim: GameSim, p: PlayerSim, kind: String) -> bool:
	if not Config.INSTANCES.has(kind):
		return false
	var f := door_for(sim, kind)
	if f.is_empty() or p.pos.distance_to(Vector2(f.x, f.y)) > reach():
		return false
	var why := refusal(sim, p, kind)
	if not why.is_empty():
		sim.notify(why, "#c96a5a")
		return false
	var inst := Instance.new()
	inst.kind = kind
	inst.def = Config.INSTANCES[kind]
	# A fresh roll every time you go in.
	inst.run_seed = sim.rng.irange(1, 0x3FFFFFFF)
	inst.door = f.stand
	inst.held = inst._interior(sim.clock.day)
	inst.swap(sim)
	sim.instance = inst
	var present := sim.present_players()
	for i in range(present.size()):
		var q := present[i]
		_arrive(q, arrival(sim.world, i, present.size()))
		q.haul.clear_all()
		inst.gained[q.seat] = {}
		inst.party.append(q.seat)
	inst._populate(sim)
	sim.emit({"t": "instance_enter", "kind": kind})
	sim.notify("%s — what you find in here leaves only past the boss" % title(kind), "#d8c98a", true)
	return true


## A fresh set of map objects for the inside: its own world, a frozen clock at
## the instance's light — on the town's day, so the HUD does not say it is
## day one — and nothing of the town's.
func _interior(day: int) -> Dictionary:
	var clock := DayNight.new()
	clock.day = day
	clock.t = float(def.clock_t)
	clock.phase = String(DayNight.phase_at(clock.t).id)
	var en := Enemies.new()
	en.rng = Rng.new(run_seed ^ 0x5C4001)
	var bullets: Array[Dictionary] = []
	var pickups: Array[Dictionary] = []
	var backpacks: Array[Dictionary] = []
	return {
		"world": World.new(run_seed, kind), "enemies": en, "bullets": bullets,
		"pickups": pickups, "backpacks": backpacks, "fire": Fire.new(), "cars": Vehicles.new(),
		"crew": Survivors.new(), "structs": Structures.new(), "stash": null,
		"quiet": QuietField.new(), "clock": clock, "threat": Threat.new(), "raid": null,
	}


## The placed population, and the boss. Nothing else ever spawns in here: the
## standing-population spawner is what makes the town never quiet, and a
## dungeon has to be clearable (§7).
func _populate(sim: GameSim) -> void:
	var tier := int(def.tier)
	for at in sim.world.enemy_spots:
		sim.enemies.spawn(sim.enemies.pick_type(tier), at)
	boss = sim.enemies.spawn(String(def.boss), sim.world.boss_spot, false, false, float(def.boss_hp_mul))


## Where the `i`th of `n` arrivals stands: side by side across the foyer, a
## body's width apart. Everyone on the one entry spot drew as a single player
## with somebody else's name over them (pillar 4). Host and guest both place
## the party with this, so a guest's picture of itself does not snap on
## arrival.
static func arrival(world: World, i: int, n: int) -> Vector2:
	return world.entry_spot + Vector2((i - (n - 1) / 2.0) * 30.0, 0.0)


static func _arrive(q: PlayerSim, at: Vector2) -> void:
	q.pos = at
	q.prev_pos = at
	q.vel = Vector2.ZERO
	q.searching = {}
	q.using = {}
	q.reviving = {}
	q.car_hold = {}
	q.swing = {}
	q.reloading = {}
	q.intent.clear_edges()


# -------------------------------------------------------------------- run --

func tick(sim: GameSim, dt: float) -> void:
	# Last in `GameSim.tick`, so this is the end of the step: the one place the
	# map changes under everybody.
	if not leaving.is_empty():
		# The way out was reached, but the step went on after it (Codex, PR
		# #31): a party that was all dead by the end of it did not walk out
		# with anything. With anyone still standing it is an extraction, and
		# the party rule brings the fallen out with everything.
		var outcome := leaving
		if outcome == "extracted" and _nobody_standing(sim):
			outcome = "wiped"
		leave(sim, outcome)
		return
	t += dt
	# Nothing culls the dead in here — the spawner that does is not running.
	var list := sim.enemies.list
	for i in range(list.size() - 1, -1, -1):
		if list[i].dead:
			list.remove_at(i)
	if state == "running" and boss != null and boss.dead:
		state = "cleared"
		sim.notify("It is down. Walk out with everything you found — the doors are open", "#ffe08a", true)
		sim.emit({"t": "instance_cleared", "kind": kind})
	# A wipe: everyone present is dead and has had their moment on the floor.
	# Nobody comes back inside on their own (`Damage.respawn_player`).
	var present := sim.present_players()
	if present.is_empty():
		return
	for q in present:
		if not q.dead or q.respawn_t > 0.0:
			return
	leave(sim, "wiped")


## Something found in here, into the tally.
func note_gain(p: PlayerSim, id: String, n: int) -> void:
	if n <= 0:
		return
	var mine: Dictionary = gained.get(p.seat, {})
	mine[id] = int(mine.get(id, 0)) + n
	gained[p.seat] = mine


func found_key(sim: GameSim, key: String) -> void:
	if keys.get(key, false):
		return
	keys[key] = true
	sim.notify("The %s key. Now the chained door." % key, "#d0c46a", true)
	sim.emit({"t": "key_found", "key": key})


## The chained door, opened with the key the party found. Its tiles become
## floor to feet, bullets and sight, and the flow fields rebuild round it.
func unlock(sim: GameSim, f: Dictionary) -> bool:
	if f.open:
		return false
	if not keys.get(String(f.key), false):
		sim.notify("Chained shut. The key is somewhere in the school", "#8a8f84")
		return false
	f.open = true
	for tile: Vector2i in f.tiles:
		sim.world.blocked[tile.y * Config.WORLD_TILES + tile.x] = 0
	sim.world_version += 1
	sim.notify("The chains come off. Something in the gym heard that", "#d8c98a", true)
	sim.emit({"t": "unlocked", "x": f.x, "y": f.y})
	return true


# ----------------------------------------------------------------- leaving --

## LEAVE on the way-out panel: walking out, which forfeits the haul unless the
## boss is down. Only from a way out, which the host checks.
static func walk_out(sim: GameSim, p: PlayerSim) -> bool:
	var inst := sim.instance
	if inst == null:
		return false
	var f := feature_near(sim, p, ["leave", "exit"])
	if f.is_empty() or (String(f.kind) == "exit" and inst.state != "cleared"):
		return false
	if inst.state != "cleared":
		var why := leave_refusal(sim, p)
		if not why.is_empty():
			sim.notify(why, "#c96a5a")
			return false
	leave(sim, "extracted" if inst.state == "cleared" else "left")
	return true


## Why `p` cannot walk the party out early yet, or "". It takes everybody and
## everything they found, so everyone still standing has to be at the door —
## one player calling it from the foyer while another fights would be a
## decision made for them. The downed and the dead come out with the party.
static func leave_refusal(sim: GameSim, p: PlayerSim) -> String:
	var f := feature_near(sim, p, ["leave"])
	var at := Vector2(f.x, f.y) if not f.is_empty() else p.pos
	var waiting: Array[String] = []
	for q in sim.present_players():
		if q == p or q.dead or q.downed:
			continue
		if q.pos.distance_to(at) > float(Config.INSTANCE.party_reach):
			waiting.append(q.display_name)
	return "" if waiting.is_empty() else "Everyone standing leaves together — waiting for %s" % ", ".join(waiting)


## Everyone who went in, here or not.
func _members(sim: GameSim) -> Array[PlayerSim]:
	var out: Array[PlayerSim] = []
	for q in sim.players:
		if party.has(q.seat) or (party.is_empty() and not q.away):
			out.append(q)
	return out


## The end of a run, however it ended: "extracted" (the boss is down and
## everything comes out), "left" (walked out early) or "wiped" (everyone died).
## The last two forfeit what was found. Either way the haul is emptied into
## the pack — what does not fit lands at the door, never nowhere — the town is
## swapped back in, and everyone is standing, or waking, outside.
static func leave(sim: GameSim, outcome: String) -> void:
	var inst := sim.instance
	if inst == null:
		return
	var spill: Array[Dictionary] = []
	var everyone := inst._members(sim)
	for q in everyone:
		if outcome != "extracted":
			inst.forfeit(q)
		inst.gained.erase(q.seat)
		spill.append_array(unpack_haul(q))
		_arrive(q, q.pos)
	inst.swap(sim)
	sim.instance = null
	var name := title(inst.kind)
	for q in everyone:
		if q.dead:
			Damage.respawn_player(sim, q, inst.door, ("You come to outside %s — the party brought you out with everything" if outcome == "extracted"
				else "You wake up outside %s — it keeps what you found") % name)
		else:
			# Down in there is up out here: the party carried you.
			if q.downed:
				q.downed = false
				q.down_t = 0.0
				q.hp = maxf(1.0, q.max_hp * float(Config.PLAYER.revive_hp_frac))
			_arrive(q, inst.door)
	for s in spill:
		Loot.spawn_pickup(sim, inst.door, String(s.kind), String(s.id), int(s.n), null, int(s.w))
	if outcome == "extracted":
		sim.cleared[inst.kind] = sim.clock.day
		sim.notify("Out of %s with everything you found" % name, "#ffe08a", true)
	elif outcome == "left":
		sim.notify("You walked out. %s keeps what you found" % name, "#c9a26a", true)
	sim.emit({"t": "instance_leave", "kind": inst.kind, "outcome": outcome})


## Takes back what `q` found in here, and not a thing more: per item, the
## smaller of what was found and what is still carried, from the haul first,
## then the pack, the hotbar and what is worn. Forty rounds brought and twenty
## found, ten fired: thirty come out. A found medkit already used costs nothing.
func forfeit(q: PlayerSim) -> void:
	var found: Dictionary = gained.get(q.seat, {})
	for id: String in found:
		var n := mini(int(found[id]), held_count(q, id))
		n -= q.haul.take(id, n)
		n -= q.bag.take(id, n)
		n -= q.hotbar.take(id, n)
		for slot: String in q.equip:
			if n > 0 and q.equip[slot] == id:
				q.equip[slot] = ""
				n -= 1
		if Config.WEAPONS.has(id) and held_count(q, id) == 0:
			q.mag.erase(id)
	gained[q.seat] = {}
	Equipment.after_equip_change(q)


static func _nobody_standing(sim: GameSim) -> bool:
	for q in sim.present_players():
		if not q.dead:
			return false
	return true


## What the haul counts against its cap (Codex, PR #31). Not the pouch's own
## weight: a find moved into the pack is still a find, and counting only the
## pouch let a full haul be emptied into spare pack space and filled again.
## Each item counts once, at the larger of what is in the haul and the finds
## of it you still hold anywhere — so moving finds between the haul and the
## pack changes nothing, and your own things put in the haul still count.
## `delta` asks what it would be with that many more (or fewer) of an id in
## the haul, for a move that has not happened yet.
static func haul_load(sim: GameSim, p: PlayerSim, delta := {}) -> float:
	var found: Dictionary = {} if sim.instance == null else sim.instance.gained.get(p.seat, {})
	var ids := {}
	for id in p.haul.entries():
		ids[id] = true
	for id in found:
		ids[id] = true
	for id in delta:
		ids[id] = true
	var load := 0.0
	for id: String in ids:
		var in_haul := p.haul.count(id) + int(delta.get(id, 0))
		var finds := mini(int(found.get(id, 0)), held_count(p, id))
		load += Items.weight_of(id) * maxi(in_haul, finds)
	return load


static func held_count(q: PlayerSim, id: String) -> int:
	var n := q.haul.count(id) + q.bag.count(id) + q.hotbar.count(id)
	for slot: String in q.equip:
		if q.equip[slot] == id:
			n += 1
	return n


## Everything in the haul into the pack, weight allowing; returns what would
## not fit as pickup records for the door.
static func unpack_haul(q: PlayerSim) -> Array[Dictionary]:
	var spill: Array[Dictionary] = []
	for i in range(q.haul.size()):
		var s := q.haul.at(i)
		if s.is_empty():
			continue
		var id := String(s.id)
		var n := int(s.n)
		var w := q.haul.wear_at(i)
		var got := 0
		if Items.stack_limit(id) <= 1:
			while got < n and Loot._give_item(q, id, Items.is_weapon(id), w):
				got += 1
		else:
			got = q.bag.add_capped(id, n, q.pack_allowance())
		if got < n:
			var d := Loot.entry_to_pickup(Loot.item_entry_id(id))
			spill.append({"kind": d.kind, "id": d.id, "n": n - got, "w": w})
	q.haul.clear_all()
	return spill


## A guest's copy of the run the host just started: the same interior from the
## same seed — the generator is deterministic — swapped into the mirror the way
## the host swapped its sim. Snapshots bring the crowd and put the players
## where the host has them; the world diff brings the doors and the tally.
static func mirror_enter(sim: GameSim, kind: String, seed: int, day: int) -> void:
	if sim.instance != null or not Config.INSTANCES.has(kind):
		return
	var inst := Instance.new()
	inst.kind = kind
	inst.def = Config.INSTANCES[kind]
	inst.run_seed = seed
	inst.mirror = true
	var f := door_for(sim, kind)
	inst.door = f.stand if not f.is_empty() else Vector2.ZERO
	inst.held = inst._interior(day)
	inst.swap(sim)
	sim.instance = inst
	var present := sim.present_players()
	for i in range(present.size()):
		present[i].pos = arrival(sim.world, i, present.size())
		present[i].prev_pos = present[i].pos
	sim.emit({"t": "instance_enter", "kind": kind})


## Back out, on a guest: the town mirror as it was, and what was cleared.
static func mirror_leave(sim: GameSim, cleared: Dictionary) -> void:
	var inst := sim.instance
	if inst == null:
		return
	inst.swap(sim)
	sim.instance = null
	for k in cleared:
		sim.cleared[String(k)] = int(cleared[k])
	for q in sim.players:
		if not q.away:
			q.pos = inst.door
			q.prev_pos = q.pos
	sim.emit({"t": "instance_leave", "kind": inst.kind, "outcome": ""})


## What a guest needs of the run that a snapshot does not carry: how it stands,
## the keys, which chained doors are open, the clock, and what that guest has
## found — which is what their way-out panel lists.
func record(sim: GameSim, seat: int) -> Dictionary:
	var opened: Array = []
	for f in sim.world.features:
		if String(f.kind) == "chained" and f.open:
			var t0: Vector2i = f.tiles[0]
			opened.append([t0.x, t0.y])
	return {"st": state, "keys": keys.keys(), "open": opened, "t": snappedf(t, 0.1),
		"g": gained.get(seat, {}).duplicate()}


func apply_record(sim: GameSim, rec: Dictionary, seat: int) -> void:
	state = String(rec.get("st", state))
	keys.clear()
	for k in rec.get("keys", []):
		keys[String(k)] = true
	t = float(rec.get("t", t))
	var mine := {}
	for k in rec.get("g", {}):
		mine[String(k)] = int(rec.g[k])
	gained[seat] = mine
	var opened := {}
	for o in rec.get("open", []):
		opened[Vector2i(int(o[0]), int(o[1]))] = true
	for f in sim.world.features:
		if String(f.kind) != "chained" or f.open or not opened.has(f.tiles[0]):
			continue
		# The mirror's own collision has to open too, or a guest predicting
		# its footsteps walks into a door the host has already unchained.
		f.open = true
		for tile: Vector2i in f.tiles:
			sim.world.blocked[tile.y * Config.WORLD_TILES + tile.x] = 0
		sim.world_version += 1


## What a save written now would say `p` has: walked out without the boss.
## Worked out on a copy, so writing the save changes nothing about the run.
func walked_out_record(p: PlayerSim) -> Dictionary:
	var ghost := PlayerSim.new()
	ghost.seat = p.seat
	ghost.bag.from_record(p.bag.to_record())
	ghost.hotbar.from_record(p.hotbar.to_record())
	ghost.haul.from_record(p.haul.to_record())
	ghost.equip = p.equip.duplicate()
	ghost.mag = p.mag.duplicate()
	var keep: Dictionary = gained.duplicate(true)
	forfeit(ghost)
	gained = keep
	unpack_haul(ghost)
	return {"x": door.x, "y": door.y, "bag": ghost.bag.to_record(), "hotbar": ghost.hotbar.to_record(),
		"equip": ghost.equip.duplicate(), "mag": ghost.mag.duplicate()}
