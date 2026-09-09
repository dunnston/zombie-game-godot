class_name Items
extends RefCounted
## One registry for everything that can sit in an inventory slot.
##
## Before this existed the player held resources, consumables and a list of
## weapon ids as separate collections, and nothing could be moved, dropped or
## looked at as a single list. A visual inventory needs one addressable list,
## so this flattens `RES`, `WEAPONS`, `GEAR` and `CONSUMABLES` into item
## definitions while leaving the plain id->count maps (the stash, a car boot)
## as the maps they already are — `map_add` and `map_take` serve those.

## id -> {id, name, kind, stack, wt, color, slot, def}. `kind` is what the
## inventory screen switches on: "res", "weapon", "gear" or "consumable".
static var _reg := {}


static func registry() -> Dictionary:
	if _reg.is_empty():
		_build()
	return _reg


static func _build() -> void:
	for id in Config.RES:
		var r: Dictionary = Config.RES[id]
		_reg[id] = {"id": id, "name": r.name, "kind": "res", "stack": r.stack,
			"wt": r.wt, "color": r.color, "slot": "", "def": r}
	for id in Config.WEAPONS:
		# Fists are not an object you carry.
		if id == "fists":
			continue
		var w: Dictionary = Config.WEAPONS[id]
		_reg[id] = {"id": id, "name": w.name, "kind": "weapon", "stack": 1,
			"wt": Config.WEAPON_WT, "color": w.color, "slot": "", "def": w}
	for id in Config.GEAR:
		var g: Dictionary = Config.GEAR[id]
		_reg[id] = {"id": id, "name": g.name, "kind": "gear", "stack": 1,
			"wt": g.wt, "color": g.color, "slot": g.slot, "def": g}
	for id in Config.CONSUMABLES:
		# The two globals are the default rather than the law: brain matter
		# stacks deeper and weighs less than a medkit, and saying so in the
		# item's own row beats a second table of exceptions.
		var c: Dictionary = Config.CONSUMABLES[id]
		_reg[id] = {"id": id, "name": c.name, "kind": "consumable",
			"stack": int(c.get("stack", Config.CONSUMABLE_STACK)),
			"wt": float(c.get("wt", Config.CONSUMABLE_WT)), "color": c.color, "slot": "", "def": c}


static func has(id: String) -> bool:
	return registry().has(id)


static func get_def(id: String) -> Dictionary:
	return registry().get(id, {})


static func name_of(id: String) -> String:
	var it := get_def(id)
	return it.name if not it.is_empty() else id


static func kind_of(id: String) -> String:
	var it := get_def(id)
	return it.kind if not it.is_empty() else ""


static func stack_limit(id: String) -> int:
	var it := get_def(id)
	return it.stack if not it.is_empty() else 1


static func weight_of(id: String) -> float:
	var it := get_def(id)
	return it.wt if not it.is_empty() else 0.0


static func color_of(id: String) -> String:
	var it := get_def(id)
	return it.color if not it.is_empty() else "#ebe6d6"


## The equipment slot a piece of gear belongs in, or "" if it is not gear.
static func gear_slot(id: String) -> String:
	var it := get_def(id)
	return it.slot if not it.is_empty() and it.kind == "gear" else ""


static func is_weapon(id: String) -> bool:
	return kind_of(id) == "weapon"


# ------------------------------------------------------------- plain maps --

## The stash, a car boot and a survivor's cargo are plain id -> count maps.
## These three keep that API in one place so a caller never has to know which
## kind of container it was handed.

static func map_count(map: Dictionary, id: String) -> int:
	return map.get(id, 0)


static func map_add(map: Dictionary, id: String, n: int) -> int:
	if n <= 0:
		return 0
	map[id] = map.get(id, 0) + n
	return n


static func map_take(map: Dictionary, id: String, n: int) -> int:
	var have: int = map.get(id, 0)
	var got := mini(have, n)
	if got > 0:
		map[id] = have - got
		if map[id] <= 0:
			map.erase(id)
	return got
