class_name Upgrade
extends RefCounted
## Weapon levels (PR E; the owner's call of 2026-09-10). A weapon is upgraded
## at the bench that makes it, from level 1 to 6, and every level adds damage
## and durability. Levels 4 to 6 cost Precision Parts — and Precision Parts
## only leave the School past its boss — so a weapon sits at 3 until the boss
## has been beaten once, with no flag anywhere. The gate is the material: that
## is `tasks/instanced-dungeons.md` §4, and pillar 2.
##
## The level lives on the weapon, as the optional `lv` on a `Slots` stack,
## exactly as condition does (`Wear`): it goes wherever the weapon goes, and
## an unset stack is level 1. `upgrade` is the one writer.

const U := Config.UPGRADE


static func level_in(stack: Dictionary) -> int:
	if stack.is_empty():
		return 1
	return clampi(int(stack.get("lv", 1)), 1, int(U.max))


static func level(cont: Slots, i: int) -> int:
	return 1 if cont == null else level_in(cont.at(i))


static func dmg_mul(lv: int) -> float:
	return 1.0 + float(U.dmg_per_level) * (lv - 1)


static func dur_mul(lv: int) -> float:
	return 1.0 + float(U.dur_per_level) * (lv - 1)


## What the weapon in the hand's level does to its damage. The swing and the
## shot are the only two readers.
static func held_mul(p: PlayerSim) -> float:
	return dmg_mul(level(p.hotbar, p.slot))


## What the next level of the weapon in a slot costs: a share of its recipe
## that grows with the level, and Precision Parts from level 4. Empty for a
## weapon nothing makes or one already at the top.
static func cost(cont: Slots, i: int) -> Dictionary:
	if cont == null:
		return {}
	var r := Wear.recipe_for(cont.id_at(i))
	var next := level(cont, i) + 1
	if r.is_empty() or next > int(U.max):
		return {}
	var share := float(U.cost_share.get(next, 1.0))
	var out := {}
	var main_id := ""
	var main_n := -1
	for cid in r.cost:
		var c: int = r.cost[cid]
		if c > main_n:
			main_n = c
			main_id = cid
		var n := ceili(c * share)
		if n > 0:
			out[cid] = n
	if not main_id.is_empty() and not out.has(main_id):
		out[main_id] = 1
	var pp := int(U.precision.get(next, 0))
	if pp > 0:
		out["precision"] = pp
	return out


## Why the weapon in this slot cannot go up a level here, in the order a
## player meets it. The bench gate is the recipe's own, as mending's is.
static func status(sim: GameSim, p: PlayerSim, cont_kind: String, i: int, bench: int) -> Dictionary:
	var cont := Wear.container_for(p, cont_kind)
	if cont == null:
		return {"ok": false, "reason": "Not something you are carrying"}
	var id := cont.id_at(i)
	if not Config.WEAPONS.has(id) or id == "fists":
		return {"ok": false, "reason": "Not a weapon"}
	var r := Wear.recipe_for(id)
	# A level is a share of the weapon's own recipe, and a weapon nothing makes
	# has none. It still mends, off its salvage (`Wear.repair_basis`), but it
	# stays the fixed point the table notes describe.
	if r.is_empty():
		return {"ok": false, "reason": "Nothing here can upgrade it"}
	if level(cont, i) >= int(U.max):
		return {"ok": false, "reason": "As good as it gets"}
	var why := Crafting.bench_reason(sim, p, r, bench)
	if not why.is_empty():
		return {"ok": false, "reason": why}
	var c := cost(cont, i)
	var pp := int(c.get("precision", 0))
	if pp > 0 and p.total_res(sim, "precision") < pp:
		return {"ok": false, "reason": "Needs %d Precision Parts" % pp}
	if not p.can_afford(sim, c):
		return {"ok": false, "reason": "Missing materials"}
	return {"ok": true, "reason": ""}


## One level, at the bench that makes it. Called through `Actions`, so on a
## guest this runs on the host with the same gates. A new level is the weapon
## made over, so it comes back whole.
static func upgrade(sim: GameSim, p: PlayerSim, cont_kind: String, i: int, bench: int) -> bool:
	var st := status(sim, p, cont_kind, i, bench)
	if not st.ok:
		sim.notify(st.reason, "#c96a5a")
		return false
	var cont := Wear.container_for(p, cont_kind)
	var c := cost(cont, i)
	p.spend(sim, c)
	var next := level(cont, i) + 1
	cont.set_level_at(i, next)
	Wear.mend(cont, i)
	var label := "%s — level %d  ·  %s" % [Config.WEAPONS[cont.id_at(i)].name, next, Structures.cost_label(c)]
	Progression.add_xp(sim, p, int(U.xp), "UPGRADE")
	sim.emit({"t": "crafted", "x": p.pos.x, "y": p.pos.y, "text": label})
	sim.notify(label, "#ffe08a")
	return true


## Every weapon the player is carrying that a bench could take further, as
## `{c, i, id}`. A weapon nothing makes is not listed: its tooltip says why.
static func upgradeable_carried(p: PlayerSim) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in ["hotbar", "bag"]:
		var cont := Wear.container_for(p, kind)
		for i in range(cont.size()):
			var id := cont.id_at(i)
			if Config.WEAPONS.has(id) and id != "fists" and not Wear.recipe_for(id).is_empty() \
					and level(cont, i) < int(U.max):
				out.append({"c": kind, "i": i, "id": id})
	return out
