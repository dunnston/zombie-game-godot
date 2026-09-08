class_name Crafting
extends RefCounted
## Crafting. Instant by design: the materials are the whole cost.
##
## The one rule worth stating twice: the room check has to name the *same*
## container the craft will actually use, or the cost is spent and the output
## lands on the floor. Weapons prefer the hotbar and fall back to the pack;
## gear only ever goes to the pack; stacks go to the pack and overflow to the
## stash, then the ground.


## The bench a player standing here has access to: 0 by hand, 1 beside a
## workbench, 2 beside an upgraded one.
static func bench_tier_at(sim: GameSim, p: PlayerSim) -> int:
	var bench := sim.structs.near_workbench(p.pos)
	return 0 if bench.is_empty() else int(bench.tier)


## Whether the player is carrying a tool with the given flag ("knife",
## "hammer"). Carried, not held: you do not have to swap to it.
static func has_tool(p: PlayerSim, flag: String) -> bool:
	for cont in [p.hotbar, p.bag]:
		for i in range(cont.size()):
			var w: Dictionary = Config.WEAPONS.get(cont.id_at(i), {})
			if w.get(flag, false):
				return true
	return false


## The recipes worth showing at this bench. A Stone Hammer in the pack shows
## the simple bench-1 work too, so the tool advertises what it is for instead
## of the list silently growing when you happen to look.
static func visible_recipes(p: PlayerSim, bench: int) -> Array:
	var hammer := has_tool(p, "hammer")
	var out: Array = []
	for r in Config.RECIPES:
		if r.bench <= bench or (r.get("hammer", false) and hammer and r.bench <= 1):
			out.append(r)
	return out


## Why a recipe cannot be made right now, in the order a player meets it.
static func status(sim: GameSim, p: PlayerSim, r: Dictionary, bench: int) -> Dictionary:
	# A Stone Hammer is a workbench for simple work — what you could
	# plausibly do on a flat rock. It never reaches Workbench II and it never
	# unlocks a gun, because no `hammer` recipe is above bench 1.
	var effective := maxi(bench, 1) if r.get("hammer", false) and has_tool(p, "hammer") else bench
	if r.bench > effective:
		return {"ok": false, "reason": "Needs a Workbench" if r.bench == 1 else "Needs Workbench II"}
	if r.has("tool") and not has_tool(p, r.tool):
		return {"ok": false, "reason": "Needs a %s" % Config.WEAPONS[r.tool].name}
	# Duplicates are allowed: gear and guns are ordinary items you can carry,
	# drop, stash or hand to the next respawn. What limits you is space — and
	# space means weight as well as slots, or standing at the cap beside a
	# full stash would let you craft a rifle you cannot lift.
	if r.give.has("weapon"):
		if p.bag.first_empty() < 0 and p.hotbar.first_empty() < 0:
			return {"ok": false, "reason": "No room for it"}
		if not _can_lift(p, r.give.weapon):
			return {"ok": false, "reason": "Too heavy to carry"}
	if r.give.has("gear"):
		if p.bag.first_empty() < 0:
			return {"ok": false, "reason": "No room in your pack"}
		if not _can_lift(p, r.give.gear):
			return {"ok": false, "reason": "Too heavy to carry"}
	if r.give.has("item") and not _room_for(p, r.give.item, r.give.n):
		return {"ok": false, "reason": "No room in your pack"}
	if not p.can_afford(sim, r.cost):
		return {"ok": false, "reason": "Missing materials"}
	return {"ok": true, "reason": ""}


## Whether one more of `id` fits inside the carry cap. Weapons and gear go
## into a slot rather than a stack, so they never meet `add_capped` and have
## to be weighed here.
static func _can_lift(p: PlayerSim, id: String) -> bool:
	return p.carried_weight() + Items.weight_of(id) <= p.carry_cap + 1e-9


## Whether the pack can take `n` of `id`, by slot space and by weight.
static func _room_for(p: PlayerSim, id: String, n: int) -> bool:
	if p.bag.room_for(id) < n:
		return false
	return p.pack_allowance() - p.bag.weight() >= Items.weight_of(id) * n - 1e-9


static func craft(sim: GameSim, p: PlayerSim, r: Dictionary, bench: int) -> bool:
	var st := status(sim, p, r, bench)
	if not st.ok:
		sim.notify(st.reason, "#c96a5a")
		return false
	p.spend(sim, r.cost)

	# Belt and braces behind the checks above: whatever will not go in lands
	# at the player's feet. The cost is already spent by this point, so the
	# one outcome that must be impossible is the output disappearing.
	var label: String = r.name
	if r.give.has("weapon"):
		var wid: String = r.give.weapon
		var w: Dictionary = Config.WEAPONS[wid]
		var placed := p.hotbar.add(wid, 1) > 0 if p.hotbar.first_empty() >= 0 else p.bag.add(wid, 1) > 0
		if not placed:
			_on_the_ground(sim, p, Loot.item_entry_id(wid), 1)
		if not p.mag.has(wid):
			p.mag[wid] = w.get("mag", 0)
		label = "%s crafted" % w.name
	elif r.give.has("gear"):
		var gid: String = r.give.gear
		if p.bag.add(gid, 1) == 0:
			_on_the_ground(sim, p, "gear:" + gid, 1)
		label = "%s crafted — equip it from your pack (Tab)" % Config.GEAR[gid].name
	elif r.give.has("item"):
		var iid: String = r.give.item
		var want: int = r.give.n
		var got := p.bag.add_capped(iid, want, p.pack_allowance())
		if got < want:
			_on_the_ground(sim, p, "item:" + iid, want - got)
		label = "%s x%d" % [Config.CONSUMABLES[iid].name, want]
	elif r.give.has("res"):
		for id in r.give.res:
			var want: int = r.give.res[id]
			var got := p.bag.add_capped(id, want, p.pack_allowance())
			if got < want:
				# Overflow goes to the stash first — it is the base's pile,
				# and you are standing at the bench — and to the ground after.
				Loot.stash_or_drop(sim, id, want - got, p.pos)
				sim.notify("Pack full — the rest went to your stash", "#d9c46a")

	sim.stats.crafted = sim.stats.get("crafted", 0) + 1
	p.xp += r.xp
	sim.threat.add(sim, Config.THREAT.per_craft, p)
	sim.emit({"t": "crafted", "x": p.pos.x, "y": p.pos.y, "text": label})
	sim.notify(label, "#b7e08a")
	return true


static func _on_the_ground(sim: GameSim, p: PlayerSim, entry: String, n: int) -> void:
	Loot.spawn_entry_pickup(sim, p.pos, entry, n)
	sim.notify("No room — it is on the ground at your feet", "#d9c46a")
