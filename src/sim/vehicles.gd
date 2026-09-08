class_name Vehicles
extends RefCounted
## Cars. About thirty of them across the town, most locked, most nearly dry.
##
## A car is the answer to distance, and the cost is noise: an engine is heard
## six hundred pixels away and climbs Threat while it runs, so driving across
## town is a decision rather than a free fast-travel. Pillar 6 again — getting
## stronger makes the world more dangerous.
##
## **A parked car blocks the tiles it sits on**, exactly like the scenery the
## generator made it from, and driving releases them. The tiles a car claimed
## are tracked precisely rather than recomputed, so releasing one never clears
## a tree that was already there.

const C := Config.CAR

var list: Array[Dictionary] = []
var seq := 0

var _scratch: Array[EnemySim] = []


func reset() -> void:
	list.clear()
	seq = 0


## Turns the generator's parked-car markers into real vehicles. Drawn from a
## stream of its own, so how many cars you break into cannot shift the world's
## or the spawner's numbers.
func spawn_all(world: World) -> int:
	list.clear()
	seq = 0
	for spot in world.vehicle_spawns:
		var r := Rng.new(int(spot.seed))
		seq += 1
		var locked := r.chance(C.locked_chance)
		list.append({
			"id": seq,
			"pos": Vector2(spot.x, spot.y),
			"prev_pos": Vector2(spot.x, spot.y),
			"angle": float(spot.rot),
			"speed": 0.0,
			"si": int(spot.si),
			"hp": C.max_hp * r.frange(0.45, 1.0),
			"max_hp": float(C.max_hp),
			"fuel": r.frange(18.0, C.fuel_max) if r.chance(C.full_tank_chance) else r.frange(0.0, 9.0),
			"locked": locked,
			"key_id": "key%d" % r.irange(1000, 9999) if locked else "",
			"key_hint": "",
			"hotwired": false,
			# A Slots like every other container, so the two-panel store screen
			# opens it without a second kind of storage UI existing.
			"trunk": Slots.new(C.trunk_slots),
			"engine_on": false,
			"destroyed": false,
			"flash": 0.0,
			"noise_t": 0.0,
			# The tiles this car is currently blocking. Copied from the spawn
			# marker, which already blocked them during generation.
			"tiles": spot.tiles.duplicate(),
		})
	return list.size()


func by_id(id: int) -> Dictionary:
	for v in list:
		if v.id == id and not v.destroyed:
			return v
	return {}


## The car this player is at the wheel of, if any.
func driven_by(p: PlayerSim) -> Dictionary:
	return by_id(p.driving_id) if p.driving_id > 0 else {}


func driver_of(sim: GameSim, v: Dictionary) -> PlayerSim:
	for q in sim.players:
		if q.driving_id == v.id:
			return q
	return null


func nearest(at: Vector2, range_: float = C.enter_range) -> Dictionary:
	var best := {}
	var bd := range_ * range_
	for v in list:
		var d: float = at.distance_squared_to(v.pos)
		if d < bd:
			bd = d
			best = v
	return best


# ------------------------------------------------------------------- locks --

func has_key_for(p: PlayerSim, v: Dictionary) -> bool:
	return not String(v.key_id).is_empty() and p.car_keys.has(v.key_id)


## Never certain, never hopeless — Perception moves it, it does not settle it.
static func pick_chance(p: PlayerSim) -> float:
	var per: int = int(p.attrs.get("per", 1))
	return clampf(C.pick_base_chance + per * C.pick_per_perception, C.pick_min, C.pick_max)


## What the interact prompt says for this car, which is also the list of what
## you could do about it.
func prompt(p: PlayerSim, v: Dictionary) -> String:
	if v.destroyed:
		return "Strip the wreck"
	if not v.locked or v.hotwired:
		return "Drive" if v.fuel > 0.5 else "Drive  (no fuel)"
	if has_key_for(p, v):
		return "Unlock with your key"
	var bits: Array[String] = []
	if p.count_carried("lockpick") > 0:
		bits.append("Pick lock (%d%%)" % roundi(pick_chance(p) * 100.0))
	if p.hotwire:
		bits.append("Hotwire")
	if bits.is_empty():
		return "Locked — needs a key, a pick, or hotwiring"
	return "  ·  ".join(bits)


## Tries to get into a locked car. True when the door is now open. Order of
## preference: your key, then a pick, then hotwiring — cheapest first, because
## a pick is consumed and hotwiring is loud.
func try_unlock(sim: GameSim, p: PlayerSim, v: Dictionary) -> bool:
	if not v.locked or v.hotwired:
		return true

	if has_key_for(p, v):
		v.locked = false
		p.car_keys.erase(v.key_id)
		sim.notify("The key turns. It is yours.", "#b7e08a", true)
		Progression.add_xp(sim, p, 25, "UNLOCK")
		return true

	if p.count_carried("lockpick") > 0:
		# Picking takes time, like hotwiring and healing do, and can be
		# interrupted by being hit. Resolving it on the interaction frame made
		# `pick_time` a number nothing read.
		p.using = {"id": "pick", "t": 0.0, "dur": C.pick_time, "vehicle": v.id}
		sim.notify("Working the lock — stay still", "#d9c46a")
		return false

	if p.hotwire:
		p.using = {"id": "hotwire", "t": 0.0,
			"dur": C.hotwire_time * p.hotwire_speed_mul, "vehicle": v.id}
		sim.notify("Hotwiring — stay still", "#d9c46a")
		return false

	sim.notify("Locked. Find the key, a lockpick, or learn to hotwire.", "#c96a5a")
	return false


## The pick attempt itself, once the held action has run its time.
func finish_pick(sim: GameSim, p: PlayerSim, v: Dictionary) -> void:
	if v.is_empty() or v.destroyed or not v.locked:
		return
	# The pick could have gone somewhere between the press and the finish.
	if p.bag.take("lockpick", 1) < 1 and p.hotbar.take("lockpick", 1) < 1:
		sim.notify("No pick left", "#c96a5a")
		return
	if sim.rng.chance(pick_chance(p)):
		v.locked = false
		sim.notify("The lock gives", "#b7e08a")
		Progression.add_xp(sim, p, 30, "PICK")
		return
	# A failed pick snaps the tool and makes noise. That is the whole cost of
	# the cheap way in.
	sim.notify("The pick snaps. Something heard that.", "#c96a5a")
	sim.emit({"t": "pick_snap", "x": v.pos.x, "y": v.pos.y})
	Sound.make_noise(sim, v.pos.x, v.pos.y, Config.NOISE.pick_snap, p)
	sim.threat.add(sim, 0.6, p)


func finish_hotwire(sim: GameSim, p: PlayerSim, v: Dictionary) -> void:
	if v.is_empty() or v.destroyed:
		return
	v.hotwired = true
	v.locked = false
	sim.notify("Engine catches. Loud, but it runs.", "#b7e08a", true)
	Sound.make_noise(sim, v.pos.x, v.pos.y, Config.NOISE.engine, p)
	sim.threat.add(sim, 2.0, p)
	Progression.add_xp(sim, p, 45, "HOTWIRE")


# ------------------------------------------------------------ in and out --

func enter(sim: GameSim, p: PlayerSim, v: Dictionary) -> bool:
	if v.destroyed:
		return false
	# One seat. A second driver would share the car's id, be treated as
	# driving, and be read by nobody — stranded until the first got out.
	var other := driver_of(sim, v)
	if other != null and other != p:
		sim.notify("%s is driving that one" % other.display_name, "#c96a5a")
		return false
	if v.locked and not v.hotwired:
		return enter(sim, p, v) if try_unlock(sim, p, v) else false

	p.driving_id = v.id
	p.searching = {}
	v.engine_on = true
	v.speed = 0.0
	release_tiles(sim, v)            # it is no longer scenery in the way
	sim.emit({"t": "enter_car", "x": v.pos.x, "y": v.pos.y})
	sim.notify("W/S to drive, A/D to steer, E to get out" if v.fuel > 0.5
		else "No fuel. You will need some.", "#d8e8c0")
	return true


## `which` lets the wrecking path pass the car explicitly: `driven_by` filters
## out destroyed vehicles, so resolving through it after marking one destroyed
## would silently fail to clear `driving_id` and strand the player with
## neither walking nor combat.
func exit(sim: GameSim, p: PlayerSim, which: Dictionary = {}) -> bool:
	var v := which if not which.is_empty() else driven_by(p)
	if v.is_empty():
		return false
	p.driving_id = 0
	v.engine_on = false
	v.speed = 0.0
	occupy_tiles(sim, v)             # parked again, so it blocks again
	# Step out beside the car, never inside a wall.
	for i in range(12):
		var a: float = v.angle + PI / 2.0 + (1.0 if i % 2 else -1.0) * PI * (float(i) / 12.0)
		var at: Vector2 = v.pos + Vector2.from_angle(a) * C.exit_range
		if not sim.world.is_blocked_px(at.x, at.y, sim.structs):
			p.pos = at
			break
	p.vel = Vector2.ZERO
	sim.emit({"t": "exit_car", "x": v.pos.x, "y": v.pos.y})
	return true


# ------------------------------------------------------------------- step --

func tick(sim: GameSim, dt: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		var v: Dictionary = list[i]
		v.flash = maxf(0.0, v.flash - dt)
		if v.destroyed:
			continue
		v.prev_pos = v.pos
		var p := driver_of(sim, v)
		if p == null or p.dead:
			if p != null and p.dead:
				exit(sim, p, v)
			continue
		_drive(sim, v, dt, p)
		# The car owns where its driver is. Set after driving, not before: the
		# players tick ahead of the cars, so copying it there would leave the
		# driver a frame behind the car they are sitting in.
		if p.driving_id == v.id:
			p.pos = v.pos
			p.angle = v.angle


func _drive(sim: GameSim, v: Dictionary, dt: float, p: PlayerSim) -> void:
	var it := p.intent
	var dry: bool = v.fuel <= 0.0

	# ---------------------------------------------------------- throttle --
	var thrust := 0.0
	if not dry:
		if it.my < 0.0:
			thrust = C.accel
		elif it.my > 0.0:
			thrust = -C.reverse_accel
	if it.sprint:
		var s := signf(v.speed)
		v.speed -= s * C.brake * dt
		if signf(v.speed) != s:
			v.speed = 0.0

	v.speed += thrust * dt
	v.speed -= v.speed * C.drag * dt
	v.speed = clampf(v.speed, -C.max_reverse, C.max_speed)
	if absf(v.speed) < 2.0:
		v.speed = 0.0

	# ---------------------------------------------------------- steering --
	# Authority scales with speed, so a stationary car cannot spin on the spot.
	var grip := clampf(absf(v.speed) / C.steer_at_speed, 0.0, 1.0)
	var dir := -1.0 if v.speed < 0.0 else 1.0
	v.angle += it.mx * C.steer * grip * dir * dt

	# -------------------------------------------------------------- move --
	var step: float = v.speed * dt
	var to: Vector2 = v.pos + Vector2.from_angle(v.angle) * step
	# Cars collide with what you built as well as with terrain: a car that
	# drives through your own gate makes the gate pointless. The driven car
	# released its own tiles, so it cannot collide with itself.
	var hit_x := sim.world.is_blocked_px(to.x, v.pos.y, sim.structs)
	var hit_y := sim.world.is_blocked_px(v.pos.x, to.y, sim.structs)
	if not hit_x:
		v.pos.x = to.x
	if not hit_y:
		v.pos.y = to.y

	if hit_x or hit_y:
		var impact := absf(v.speed)
		if impact > C.crash_speed:
			damage(sim, v, (impact - C.crash_speed) * C.crash_damage_per, "crash")
			sim.emit({"t": "shake", "amount": clampf(impact * 0.02, 2.0, 8.0)})
			Sound.make_noise(sim, v.pos.x, v.pos.y, Config.NOISE.crash, p)
		v.speed *= -0.15
	var lim: float = Config.WORLD_SIZE - 40.0
	v.pos.x = clampf(v.pos.x, 40.0, lim)
	v.pos.y = clampf(v.pos.y, 40.0, lim)

	if v.destroyed:
		return

	# ---------------------------------------------------------- roadkill --
	if absf(v.speed) > C.ram_speed:
		sim.enemies.hash.query(v.pos.x, v.pos.y, C.r + 26.0, _scratch)
		for e: EnemySim in _scratch:
			if e.dead:
				continue
			var reach: float = C.r + e.r
			if v.pos.distance_squared_to(e.pos) > reach * reach:
				continue
			var force := absf(v.speed) / C.max_speed
			# The driver made this kill: their XP, and their Luck on the drop.
			Damage.damage_enemy(sim, e, C.ram_damage * force * 2.0, v.pos, 340.0 * force, true, p)
			damage(sim, v, C.ram_self_damage * (1.0 + force), "ram")
			v.speed *= 0.86
			sim.emit({"t": "shake", "amount": 3.0})
			if v.destroyed:
				return

	# ------------------------------------------------------ fuel and noise --
	# A running engine burns whether or not it is going anywhere: `burn_per_sec`
	# is the *idle* rate, and gating the whole thing on movement let a car sit
	# there running for free.
	if not dry:
		v.fuel = maxf(0.0, v.fuel - (C.burn_per_sec + absf(v.speed) * C.burn_per_speed) * dt)
		if v.fuel <= 0.0:
			sim.notify("Out of fuel", "#d98a4a", true)
	if absf(v.speed) > C.quiet_speed:
		var loud := absf(v.speed) / C.max_speed
		sim.threat.add(sim, C.threat_per_sec * dt * loud, p)
		v.noise_t -= dt
		if v.noise_t <= 0.0:
			v.noise_t = C.noise_every
			Sound.make_noise(sim, v.pos.x, v.pos.y, C.noise_radius * loud, p)


# ------------------------------------------------------------------ damage --

func damage(sim: GameSim, v: Dictionary, dmg: float, cause := "hit") -> void:
	if v.destroyed or dmg <= 0.0:
		return
	v.hp -= dmg
	v.flash = 0.1
	if v.hp <= 0.0:
		_wreck(sim, v, cause)


func _wreck(sim: GameSim, v: Dictionary, cause: String) -> void:
	# Get the driver out *before* the car is marked destroyed — see `exit`.
	var p := driver_of(sim, v)
	if p != null:
		exit(sim, p, v)
	v.destroyed = true
	v.hp = 0.0
	# Anything in the boot spills onto the road rather than leaving with it.
	var held: Dictionary = v.trunk.entries()
	for id in held:
		var n := int(held[id])
		if n > 0:
			Loot.spawn_entry_pickup(sim, v.pos, Loot.item_entry_id(String(id)), n)
	v.trunk.clear_all()
	sim.emit({"t": "car_wrecked", "x": v.pos.x, "y": v.pos.y, "cause": cause})
	sim.emit({"t": "shake", "amount": 8.0})
	sim.notify("The car is finished", "#c96a5a", true)




# -------------------------------------------------------------- the boot --

## What the boot is carrying, by count. The cap is bulk rather than slots: a
## boot takes a haul, not a collection.
static func trunk_load(v: Dictionary) -> int:
	var n := 0
	var e: Dictionary = v.trunk.entries()
	for id in e:
		n += int(e[id])
	return n


func trunk_room(v: Dictionary) -> int:
	return maxi(0, int(C.trunk_cap) - trunk_load(v))


## Raw materials only. The boot is for the haul, not for your rifle or the
## bandages you are about to need.
func stow(sim: GameSim, v: Dictionary, p: PlayerSim) -> int:
	var moved := 0
	for id in Config.RES:
		var room := trunk_room(v)
		if room <= 0:
			break
		var have := p.bag.count(String(id))
		if have <= 0:
			continue
		var take := p.bag.take(String(id), mini(have, room))
		if take <= 0:
			continue
		var put: int = v.trunk.add(String(id), take)
		# Whatever the boot could not physically hold goes back in the pack
		# rather than evaporating between the two.
		if put < take:
			p.bag.add(String(id), take - put)
		moved += put
	if moved > 0:
		sim.notify("%d units into the boot" % moved, "#b7e08a")
	else:
		sim.notify("Nothing to stow, or the boot is full", "#8a8f84")
	return moved


func unload(sim: GameSim, v: Dictionary, p: PlayerSim) -> int:
	var moved := 0
	var held: Dictionary = v.trunk.entries()
	for id in held:
		var n := int(held[id])
		if n <= 0:
			continue
		var got := p.bag.add_capped(String(id), n, p.pack_allowance())
		if got > 0:
			v.trunk.take(String(id), got)
			moved += got
	if moved > 0:
		sim.notify("%d units out of the boot" % moved, "#b7e08a")
	else:
		sim.notify("Nothing you can carry", "#8a8f84")
	return moved
func refuel(sim: GameSim, v: Dictionary, p: PlayerSim) -> bool:
	var need := ceili(C.fuel_max - v.fuel)
	if need <= 0:
		sim.notify("Tank is full", "#8a8f84")
		return false
	var took := p.bag.take("fuel", need)
	if took < need and sim.stash != null:
		took += sim.stash.take("fuel", need - took)
	if took <= 0:
		sim.notify("No fuel to put in it", "#c96a5a")
		return false
	v.fuel = minf(C.fuel_max, v.fuel + took)
	sim.emit({"t": "refuel", "x": v.pos.x, "y": v.pos.y, "n": took})
	return true


## Stripping a wreck, so a dead car is still worth something.
func salvage(sim: GameSim, v: Dictionary, p: PlayerSim) -> bool:
	if not v.destroyed:
		return false
	var scrap := int(C.salvage_scrap[0]) + roundi(sim.rng.next() * (int(C.salvage_scrap[1]) - int(C.salvage_scrap[0])) * p.loot_mul)
	Loot.stash_or_drop(sim, "scrap", scrap, v.pos)
	var parts := 1 if sim.rng.chance(C.salvage_parts_chance) else 0
	if parts > 0:
		Loot.stash_or_drop(sim, "parts", parts, v.pos)
	release_tiles(sim, v)
	list.erase(v)
	sim.notify("Stripped the wreck — %d scrap%s" % [scrap, " and a part" if parts else ""], "#b7e08a")
	Progression.add_xp(sim, p, 12, "SALVAGE")
	return true


# ------------------------------------------------------------------ keys --

## Hides the key for every locked car in the nearest container, so "whose car
## is this?" always has a findable answer.
##
## Called both when a world is generated and when one is loaded: the markers
## live on the container objects, which a load rebuilds from the seed, so a
## load without this leaves every locked car keyless.
func plant_keys(sim: GameSim) -> void:
	var used := {}
	# Containers bucketed by a coarse grid, built once. Scanning all six
	# hundred of them per locked car ran to five milliseconds — on every
	# `GameSim.start`, which is every test — and that was the single most
	# expensive thing vehicles added anywhere.
	var span := ceili(C.key_range / Config.TILE)
	var cell := maxi(1, span)
	var buckets := {}
	for c in sim.world.containers:
		c.erase("extra")
		var key: int = (int(c.tx) / cell) * 100000 + (int(c.ty) / cell)
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(c)

	for v in list:
		if v.destroyed or not v.locked or String(v.key_id).is_empty():
			continue
		var best := {}
		var bd: float = C.key_range * C.key_range
		var vx := floori(v.pos.x / Config.TILE) / cell
		var vy := floori(v.pos.y / Config.TILE) / cell
		for j in range(-1, 2):
			for i in range(-1, 2):
				for c in buckets.get((vx + i) * 100000 + (vy + j), []):
					var key: int = int(c.tx) * 100000 + int(c.ty)
					if used.has(key):
						continue
					var d: float = Vector2(c.x, c.y).distance_squared_to(v.pos)
					if d < bd:
						bd = d
						best = c
		if best.is_empty():
			# Nowhere close to hide one: this car needs a pick or a wire.
			v.key_id = ""
			v.key_hint = ""
			continue
		used[int(best.tx) * 100000 + int(best.ty)] = true
		best["extra"] = [{"id": "key:" + String(v.key_id), "n": 1}]
		v.key_hint = String(best.label)


# ---------------------------------------------------------- parked tiles --
#
# A parked car blocks the tiles it sits on, exactly like the scenery the
# generator made it from. Driving releases them and parking claims new ones —
# tracking precisely which tiles *this car* claimed, so releasing never clears
# a wall or a tree that was already there.

func release_tiles(sim: GameSim, v: Dictionary) -> void:
	for t: Vector2i in v.tiles:
		if World.in_bounds(t.x, t.y):
			sim.world.blocked[t.y * Config.WORLD_TILES + t.x] = 0
	v.tiles = []
	sim.world_version += 1


func occupy_tiles(sim: GameSim, v: Dictionary) -> void:
	var claimed: Array[Vector2i] = []
	var cx := floori(v.pos.x / Config.TILE)
	var cy := floori(v.pos.y / Config.TILE)
	# Two tiles along the car's long axis, rounded to the nearest cardinal.
	var along := Vector2i(1, 0) if absf(cos(v.angle)) > 0.5 else Vector2i(0, 1)
	for off: Vector2i in [Vector2i.ZERO, along]:
		var t := Vector2i(cx + off.x, cy + off.y)
		if not World.in_bounds(t.x, t.y):
			continue
		# Never claim a tile something else already owns. Both maps have to be
		# asked (invariant 2): the terrain bitmap does not know about your
		# walls, so checking it alone lets a car park inside your own gate —
		# and then free that tile again when it drives off.
		if sim.world.is_blocked_tile(t.x, t.y, sim.structs):
			continue
		sim.world.blocked[t.y * Config.WORLD_TILES + t.x] = 1
		claimed.append(t)
	v.tiles = claimed
	sim.world_version += 1
