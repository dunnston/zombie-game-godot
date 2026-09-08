class_name Structures
extends RefCounted
## Everything the player builds: the destructible map, placement, damage,
## repair, demolition, power, turrets and traps.
##
## This is the *second* collision source (invariant 2). The terrain bitmap
## never changes; this map does, one tile at a time, and every query that
## cares — movement, sight, steering, the flow field, build validation —
## takes it as a parameter rather than reading a global. Bullets do not
## consult it at all (invariant 3): you can shoot over your own barricade.

var list: Array[Dictionary] = []
var grid := {}                   # tile index (ty * W + tx) -> structure
var bench_tier := 0

const W := Config.WORLD_TILES
const B := Config.BUILD


static func key(tx: int, ty: int) -> int:
	return ty * W + tx


# ---------------------------------------------------------------- queries --

func at_tile(tx: int, ty: int) -> Dictionary:
	var s: Dictionary = grid.get(key(tx, ty), {})
	return {} if s.is_empty() or s.destroyed else s


func at_px(px: float, py: float) -> Dictionary:
	return at_tile(floori(px / Config.TILE), floori(py / Config.TILE))


## Blocks feet. An open gate does not, which is the whole point of a gate.
func solid_at(tx: int, ty: int) -> bool:
	var s := at_tile(tx, ty)
	if s.is_empty() or not s.solid:
		return false
	return not (s.def.get("gate", false) and s.open)


func solid_at_px(px: float, py: float) -> bool:
	return solid_at(floori(px / Config.TILE), floori(py / Config.TILE))


func nearest(at: Vector2, radius: float, pred := Callable()) -> Dictionary:
	var best := {}
	var bd := radius * radius
	for s in list:
		if s.destroyed:
			continue
		if pred.is_valid() and not pred.call(s):
			continue
		var d: float = at.distance_squared_to(s.pos)
		if d < bd:
			bd = d
			best = s
	return best


func hp_total() -> float:
	var n := 0.0
	for s in list:
		if not s.destroyed:
			n += s.hp
	return n


func count() -> int:
	var n := 0
	for s in list:
		if not s.destroyed:
			n += 1
	return n


## The middle of your important buildings — where a raid converges. The
## pieces worth protecting weigh triple, so a perimeter of forty walls does
## not drag the centre off the compound.
func base_centre() -> Dictionary:
	var sum := Vector2.ZERO
	var n := 0.0
	for s in list:
		if s.destroyed:
			continue
		var w: float = 3.0 if s.def.get("protect", false) else 1.0
		sum += s.pos * w
		n += w
	if n == 0.0:
		return {"pos": Vector2.ZERO, "has_base": false}
	return {"pos": sum / n, "has_base": true}


## What a raider walks toward. Deliberately the *nearest* piece rather than
## the most valuable: that is what makes a horde break on the perimeter,
## which is the whole reason to build one. Protected pieces pull a little
## harder, so a raider already inside heads for the workbench, not back out.
func raid_target(from: Vector2) -> Dictionary:
	var best := {}
	var best_score := INF
	for s in list:
		if s.destroyed:
			continue
		var score: float = from.distance_squared_to(s.pos) * (0.55 if s.def.get("protect", false) else 1.0)
		if score < best_score:
			best_score = score
			best = s
	return best


func near_workbench(at: Vector2) -> Dictionary:
	return nearest(at, B.bench_range, func(s: Dictionary) -> bool: return s.type == "workbench")


## The store of the structure on a tile, if this player is close enough to
## be using it. Range-checked here rather than in the screen: the rule has
## to hold for a guest's command too.
func reachable_store(p: PlayerSim, tx: int, ty: int) -> Slots:
	var s := at_tile(tx, ty)
	if s.is_empty() or s.store == null:
		return null
	var r: float = Config.PLAYER.interact_range + B.store_reach_bonus
	return s.store if p.pos.distance_squared_to(s.pos) <= r * r else null


# -------------------------------------------------------------- placement --

func is_unlocked(type: String) -> bool:
	var def: Dictionary = Config.STRUCTURES.get(type, {})
	return def.is_empty() or def.tier <= 1 or bench_tier >= 2


func cost_of(type: String, p: PlayerSim) -> Dictionary:
	var def: Dictionary = Config.STRUCTURES.get(type, {})
	return {} if def.is_empty() else PlayerSim.scaled_cost(def.cost, p.build_cost_mul)


## Every reason a piece cannot go here, in the order a player would meet
## them. The reason is the message: "Blocked" and "Not enough resources"
## are different problems and the build bar says which.
func can_place(sim: GameSim, type: String, tx: int, ty: int, p: PlayerSim) -> Dictionary:
	var def: Dictionary = Config.STRUCTURES.get(type, {})
	if def.is_empty():
		return {"ok": false, "reason": "Unknown"}
	if not is_unlocked(type):
		return {"ok": false, "reason": "Needs Workbench II"}
	if tx < 1 or ty < 1 or tx >= W - 1 or ty >= W - 1:
		return {"ok": false, "reason": "Out of bounds"}
	if sim.world.is_blocked_tile(tx, ty):
		return {"ok": false, "reason": "Blocked"}
	if not at_tile(tx, ty).is_empty():
		return {"ok": false, "reason": "Occupied"}

	var centre := Vector2(tx * Config.TILE + Config.TILE / 2.0, ty * Config.TILE + Config.TILE / 2.0)
	if centre.distance_squared_to(p.pos) > B.range * B.range:
		return {"ok": false, "reason": "Too far"}

	# Never let a solid piece trap anyone — or anything — inside its tile.
	if def.solid:
		var half: float = Config.TILE * 0.5
		for q in sim.players:
			if q.dead:
				continue
			if absf(centre.x - q.pos.x) < half + q.r and absf(centre.y - q.pos.y) < half + q.r:
				return {"ok": false, "reason": "You are standing there" if q == p else "%s is standing there" % q.display_name}
		for e in sim.enemies.list:
			if e.dead:
				continue
			if absf(centre.x - e.pos.x) < half + e.r and absf(centre.y - e.pos.y) < half + e.r:
				return {"ok": false, "reason": "Enemy in the way"}
	# Loot cannot be buried: a container blocks its own tile in the terrain
	# bitmap, so "Blocked" above has already refused it. The prototype
	# carried a separate check here; here it could never fire.
	if not p.can_afford(sim, def.cost, p.build_cost_mul):
		return {"ok": false, "reason": "Not enough materials"}
	return {"ok": true, "reason": ""}


func make(sim: GameSim, type: String, tx: int, ty: int, hp_mul := 1.0) -> Dictionary:
	var def: Dictionary = Config.STRUCTURES[type]
	var max_hp := roundf(def.hp * hp_mul)
	var store: Slots = null
	if def.has("store"):
		# A Supply Stash is a door into the base's one shared pile, not a pile
		# of its own: survivors and towers read that pile and must not have to
		# guess which of your three stashes the rations are in. Everything else
		# with a store gets its own.
		if type == "stash":
			if sim.stash == null:
				sim.stash = Slots.new(Config.STASH_SLOTS)
			store = sim.stash
		else:
			store = Slots.new(def.store)
	var s := {
		"type": type, "def": def, "tx": tx, "ty": ty,
		"pos": Vector2(tx * Config.TILE + Config.TILE / 2.0, ty * Config.TILE + Config.TILE / 2.0),
		"hp": max_hp, "max_hp": max_hp, "solid": def.solid, "flash": 0.0,
		"open": false, "cd": 0.0, "ammo": 0, "reload_t": 0.0, "aim": 0.0,
		"fuel": 0.0, "on": true, "running": false, "powered": false, "starved": false,
		"noise_t": 0.0, "tier": 1, "destroyed": false, "active": false,
		"store": store,
		# Which armament a manned tower is set to. Arrows until told
		# otherwise, so a tower is never a thing you built that does nothing.
		"arm": Config.DEFAULT_ARMAMENT if def.get("post", "") == "sniper" else "",
	}
	list.append(s)
	grid[key(tx, ty)] = s
	if s.solid:
		# A new wall is a new obstacle: the flow fields have to be rebuilt or
		# the horde walks through it in spirit.
		sim.world_version += 1
	return s


func place(sim: GameSim, type: String, tx: int, ty: int, p: PlayerSim) -> Dictionary:
	var check := can_place(sim, type, tx, ty, p)
	if not check.ok:
		sim.notify(check.reason, "#c96a5a")
		return {}
	var def: Dictionary = Config.STRUCTURES[type]
	p.spend(sim, def.cost, p.build_cost_mul)
	# Wall strength is a base-wide number, so it comes off the host's build.
	var s := make(sim, type, tx, ty, sim.host().struct_hp_mul if sim.host() != null else 1.0)

	if type == "bedroll":
		for q in sim.players:
			if q.spawn_tile == Vector2i(tx, ty):
				q.spawn_tile = Vector2i(-1, -1)
		p.spawn_tile = Vector2i(tx, ty)
		refresh_bedrolls(sim)
		sim.notify("Respawn point set", "#b7e08a", true)
	if type == "workbench":
		bench_tier = maxi(bench_tier, 1)

	sim.emit({"t": "built", "x": s.pos.x, "y": s.pos.y, "type": type})
	sim.threat.add(sim, Config.THREAT.per_build * def.threat, p)
	# Hammering carries. Threat is the slow half of "building draws a horde";
	# this is the immediate, local half.
	Sound.make_noise(sim, s.pos.x, s.pos.y, Config.NOISE.build, p)
	Progression.add_xp(sim, p, maxi(2, roundi(def.threat * 4.0 + 3.0)), "BUILD")
	return s


## Marks the bedroll that is somebody's respawn point, for the view.
func refresh_bedrolls(sim: GameSim) -> void:
	for s in list:
		if s.type != "bedroll":
			continue
		s.active = false
		for q in sim.players:
			if q.spawn_tile == Vector2i(s.tx, s.ty):
				s.active = true


# ----------------------------------------------------------------- damage --

func damage(sim: GameSim, s: Dictionary, amount: float, from := Vector2.INF) -> float:
	if s.is_empty() or s.destroyed or amount <= 0.0:
		return 0.0
	s.hp -= amount
	s.flash = 0.12
	sim.stats.structure_damage = sim.stats.get("structure_damage", 0.0) + amount
	sim.emit({"t": "struct_hit", "x": s.pos.x, "y": s.pos.y, "wall": s.def.get("wall", false)})
	if s.hp <= 0.0:
		destroy(sim, s)
	return amount


func destroy(sim: GameSim, s: Dictionary) -> void:
	if s.destroyed:
		return
	s.destroyed = true
	# Whatever was in it comes out. Nothing is destroyed for want of
	# somewhere to put it, not even by a brute.
	spill_store(sim, s)
	_unlink(s)
	sim.world_version += 1
	sim.emit({"t": "struct_down", "x": s.pos.x, "y": s.pos.y, "wall": s.def.get("wall", false)})
	sim.emit({"t": "shake", "amount": 4.0})
	if sim.raid != null:
		sim.notify("%s destroyed!" % s.def.name, "#e05a4a")
	_after_removed(sim, s)


## What has to be true again once a piece has left the map, however it left:
## a bedroll takes its respawn point with it, and the bench tier is what the
## benches still standing say it is. Both paths call this — the version that
## only ran on destruction let you salvage your only Workbench II and go on
## building steel walls for ever.
func _after_removed(sim: GameSim, s: Dictionary) -> void:
	for q in sim.players:
		if s.type == "bedroll" and q.spawn_tile == Vector2i(s.tx, s.ty):
			q.spawn_tile = Vector2i(-1, -1)
	if s.type == "workbench":
		bench_tier = 0
		for o in list:
			if o.type == "workbench" and not o.destroyed:
				bench_tier = maxi(bench_tier, o.tier)


func _unlink(s: Dictionary) -> void:
	var k := key(s.tx, s.ty)
	if grid.get(k) == s:
		grid.erase(k)
	list.erase(s)


## A container that stops existing drops what was in it. A Supply Stash is
## the exception with a reason: every stash is a door into one shared pile,
## so knocking one over while another stands would empty the base's whole
## pantry onto the ground. It spills only when it was the last door.
func spill_store(sim: GameSim, s: Dictionary) -> int:
	if s.store == null:
		return 0
	if s.type == "stash":
		for o in list:
			if o != s and o.type == "stash" and not o.destroyed:
				return 0
	var spilled := 0
	var entries: Dictionary = s.store.entries()
	for id in entries:
		var n: int = entries[id]
		if n <= 0:
			continue
		s.store.take(id, n)
		var at: Vector2 = s.pos + Vector2(sim.loot_rng.frange(-13, 13), sim.loot_rng.frange(-13, 13))
		Loot.spawn_entry_pickup(sim, at, Loot.item_entry_id(id), n)
		spilled += n
	if s.type == "stash":
		# The last door into the shared pile has gone, and the pile is on the
		# ground. Leaving `sim.stash` pointing at the empty container would
		# leave every path that writes to it — raid salvage, crafting
		# overflow, a demolition refund — depositing into something nobody
		# can open.
		sim.stash = null
	return spilled


# ----------------------------------------------------------------- repair --

static func is_damaged(s: Dictionary) -> bool:
	return not s.is_empty() and not s.destroyed and s.hp / s.max_hp < 0.999


## What it costs to bring `s` back to full: a share of the build price
## scaled by how much is missing. A material the damage would not plausibly
## have consumed drops off the bill — a scratch on a steel wall does not
## cost a weapon part — but the main material is always at least one, so no
## repair is ever free.
static func repair_cost(s: Dictionary, cost_mul := 1.0) -> Dictionary:
	if not is_damaged(s):
		return {}
	var frac: float = 1.0 - s.hp / s.max_hp
	var out := {}
	var main_id := ""
	var main_n := -1
	for id in s.def.cost:
		var c: int = s.def.cost[id]
		if c > main_n:
			main_n = c
			main_id = id
		var n := roundi(c * frac * B.repair_cost_share * cost_mul)
		if n > 0:
			out[id] = n
	if not main_id.is_empty() and not out.has(main_id):
		out[main_id] = 1
	return out


func repair(sim: GameSim, s: Dictionary, p: PlayerSim) -> bool:
	var cost := repair_cost(s, p.build_cost_mul)
	if cost.is_empty():
		sim.notify("Already intact", "#8a8f84")
		return false
	if not p.can_afford(sim, cost):
		sim.notify("Not enough materials to repair — needs %s" % cost_label(cost), "#c96a5a")
		return false
	p.spend(sim, cost)
	_restore(sim, s, p)
	sim.notify("Repaired %s — %s" % [s.def.name, cost_label(cost)], "#7ce08a")
	return true


func _restore(sim: GameSim, s: Dictionary, p: PlayerSim) -> void:
	s.hp = s.max_hp
	sim.emit({"t": "repaired", "x": s.pos.x, "y": s.pos.y})
	Progression.add_xp(sim, p, 3, "REPAIR")


## "WOOD 4 · SCRP 2" — one way to print a bill, used by every prompt.
static func cost_label(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for id in cost:
		var def: Dictionary = Config.RES.get(id, {})
		parts.append("%s %d" % [def.get("short", id.to_upper()), cost[id]])
	return " · ".join(parts)


func damaged_within(at: Vector2, radius := B.repair_all_range) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in list:
		if not is_damaged(s):
			continue
		if at.distance_squared_to(s.pos) > radius * radius:
			continue
		out.append(s)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.hp / a.max_hp < b.hp / b.max_hp)
	return out


## The bill for a REPAIR ALL from where `p` stands: which pieces it would
## fix, in the order it would fix them, and what that comes to. Pieces the
## player cannot pay for are skipped rather than stopping the sweep, so one
## steel wall you cannot afford never blocks the wood walls behind it.
## `repair_all` runs exactly this plan, so the label is what the button does.
func plan_repair_all(sim: GameSim, p: PlayerSim, radius := B.repair_all_range) -> Dictionary:
	var ledger := {}
	var plan := {"pieces": [], "cost": {}, "repairable": 0, "skipped": 0}
	for s in damaged_within(p.pos, radius):
		var cost := repair_cost(s, p.build_cost_mul)
		var ok := true
		for id in cost:
			if not ledger.has(id):
				ledger[id] = p.total_res(sim, id)
			if ledger[id] < cost[id]:
				ok = false
		if ok:
			for id in cost:
				ledger[id] -= cost[id]
				plan.cost[id] = plan.cost.get(id, 0) + cost[id]
			plan.repairable += 1
		else:
			plan.skipped += 1
		plan.pieces.append({"s": s, "cost": cost, "ok": ok})
	return plan


func repair_all(sim: GameSim, p: PlayerSim, radius := B.repair_all_range) -> int:
	var plan := plan_repair_all(sim, p, radius)
	if plan.pieces.is_empty():
		sim.notify("Nothing in range needs repair", "#8a8f84")
		return 0
	if plan.repairable == 0:
		sim.notify("Not enough materials to repair anything here", "#c96a5a")
		return 0
	var n := 0
	for entry in plan.pieces:
		if not entry.ok or entry.s.destroyed:
			continue
		p.spend(sim, entry.cost)
		_restore(sim, entry.s, p)
		n += 1
	var tail := "  ·  %d more need materials" % plan.skipped if plan.skipped > 0 else ""
	sim.notify("Repaired %d piece%s — %s%s" % [n, "" if n == 1 else "s", cost_label(plan.cost), tail], "#7ce08a", true)
	return n


# -------------------------------------------------------------- demolition --

func demolish(sim: GameSim, s: Dictionary, p: PlayerSim) -> bool:
	if s.is_empty() or s.destroyed:
		return false
	# The refund is a share of what this player *paid*, not of the list price.
	# Without the build multiplier, Engineer at rank 3 builds for 0.47 and
	# salvages for 0.55, and a wall you put up and took down again is profit.
	var refund: float = B.salvage_share * (s.hp / s.max_hp) * p.build_cost_mul
	var lines := 0
	for id in s.def.cost:
		var n := floori(s.def.cost[id] * refund)
		if n > 0:
			Loot.stash_or_drop(sim, id, n, s.pos)
			lines += 1
	# Whatever was stored in it comes out first: taking your own full chest
	# apart must not delete what is inside it.
	spill_store(sim, s)
	s.destroyed = true
	_unlink(s)
	sim.world_version += 1
	_after_removed(sim, s)
	sim.emit({"t": "struct_down", "x": s.pos.x, "y": s.pos.y, "wall": s.def.get("wall", false)})
	sim.notify("Salvaged %s" % s.def.name if lines > 0 else "Removed %s" % s.def.name, "#c9a227")
	return true


# ------------------------------------------------------------------ power --

func has_power(at: Vector2) -> bool:
	for s in list:
		if s.type != "generator" or s.destroyed:
			continue
		if not generator_running(s):
			continue
		var r: float = s.def.power_radius
		if at.distance_squared_to(s.pos) <= r * r:
			return true
	return false


static func generator_running(s: Dictionary) -> bool:
	return s.on and s.fuel > 0.0


## One key does both jobs, but switching *off* always takes priority:
## routing every press through refuelling meant a half-full generator with no
## spare fuel could never be shut up, which flatly contradicts lying low.
func use_generator(sim: GameSim, s: Dictionary, p: PlayerSim) -> bool:
	if generator_running(s):
		s.on = false
		s.running = false
		sim.notify("Generator off", "#d8e8c0")
		return true
	var need := ceili(s.def.fuel_max - s.fuel)
	var got := 0
	if need > 0:
		got = p.bag.take("fuel", need)
		if got < need and sim.stash != null:
			got += sim.stash.take("fuel", need - got)
		if got > 0:
			s.fuel = minf(s.def.fuel_max, s.fuel + got)
	if s.fuel <= 0.0:
		sim.notify("No fuel — find some before this will run", "#c96a5a")
		return false
	s.on = true
	sim.notify("Generator refuelled and running" if got > 0 else "Generator on", "#b7e08a")
	return true


func upgrade_bench(sim: GameSim, s: Dictionary, p: PlayerSim) -> bool:
	if s.tier >= 2:
		sim.notify("Already upgraded", "#8a8f84")
		return false
	if not p.can_afford(sim, Config.BENCH_UPGRADE_COST):
		sim.notify("Need %s" % cost_label(Config.BENCH_UPGRADE_COST), "#c96a5a")
		return false
	p.spend(sim, Config.BENCH_UPGRADE_COST)
	s.tier = 2
	bench_tier = 2
	sim.notify("WORKBENCH II — advanced weapons and steel unlocked", "#59b8c4", true)
	Progression.add_xp(sim, p, 60, "WORKBENCH II")
	sim.threat.add(sim, 4.0, p)
	return true


func toggle_gate(sim: GameSim, s: Dictionary) -> bool:
	s.open = not s.open
	sim.world_version += 1
	sim.notify("Gate open" if s.open else "Gate closed", "#d8e8c0")
	return true


# ------------------------------------------------------------------- step --

func tick(sim: GameSim, dt: float) -> void:
	_tick_generators(sim, dt)
	for s in list:
		if s.destroyed:
			continue
		s.flash = maxf(0.0, s.flash - dt)
		if s.def.get("powered", false):
			s.powered = has_power(s.pos)
	_tick_turrets(sim, dt)
	_tick_traps(sim, dt)


func _tick_generators(sim: GameSim, dt: float) -> void:
	for s in list:
		if s.type != "generator" or s.destroyed:
			continue
		if not generator_running(s):
			s.running = false
			continue
		s.running = true
		s.fuel = maxf(0.0, s.fuel - s.def.fuel_burn * dt)
		sim.threat.add(sim, Config.THREAT.generator_per_sec * dt)
		# The loudest thing in a base, and it was silent to the AI. Pulsed
		# rather than continuous: a sweep every other second is the same
		# behaviour at a fraction of the cost.
		s.noise_t -= dt
		if s.noise_t <= 0.0:
			s.noise_t = 2.0
			Sound.make_noise(sim, s.pos.x, s.pos.y, Config.NOISE.generator, null)
		if s.fuel <= 0.0:
			sim.notify("Generator out of fuel", "#d98a4a")


func _tick_turrets(sim: GameSim, dt: float) -> void:
	# Turret power is a base-wide number off the host's build (Fire Control,
	# and Intelligence). Range gets half the bonus damage does: a turret that
	# reached across the compound would stop the walls mattering.
	var owner := sim.host()
	var turret_mul: float = owner.turret_mul if owner != null else 1.0
	for s in list:
		if s.type != "turret" or s.destroyed:
			continue
		var def: Dictionary = s.def
		s.cd = maxf(0.0, s.cd - dt)
		if not s.powered:
			continue

		# Reload from the stash, falling back to whatever anyone is carrying.
		if s.ammo <= 0:
			s.reload_t += dt
			if s.reload_t >= def.reload:
				s.reload_t = 0.0
				var got := 0
				if sim.stash != null:
					got = sim.stash.take("ammoP", def.mag)
				for q in sim.players:
					if got > 0:
						break
					got = q.bag.take("ammoP", def.mag)
				s.ammo = got
				s.starved = got == 0
			continue
		s.starved = false

		# Nearest live enemy in range that the turret can actually hit.
		# Without the sight test it happily locks onto something behind a
		# tree and pumps its whole magazine into the trunk.
		var range_: float = def.range * (1.0 + (turret_mul - 1.0) * 0.5)
		sim.enemies.hash.query(s.pos.x, s.pos.y, range_, sim.enemies._scratch)
		var best: EnemySim = null
		var bd := range_ * range_
		for e: EnemySim in sim.enemies._scratch:
			if e.dead:
				continue
			var d: float = s.pos.distance_squared_to(e.pos)
			if d < bd and sim.world.has_terrain_line_of_sight(s.pos, e.pos):
				bd = d
				best = e
		if best == null:
			continue

		var want: float = (best.pos - s.pos).angle()
		var delta := Enemies.angle_delta(s.aim, want)
		s.aim += clampf(delta, -7.0 * dt, 7.0 * dt)
		if absf(delta) < 0.22 and s.cd <= 0.0:
			s.cd = def.fire_cd
			s.ammo -= 1
			var a: float = s.aim + sim.rng.frange(-0.035, 0.035)
			Combat.spawn_bullet(sim, s.pos + Vector2.from_angle(a) * 18.0, a, 1300.0, def.dmg * turret_mul, 0.5, 45.0, 0, null, false, "turret", "#9fe0ff")
			sim.emit({"t": "muzzle", "x": s.pos.x + cos(a) * 20.0, "y": s.pos.y + sin(a) * 20.0, "a": a, "w": "turret"})
			sim.threat.add(sim, Config.THREAT.turret_per_shot)
			# A machine gun on a post pulls the horde onto itself, which is
			# the trade an arrow tower exists to offer an alternative to.
			Sound.make_noise(sim, s.pos.x, s.pos.y, Config.NOISE.turret, null)


func _tick_traps(sim: GameSim, dt: float) -> void:
	# Spikes are structure, so Fortifier sharpens them — at a reduced rate,
	# because a perk about walls standing up should not quietly become the
	# best source of damage in the base.
	var owner := sim.host()
	var trap_mul := 1.0 + (owner.struct_hp_mul - 1.0) * 0.4 if owner != null else 1.0
	for i in range(list.size() - 1, -1, -1):
		var s: Dictionary = list[i]
		if s.type != "spike" or s.destroyed:
			continue
		s.cd = maxf(0.0, s.cd - dt)
		if s.cd > 0.0:
			continue
		var def: Dictionary = s.def
		sim.enemies.hash.query(s.pos.x, s.pos.y, Config.TILE, sim.enemies._scratch)
		var hit := false
		for e: EnemySim in sim.enemies._scratch:
			if e.dead:
				continue
			if absf(e.pos.x - s.pos.x) < Config.TILE * 0.62 and absf(e.pos.y - s.pos.y) < Config.TILE * 0.62:
				Damage.damage_enemy(sim, e, def.trap_dmg * trap_mul, s.pos, 30.0)
				e.slow_t = 0.5
				hit = true
		if hit:
			s.cd = def.trap_cd
			# Traps are consumable: repair or replace.
			s.hp -= 8.0
			sim.emit({"t": "struct_hit", "x": s.pos.x, "y": s.pos.y, "wall": false})
			if s.hp <= 0.0:
				destroy(sim, s)


# ---------------------------------------------------------------- storage --

## Empties the haul into a container: raw materials and ammunition, plus
## consumables above a working supply of four. Weapons, gear and the
## bandages in your pocket stay on you — a deposit-all that stripped your
## rifle would be a trap rather than a convenience.
func deposit_all(sim: GameSim, p: PlayerSim, store: Slots) -> int:
	if store == null:
		return 0
	var moved := 0
	var left := 0
	var entries: Dictionary = p.bag.entries()
	for id in entries:
		var n: int = entries[id]
		var kind := Items.kind_of(id)
		var want := 0
		if kind == "res":
			want = n
		elif kind == "consumable" and n > 4:
			want = n - 4
		if want <= 0:
			continue
		var got := store.add(id, want)
		if got > 0:
			p.bag.take(id, got)
		moved += got
		left += want - got
	if moved > 0:
		sim.notify("Deposited %d — no room for %d more" % [moved, left] if left > 0 else "Deposited %d items" % moved,
			"#d9c46a" if left > 0 else "#b7e08a")
	elif left > 0:
		sim.notify("That container is full", "#c96a5a")
	else:
		sim.notify("Nothing to deposit", "#8a8f84")
	return moved


const WITHDRAW_IDS := ["ammoP", "ammoS", "ammoR", "arrow", "med", "fuel", "battery"]

## Pulls the going-out list back out before a trip: ammunition, medical,
## fuel and consumables. Building material stays put — nobody wants
## deposit-all and take-all to be a loop.
func withdraw_supplies(sim: GameSim, p: PlayerSim, store: Slots) -> int:
	if store == null:
		return 0
	var moved := 0
	var entries: Dictionary = store.entries()
	for id in entries:
		var have: int = entries[id]
		if have <= 0:
			continue
		if not (Items.kind_of(id) == "consumable" or WITHDRAW_IDS.has(id)):
			continue
		var got := p.bag.add_capped(id, have, p.pack_allowance())
		store.take(id, got)
		moved += got
	sim.notify("Took %d items" % moved if moved > 0 else "Nothing there worth taking out",
		"#b7e08a" if moved > 0 else "#8a8f84")
	return moved
