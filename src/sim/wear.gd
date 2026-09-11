class_name Wear
extends RefCounted
## Weapons wear out, and the bench that made one is where it is mended.
##
## **Condition belongs to the weapon, not to the carrier.** It lives in the
## slot, as the optional `w` on a `Slots` stack, so it travels wherever the
## weapon travels: into a chest, into a car boot, onto the ground, into
## somebody else's pack. Anything else leaks — a broken weapon left in a
## chest would come back whole to the next person to open it, a fresh weapon
## would arrive already broken because the last one of its kind had been, and
## the free repair the death drop is careful to prevent would be one deposit
## away.
##
## This is deliberately *not* how `PlayerSim.mag` works, and the difference is
## the point: a magazine refills for free the moment you have ammunition, so
## it barely matters where the count is kept. Condition only comes back by
## paying materials at a bench, which makes who owns it the whole mechanic.
##
## `use` is the only thing that spends it — the same rule `Mutation.add`
## carries, and for the same reason: it is what makes a guest agree with the
## host about whether the axe in its hand still swings.

const W := Config.WEAR


## How many uses this weapon has when new, or 0 for something that never
## wears. Fists are the 0: they are not an object you carry.
static func max_of(id: String) -> int:
	return int(Config.WEAPONS.get(id, {}).get("dur", 0))


static func wears(id: String) -> bool:
	return max_of(id) > 0


## How many uses this particular weapon has when whole: the row's `dur`,
## raised by its level (`Upgrade`). Two Machetes at different levels last
## differently, which is why the ceiling is read off the stack.
static func max_in(stack: Dictionary) -> int:
	var id := String(stack.get("id", ""))
	return roundi(max_of(id) * Upgrade.dur_mul(Upgrade.level_in(stack)))


static func max_at(cont: Slots, i: int) -> int:
	return 0 if cont == null else max_in(cont.at(i))


## Uses left, read off a stack. An unset stack is a whole weapon, so nothing
## has to write a full value into a slot to say the obvious — which is also
## what makes a crafted or scavenged weapon arrive new without anyone
## arranging it.
##
## The stack is the core because the pack screen is handed one directly; the
## container forms below are the same question asked by slot.
static func left_in(stack: Dictionary) -> int:
	if stack.is_empty():
		return 0
	var id := String(stack.get("id", ""))
	if not wears(id):
		return 0
	var raw := int(stack.get("w", -1))
	return max_in(stack) if raw < 0 else clampi(raw, 0, max_in(stack))


static func broken_in(stack: Dictionary) -> bool:
	return wears(String(stack.get("id", ""))) and left_in(stack) <= 0


static func left(cont: Slots, i: int) -> int:
	return 0 if cont == null else left_in(cont.at(i))


## 0.0 to 1.0. Something that cannot wear reads as whole, so every caller can
## ask without checking `wears` first.
static func frac(cont: Slots, i: int) -> float:
	if cont == null or not wears(cont.id_at(i)):
		return 1.0
	return float(left(cont, i)) / float(max_at(cont, i))


static func is_broken(cont: Slots, i: int) -> bool:
	return cont != null and wears(cont.id_at(i)) and left(cont, i) <= 0


static func is_worn(cont: Slots, i: int) -> bool:
	if cont == null:
		return false
	var id := cont.id_at(i)
	return wears(id) and left(cont, i) < max_at(cont, i)


## Sets a slot back to new — new for its level.
static func mend(cont: Slots, i: int) -> void:
	if cont != null and wears(cont.id_at(i)):
		cont.set_wear_at(i, max_at(cont, i))


# ------------------------------------------------------------- what is held --

## Everything combat needs to know about the weapon in the player's hand. The
## held slot is `hotbar[slot]` and this is the only place that says so.

static func held_broken(p: PlayerSim) -> bool:
	return is_broken(p.hotbar, p.slot)


static func use_held(sim: GameSim, p: PlayerSim, n := 1) -> void:
	use(sim, p, p.hotbar, p.slot, n)


## Spend `n` uses of the weapon in a slot. The one writer.
##
## The warnings fire on the crossing rather than on the frame, so holding a
## trigger cannot spam them, and the weapon's numbers do not change on the
## way down: it swings exactly as well at 5% as at 100% and then it stops.
## A weapon that got quietly worse would be a chore you could not see, and
## pillar 1 is survival without those.
static func use(sim: GameSim, p: PlayerSim, cont: Slots, i: int, n := 1) -> void:
	if cont == null or n <= 0:
		return
	var id := cont.id_at(i)
	if not wears(id):
		return
	var before := left(cont, i)
	if before <= 0:
		return
	var after := maxi(0, before - n)
	var cap := max_at(cont, i)
	cont.set_wear_at(i, after)
	var name_: String = Config.WEAPONS[id].name
	if after <= 0:
		sim.notify("%s broke — it needs mending before it is any use" % name_, "#c96a5a", true)
		sim.emit({"t": "broke", "seat": p.seat, "x": p.pos.x, "y": p.pos.y, "w": id})
	elif _crossed(before, after, cap, W.spent_at):
		sim.notify("%s is nearly gone" % name_, "#c96a5a")
	elif _crossed(before, after, cap, W.worn_at):
		sim.notify("%s is wearing out" % name_, "#d9c46a")


## Whether this step took the bar down through `mark`. Both ends compared
## against the same threshold, so a single big step still reports once.
static func _crossed(before: int, after: int, cap: int, mark: float) -> bool:
	var at := mark * float(cap)
	return float(before) > at and float(after) <= at


# ----------------------------------------------------------------- repair --

## The recipe that makes this weapon, or empty. A found weapon has none, and
## that used to mean it could never be mended. It no longer does: every
## weapon can be found and every weapon can be repaired (owner, 2026-09-11),
## so a weapon with no recipe is mended off its `salvage` instead.
static func recipe_for(id: String) -> Dictionary:
	for r in Config.RECIPES:
		if String(r.get("give", {}).get("weapon", "")) == id:
			return r
	return {}


## What a weapon is worth in parts. A recipe if something makes it, else the
## row's `salvage` — what recycling it gives back. Every weapon has one or
## the other, and that is what lets every weapon be mended.
static func repair_basis(id: String) -> Dictionary:
	var r := recipe_for(id)
	if not r.is_empty():
		return r.cost
	return Config.WEAPONS.get(id, {}).get("salvage", {})


## The bench a mend asks for. A weapon with a recipe is mended where it was
## made. A found weapon has no recipe to ask, so its tier answers: the
## Workbench for the first two bands, its upgrade for the third.
static func mend_bench(id: String) -> int:
	var r := recipe_for(id)
	if not r.is_empty():
		return int(r.get("bench", 0))
	return 2 if int(Config.WEAPONS.get(id, {}).get("tier", 1)) >= 3 else 1


## What mending the weapon in a slot costs: a share of what it cost to make,
## scaled by how much of it is gone. The main material is always at least one,
## so no repair is ever free — the same shape, and the same reasoning, as
## `Structures.repair_cost`.
##
## Deliberately *not* scaled by `build_cost_mul`, which the structure version
## does take: that multiplier is the Engineer perk and the Intelligence
## ladder making the things you *construct* cheaper, and `Crafting.craft`
## already ignores it — a Machete costs 24 scrap at any Intelligence. Mending
## one for a share of a price the perk does not touch has to ignore it too,
## or a high-INT survivor would find repairing cheaper than crafting for a
## reason nothing in the game ever states.
static func repair_cost(cont: Slots, i: int) -> Dictionary:
	if cont == null or not is_worn(cont, i):
		return {}
	var basis := repair_basis(cont.id_at(i))
	if basis.is_empty():
		return {}
	var gone := 1.0 - frac(cont, i)
	var out := {}
	var main_id := ""
	var main_n := -1
	for cid in basis:
		var c: int = basis[cid]
		if c > main_n:
			main_n = c
			main_id = cid
		var n := roundi(c * gone * W.repair_cost_share)
		if n > 0:
			out[cid] = n
	if not main_id.is_empty() and not out.has(main_id):
		out[main_id] = 1
	return out


## The container a repair may name. The pack and the hotbar and nothing else:
## a bench mends what you brought to it, not what is still in the chest, and
## on a guest this is what stops a slot index naming somebody else's locker.
static func container_for(p: PlayerSim, cont_kind: String) -> Slots:
	match cont_kind:
		"bag": return p.bag
		"hotbar": return p.hotbar
	return null


## Why the weapon in this slot cannot be mended where the player stands, in
## the order they meet it. The bench gate is the recipe's own — "the same
## bench it was made at" is literally `Crafting.bench_reason` asked about the
## same row.
static func repair_status(sim: GameSim, p: PlayerSim, cont_kind: String, i: int, bench: int) -> Dictionary:
	var cont := container_for(p, cont_kind)
	if cont == null:
		return {"ok": false, "reason": "Not something you are carrying"}
	var id := cont.id_at(i)
	if not wears(id):
		return {"ok": false, "reason": "Nothing to mend"}
	if not is_worn(cont, i):
		return {"ok": false, "reason": "Not worn"}
	var r := recipe_for(id)
	if r.is_empty():
		# Found, so there is no recipe to ask about a bench or a tool.
		if repair_basis(id).is_empty():
			return {"ok": false, "reason": "Nothing here can mend it"}
		var need := mend_bench(id)
		if bench < need:
			return {"ok": false, "reason": "Needs a Workbench" if need == 1 else "Needs Workbench II"}
	else:
		var why := Crafting.bench_reason(sim, p, r, bench)
		if not why.is_empty():
			return {"ok": false, "reason": why}
	if not p.can_afford(sim, repair_cost(cont, i)):
		return {"ok": false, "reason": "Missing materials"}
	return {"ok": true, "reason": ""}


## Mend one weapon at the bench that makes it. Called through `Actions`, so
## on a guest this same function runs on the host with the same gates.
##
## The slot rather than the weapon id, for the reason `use_slot` names: a slot
## is what was clicked, and an id would let a guest mend something it is not
## holding — and now that two Machetes can be worn differently, an id would
## not even say which one.
static func repair(sim: GameSim, p: PlayerSim, cont_kind: String, i: int, bench: int) -> bool:
	var st := repair_status(sim, p, cont_kind, i, bench)
	if not st.ok:
		sim.notify(st.reason, "#c96a5a")
		return false
	var cont := container_for(p, cont_kind)
	var cost := repair_cost(cont, i)
	p.spend(sim, cost)
	mend(cont, i)
	var label := "%s mended — %s" % [Config.WEAPONS[cont.id_at(i)].name, Structures.cost_label(cost)]
	Progression.add_xp(sim, p, 3, "REPAIR")
	sim.emit({"t": "crafted", "x": p.pos.x, "y": p.pos.y, "text": label})
	sim.notify(label, "#7ce08a")
	return true


## Every worn weapon the player is carrying, as `{c, i, id}` — the container
## it is in, the slot, and what it is. Two Machetes worn differently are two
## rows now, which is the point of keeping condition on the object.
##
## The craft screen lists these above the recipes; a row that cannot be
## mended here still shows, with the reason, for the same reason a recipe
## does — "needs a Workbench" is a plan and a blank list is a mystery.
static func worn_carried(p: PlayerSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in ["hotbar", "bag"]:
		var cont := container_for(p, kind)
		for i in range(cont.size()):
			if is_worn(cont, i):
				out.append({"c": kind, "i": i, "id": cont.id_at(i)})
	return out
