class_name Actions
extends RefCounted
## The one seam between the screens and anything that changes shared state.
##
## In solo and on the host, `Actions.craft(...)` is `Crafting.craft(...)` for
## the local player. On a guest it is a command to the host, who validates it
## with the same function — range, cost and room checks included — and
## executes it; the result comes back as an inventory or store diff. The pack
## screen, the character sheet and the roster call `Actions.*` and never care
## which.
##
## Building, searching, driving and reviving are not here: they are edges on
## the Intent, and a guest's intent already crosses the wire.

## Set by the scene while this machine is a guest. Null everywhere else.
static var guest: NetGuest = null


static func _remote(name_: String, args: Dictionary) -> bool:
	if guest == null:
		return false
	guest.send_cmd(name_, args)
	return true


static func craft(sim: GameSim, p: PlayerSim, recipe: Dictionary, bench: int) -> bool:
	if _remote("craft", {"id": String(recipe.id), "tier": bench}):
		return false
	return Crafting.craft(sim, p, recipe, bench)


## Mend a worn weapon at the bench that made it. The slot rather than the
## weapon id, for the reason `use_slot` names — a slot is what was clicked,
## and an id would let a guest mend something it is not carrying. The host
## re-derives the bench from where the player is actually standing, so a
## guest naming a tier it is nowhere near buys nothing.
static func repair_weapon(sim: GameSim, p: PlayerSim, cont_kind: String, index: int, bench: int) -> bool:
	if _remote("repair_weapon", {"c": cont_kind, "i": index, "tier": bench}):
		return false
	return Wear.repair(sim, p, cont_kind, index, bench)


## The bench menu's UPGRADE button. Named by tile like a chest, and the host
## re-derives the bench from where the player is standing: a guest naming a
## workbench across town upgrades nothing.
static func upgrade_bench(sim: GameSim, p: PlayerSim, at: Vector2i) -> bool:
	if _remote("upgrade_bench", {"tx": at.x, "ty": at.y}):
		return false
	var s := reachable_bench(sim, p, at)
	return not s.is_empty() and sim.structs.upgrade_bench(sim, s, p)


## ENTER on the panel an instance's door opened. The host checks the player is
## at that door, and that it would open: alone for now, and not chained for
## the day.
static func enter_instance(sim: GameSim, p: PlayerSim, kind: String) -> bool:
	if _remote("enter_instance", {"kind": kind}):
		return false
	return Instance.enter(sim, p, kind)


## LEAVE on the panel the way out opened: walking out early, which forfeits
## what was found. The host checks the player is at a way out.
static func leave_instance(sim: GameSim, p: PlayerSim) -> bool:
	if _remote("leave_instance", {}):
		return false
	return Instance.walk_out(sim, p)


## The workbench on a tile, if `p` is close enough to be using it.
static func reachable_bench(sim: GameSim, p: PlayerSim, at: Vector2i) -> Dictionary:
	var s := sim.structs.at_tile(at.x, at.y)
	if s.is_empty() or s.destroyed or s.type != "workbench":
		return {}
	var r: float = Config.BUILD.bench_range
	return s if p.pos.distance_squared_to(s.pos) <= r * r else {}


static func raise_attribute(sim: GameSim, p: PlayerSim, id: String) -> bool:
	if _remote("attr", {"id": id}):
		return false
	return Progression.raise_attribute(sim, p, id)


static func buy_perk(sim: GameSim, p: PlayerSim, id: String) -> bool:
	if _remote("perk", {"id": id}):
		return false
	return Progression.buy_perk(sim, p, id)


static func assign_job(sim: GameSim, s: SurvivorSim, job: String) -> bool:
	if _remote("job", {"id": s.id, "job": job}):
		return false
	return sim.crew.assign_job(sim, s, job)


## `at` names a chest by tile and `car` a boot by id; one or the other. The
## host resolves either itself and checks the reach.
static func deposit_all(sim: GameSim, p: PlayerSim, at: Vector2i, car: int) -> int:
	if _remote("deposit", {"tx": at.x, "ty": at.y, "car": car}):
		return 0
	return sim.structs.deposit_all(sim, p, store_for(sim, p, at, car))


static func withdraw_supplies(sim: GameSim, p: PlayerSim, at: Vector2i, car: int) -> int:
	if _remote("withdraw", {"tx": at.x, "ty": at.y, "car": car}):
		return 0
	return sim.structs.withdraw_supplies(sim, p, store_for(sim, p, at, car))


static func refuel(sim: GameSim, p: PlayerSim, car: int) -> bool:
	if _remote("refuel", {"car": car}):
		return false
	var v := sim.cars.by_id(car)
	return not v.is_empty() and sim.cars.refuel(sim, v, p)


## The four things you can do to a Raised Bed. Each names the bed by tile, the
## way a chest is named, so the host re-derives it from where the player is
## actually standing: a guest that could name any tile in the world would
## otherwise harvest the whole town from its bedroll.
static func plant(sim: GameSim, p: PlayerSim, at: Vector2i, seed_id: String) -> bool:
	if _remote("plant", {"tx": at.x, "ty": at.y, "id": seed_id}):
		return false
	return Farming.plant(sim, p, Farming.reachable_bed(sim, p, at.x, at.y), seed_id)


static func fertilize(sim: GameSim, p: PlayerSim, at: Vector2i, fert_id: String) -> bool:
	if _remote("fertilize", {"tx": at.x, "ty": at.y, "id": fert_id}):
		return false
	return Farming.fertilize(sim, p, Farming.reachable_bed(sim, p, at.x, at.y), fert_id)


static func water_bed(sim: GameSim, p: PlayerSim, at: Vector2i) -> bool:
	if _remote("water_bed", {"tx": at.x, "ty": at.y}):
		return false
	return Farming.water(sim, p, Farming.reachable_bed(sim, p, at.x, at.y))


static func harvest(sim: GameSim, p: PlayerSim, at: Vector2i) -> int:
	if _remote("harvest", {"tx": at.x, "ty": at.y}):
		return 0
	return Farming.harvest(sim, p, Farming.reachable_bed(sim, p, at.x, at.y))


static func equip_best(sim: GameSim, p: PlayerSim) -> int:
	if _remote("equip_best", {}):
		return 0
	return Equipment.equip_best(sim, p)


static func equip_from_bag(sim: GameSim, p: PlayerSim, index: int) -> bool:
	if _remote("equip", {"i": index}):
		return false
	return Equipment.equip_from_bag(sim, p, index)


static func unequip(sim: GameSim, p: PlayerSim, slot: String) -> bool:
	if _remote("unequip", {"slot": slot}):
		return false
	return Equipment.unequip(sim, p, slot)


static func unequip_to(sim: GameSim, p: PlayerSim, slot: String, cont_kind: String, index: int) -> bool:
	if _remote("unequip_to", {"slot": slot, "c": cont_kind, "i": index}):
		return false
	return Equipment.unequip_to(p, slot, cont_kind, index)


static func equip_from_slot(sim: GameSim, p: PlayerSim, cont_kind: String, index: int, slot: String) -> bool:
	if _remote("equip_from_slot", {"c": cont_kind, "i": index, "slot": slot}):
		return false
	return Equipment.equip_from_slot(p, cont_kind, index, slot)


static func move_stack(sim: GameSim, p: PlayerSim, from_cont: String, from_index: int, to_cont: String, to_index: int, at: Vector2i, car: int) -> bool:
	if _remote("move", {"fc": from_cont, "fi": from_index, "tc": to_cont, "ti": to_index, "tx": at.x, "ty": at.y, "car": car}):
		return false
	return Equipment.move_stack(sim, p, from_cont, from_index, to_cont, to_index, at, car)


static func split_stack(sim: GameSim, p: PlayerSim, cont_kind: String, from_index: int, to_index: int, at: Vector2i, car: int) -> bool:
	if _remote("split", {"c": cont_kind, "fi": from_index, "ti": to_index, "tx": at.x, "ty": at.y, "car": car}):
		return false
	var c := Equipment.container(p, cont_kind, store_for(sim, p, at, car))
	return c != null and c.split(from_index, to_index)


static func drop_stack(sim: GameSim, p: PlayerSim, cont_kind: String, index: int, all: bool, at: Vector2i, car: int) -> bool:
	if _remote("drop", {"c": cont_kind, "i": index, "all": all, "tx": at.x, "ty": at.y, "car": car}):
		return false
	return Equipment.drop_stack(sim, p, cont_kind, index, all, at, car)


## Use the thing in this slot: a bandage, a meal, a dose. The slot rather than
## the item id, because a slot is what was clicked and an id would let a guest
## consume something it is not carrying.
static func use_slot(sim: GameSim, p: PlayerSim, cont_kind: String, index: int) -> bool:
	if _remote("use_slot", {"c": cont_kind, "i": index}):
		return false
	var cont := Equipment.container(p, cont_kind, null)
	if cont == null:
		return false
	var id := cont.id_at(index)
	return false if id.is_empty() else p.start_use(sim, id)


static func drop_equipped(sim: GameSim, p: PlayerSim, slot: String) -> bool:
	if _remote("drop_eq", {"slot": slot}):
		return false
	return Equipment.drop_equipped(sim, p, slot)


## The container a tile or a car id names, if `p` is close enough to be
## using it, else null. One resolver for the screen and for the host.
static func store_for(sim: GameSim, p: PlayerSim, at: Vector2i, car: int) -> Slots:
	if car > 0:
		var v := sim.cars.by_id(car)
		if v.is_empty() or v.destroyed:
			return null
		var r: float = Config.CAR.enter_range
		return v.trunk if p.pos.distance_squared_to(v.pos) <= r * r else null
	if at.x < 0:
		return null
	return sim.structs.reachable_store(p, at.x, at.y)


# --------------------------------------------------------------- host side --

## Runs a guest's command as that guest. Every branch goes through the same
## function the screen would have called locally, so range, cost and room
## checks are the ones solo uses. Unknown or malformed commands do nothing.
static func execute(sim: GameSim, p: PlayerSim, name_: String, a: Dictionary) -> bool:
	if p == null or p.away or p.dead or p.downed:
		return false
	var at := Vector2i(int(a.get("tx", -1)), int(a.get("ty", -1)))
	var car := int(a.get("car", 0))
	match name_:
		"craft":
			var r := {}
			for rec in Config.RECIPES:
				if String(rec.id) == String(a.get("id", "")):
					r = rec
			if r.is_empty():
				return false
			return Crafting.craft(sim, p, r, mini(int(a.get("tier", 0)), Crafting.bench_tier_at(sim, p)))
		"repair_weapon":
			return Wear.repair(sim, p, String(a.get("c", "")), int(a.get("i", -1)),
				mini(int(a.get("tier", 0)), Crafting.bench_tier_at(sim, p)))
		"upgrade_bench":
			var bench := reachable_bench(sim, p, at)
			return not bench.is_empty() and sim.structs.upgrade_bench(sim, bench, p)
		"enter_instance":
			return Instance.enter(sim, p, String(a.get("kind", "")))
		"leave_instance":
			return Instance.walk_out(sim, p)
		"attr":
			return Progression.raise_attribute(sim, p, String(a.get("id", "")))
		"perk":
			return Progression.buy_perk(sim, p, String(a.get("id", "")))
		"job":
			for s in sim.crew.list:
				if s.id == int(a.get("id", -1)) and not s.dead:
					return sim.crew.assign_job(sim, s, String(a.get("job", "")))
			return false
		"deposit":
			var st := store_for(sim, p, at, car)
			return st != null and sim.structs.deposit_all(sim, p, st) > 0
		"withdraw":
			var st := store_for(sim, p, at, car)
			return st != null and sim.structs.withdraw_supplies(sim, p, st) > 0
		"refuel":
			var v := sim.cars.by_id(car)
			var r: float = Config.CAR.enter_range
			return not v.is_empty() and p.pos.distance_squared_to(v.pos) <= r * r and sim.cars.refuel(sim, v, p)
		"plant":
			return Farming.plant(sim, p, Farming.reachable_bed(sim, p, at.x, at.y), String(a.get("id", "")))
		"fertilize":
			return Farming.fertilize(sim, p, Farming.reachable_bed(sim, p, at.x, at.y), String(a.get("id", "")))
		"water_bed":
			return Farming.water(sim, p, Farming.reachable_bed(sim, p, at.x, at.y))
		"harvest":
			return Farming.harvest(sim, p, Farming.reachable_bed(sim, p, at.x, at.y)) > 0
		"equip_best":
			return Equipment.equip_best(sim, p) > 0
		"equip":
			return Equipment.equip_from_bag(sim, p, int(a.get("i", -1)))
		"unequip":
			return Equipment.unequip(sim, p, String(a.get("slot", "")))
		"unequip_to":
			return Equipment.unequip_to(p, String(a.get("slot", "")), String(a.get("c", "")), int(a.get("i", -1)))
		"equip_from_slot":
			return Equipment.equip_from_slot(p, String(a.get("c", "")), int(a.get("i", -1)), String(a.get("slot", "")))
		"move":
			return Equipment.move_stack(sim, p, String(a.get("fc", "")), int(a.get("fi", -1)),
				String(a.get("tc", "")), int(a.get("ti", -1)), at, car)
		"split":
			var c := Equipment.container(p, String(a.get("c", "")), store_for(sim, p, at, car))
			return c != null and c.split(int(a.get("fi", -1)), int(a.get("ti", -1)))
		"drop":
			return Equipment.drop_stack(sim, p, String(a.get("c", "")), int(a.get("i", -1)), bool(a.get("all", true)), at, car)
		"drop_eq":
			return Equipment.drop_equipped(sim, p, String(a.get("slot", "")))
		"use_slot":
			var cont := Equipment.container(p, String(a.get("c", "")), null)
			if cont == null:
				return false
			var id := cont.id_at(int(a.get("i", -1)))
			return false if id.is_empty() else p.start_use(sim, id)
	return false
