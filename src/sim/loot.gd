class_name Loot
extends RefCounted
## Loot rolls, ground pickups and the death backpack.
##
## Everything here obeys one rule: **anything that will not fit lands on the
## ground, never nowhere.** A pack too full to take a rifle leaves the rifle
## where it was; a crafted stack that overflows falls at your feet. No path
## may destroy material for want of somewhere to put it.

## A loot entry id is either a bare resource ("scrap") or prefixed:
## "weapon:rifle", "gear:milVest", "item:bandage". Ground pickups are the same
## grammar seen from the other side, so both directions live in this file —
## they drifted apart once in the prototype and the symptom was rare gear
## silently deleted on contact.


static func entry_to_pickup(entry: String) -> Dictionary:
	var c := entry.find(":")
	if c < 0:
		return {"kind": "res", "id": entry}
	var prefix := entry.substr(0, c)
	var id := entry.substr(c + 1)
	match prefix:
		"weapon": return {"kind": "weapon", "id": id}
		"item": return {"kind": "item", "id": id}
		"gear", "armor": return {"kind": "gear", "id": id}
	return {"kind": "res", "id": entry}


## The entry id for a bare item id — what you need to drop something you are
## holding in a slot.
static func item_entry_id(id: String) -> String:
	match Items.kind_of(id):
		"weapon": return "weapon:" + id
		"gear": return "gear:" + id
		"consumable": return "item:" + id
	return id


## Rebuilds the entry id a ground pickup came from, for handing back to
## `give_entry`.
static func pickup_entry_id(it: Dictionary) -> String:
	match it.kind:
		"res": return it.id
		"item": return "item:" + it.id
		"weapon": return "weapon:" + it.id
	return "gear:" + it.id


# ------------------------------------------------------------------- rolls --

## Rolls a container's table. Returns [{id, n}] where `id` may be prefixed.
## `loot_mul` multiplies bulk resources only — unique equipment is not
## something a perk can hand you two of.
static func roll_container(sim: GameSim, c: Dictionary, loot_mul := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table: Array = Config.LOOT.get(c.table, [])
	if table.is_empty():
		return out
	var lo: int = c.rolls[0]
	var hi: int = c.rolls[1]
	var rolls := sim.loot_rng.irange(lo, hi)
	var totals := {}
	var order: Array[String] = []
	for i in range(rolls):
		var e := _weighted_pick(sim, table)
		if e.is_empty():
			continue
		var n := sim.loot_rng.irange(e.min, e.max)
		if Config.RES.has(e.id):
			n = maxi(1, roundi(n * loot_mul))
		# Only stacking things are aggregated. Two rolls of the same rifle are
		# two rifles, and an entry saying `{rifle, n: 2}` would hand over one
		# and quietly lose the other — a weapon has no `n`.
		if Items.stack_limit(entry_to_pickup(e.id).id) <= 1:
			for k in range(n):
				out.append({"id": e.id, "n": 1})
			continue
		if not totals.has(e.id):
			order.append(e.id)
		totals[e.id] = totals.get(e.id, 0) + n
	for id in order:
		out.append({"id": id, "n": totals[id]})
	return out


static func _weighted_pick(sim: GameSim, table: Array) -> Dictionary:
	var total := 0.0
	for e in table:
		total += e.w
	var r := sim.loot_rng.next() * total
	for e in table:
		r -= e.w
		if r <= 0.0:
			return e
	return table[table.size() - 1]


# ------------------------------------------------------------------ giving --

## Gives one loot entry to a player.
##
## Returns {text, color, major, overflow}. `overflow` is a full **prefixed**
## entry id and a count, so a bandage that did not fit becomes a bandage on
## the floor rather than an undecodable pickup.
static func give_entry(sim: GameSim, p: PlayerSim, entry: Dictionary) -> Dictionary:
	var id: String = entry.id
	var n: int = entry.get("n", 1)

	if id.begins_with("weapon:"):
		var wid := id.substr(7)
		if not Config.WEAPONS.has(wid):
			return {}
		var w: Dictionary = Config.WEAPONS[wid]
		if p.carries(wid):
			# A duplicate gun is worth more as a magazine of its ammunition.
			# What will not fit is dropped rather than returned as overflow:
			# the pile this came from is a *gun*, and handing back an ammo
			# entry would rewrite it into something it is not.
			if w.has("ammo"):
				var give: int = w.mag * 2
				var got := p.bag.add_capped(w.ammo, give, p.pack_allowance())
				if got < give:
					spawn_entry_pickup(sim, p.pos, w.ammo, give - got)
				return {"text": "%s (spare ammo +%d)" % [w.name, got], "color": "#d8c98a"}
			return {"text": "%s (already carried)" % w.name, "color": "#8a8f84"}
		if not _give_item(p, wid, true):
			return {"text": "%s — NO ROOM" % w.name, "color": "#c96a5a", "overflow": {"entry": id, "n": 1}}
		if not p.mag.has(wid):
			p.mag[wid] = w.get("mag", 0)
		return {"text": "%s acquired" % w.name, "color": "#ffe08a", "major": true}

	if id.begins_with("gear:") or id.begins_with("armor:"):
		var gid := id.substr(id.find(":") + 1)
		if not Config.GEAR.has(gid):
			return {}
		var g: Dictionary = Config.GEAR[gid]
		# Gear goes to the pack and waits. Nothing equips itself — silently
		# wearing the highest-armour piece is what made the old system
		# impossible to reason about.
		if not _give_item(p, gid, false):
			return {"text": "%s — NO ROOM" % g.name, "color": "#c96a5a", "overflow": {"entry": "gear:" + gid, "n": 1}}
		var worn: String = p.equip.get(g.slot, "")
		var better: bool = worn.is_empty() or g.dr > float(Config.GEAR[worn].dr)
		return {
			"text": ("%s — better than what you are wearing" % g.name) if better else ("%s stowed" % g.name),
			"color": "#ffe08a" if better else "#a8b09a", "major": better,
		}

	if id.begins_with("item:"):
		var iid := id.substr(5)
		if not Config.CONSUMABLES.has(iid):
			return {}
		var c: Dictionary = Config.CONSUMABLES[iid]
		var got := p.bag.add_capped(iid, n, p.pack_allowance())
		var res := {
			"text": ("%s x%d" % [c.name, got]) if got > 0 else ("%s — PACK FULL" % c.name),
			"color": c.color if got > 0 else "#c96a5a",
		}
		if n - got > 0:
			res["overflow"] = {"entry": "item:" + iid, "n": n - got}
		return res

	if not Config.RES.has(id):
		return {}
	var def: Dictionary = Config.RES[id]
	var taken := p.bag.add_capped(id, n, p.pack_allowance())
	var out := {
		"text": ("%s +%d" % [def.name, taken]) if taken > 0 else ("%s — PACK FULL" % def.name),
		"color": def.color if taken > 0 else "#c96a5a",
	}
	if n - taken > 0:
		out["overflow"] = {"entry": id, "n": n - taken}
	return out


## One non-stacking item into the first free slot, preferring the hotbar for
## weapons so a gun you pick up is immediately to hand.
##
## Weight is the capacity rule, so it applies here too: a six-unit rifle at
## 199 of 200 units carried is refused and stays on the ground, exactly as an
## overweight stack of scrap would be. Slot space alone is not enough.
static func _give_item(p: PlayerSim, id: String, prefer_hotbar: bool) -> bool:
	if p.carried_weight() + Items.weight_of(id) > p.carry_cap + 1e-9:
		return false
	if prefer_hotbar and p.hotbar.first_empty() >= 0:
		return p.hotbar.add(id, 1) > 0
	if p.bag.first_empty() >= 0:
		return p.bag.add(id, 1) > 0
	if p.hotbar.first_empty() >= 0:
		return p.hotbar.add(id, 1) > 0
	return false


## Into the pack if it fits, onto the ground if it does not. What harvesting
## and gathering use, so a full pack costs you a walk rather than the wood.
static func give_res_or_drop(sim: GameSim, p: PlayerSim, id: String, n: int, at: Vector2) -> int:
	var took := p.bag.add_capped(id, n, p.pack_allowance())
	if took < n:
		spawn_entry_pickup(sim, at, item_entry_id(id), n - took)
	return took


## Applies a whole roll, drops what would not fit, and returns the lines the
## view floats over the container.
static func grant_loot(sim: GameSim, p: PlayerSim, entries: Array, at: Vector2) -> Dictionary:
	var lines: Array[Dictionary] = []
	var any_major := false
	for e in entries:
		var r := give_entry(sim, p, e)
		if r.is_empty():
			continue
		lines.append({"text": r.text, "color": r.color})
		if r.get("major", false):
			any_major = true
		if r.has("overflow"):
			spawn_entry_pickup(sim, at, r.overflow.entry, r.overflow.n)
	return {"lines": lines, "major": any_major}


# ----------------------------------------------------------------- pickups --

## Puts a pile on the ground.
##
## `owner` is the player who deliberately dropped it. A dropped pile lands at
## their feet, already inside collection range, so without this it is swallowed
## again on the very next frame and dropping does nothing at all. The pile
## ignores that one player's magnet until they have stepped clear of it once —
## a state, not a timer. Everyone else may take it immediately: putting
## something down at a teammate's feet is how you hand it to them.
static func spawn_pickup(sim: GameSim, at: Vector2, kind: String, id: String, n := 1, owner: PlayerSim = null) -> Dictionary:
	var pos := at
	var guard := 0
	while sim.world.is_blocked_px(pos.x, pos.y) and guard < 24:
		guard += 1
		var a := sim.loot_rng.frange(0.0, TAU)
		pos = at + Vector2(cos(a), sin(a)) * (8.0 + guard * 3.0)
	sim.pickup_seq += 1
	var it := {
		"uid": sim.pickup_seq, "pos": pos, "kind": kind, "id": id, "n": n,
		"vel": Vector2(sim.loot_rng.frange(-40, 40), sim.loot_rng.frange(-40, 40)),
		"t": 0.0, "bob": sim.loot_rng.frange(0.0, TAU), "life": 600.0,
		"inert_for": owner,
	}
	sim.pickups.append(it)
	return it


static func spawn_entry_pickup(sim: GameSim, at: Vector2, entry: String, n: int) -> Dictionary:
	var d := entry_to_pickup(entry)
	return spawn_pickup(sim, at, d.kind, d.id, n)


static func update_pickups(sim: GameSim, dt: float) -> void:
	for i in range(sim.pickups.size() - 1, -1, -1):
		var it: Dictionary = sim.pickups[i]
		it.t += dt
		it.life -= dt
		it.pos += it.vel * dt
		it.vel *= exp(-6.0 * dt)
		if it.life <= 0.0:
			sim.pickups.remove_at(i)
			continue

		# Whoever is closest gets the pull, and the loot.
		var p := sim.nearest_player(it.pos)
		if p == null:
			continue
		var d2: float = it.pos.distance_squared_to(p.pos)
		var range_ := p.pickup_range

		# A pile you put down yourself waits until you have stepped clear.
		# Re-arms well outside the collection radius so standing on the edge
		# does not flicker between dropping and collecting.
		if it.inert_for != null:
			if it.inert_for == p:
				if d2 > pow(range_ * 1.2, 2.0):
					it.inert_for = null
				continue

		if d2 < range_ * range_ * 5.5:
			var d := maxf(sqrt(d2), 1.0)
			var pull := clampf(700.0 / d, 40.0, 620.0)
			it.vel += (p.pos - it.pos) / d * pull * dt
		if d2 < pow(range_ * 0.45, 2.0):
			var entry := pickup_entry_id(it)
			var r := give_entry(sim, p, {"id": entry, "n": it.n})
			if not r.is_empty() and r.has("overflow") and r.overflow.entry == entry:
				# No room: leave it, and shove it clear so it stops being
				# offered every frame. The entry has to match the pile — this
				# rewrites what is lying there, and a mismatch would turn a
				# rifle on the ground into a heap of 9mm.
				it.n = r.overflow.n
				it.vel = (it.pos - p.pos) * 1.2
				continue
			if not r.is_empty():
				sim.emit({"t": "float", "x": it.pos.x, "y": it.pos.y - 8.0, "text": r.text, "color": r.color})
			sim.emit({"t": "picked_up", "x": it.pos.x, "y": it.pos.y})
			sim.pickups.remove_at(i)


## Into the shared stash if it fits, onto the ground beside `at` if it does
## not. Every path that used to write to the stash unconditionally comes
## through here, because storage is finite.
static func stash_or_drop(sim: GameSim, id: String, n: int, at: Vector2) -> int:
	if n <= 0:
		return 0
	var took := 0
	if sim.stash != null:
		took = sim.stash.add(id, n)
	if took < n:
		spawn_entry_pickup(sim, at, item_entry_id(id), n - took)
	return took


# --------------------------------------------------------------- backpacks --

## Everything the player was carrying, dropped where they fell. You keep the
## starting weapon, so a respawn is never completely toothless.
static func drop_backpack(sim: GameSim, p: PlayerSim) -> Dictionary:
	var held := {}
	for cont in [p.bag, p.hotbar]:
		var entries: Dictionary = cont.entries()
		for id in entries:
			held[id] = held.get(id, 0) + entries[id]
	for slot in p.equip:
		var id: String = p.equip[slot]
		if not id.is_empty():
			held[id] = held.get(id, 0) + 1
	var keep: String = p.start_weapon
	if held.has(keep):
		held[keep] -= 1
		if held[keep] <= 0:
			held.erase(keep)

	p.bag.clear_all()
	p.hotbar.clear_all()
	for slot in p.equip:
		p.equip[slot] = ""
	p.hotbar.add(keep, 1)
	p.slot = 0
	# Losing your armour has to actually cost you the mitigation, and the
	# light that went into the pack has to stop being lit.
	Equipment.after_equip_change(p)

	if held.is_empty():
		return {}
	var pack := {"pos": p.pos, "held": held, "mag": p.mag.duplicate(), "t": 0.0, "seat": p.seat}
	sim.backpacks.append(pack)
	# The rounds went into the pack with the gun. Leaving them on the player
	# would hand a freshly found replacement the dead one's magazine, and
	# would mean the saved value could never be restored on recovery.
	for id in held:
		if id != keep:
			p.mag.erase(id)
	return pack


static func collect_backpack(sim: GameSim, p: PlayerSim, pack: Dictionary) -> int:
	var moved := 0
	for id in pack.held.keys():
		var want: int = pack.held[id]
		var got := p.bag.add_capped(id, want, p.pack_allowance())
		pack.held[id] -= got
		if pack.held[id] <= 0:
			pack.held.erase(id)
		if got > 0 and Config.WEAPONS.has(id) and not p.mag.has(id):
			p.mag[id] = pack.mag.get(id, Config.WEAPONS[id].get("mag", 0))
		moved += got
	var left := 0
	for id in pack.held:
		left += pack.held[id]
	if left <= 0:
		sim.backpacks.erase(pack)
		sim.notify("Pack recovered", "#b7e08a")
	else:
		sim.notify("Recovered what fits — %d left in the pack" % left, "#d9c46a")
	sim.emit({"t": "ring", "x": pack.pos.x, "y": pack.pos.y, "r0": 6.0, "r1": 60.0, "color": "#c9a227"})
	return moved


# -------------------------------------------------------------- enemy drop --

## Small drops from a dead body, so guns stay usable between containers.
static func enemy_drop(sim: GameSim, e: EnemySim) -> void:
	if e.def.get("boss", false):
		spawn_pickup(sim, e.pos, "res", "mil", sim.loot_rng.irange(4, 8))
		spawn_pickup(sim, e.pos, "res", "parts", sim.loot_rng.irange(2, 4))
		spawn_pickup(sim, e.pos, "res", "ammoR", sim.loot_rng.irange(10, 18))
		return
	var roll := sim.loot_rng.next()
	if roll < 0.16:
		spawn_pickup(sim, e.pos, "res", "ammoP", sim.loot_rng.irange(4, 10))
	elif roll < 0.24:
		spawn_pickup(sim, e.pos, "res", "cloth", sim.loot_rng.irange(1, 3))
	elif roll < 0.30:
		spawn_pickup(sim, e.pos, "res", "scrap", sim.loot_rng.irange(1, 4))
	elif roll < 0.335:
		spawn_pickup(sim, e.pos, "item", "bandage", 1)
	elif roll < 0.35 and e.type == "brute":
		spawn_pickup(sim, e.pos, "res", "parts", 1)
