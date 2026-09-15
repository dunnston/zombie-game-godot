class_name Crafting
extends RefCounted
## Crafting. The materials are the whole cost; the time is a beat you can see.
##
## `start` opens `PlayerSim.crafting` and `tick` fills it; `craft` is what
## happens when it is full, and it is still the whole of the rules — it asks
## `status` again and pays then. Nothing is spent at the start, so stopping
## (a hit, walking off, CANCEL) loses the time and nothing else. It was instant
## until the owner pressed CRAFT, saw nothing happen, and pressed it again.
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


## The specialised benches within reach, as a set of station ids. A separate
## gate to `bench` on purpose: chemistry is different work, not harder
## metalwork, and a recipe that names a `station` is unreachable at any
## workbench tier without one standing beside you.
static func stations_at(sim: GameSim, p: PlayerSim) -> Dictionary:
	var out := {}
	for id in STATIONS:
		if not sim.structs.near_station(p.pos, id).is_empty():
			out[id] = true
	return out


## Every station a structure offers. Derived rather than listed, so building
## a second kind of bench is a `STRUCTURES` edit and nothing else.
static var STATIONS: Array:
	get:
		if _stations.is_empty():
			for id in Config.STRUCTURES:
				var s := String(Config.STRUCTURES[id].get("station", ""))
				if not s.is_empty() and not _stations.has(s):
					_stations.append(s)
		return _stations

static var _stations: Array = []


## What a station is called, for the refusal a player actually reads.
static func station_name(station: String) -> String:
	for id in Config.STRUCTURES:
		if String(Config.STRUCTURES[id].get("station", "")) == station:
			return String(Config.STRUCTURES[id].name)
	return station


## Whether the player is carrying a tool with the given flag ("knife",
## "hammer"). Carried, not held: you do not have to swap to it.
##
## A broken one does not count. "Broken weapons do nothing until mended" has
## to mean the bench too, or a zero-condition Stone Knife would still cut
## cordage. Nothing deadlocks: every tool a recipe names is itself a bench-0
## recipe, so a broken knife is always mendable by hand.
static func has_tool(p: PlayerSim, flag: String) -> bool:
	for cont in [p.hotbar, p.bag]:
		for i in range(cont.size()):
			var w: Dictionary = Config.WEAPONS.get(cont.id_at(i), {})
			if w.get(flag, false) and not Wear.is_broken(cont, i):
				return true
	return false


## The recipes worth showing at this bench. By hand (bench 0) that is the six
## things you make before you have a base; everything else is bench work.
static func visible_recipes(_p: PlayerSim, bench: int, stations := {}) -> Array:
	var out: Array = []
	for r in Config.RECIPES:
		# A station recipe is shown only at its station: it is not the top of
		# the workbench ladder, so listing it greyed out beside the guns would
		# read as "keep upgrading" and send the player the wrong way.
		var st := String(r.get("station", ""))
		if not st.is_empty():
			if stations.has(st):
				out.append(r)
			continue
		if r.bench <= bench:
			out.append(r)
	return out


## Why this recipe's *bench* cannot do the work here: the workbench tier, the
## station and the tool in the pack, and nothing about cost or room.
##
## Split out of `status` so repair can ask the same question: "mended at the
## bench that made it" is this function, asked about the same recipe row, and
## a second copy of the gate would be a second thing to keep in step.
## Returns "" when the bench is fine.
static func bench_reason(sim: GameSim, p: PlayerSim, r: Dictionary, bench: int) -> String:
	if r.bench > bench:
		return "Needs a Workbench" if r.bench == 1 else "Needs Workbench II"
	# Asked of the world rather than taken from the caller: on a guest this
	# same function runs on the host, where standing beside the station is the
	# only thing that can be checked honestly.
	var station := String(r.get("station", ""))
	if not station.is_empty() and sim.structs.near_station(p.pos, station).is_empty():
		return "Needs a %s" % station_name(station)
	if r.has("tool") and not has_tool(p, r.tool):
		return "Needs a %s" % Config.WEAPONS[r.tool].name
	return ""


## Why a recipe cannot be made right now, in the order a player meets it.
static func status(sim: GameSim, p: PlayerSim, r: Dictionary, bench: int) -> Dictionary:
	# Nothing is made inside an instance (Codex, PR #31). The ledger writes
	# down what was found, and crafting would turn four found cloth into two
	# bandages it never wrote down — which a walk-out or a death would then
	# leave in your pack, and only the boss is meant to let things out. What
	# you need in there is what you brought: the loadout is the decision.
	if sim != null and sim.instance != null:
		return {"ok": false, "reason": "Nothing can be made in here"}
	var why := bench_reason(sim, p, r, bench)
	if not why.is_empty():
		return {"ok": false, "reason": why}
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


## A recipe row by id, or empty. The wire and the channel both carry the id.
static func recipe(id: String) -> Dictionary:
	for r in Config.RECIPES:
		if String(r.id) == id:
			return r
	return {}


## How long one of anything takes this player to make.
static func duration(p: PlayerSim) -> float:
	return maxf(0.05, float(Config.PLAYER.craft_time) * p.craft_time_mul)


## Begin making `n` of a recipe, one after another. Refuses with the same
## reason `status` gives, so the screen and this can never disagree.
static func start(sim: GameSim, p: PlayerSim, r: Dictionary, bench: int, n := 1) -> bool:
	if p.dead or p.downed or p.away:
		return false
	if not p.crafting.is_empty():
		# One thing at a time. The screen turns CRAFT into CANCEL while the bar
		# fills, so this is a second press racing the first (or a guest's,
		# arriving before the snapshot that shows the bar).
		return false
	var st := status(sim, p, r, bench)
	if not st.ok:
		sim.notify(st.reason, "#c96a5a")
		return false
	p.crafting = {"id": String(r.id), "t": 0.0, "dur": duration(p), "bench": bench, "left": maxi(1, n)}
	return true


## Fill the bar; at the top, make one and start the next. Called from
## `PlayerSim.tick` whenever something is being made.
static func tick(sim: GameSim, p: PlayerSim, dt: float) -> void:
	var c := p.crafting
	# Parked, dead, downed, behind a wheel or not in charge of your own legs:
	# no reason on screen, because whatever did it has a louder one of its
	# own. Driving is here because behind the wheel "what can you do" is
	# "drive" (`PlayerSim.tick`) — and this runs above that return (Codex, #49).
	if p.away or p.dead or p.downed or p.driving_id > 0 or p.lurch_t > 0.0:
		p.crafting = {}
		return
	var r := recipe(String(c.id))
	if r.is_empty():
		p.crafting = {}
		return
	# The bench is asked of the world every step, not only at the end: walking
	# off should stop the bar where you left it, not fill it and then refuse.
	# The claimed tier can only fall — the same `mini` a guest's command gets.
	var bench := mini(int(c.bench), bench_tier_at(sim, p))
	var st := status(sim, p, r, bench)
	if not st.ok:
		stop(sim, p, String(st.reason))
		return
	c.t = float(c.t) + dt
	if float(c.t) < float(c.dur):
		return
	if not craft(sim, p, r, bench):
		p.crafting = {}
		return
	c.left = int(c.left) - 1
	if int(c.left) <= 0:
		p.crafting = {}
		return
	c.t = 0.0
	c.dur = duration(p)


## Stop, and say why — to the HUD, and to the craft screen, which covers it.
static func stop(sim: GameSim, p: PlayerSim, reason: String) -> void:
	p.crafting = {}
	sim.notify(reason, "#d9c46a")
	sim.emit({"t": "craft_stopped", "by": p.seat, "text": reason})


## The player's own CANCEL. Quiet on the HUD: you know why you pressed it.
static func cancel(sim: GameSim, p: PlayerSim) -> bool:
	if p.crafting.is_empty():
		return false
	p.crafting = {}
	sim.emit({"t": "craft_stopped", "by": p.seat, "text": "Cancelled"})
	return true


## Make one, now: check again, pay, and hand it over. The end of the bar.
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
		# No key named here: the sim does not know what the keyboard says, and a
		# hardcoded "(Tab)" is a lie the moment somebody rebinds the pack.
		label = "%s crafted — equip it from your pack" % Config.GEAR[gid].name
	elif r.give.has("item"):
		var iid: String = r.give.item
		var want: int = r.give.n
		var got := p.bag.add_capped(iid, want, p.pack_allowance())
		if got < want:
			_on_the_ground(sim, p, "item:" + iid, want - got)
		label = "%s x%d" % [Config.CONSUMABLES[iid].name, want]
	elif r.give.has("res"):
		for id in r.give.res:
			# Gunsmith pays out in ammunition only: a bigger batch of arrows,
			# not a bigger batch of everything a recipe happens to give back.
			var yield_mul: float = p.craft_yield_mul if id in Config.AMMO_IDS else 1.0
			var want := roundi(r.give.res[id] * yield_mul)
			var got := p.bag.add_capped(id, want, p.pack_allowance())
			if got < want:
				# Overflow goes to the stash first — it is the base's pile,
				# and you are standing at the bench — and to the ground after.
				Loot.stash_or_drop(sim, id, want - got, p.pos)
				sim.notify("Pack full — the rest went to your stash", "#d9c46a")

	sim.stats.crafted = sim.stats.get("crafted", 0) + 1
	Progression.add_xp(sim, p, r.xp, "CRAFT")
	sim.threat.add(sim, Config.THREAT.per_craft, p)
	# `by`, so the craft screen — which covers the HUD's notice — can say it
	# too, on the maker's machine only. Not `seat`: the host relays a seated
	# event to that guest alone, and the teammate beside you should still hear
	# the bench.
	sim.emit({"t": "crafted", "by": p.seat, "x": p.pos.x, "y": p.pos.y, "text": label})
	sim.notify(label, "#b7e08a")
	return true


static func _on_the_ground(sim: GameSim, p: PlayerSim, entry: String, n: int) -> void:
	Loot.spawn_entry_pickup(sim, p.pos, entry, n)
	sim.notify("No room — it is on the ground at your feet", "#d9c46a")
