class_name Wear
extends RefCounted
## Weapons wear out, and the bench that made one is where it is mended.
##
## Wear is kept the way a magazine is kept: `PlayerSim.wear` is weapon id ->
## uses left, exactly as `PlayerSim.mag` is weapon id -> rounds loaded. That
## is deliberate and it has a consequence worth saying out loud — two
## Hatchets in one pack share one wear value, the same way two pistols
## already share one magazine. A slot is `{id, n}` and nothing else
## (`Slots`), so per-instance durability would mean per-instance state in
## every container, every save record and every wire diff. Matching `mag` is
## the smaller, truer answer.
##
## `use` is the only thing that writes it — the same rule `Mutation.add`
## carries, and for the same reason: it is what makes a guest agree with the
## host about whether the axe in its hand still swings.

const W := Config.WEAR


## How many uses this weapon has when new, or 0 for something that never
## wears. Fists are the 0: they are not an object you carry.
static func max_of(id: String) -> int:
	return int(Config.WEAPONS.get(id, {}).get("dur", 0))


static func wears(id: String) -> bool:
	return max_of(id) > 0


## Uses left. Unknown means untouched, so a weapon just picked up is whole
## without anyone having to write a full value into the dictionary first.
static func left(p: PlayerSim, id: String) -> int:
	if not wears(id):
		return 0
	return clampi(int(p.wear.get(id, max_of(id))), 0, max_of(id))


## 0.0 to 1.0. Something that never wears reads as whole, so every caller
## can ask without checking `wears` first.
static func frac(p: PlayerSim, id: String) -> float:
	if not wears(id):
		return 1.0
	return float(left(p, id)) / float(max_of(id))


static func is_broken(p: PlayerSim, id: String) -> bool:
	return wears(id) and left(p, id) <= 0


static func is_worn(p: PlayerSim, id: String) -> bool:
	return wears(id) and left(p, id) < max_of(id)


## Spend `n` uses of `id`. The one writer.
##
## The warnings fire on the crossing rather than on the frame, so holding a
## trigger cannot spam them, and the weapon's numbers do not change on the
## way down: it swings exactly as well at 5% as at 100% and then it stops.
## A weapon that got quietly worse would be a chore you could not see, and
## pillar 1 is survival without those.
static func use(sim: GameSim, p: PlayerSim, id: String, n := 1) -> void:
	if not wears(id) or n <= 0:
		return
	var before := left(p, id)
	if before <= 0:
		return
	var after := maxi(0, before - n)
	p.wear[id] = after
	var cap := max_of(id)
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


## Sets `id` back to new. Used by repair and by the dev menu.
static func mend(p: PlayerSim, id: String) -> void:
	if wears(id):
		p.wear[id] = max_of(id)


# ----------------------------------------------------------------- repair --

## The recipe that makes this weapon, or empty. A weapon nothing makes is
## repaired nowhere: that is the whole rule behind "found weapons are not
## bench work", and it needs no flag of its own — the absence of a recipe
## already says it. Give such a weapon a bigger `dur` and it is the thing
## that lasts longer and cannot be mended, with no second system underneath.
static func recipe_for(id: String) -> Dictionary:
	for r in Config.RECIPES:
		if String(r.get("give", {}).get("weapon", "")) == id:
			return r
	return {}


## What mending `id` costs: a share of what it cost to make, scaled by how
## much of it is gone. The main material is always at least one, so no repair
## is ever free — the same shape, and the same reasoning, as
## `Structures.repair_cost`.
##
## Deliberately *not* scaled by `build_cost_mul`, which the structure version
## does take: that multiplier is the Engineer perk and the Intelligence
## ladder making the things you *construct* cheaper, and `Crafting.craft`
## already ignores it — a Machete costs 24 scrap at any Intelligence. Mending
## one for a share of a price the perk does not touch has to ignore it too,
## or a high-INT survivor would find repairing cheaper than crafting for a
## reason nothing in the game ever states.
static func repair_cost(p: PlayerSim, id: String) -> Dictionary:
	var r := recipe_for(id)
	if r.is_empty() or not is_worn(p, id):
		return {}
	var gone := 1.0 - frac(p, id)
	var out := {}
	var main_id := ""
	var main_n := -1
	for cid in r.cost:
		var c: int = r.cost[cid]
		if c > main_n:
			main_n = c
			main_id = cid
		var n := roundi(c * gone * W.repair_cost_share)
		if n > 0:
			out[cid] = n
	if not main_id.is_empty() and not out.has(main_id):
		out[main_id] = 1
	return out


## Why `id` cannot be mended where the player stands, in the order they meet
## it. The bench gate is the recipe's own — "the same bench it was made at"
## is literally `Crafting.bench_reason` asked about the same row.
static func repair_status(sim: GameSim, p: PlayerSim, id: String, bench: int) -> Dictionary:
	if not wears(id):
		return {"ok": false, "reason": "Nothing to mend"}
	if p.count_carried(id) <= 0:
		return {"ok": false, "reason": "You are not carrying one"}
	if not is_worn(p, id):
		return {"ok": false, "reason": "Not worn"}
	var r := recipe_for(id)
	if r.is_empty():
		return {"ok": false, "reason": "Nothing here can mend it"}
	var why := Crafting.bench_reason(sim, p, r, bench)
	if not why.is_empty():
		return {"ok": false, "reason": why}
	if not p.can_afford(sim, repair_cost(p, id)):
		return {"ok": false, "reason": "Missing materials"}
	return {"ok": true, "reason": ""}


## Mend one weapon at the bench that makes it. Called through `Actions`, so
## on a guest this same function runs on the host with the same gates.
static func repair(sim: GameSim, p: PlayerSim, id: String, bench: int) -> bool:
	var st := repair_status(sim, p, id, bench)
	if not st.ok:
		sim.notify(st.reason, "#c96a5a")
		return false
	var cost := repair_cost(p, id)
	p.spend(sim, cost)
	mend(p, id)
	var label := "%s mended — %s" % [Config.WEAPONS[id].name, Structures.cost_label(cost)]
	Progression.add_xp(sim, p, 3, "REPAIR")
	sim.emit({"t": "crafted", "x": p.pos.x, "y": p.pos.y, "text": label})
	sim.notify(label, "#7ce08a")
	return true


## Every worn weapon the player is carrying, whichever container it is in.
## The craft screen lists these above the recipes; a row that cannot be
## mended here still shows, with the reason, for the same reason a recipe
## does — "needs a Workbench" is a plan and a blank list is a mystery.
static func worn_carried(p: PlayerSim) -> Array[String]:
	var out: Array[String] = []
	for cont in [p.hotbar, p.bag]:
		for i in range(cont.size()):
			var id: String = cont.id_at(i)
			if not id.is_empty() and is_worn(p, id) and not out.has(id):
				out.append(id)
	return out
