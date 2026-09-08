class_name Equipment
extends RefCounted
## What is worn, and every move the inventory screen can make.
##
## Kept out of PlayerSim so there is one obvious place the UI calls into, and
## so every path that changes what is worn ends in `recompute_stats()` —
## invariant 4: that is the only function that writes a stat modifier.


## The only source of derived player stats.
##
## Phase 3 produces one of them: damage reduction from what is worn, capped so
## no amount of scavenging makes you immune. Phase 4 grows this into the full
## build — attributes and perks feed the same function, and nothing else is
## ever allowed to write these fields.
static func recompute_stats(p: PlayerSim) -> void:
	var dr := 0.0
	for slot in Config.ARMOR_SLOTS:
		var id: String = p.equip.get(slot, "")
		if not id.is_empty() and Config.GEAR.has(id):
			dr += float(Config.GEAR[id].dr)
	p.armor_dr = minf(dr, Config.MAX_GEAR_DR)


## Reconciles the off-hand after anything changes what is worn, then rebuilds
## the stats. Every mutator here ends with this, so there is exactly one place
## the light can fall out of step with the slot.
##
## A light's charge lives on the player, not in the slot, because a slot is
## only `{id, n}`. It is kept **per light id** in `light_charge`, so a torch
## you put down half burned comes back half burned — swapping to a
## flashlight and back is not a way to refill it.
static func after_equip_change(p: PlayerSim) -> void:
	var id: String = p.equip.get("offhand", "")
	var g: Dictionary = Config.GEAR.get(id, {})
	if g.is_empty() or not g.has("light"):
		# Nothing lit. Bank what the last light had left, so picking it back
		# up resumes rather than restarts.
		if not p.light_id.is_empty():
			p.light_charge[p.light_id] = p.light_fuel
		p.light_on = false
	elif p.light_id != id:
		if not p.light_id.is_empty():
			p.light_charge[p.light_id] = p.light_fuel
		p.light_id = id
		# A torch comes ready to burn the first time. A flashlight arrives
		# flat, so finding one is not the same as having light — you still
		# need a battery.
		p.light_fuel = p.light_charge.get(id, 0.0 if g.has("battery") else float(g.burn))
		p.light_on = false
	p.lit = p.light_on
	recompute_stats(p)


static func equipped_light(p: PlayerSim) -> Dictionary:
	var g: Dictionary = Config.GEAR.get(p.equip.get("offhand", ""), {})
	return g if g.has("light") else {}


# ---------------------------------------------------------------- equipping --

## Wears the item in bag slot `index`. Anything already in that equipment slot
## goes back to the pack — swapping a helmet never destroys the old one.
static func equip_from_bag(sim: GameSim, p: PlayerSim, index: int) -> bool:
	var stack := p.bag.at(index)
	if stack.is_empty():
		return false
	var slot := Items.gear_slot(stack.id)
	if slot.is_empty():
		return false
	var previous: String = p.equip.get(slot, "")
	p.equip[slot] = stack.id
	# Gear never stacks, so the slot is emptied outright.
	p.bag.slots[index] = {"id": previous, "n": 1} if not previous.is_empty() else {}
	after_equip_change(p)
	if sim != null:
		sim.notify("%s equipped" % Config.GEAR[stack.id].name, "#b7e08a")
	return true


## Takes a piece off. Fails if there is nowhere to put it.
static func unequip(sim: GameSim, p: PlayerSim, slot: String) -> bool:
	var id: String = p.equip.get(slot, "")
	if id.is_empty():
		return false
	if p.bag.first_empty() < 0:
		if sim != null:
			sim.notify("No room in your pack", "#c96a5a")
		return false
	p.equip[slot] = ""
	p.bag.add(id, 1)
	after_equip_change(p)
	return true


## Drag from a body slot onto a pack or hotbar cell: takes the piece off into
## that cell, swapping only with a piece for the same slot. A helmet cannot
## land on a stack of nails.
static func unequip_to(p: PlayerSim, slot: String, cont_kind: String, index: int) -> bool:
	var id: String = p.equip.get(slot, "")
	if id.is_empty():
		return false
	var cont := container(p, cont_kind)
	if cont == null or index < 0 or index >= cont.size():
		return false
	var target := cont.at(index)
	if not target.is_empty():
		var g: Dictionary = Config.GEAR.get(target.id, {})
		if g.is_empty() or g.slot != slot or target.n != 1:
			return false
		p.equip[slot] = target.id
	else:
		p.equip[slot] = ""
	cont.slots[index] = {"id": id, "n": 1}
	after_equip_change(p)
	return true


## Drag from a pack or hotbar cell onto a body slot.
static func equip_from_slot(p: PlayerSim, cont_kind: String, index: int, slot: String) -> bool:
	var cont := container(p, cont_kind)
	if cont == null:
		return false
	var s := cont.at(index)
	if s.is_empty():
		return false
	var g: Dictionary = Config.GEAR.get(s.id, {})
	if g.is_empty() or g.slot != slot:
		return false
	var previous: String = p.equip.get(slot, "")
	p.equip[slot] = s.id
	cont.slots[index] = {"id": previous, "n": 1} if not previous.is_empty() else {}
	after_equip_change(p)
	return true


## Wears the best thing carried for every armour slot — the quick-equip
## button. Armour only: choosing between a torch and a flashlight is a
## decision about how loud and how long you want to be lit, not one a button
## can make for you.
static func equip_best(sim: GameSim, p: PlayerSim) -> int:
	var changed := 0
	for slot in Config.ARMOR_SLOTS:
		var worn: String = p.equip.get(slot, "")
		var best_dr: float = float(Config.GEAR[worn].dr) if not worn.is_empty() else -1.0
		var best_index := -1
		for i in range(p.bag.size()):
			var s := p.bag.at(i)
			if s.is_empty():
				continue
			var g: Dictionary = Config.GEAR.get(s.id, {})
			if g.is_empty() or g.slot != slot:
				continue
			if g.dr > best_dr:
				best_dr = g.dr
				best_index = i
		if best_index >= 0 and equip_from_bag(sim, p, best_index):
			changed += 1
	if changed == 0 and sim != null:
		sim.notify("Nothing better to wear", "#8a8f84")
	return changed


# -------------------------------------------------------------------- moves --

static func container(p: PlayerSim, name: String, store: Slots = null) -> Slots:
	match name:
		"bag": return p.bag
		"hotbar": return p.hotbar
		"store": return store
	return null


## Moves or merges between any two containers this player can reach.
##
## `at` names WHICH chest, rather than the screen passing the container
## itself: the host resolves the structure and checks the player is standing
## beside it, instead of trusting a panel it cannot see. That is also what a
## guest's move will carry.
static func move_stack(sim: GameSim, p: PlayerSim, from_cont: String, from_index: int, to_cont: String, to_index: int, at := Vector2i(-1, -1)) -> bool:
	var store: Slots = null
	if at.x >= 0 and sim != null:
		store = sim.structs.reachable_store(p, at.x, at.y)
	if (from_cont == "store" or to_cont == "store") and store == null:
		return false
	var from := container(p, from_cont, store)
	var to := container(p, to_cont, store)
	if from == null or to == null:
		return false
	return from.move(from_index, to_index) if from == to else from.move(from_index, to_index, to)


static func split_stack(p: PlayerSim, cont_kind: String, from_index: int, to_index: int) -> bool:
	var c := container(p, cont_kind)
	return c != null and c.split(from_index, to_index)


## Drops a stack at the player's feet, where it can be picked back up.
## `at` names a chest, so ctrl+click on a container slot drops on the ground
## rather than silently doing nothing.
static func drop_stack(sim: GameSim, p: PlayerSim, cont_kind: String, index: int, all := true, at := Vector2i(-1, -1)) -> bool:
	var store: Slots = null
	if at.x >= 0 and sim != null:
		store = sim.structs.reachable_store(p, at.x, at.y)
	if cont_kind == "store" and store == null:
		return false
	var c := container(p, cont_kind, store)
	if c == null:
		return false
	var s := c.at(index)
	if s.is_empty():
		return false
	var id: String = s.id
	var n: int = s.n if all else 1
	# Out of *this* slot, not out of the first stack that happens to hold the
	# same thing: `take(id, n)` would empty an unrelated pile across the grid
	# and leave the cell you clicked still full.
	s.n -= n
	if s.n <= 0:
		c.slots[index] = {}
	var d := Loot.entry_to_pickup(Loot.item_entry_id(id))
	Loot.spawn_pickup(sim, p.pos, d.kind, d.id, n, p)
	sim.notify("Dropped %d %s" % [n, Items.name_of(id)], "#8a8f84")
	return true


## Drops a worn piece straight on the ground, without needing pack room.
static func drop_equipped(sim: GameSim, p: PlayerSim, slot: String) -> bool:
	var id: String = p.equip.get(slot, "")
	if id.is_empty():
		return false
	p.equip[slot] = ""
	after_equip_change(p)
	Loot.spawn_pickup(sim, p.pos, "gear", id, 1, p)
	return true


# -------------------------------------------------------------------- light --

## Strike it or douse it. A flat flashlight spends a battery from the pack
## first, then the stash — running out mid-street should send you home rather
## than end the night.
static func toggle_light(sim: GameSim, p: PlayerSim) -> bool:
	var g := equipped_light(p)
	if g.is_empty():
		sim.notify("Nothing in your off-hand — craft a Torch from sticks and fiber", "#d9c46a")
		return false
	if p.light_on:
		p.light_on = false
		p.lit = false
		return true
	if p.light_fuel <= 0.0:
		if not g.has("battery"):
			return false                      # a spent torch is gone already
		var got := p.bag.take(g.battery, 1)
		if got == 0 and sim.stash != null:
			got = sim.stash.take(g.battery, 1)
		if got == 0:
			sim.notify("%s is flat — it needs a battery" % g.name, "#c96a5a")
			return false
		p.light_fuel = g.burn
		sim.notify("Fresh battery", "#b7e08a")
	p.light_on = true
	p.lit = true
	return true


static func update_light(sim: GameSim, p: PlayerSim, dt: float) -> void:
	if not p.light_on:
		p.lit = false
		return
	var g := equipped_light(p)
	if g.is_empty():
		p.light_on = false
		p.lit = false
		return
	p.light_fuel = maxf(0.0, p.light_fuel - dt)
	p.lit = true
	if p.light_fuel > 0.0:
		return
	p.light_on = false
	p.lit = false
	if g.get("consumed", false):
		# A torch burns itself up. That is the cost of having had light, and
		# another is three sticks and three fiber. Its banked charge goes with
		# it, so the next torch is a fresh one.
		p.equip["offhand"] = ""
		p.light_charge.erase(p.light_id)
		p.light_id = ""
		after_equip_change(p)
		sim.notify("Your torch burns out", "#c96a5a")
	else:
		sim.notify("%s is dead — load a battery" % g.name, "#c96a5a")
