class_name Recycle
extends RefCounted
## The Recycler: a bench that turns a thing back into materials (Notion DL-86,
## and the fifth bench on the owner's Workbenches table — "nothing is crafted
## here; what each item gives back is on the item, under Breaks down into").
##
## The table is `Config.RECYCLE`, one row per item, written from that column.
## Buildings are deliberately absent: taking one down already pays through
## `Structures.demolish`, and a second refund for the same wall is a loop.
##
## Two things scale what comes back, and both are the same shape as the rest of
## the game: `Config.RECYCLE_SHARE` (a knob, 1.0 today), and a worn tool's
## condition — a Machete at 30% is 30% of a Machete's worth of steel. Nothing
## is ever rounded away to nothing: a row that gives anything gives at least
## one of its biggest material, or "recycle" would quietly mean "destroy".

const RANGE := Config.BUILD.bench_range


## What one of `id` returns, at `wear_frac` of its condition (1.0 for anything
## that does not wear). Empty when the thing cannot be recycled at all.
static func yield_of(id: String, wear_frac := 1.0) -> Dictionary:
	var row: Dictionary = Config.RECYCLE.get(id, {})
	if row.is_empty():
		return {}
	var gives: Dictionary = row.get("gives", {})
	var scale := clampf(wear_frac, 0.0, 1.0) * float(Config.RECYCLE_SHARE)
	var out := {}
	var best := ""
	var best_n := -1
	for res_id: String in gives:
		var n: int = gives[res_id]
		if n > best_n:
			best_n = n
			best = res_id
		var got := int(floor(n * scale))
		if got > 0:
			out[res_id] = got
	# A broken Machete is still a lump of steel. The biggest material always
	# comes back at least once, so nothing ever goes in and nothing comes out.
	if out.is_empty() and not best.is_empty():
		out[best] = 1
	return out


static func can_recycle(id: String) -> bool:
	return Config.RECYCLE.has(id)


## The Recycler this player is standing at, or an empty Dictionary. Asked of
## the world every time, exactly as a workbench's tier is, so walking away
## while the screen is open ends it — and so a guest's command is checked
## against where the host says they are.
static func bench_near(sim: GameSim, p: PlayerSim) -> Dictionary:
	if sim == null or sim.structs == null:
		return {}
	var s := sim.structs.near_station(p.pos, "recycle")
	if s.is_empty():
		return {}
	return s if Interact.in_sight_of(sim, p, s.pos, s) else {}


## Breaks one item out of `cont_kind[index]` down. Returns what it gave back,
## or an empty Dictionary with the reason said out loud.
##
## One at a time, like crafting: a stack of twelve pipes is twelve presses, and
## every one of them is a decision you can stop making halfway through.
static func recycle(sim: GameSim, p: PlayerSim, cont_kind: String, index: int) -> Dictionary:
	if bench_near(sim, p).is_empty():
		sim.notify("Stand at a Recycler", "#c96a5a")
		return {}
	var cont := Equipment.container(p, cont_kind)
	if cont == null:
		return {}
	var stack := cont.at(index)
	if stack.is_empty():
		return {}
	var id := String(stack.id)
	if not can_recycle(id):
		sim.notify("%s does not break down into anything" % Items.name_of(id), "#c96a5a")
		return {}
	var frac := Wear.frac(cont, index) if Wear.wears(id) else 1.0
	var gives := yield_of(id, frac)
	if gives.is_empty():
		sim.notify("%s does not break down into anything" % Items.name_of(id), "#c96a5a")
		return {}
	# Taken first: a failure to hand the materials over must not also be a way
	# to duplicate the thing being taken apart.
	if cont.take(id, 1) != 1:
		return {}
	for res_id: String in gives:
		var n: int = gives[res_id]
		var got := p.bag.add_capped(res_id, n, p.pack_allowance())
		if got < n:
			# The usual overflow rule: the stash if there is one, the ground if
			# there is not. Nothing a bench produces is ever destroyed.
			Loot.stash_or_drop(sim, res_id, n - got, p.pos)
	sim.notify("Broke down %s — %s" % [Items.name_of(id), Structures.cost_label(gives)], "#b7e08a")
	sim.emit({"t": "recycled", "by": p.seat, "id": id, "x": p.pos.x, "y": p.pos.y})
	Progression.add_xp(sim, p, 4, "RECYCLE")
	return gives
