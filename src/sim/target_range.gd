class_name TargetRange
extends RefCounted
## The Target Range (`tasks/target-range.md`, Notion DL-109): a developer's
## instance for testing every weapon — its sound, what it deals and what the
## things it is pointed at deal back.
##
## It is an `Instance` like the School, so the map swap, the frozen town, the
## co-op mirror and "nothing is saved in here" are all the School's. What is
## its own, and lives here:
## - it is reached from the F1 menu, never from the town, and only in a
##   developer's build (`Actions.dev`);
## - you go in empty-handed on a baseline build — level 1, no perks, the
##   Mutation meter clear — so two testers read the same numbers, and
##   everything you had, build and pack alike, is held until you leave;
## - its lockers hold every weapon at level 1, every ammunition, every piece
##   of gear and every consumable, and a restock puts them all back;
## - dying keeps you in here: you get up at the entrance with what you had;
## - leaving gives you back exactly what you walked in with, at the spot a new
##   game starts, and nothing from in here comes out.

## What is held while you are in here, per seat. The keys are the save's own
## (`SaveGame._town_dict`), so a save written from inside merges it straight
## over the player: nobody is ever written down on a baseline build.
const HELD_KEYS := ["xp", "level", "xp_next", "skill_points", "attrs", "perks", "second_wind_cd", "pack_tier",
	"mutation", "effects", "slot", "bag", "hotbar", "equip", "mag", "hp", "stam",
	"light_on", "light_fuel", "light_id", "light_doused", "light_charge"]


static func is_range(sim: GameSim) -> bool:
	return sim.instance != null and sim.instance.kind == "range"


# ------------------------------------------------------------- the build --

## Everything about `p` the range sets aside, in the save's own keys.
static func hold(p: PlayerSim) -> Dictionary:
	return {
		"xp": p.xp, "level": p.level, "xp_next": p.xp_next, "skill_points": p.skill_points,
		"attrs": p.attrs.duplicate(), "perks": p.perks.duplicate(), "second_wind_cd": p.second_wind_cd,
		"pack_tier": p.pack_tier,
		"mutation": p.mutation, "effects": p.effects.duplicate(),
		"slot": p.slot, "bag": p.bag.to_record(), "hotbar": p.hotbar.to_record(),
		"equip": p.equip.duplicate(), "mag": p.mag.duplicate(), "hp": p.hp, "stam": p.stam,
		"light_on": p.light_on, "light_fuel": p.light_fuel, "light_id": p.light_id,
		"light_doused": p.light_doused, "light_charge": p.light_charge.duplicate(),
	}


## Puts back what `hold` set aside. Written the way a save is read back
## (`SaveGame.apply`): the meter is set and its band derived before the one
## recompute, which is the exception invariant 9 already makes for loading —
## this is not the meter moving, it is a character being put back as it was.
static func give_back(p: PlayerSim, rec: Dictionary) -> void:
	p.xp = float(rec.xp)
	p.level = int(rec.level)
	p.xp_next = int(rec.xp_next)
	p.skill_points = int(rec.skill_points)
	p.attrs = (rec.attrs as Dictionary).duplicate()
	p.perks = (rec.perks as Dictionary).duplicate()
	p.second_wind_cd = float(rec.second_wind_cd)
	p.pack_tier = int(rec.get("pack_tier", 0))
	p.mutation = float(rec.mutation)
	p.mut_band = Mutation.band_index(p.mutation)
	p.effects = (rec.effects as Dictionary).duplicate()
	p.bag.from_record(rec.bag)
	p.hotbar.from_record(rec.hotbar)
	p.equip = (rec.equip as Dictionary).duplicate()
	p.mag = (rec.mag as Dictionary).duplicate()
	p.slot = clampi(int(rec.slot), 0, maxi(0, p.hotbar.size() - 1))
	p.light_id = String(rec.light_id)
	p.light_fuel = float(rec.light_fuel)
	p.light_charge = (rec.light_charge as Dictionary).duplicate()
	p.light_on = bool(rec.light_on)
	p.lit = p.light_on
	p.light_doused = bool(rec.light_doused)
	Equipment.recompute_stats(p)
	# After the recompute: the ceiling has to exist before what stands under it.
	p.hp = minf(float(rec.hp), p.max_hp)
	Stamina.restore(p, float(rec.stam))


## The baseline every tester reads the same numbers on: a new survivor's
## build, nothing carried and nothing worn, the meter clear, at full health.
static func baseline(p: PlayerSim) -> void:
	p.xp = 0.0
	p.level = 1
	p.xp_next = Config.xp_for_level(1)
	p.skill_points = 0
	p.attrs = Perks.starting_attrs()
	p.perks = {}
	# The pack is the build too (step D): a Pack Frame fitted in the range
	# must not leave with you (Codex, PR #66).
	p.pack_tier = 0
	p.mutation = 0.0
	p.mut_band = Mutation.band_index(0.0)
	p.effects = {}
	p.bag.clear_all()
	p.hotbar.clear_all()
	p.haul.clear_all()
	for k: String in p.equip:
		p.equip[k] = ""
	p.mag = {}
	p.slot = 0
	p.light_on = false
	p.lit = false
	p.light_id = ""
	p.light_fuel = 0.0
	Equipment.after_equip_change(p)
	p.hp = p.max_hp
	Stamina.refill(p)


# ------------------------------------------------------------ in and out --

## F1's "Walk into the Target Range": everyone here goes in together, from
## wherever they are standing. False, with the reason said, when it will not.
static func enter(sim: GameSim, p: PlayerSim) -> bool:
	var why := refusal(sim)
	if not why.is_empty():
		sim.notify(why, "#c96a5a")
		return false
	var inst := Instance.begin(sim, "range", main_spawn(sim))
	for q in sim.present_players():
		inst.range_held[q.seat] = hold(q)
		baseline(q)
	furnish(sim)
	restock(sim)
	sim.notify("TARGET RANGE — your own things wait outside. Leave by the door or from F1", "#d8c98a", true)
	return true


## Why the party cannot go in, or "". Nobody driving (entering swaps the
## town's cars out from under a driver), and nobody on the floor.
static func refusal(sim: GameSim) -> String:
	if sim.instance != null:
		return "You are already inside %s" % Instance.title(sim.instance.kind)
	for q in sim.present_players():
		if q.dead or q.downed:
			return "%s has to be on their feet to go in" % q.display_name
		if q.driving_id > 0:
			return "%s has to get out of the car first" % q.display_name
	return ""


## Out, everyone who went in: what they walked in with back, at the spot a
## new game starts. Called at the end of a step (`Instance.tick`), never from
## the middle of a player's.
static func leave(sim: GameSim) -> void:
	var inst := sim.instance
	var everyone := inst._members(sim)
	inst.swap(sim)
	sim.instance = null
	for i in range(everyone.size()):
		var q := everyone[i]
		q.dead = false
		q.downed = false
		q.down_t = 0.0
		q.respawn_t = 0.0
		if inst.range_held.has(q.seat):
			give_back(q, inst.range_held[q.seat])
		Instance._arrive(q, arrival(sim, inst.door, i, everyone.size()))
	sim.notify("Out of the range — everything you took in is back with you", "#d8c98a", true)
	sim.emit({"t": "instance_leave", "kind": inst.kind, "outcome": "left"})


## Where the party comes out: the spot a new game starts, by the Roadside
## Camp. Worked out, not rolled, so a guest's mirror puts it in the same place.
static func main_spawn(sim: GameSim) -> Vector2:
	var camp: Rect2i = sim.world.locations[0].rect
	var centre := Vector2(camp.position.x + camp.size.x / 2.0, camp.position.y + camp.size.y / 2.0) * Config.TILE
	return sim.world.unstick(centre, float(Config.PLAYER.r), sim.structs)


## Side by side, a body's width apart, as the School's foyer does it.
static func arrival(sim: GameSim, at: Vector2, i: int, n: int) -> Vector2:
	var spot := at + Vector2((i - (n - 1) / 2.0) * 30.0, 0.0)
	return sim.world.unstick(spot, float(Config.PLAYER.r), sim.structs)


## Why the party cannot walk out yet, or "": it takes everybody, so everyone
## standing has to be with whoever asked — the School's rule.
static func leave_refusal(sim: GameSim, p: PlayerSim) -> String:
	return Instance.leave_refusal(sim, p)


# --------------------------------------------------------------- lockers --

## The lockers, on the tiles the layout names. Built on the host and on a
## guest's mirror alike — same tiles, same sizes — so a store sent by tile
## lands in the same locker on both.
static func furnish(sim: GameSim) -> void:
	var kits := stock_lists()
	for i in range(mini(kits.size(), sim.world.range_lockers.size())):
		var t: Vector2i = sim.world.range_lockers[i]
		var s := sim.structs.make(sim, "locker", t.x, t.y)
		s.store = Slots.new(maxi(int(s.def.store), (kits[i] as Array).size()))


## Every locker full again, exactly as it was stocked.
static func restock(sim: GameSim) -> void:
	var kits := stock_lists()
	for i in range(mini(kits.size(), sim.world.range_lockers.size())):
		var t: Vector2i = sim.world.range_lockers[i]
		var s := sim.structs.at_tile(t.x, t.y)
		if s.is_empty() or s.store == null:
			continue
		var store: Slots = s.store
		store.clear_all()
		for e: Array in kits[i]:
			store.add(String(e[0]), int(e[1]))


## What goes in each locker, in order, as [id, n] stacks — one entry per slot,
## so a locker's size is its list's length. Melee is two lockers (41 of them),
## ranged one; then ammunition, gear, and the consumables.
static func stock_lists() -> Array:
	var melee: Array = []
	var ranged: Array = []
	for id: String in _sorted(Config.WEAPONS.keys(), Config.WEAPONS):
		if id == "fists":
			continue
		if String(Config.WEAPONS[id].get("kind", "melee")) == "gun":
			ranged.append([id, 1])
		else:
			melee.append([id, 1])
	var half := ceili(melee.size() / 2.0)
	var ammo: Array = []
	for id: String in Config.AMMO_IDS:
		var stack := int(Items.registry()[id].stack)
		for i in range(int(Config.RANGE.ammo_stacks)):
			ammo.append([id, stack])
	var gear: Array = []
	for id: String in _sorted(Config.GEAR.keys(), Config.GEAR):
		gear.append([id, 1])
	var food: Array = []
	var n := int(Config.RANGE.consumable_n)
	for id: String in Config.CONSUMABLES:
		var stack := int(Items.registry()[id].stack)
		var left := n
		while left > 0:
			food.append([id, mini(stack, left)])
			left -= mini(stack, left)
	return [melee.slice(0, half), melee.slice(half), ranged, ammo, gear, food]


## By tier, then by name: a locker reads from the stone tools up.
static func _sorted(ids: Array, table: Dictionary) -> Array:
	var out := ids.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool:
		var ta := int(table[a].get("tier", 0))
		var tb := int(table[b].get("tier", 0))
		return ta < tb if ta != tb else String(table[a].name) < String(table[b].name))
	return out


# ---------------------------------------------------- targets and rooms --

## Every enemy type the range puts up, bosses left out (owner, 2026-09-29).
## Off the table, so a new type is in the range the day it exists.
static func types() -> Array[String]:
	var out: Array[String] = []
	for type: String in Config.ENEMIES:
		if not bool(Config.ENEMIES[type].get("boss", false)):
			out.append(type)
	return out


## The targets and the live rooms, as they are when you walk in.
static func populate(sim: GameSim) -> void:
	reset_targets(sim)
	refill_rooms(sim)


## Where the targets stand: a line across the far end of the lane, facing
## back down it, spread evenly from wall to wall.
static func target_line_x(world: World) -> float:
	return (world.range_lane.end.x - 2.5) * float(Config.TILE)


static func target_post(world: World, i: int, n: int) -> Vector2:
	var lane := world.range_lane
	var span := float(lane.size.y * Config.TILE)
	return Vector2(target_line_x(world), lane.position.y * float(Config.TILE) + span * (i + 0.5) / float(n))


## The floor a live room's enemies are held on: the room's inside, short of
## the row in front of its doorway, so nothing follows you out (in pixels).
static func leash_of(room: Rect2i) -> Rect2:
	var tile := float(Config.TILE)
	var inside := Rect2i(room.position + Vector2i.ONE, room.size - Vector2i(2, 3))
	return Rect2(Vector2(inside.position) * tile, Vector2(inside.size) * tile)


static func _spawn_target(sim: GameSim, type: String, at: Vector2) -> EnemySim:
	var e := sim.enemies.spawn(type, at)
	if e != null:
		e.passive = true
		e.post = at
		# Facing back down the lane, at whoever is shooting.
		e.angle = PI
	return e


## Every target back on its post at full health, and nothing waiting.
static func reset_targets(sim: GameSim) -> void:
	_remove(sim, true)
	sim.instance.range_respawn.clear()
	var list := types()
	for i in range(list.size()):
		_spawn_target(sim, list[i], target_post(sim.world, i, list.size()))


## Each live room emptied and filled again: one type to a room, in the
## order `types` gives, `Config.RANGE.room_count` of it, on its leash.
static func refill_rooms(sim: GameSim) -> void:
	_remove(sim, false)
	var list := types()
	var tile := float(Config.TILE)
	for i in range(mini(list.size(), sim.world.range_rooms.size())):
		var room: Rect2i = sim.world.range_rooms[i]
		var leash := leash_of(room)
		var n := int(Config.RANGE.room_count)
		for k in range(n):
			var at := Vector2(leash.position.x + leash.size.x * (k + 1) / float(n + 1), leash.position.y + 2.0 * tile)
			var e := sim.enemies.spawn(list[i], at)
			if e != null:
				e.leash = leash


## Takes the targets (or the live rooms' enemies) off the map outright:
## not killed, so nothing counts it as a death and no target is queued back.
static func _remove(sim: GameSim, targets: bool) -> void:
	var list := sim.enemies.list
	for i in range(list.size() - 1, -1, -1):
		if list[i].passive == targets:
			list.remove_at(i)


## A blow a player dealt in the range, for the damage panel: a `dealt` event
## carrying the seat, which the host sends only to that seat's guest, so each
## player's panel is their own hits. Bleed is summed and reported every
## `RANGE.bleed_report` seconds, or at once on the tick that kills.
static func note_dealt(sim: GameSim, e: EnemySim, dmg: float, source: Variant, crit: bool, kind: String) -> void:
	if not (source is PlayerSim):
		return
	var seat := (source as PlayerSim).seat
	if kind == "bleed":
		e.range_bleed += dmg
		e.range_bleed_seat = seat
		if e.hp <= 0.0:
			_report_bleed(sim, e)
		return
	_report(sim, e, seat, dmg, crit, kind)


static func _report(sim: GameSim, e: EnemySim, seat: int, dmg: float, crit: bool, kind: String) -> void:
	sim.emit({"t": "dealt", "seat": seat, "id": e.id, "type": e.type, "dmg": dmg, "hp": maxf(0.0, e.hp),
		"max": e.max_hp, "kind": kind, "crit": crit, "x": e.pos.x, "y": e.pos.y, "r": e.r})


static func _report_bleed(sim: GameSim, e: EnemySim) -> void:
	if e.range_bleed > 0.0:
		_report(sim, e, e.range_bleed_seat, e.range_bleed, false, "bleed")
	e.range_bleed = 0.0
	e.range_bleed_t = 0.0


## A target that went down is put back on its post `target_respawn` later.
## Called from `Instance.tick` before it culls the dead, so a target that
## fell this step is seen here exactly once.
static func tick(sim: GameSim, dt: float) -> void:
	var inst := sim.instance
	for e in sim.enemies.list:
		if e.range_bleed > 0.0 and not e.dead:
			e.range_bleed_t += dt
			if e.range_bleed_t >= float(Config.RANGE.bleed_report) or e.bleed_t <= 0.0:
				_report_bleed(sim, e)
		if e.dead and e.passive:
			inst.range_respawn.append({"type": e.type, "post": e.post, "t": float(Config.RANGE.target_respawn)})
	for i in range(inst.range_respawn.size() - 1, -1, -1):
		var r: Dictionary = inst.range_respawn[i]
		r.t = float(r.t) - dt
		if float(r.t) <= 0.0:
			inst.range_respawn.remove_at(i)
			_spawn_target(sim, String(r.type), r.post)


# -------------------------------------------------------------- controls --

## A range control, from F1 — on the host, or sent by a guest and run here by
## `Actions.execute` as that guest. Every one is refused outside the range
## except going in. Returns whether anything happened.
static func control(sim: GameSim, p: PlayerSim, verb: String, a := {}) -> bool:
	if verb == "enter":
		return enter(sim, p)
	if not is_range(sim):
		sim.notify("Only in the Target Range", "#8a8f84")
		return false
	var inst := sim.instance
	match verb:
		"leave":
			var why := leave_refusal(sim, p)
			if not why.is_empty():
				sim.notify(why, "#c96a5a")
				return false
			inst.leaving = "range"
			return true
		"restock":
			restock(sim)
			sim.notify("RANGE  lockers restocked", "#b7e08a")
			return true
		"wear":
			inst.range_wear = not inst.range_wear
			sim.notify("RANGE  weapon wear %s" % ("ON — uses are spent" if inst.range_wear else "OFF"), "#d9c46a", true)
			return true
		"level":
			return set_level(sim, p, int(a.get("d", 1)))
		"reset":
			reset_targets(sim)
			sim.notify("RANGE  targets reset", "#b7e08a")
			return true
		"refill":
			refill_rooms(sim)
			sim.notify("RANGE  live rooms refilled", "#b7e08a")
			return true
	return false


## The weapon in your hand a level up or down, 1 to `Config.UPGRADE.max`.
static func set_level(sim: GameSim, p: PlayerSim, d: int) -> bool:
	var id := p.held_id()
	if not Config.WEAPONS.has(id) or id == "fists":
		sim.notify("RANGE  hold a weapon to change its level", "#8a8f84")
		return false
	var lv := clampi(maxi(1, p.hotbar.level_at(p.slot)) + d, 1, int(Config.UPGRADE.max))
	p.hotbar.set_level_at(p.slot, lv)
	Equipment.recompute_stats(p)
	sim.notify("RANGE  %s is level %d" % [Config.WEAPONS[id].name, lv], "#d9c46a")
	return true
