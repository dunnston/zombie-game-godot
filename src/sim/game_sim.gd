class_name GameSim
extends RefCounted
## The whole simulation: the world and everyone in it, stepped by tick().
## Owns no nodes. Presentation reads it; input reaches it only through each
## player's Intent; what happened this step comes back out as `events`.

var world: World
var players: Array[PlayerSim] = []
var enemies := Enemies.new()
var bullets: Array[Dictionary] = []
var quiet := QuietField.new()
var threat := Threat.new()
var clock := DayNight.new()
var fire := Fire.new()
var crew := Survivors.new()
var raid: Raid = null
var raids_done := 0
var time := 0.0
var rng: Rng
var stats := {"kills": 0, "deaths": 0, "damage_dealt": 0.0, "damage_taken": 0.0, "looted": 0}

## Piles on the ground, and the packs the dead leave behind.
var pickups: Array[Dictionary] = []
var backpacks: Array[Dictionary] = []
var pickup_seq := 0

## Loot rolls draw from their own stream, so how much you search cannot shift
## the world's or the spawner's numbers.
var loot_rng: Rng

## Kept so a save can reproduce this run's streams.
var run_seed := 1

## The base's one shared pile. A Supply Stash (Phase 3b) is a door into it,
## not a pile of its own; until one is built there is nowhere to overflow to
## and everything falls on the ground.
var stash: Slots = null

## Everything the player has built. The second collision source: terrain is
## the bitmap, this is the destructible map (invariant 2).
var structs: Structures = null

## The view drains these every frame: shots, hits, kills, notices, shakes.
## Co-op sends the same list to guests.
var events: Array[Dictionary] = []

## Half the diagonal of the local screen in world px. The presentation sets
## it so the spawn ring stays off screen; a guest's is a fixed 880.
var view_radius := 0.0

## Bumped whenever collision changes (a tree felled, later a wall built), so
## flow fields know to rebuild.
var world_version := 0

## Off, enemies steer straight at you as the prototype's did. Kept so the
## tests can measure the field against a control, and the owner can feel
## the difference.
var nav_enabled := true

var _nav := {}                    # seat -> NavField


func _init() -> void:
	# Built here rather than in the member list: a member initializer runs
	# while the class is still loading, and reaching for another class_name
	# at that moment fails (§8).
	structs = Structures.new()


func new_game(world_seed: int = 20240917, run_seed: int = 1) -> void:
	start(World.new(world_seed), run_seed)


## A new run on an already-built world. Tests share one world between
## dozens of sims because generating it costs a third of a second.
func start(world_: World, run_seed: int = 1) -> void:
	world = world_
	rng = Rng.new(run_seed)
	loot_rng = Rng.new(run_seed * 2654435761 + 0xC0FFEE)
	self.run_seed = run_seed
	time = 0.0
	players.clear()
	pickups.clear()
	backpacks.clear()
	stash = null
	structs = Structures.new()
	# Everything a run accumulates and a save does not carry. `start` is also
	# the front half of loading into a live game (SaveGame.apply), so any
	# runtime field left standing here survives the load: a raid that was
	# under way would go on spawning waves into the restored snapshot, and
	# bullets already in the air would arrive at the restored player.
	raid = null
	raids_done = 0
	bullets.clear()
	enemies.list.clear()
	enemies.corpses.clear()
	enemies.rebuild_spatial()
	quiet = QuietField.new()
	threat = Threat.new()
	clock = DayNight.new()
	fire.reset()
	crew.reset()
	crew.seed_rescues(world)
	world_version += 1                # any cached flow field is about a dead world
	_nav.clear()
	events.clear()
	for k in stats:
		stats[k] = 0 if stats[k] is int else 0.0
	var p := PlayerSim.new()
	p.seat = 0
	p.display_name = Config.PLAYER.names[0]
	# The first morning starts by the Roadside Camp, not in a field across
	# the river.
	var camp: Rect2i = world.locations[0].rect
	var centre := Vector2(camp.position.x + camp.size.x / 2.0, camp.position.y + camp.size.y / 2.0) * Config.TILE
	p.pos = pick_random_spawn(centre, 30.0 * Config.TILE)
	p.intent.aim = p.pos + Vector2.RIGHT
	give_kit(p)
	players.append(p)
	enemies.seed_area(self, p.pos, Config.SPAWN.seed_radius, Config.SPAWN.seed_count)
	notify("You wake up on the roadside. Find shelter before dark.", "#d8e8c0", true)


## What a new survivor wakes up holding: a pipe and a couple of bandages.
## Everything else is out there.
func give_kit(p: PlayerSim) -> void:
	for entry in Config.START_KIT.hotbar:
		p.hotbar.add(entry[0], entry[1])
	Equipment.recompute_stats(p)


## The six-weapon test kit, loaded and carrying ammunition. Not a thing a game
## ever starts with — the smoke run and the combat tests ask for it by name.
func give_test_kit(p: PlayerSim) -> void:
	p.hotbar.clear_all()
	p.bag.clear_all()
	for entry in Config.TEST_KIT.hotbar:
		p.hotbar.add(entry[0], entry[1])
	for entry in Config.TEST_KIT.bag:
		p.bag.add(entry[0], entry[1])
	for i in range(p.hotbar.size()):
		var id := p.hotbar.id_at(i)
		var w: Dictionary = Config.WEAPONS.get(id, {})
		if w.has("mag"):
			p.mag[id] = w.mag
			p.take_res(w.ammo, w.mag)
	Equipment.recompute_stats(p)


## A random open tile in tier-1 land. With `near`, only tiles within
## `radius` of that point are considered (falling back to all of them).
## Rejects spots with enemies within `min_enemy_dist` so a respawn is never
## an instant second death.
func pick_random_spawn(near: Vector2 = Vector2.INF, radius: float = 0.0, min_enemy_dist := 0.0) -> Vector2:
	var tiles := world.spawn_tiles
	if near != Vector2.INF:
		var close: Array[Vector2i] = []
		var r2 := radius * radius
		for t in tiles:
			var c := Vector2(t.x * Config.TILE + 16, t.y * Config.TILE + 16)
			if c.distance_squared_to(near) <= r2:
				close.append(t)
		if not close.is_empty():
			tiles = close
	if tiles.is_empty():
		return Vector2(160 * Config.TILE, 160 * Config.TILE)
	var d2 := min_enemy_dist * min_enemy_dist
	var fallback := Vector2.INF
	for i in range(40):
		var t: Vector2i = rng.pick(tiles)
		var spot := Vector2(t.x * Config.TILE + 16, t.y * Config.TILE + 16)
		if fallback == Vector2.INF:
			fallback = spot
		if min_enemy_dist <= 0.0:
			return spot
		var clear := true
		for e in enemies.list:
			if not e.dead and e.pos.distance_squared_to(spot) < d2:
				clear = false
				break
		if clear:
			return spot
	return fallback


# -------------------------------------------------------------- questions --

## The nearest player an enemy could go for, or null if nobody qualifies.
func nearest_player(at: Vector2) -> PlayerSim:
	var best: PlayerSim = null
	var bd := INF
	for p in players:
		if p.dead:
			continue
		var d := p.pos.distance_squared_to(at)
		if d < bd:
			bd = d
			best = p
	return best


func living_players() -> Array[PlayerSim]:
	var out: Array[PlayerSim] = []
	for p in players:
		if not p.dead:
			out.append(p)
	return out


## What the dark is worth, off the clock. Four callers had been reading this
## since Phase 2 against a stub that always said noon.
func night_factors() -> Dictionary:
	return clock.factors()


## Where a raid aims. With structures (Phase 3) it is their centre; without
## a base it is whoever is nearest, which reads as "they are coming for you".
func base_centre() -> Dictionary:
	var c := structs.base_centre()
	if c.has_base:
		return c
	var p := nearest_player(Vector2(Config.WORLD_SIZE / 2.0, Config.WORLD_SIZE / 2.0))
	if p == null and not players.is_empty():
		p = players[0]
	return {"pos": p.pos if p != null else Vector2.ZERO, "has_base": false}


## Sum of structure health, for the raid's progress signature.
func structure_hp_total() -> float:
	return structs.hp_total()


## The flow field toward a player, rebuilt when they have moved a couple of
## tiles or the world has changed. Enemies hunting them read it.
func nav_for(p: PlayerSim) -> NavField:
	if not nav_enabled:
		return null
	var tile := Vector2i(floori(p.pos.x / Config.TILE), floori(p.pos.y / Config.TILE))
	var nf: NavField = _nav.get(p.seat)
	if nf != null and nf.version == world_version:
		var moved := maxi(absi(tile.x - nf.target.x), absi(tile.y - nf.target.y))
		if moved == 0 or (moved < 2 and time - nf.built_at < Config.NAV.max_age):
			return nf
	if nf == null:
		nf = NavField.new()
		_nav[p.seat] = nf
	nf.build(world, tile, Config.NAV.radius_tiles, time, world_version, structs)
	return nf


## The base belongs to one player. Wall strength, turret reach, upkeep and
## the roster cap are read off the host's build and not off whoever happens
## to be standing next to the thing — otherwise a guest walking past a turret
## would change how hard it hits.
func host() -> PlayerSim:
	return players[0] if not players.is_empty() else null


# ----------------------------------------------------------------- output --

func emit(ev: Dictionary) -> void:
	events.append(ev)


func notify(text: String, color := "#ebe6d6", important := false) -> void:
	events.append({"t": "notify", "text": text, "color": color, "important": important})


# ------------------------------------------------------------------- step --

func tick(dt: float) -> void:
	time += dt
	# The clock first: everything below it that asks about the dark — the
	# spawner, the sense check, walk speed, Threat — should be asking about
	# this tick and not the last one.
	clock.tick(self, dt)
	enemies.rebuild_spatial()
	for p in players:
		p.tick(self, dt)
	enemies.tick_ai(self, dt)
	Combat.tick_bullets(self, dt)
	structs.tick(self, dt)
	# After the structures and before the spawner: fire kills, and a kill
	# should deposit its quiet before the refill check reads the field.
	fire.tick(self, dt)
	# After the structures so a builder patches what this tick damaged, and
	# before the spawner so a survivor kill deposits its quiet in time.
	crew.tick(self, dt)
	Loot.update_pickups(self, dt)
	# Quiet decays before the spawner reads it, so a lull always ends on time.
	quiet.tick(dt)
	enemies.tick_spawning(self, dt)
	threat.tick(self, dt)
	if raid != null:
		raid.tick(self, dt)
	elif threat.raid_ready(self):
		Raid.start(self)
	for c in enemies.corpses:
		c.t += dt
	while not enemies.corpses.is_empty() and enemies.corpses[0].t > enemies.corpses[0].life:
		enemies.corpses.pop_front()
	for p in players:
		p.intent.clear_edges()
