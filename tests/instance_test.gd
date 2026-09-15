extends "res://tests/test_case.gd"
## The School, the first instanced dungeon (`tasks/instanced-dungeons.md`,
## its §0 for the owner's decisions of 2026-09-10). Every rule the owner set is
## asserted here on an outcome: what is in your pack after each way out, what
## the town looks like when you come back, and what the door says.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.god_mode = true


func _door() -> Dictionary:
	var f := Instance.door_for(sim, "school")
	p.pos = f.stand
	p.prev_pos = p.pos
	return f


func _enter() -> Instance:
	_door()
	ok(Instance.enter(sim, p, "school"), "the door opens")
	return sim.instance


func _find(entry: String, n := 1) -> Dictionary:
	return Loot.give_entry(sim, p, {"id": entry, "n": n})


## What is in the haul stays there (owner, 2026-09-15), so the tests below
## check the find where it actually is rather than moving it into the pack.
func _haul_count(id: String) -> int:
	return p.haul.count(id)


# --------------------------------------------------------------- the town --

func test_the_school_stands_in_the_town_and_nothing_else_moved() -> void:
	var w := world()
	var f := Instance.door_for(sim, "school")
	ok(not f.is_empty(), "a door to the School")
	var d: Dictionary = Config.INSTANCES.school
	var shell: Rect2i = d.shell
	var inside := shell.position + Vector2i(5, 5)
	eq(w.tile(inside.x, inside.y), Config.T.ROOF, "a roof, not a floor")
	ok(w.is_blocked_tile(inside.x, inside.y), "and you cannot walk onto it")
	for t: Vector2i in f.tiles:
		ok(w.is_blocked_tile(t.x, t.y), "the door answers E; it does not let you through")
	ok(not w.is_blocked_px(f.stand.x, f.stand.y), "somewhere to stand at the door")
	eq(String(w.location_at_px(f.stand.x, f.stand.y).get("id", "")), "school")
	# Stamped after the generator, so no draw on its RNG moved: the container
	# count is the prototype's to the unit, and it is the most RNG-sensitive
	# number the town has.
	eq(w.containers.size(), 644, "every container where it was")
	ne(w.base_fingerprint, w.fingerprint(), "and the map is a different map")


func test_a_save_from_before_the_school_still_loads() -> void:
	var d := SaveGame.to_dict(sim)
	d.fingerprint = world().base_fingerprint
	var again := GameSim.new()
	ok(SaveGame.apply(again, d, world()).ok, "last week's save")
	d.fingerprint = 12345
	ok(not SaveGame.apply(GameSim.new(), d, world()).ok, "but not a different town's")


func test_last_weeks_save_moves_what_it_left_where_the_school_now_stands() -> void:
	# Codex on PR #31: it loads, and whatever it left on ground the School now
	# covers loaded inside the roof — a player too deep for `unstick`, a chest
	# and a car overlapping the building.
	var shell: Rect2i = Config.INSTANCES.school.shell
	var t := shell.get_center()
	var mid := (Vector2(t) + Vector2(0.5, 0.5)) * float(Config.TILE)
	var chest := sim.structs.make(sim, "chest", t.x, t.y)
	chest.store.add("scrap", 7)
	var d := SaveGame.to_dict(sim)
	d.fingerprint = sim.world.base_fingerprint
	d.players[0].x = mid.x
	d.players[0].y = mid.y
	d.cars[0].x = mid.x
	d.cars[0].y = mid.y
	d.cars[0].tiles = []
	var again := GameSim.new()
	ok(SaveGame.apply(again, d, World.new(sim.world.world_seed)).ok, "it loads")
	var on := func(at: Vector2) -> bool:
		return shell.has_point(Vector2i(floori(at.x / Config.TILE), floori(at.y / Config.TILE)))
	var q: PlayerSim = again.players[0]
	ok(not on.call(q.pos), "the player is not inside the roof")
	ok(not again.world.is_blocked_px(q.pos.x, q.pos.y, again.structs), "and is standing somewhere")
	ok(again.structs.at_tile(t.x, t.y).is_empty(), "the chest is not standing in the building")
	# What was in the chest, and the whole of what it cost, at the door.
	var want := {"scrap": 7}
	for id in Config.STRUCTURES.chest.cost:
		want[id] = int(want.get(id, 0)) + int(Config.STRUCTURES.chest.cost[id])
	var got := {}
	for it in again.pickups:
		ok(not on.call(it.pos), "a pile inside the roof")
		got[String(it.id)] = int(got.get(String(it.id), 0)) + int(it.n)
	for id in want:
		ok(int(got.get(id, 0)) >= int(want[id]), "%d %s at the door, got %d" % [want[id], id, got.get(id, 0)])
	for v in again.cars.list:
		ok(not on.call(v.pos), "car %d is inside the building" % v.id)


func test_nothing_comes_back_out_of_the_haul() -> void:
	# Owner, 2026-09-15: dragging a find into the pack is off. It never kept
	# anything — `haul_load` counted it wherever it sat and `leave` forfeited
	# it either way — so all it did was look like a way to cheat the run.
	#
	# It replaces the Codex PR #31 rule (a full haul emptied into the pack and
	# refilled), which cannot happen now that the move does not exist.
	_enter()
	p.carry_cap = 100000.0
	var cap: float = Config.INSTANCE.haul_cap
	_find("scrap", 10)
	var found := p.haul.count("scrap")
	gt(found, 0, "the find went into the haul")
	var free := p.bag.first_empty()
	ok(free >= 0, "there is room in the pack")
	for i in range(p.haul.size()):
		if p.haul.id_at(i) == "scrap":
			ok(not Equipment.move_stack(sim, p, "haul", i, "bag", free), "a find came out of the haul")
			break
	eq(p.haul.count("scrap"), found, "and it is still in there")
	eq(p.bag.count("scrap"), 0, "with nothing in the pack")
	ok(Instance.haul_load(sim, p) <= cap + 1e-6, "the load never passed the cap")


func test_nothing_can_be_made_in_here() -> void:
	# Codex on PR #31: crafting turned found cloth into bandages the ledger
	# never wrote down, and they survived a walk-out.
	var r: Dictionary = Crafting.visible_recipes(p, 0)[0]
	_enter()
	eq(String(Crafting.status(sim, p, r, 0).reason), "Nothing can be made in here")


func test_dying_after_reaching_the_way_out_in_the_same_step_is_still_dying() -> void:
	# Codex on PR #31: E at the open exit sets the extraction for the end of
	# the step; lethal damage later in that step still walked you out with
	# everything.
	_enter()
	var before := Instance.held_count(p, "medkit")
	_find("item:medkit")
	eq(Instance.held_count(p, "medkit"), before + 1, "found")
	sim.instance.state = "cleared"
	sim.instance.leaving = "extracted"
	p.god_mode = false
	Damage.kill_player(sim, p)
	sim.tick(1.0 / 60.0)
	ok(sim.instance == null, "the run ended")
	eq(Instance.held_count(p, "medkit"), before, "the way dying ends it: the find stays inside")


func test_the_door_says_what_it_would_do() -> void:
	_door()
	var t := Interact.best_target(sim, p)
	eq(String(t.get("kind", "")), "instance_door")
	eq(String(t.get("label", "")), "Enter Pine Hollow High")


func test_the_party_goes_in_together_or_not_at_all() -> void:
	var g := sim.join_player("somebody", "Bex")
	g.god_mode = true
	_door()
	g.pos = p.pos + Vector2(0, 600)
	ok(Instance.refusal(sim, p, "school").contains("waiting for Bex"), Instance.refusal(sim, p, "school"))
	ok(not Instance.enter(sim, p, "school"), "and the door stays shut")
	eq(sim.instance, null)
	g.pos = p.pos + Vector2(0, 24)
	eq(Instance.refusal(sim, p, "school"), "", "both at the door")
	ok(Instance.enter(sim, p, "school"))
	ok(g.pos.distance_to(sim.world.entry_spot) < 64.0 and p.pos.distance_to(sim.world.entry_spot) < 64.0,
		"and both of you are in the foyer")
	gt(g.pos.distance_to(p.pos), 2.0 * p.r, "side by side, not one on top of the other")
	ok(not sim.world.circle_hits_solid(g.pos.x, g.pos.y, g.r) and not sim.world.circle_hits_solid(p.pos.x, p.pos.y, p.r),
		"and neither of you in a wall")
	eq(sim.instance.party.size(), 2)


func test_nobody_goes_in_from_behind_a_wheel() -> void:
	# Codex on PR #32: only the player who pressed E was checked, so a friend
	# parked at the door in a running car was swapped inside without getting
	# out, and the car was left running with nothing colliding with it.
	var g := sim.join_player("somebody", "Bex")
	g.god_mode = true
	_door()
	g.pos = p.pos + Vector2(0, 24)
	g.driving_id = int(sim.cars.list[0].id)
	ok(Instance.refusal(sim, p, "school").contains("Bex"), Instance.refusal(sim, p, "school"))
	ok(not Instance.enter(sim, p, "school"), "the door stays shut")
	ok(sim.instance == null)
	g.driving_id = 0
	eq(Instance.refusal(sim, p, "school"), "", "out of the car, in you go")


func test_whoever_went_in_comes_out_the_downed_the_dead_and_the_dropped() -> void:
	# §10: extraction is a party event. Four go in; one dies, one is down, one
	# drops off the line, and the host puts the boss down.
	var mates: Array[PlayerSim] = []
	for n in ["Ash", "Bex", "Cole"]:
		var q := sim.join_player("id-" + n, n)
		q.god_mode = true
		mates.append(q)
	_door()
	for q in mates:
		q.pos = p.pos + Vector2(0, 20)
	var inst := _enter()
	var dead := mates[0]
	var down := mates[1]
	var gone := mates[2]
	Loot.give_entry(sim, dead, {"id": "scrap", "n": 9})
	dead.god_mode = false
	Damage.kill_player(sim, dead)
	Damage.down_player(sim, down)
	sim.park_player(gone)
	Damage.kill_enemy(sim, inst.boss, p)
	run(sim, 0.1)
	Instance.leave(sim, "extracted")
	var door: Vector2 = Instance.door_for(sim, "school").stand
	for q in [p, dead, down, gone]:
		ok(q.pos.distance_to(door) < 1.0, "%s is outside" % q.display_name)
	ok(not dead.dead, "the dead wake at the door")
	eq(dead.count_carried("scrap"), 9, "with what they found — the party brought it out")
	ok(not down.downed, "the downed are carried out on their feet")
	ok(gone.away, "and the one who dropped is still dropped, but outside")


func test_walking_out_early_needs_everyone_standing_at_the_way_out() -> void:
	var g := sim.join_player("somebody", "Bex")
	g.god_mode = true
	_door()
	g.pos = p.pos + Vector2(0, 20)
	_enter()
	g.pos = sim.world.boss_spot + Vector2(0, 200)
	ok(not Instance.walk_out(sim, p), "not while Bex is in the gym")
	ok(Instance.leave_refusal(sim, p).contains("waiting for Bex"))
	ok(sim.instance != null)
	Damage.down_player(sim, g)
	ok(Instance.walk_out(sim, p), "the downed come out with the party")
	eq(sim.instance, null)


func test_a_save_written_inside_brings_a_dropped_friend_out_too() -> void:
	var g := sim.join_player("somebody", "Bex")
	g.god_mode = true
	_door()
	g.pos = p.pos + Vector2(0, 20)
	_enter()
	sim.park_player(g)
	var d := SaveGame.to_dict(sim)
	var door: Vector2 = sim.instance.door
	for rec in d.players:
		ok(Vector2(float(rec.x), float(rec.y)).distance_to(door) < 1.0, "%s is written down at the door" % rec.name)


# ------------------------------------------------------- going in, coming out --

func test_the_door_opens_onto_the_foyer_and_the_town_is_set_aside() -> void:
	var town := sim.world
	var inst := _enter()
	ne(sim.world, town, "a different map")
	eq(sim.world.layout, "school")
	eq(p.pos, sim.world.entry_spot, "alone, on the spot itself")
	eq(sim.structs.count(), 0, "nothing of your base in here")
	eq(sim.stash, null)
	eq(sim.enemies.list.size(), sim.world.enemy_spots.size() + 1, "the placed crowd and the boss")
	ok(inst.boss != null and inst.boss.type == String(Config.INSTANCES.school.boss), "its boss")
	ok(inst.boss.brain != null, "with its script")
	eq(inst.held.world, town, "the town is held, not thrown away")


func test_leaving_puts_the_town_back_exactly_as_it_was() -> void:
	var town := sim.world
	var crowd := sim.enemies
	var t0 := sim.clock.t
	var day := sim.clock.day
	Loot.spawn_pickup(sim, p.pos + Vector2(200, 0), "res", "scrap", 3)
	var piles := sim.pickups.size()
	sim.threat.value = 40.0
	_enter()
	run(sim, 3.0)
	ok(Instance.walk_out(sim, p), "out through the foyer")
	eq(sim.instance, null)
	eq(sim.world, town, "the same town")
	eq(sim.enemies, crowd, "the same crowd")
	near(sim.clock.t, t0, 1e-9, "not a second of it passed")
	eq(sim.clock.day, day)
	near(sim.threat.value, 40.0, 1e-6)
	eq(sim.pickups.size(), piles, "the scrap is still on the ground")
	eq(p.pos, Instance.door_for(sim, "school").stand, "standing at the door")


func test_nothing_that_runs_the_town_runs_in_here() -> void:
	var inst := _enter()
	var town_clock: DayNight = inst.held.clock
	var t0 := town_clock.t
	# Emptied out, so a standing-population spawner that was running would
	# have room to refill it — with the crowd still in, it would add nobody
	# either way and this could not tell the difference. And the *inside's*
	# Threat at the top, which is the one a raid would read.
	sim.enemies.list.clear()
	sim.threat.value = 100.0
	run(sim, 20.0)
	eq(sim.enemies.list.size(), 0, "nothing spawned into the empty building")
	eq(sim.raid, null, "and Threat at 100 sent nothing")
	near(sim.clock.t, float(Config.INSTANCES.school.clock_t), 1e-9, "the inside's clock is frozen")
	near(town_clock.t, t0, 1e-9, "and so is the town's day")


func test_inside_is_its_own_daylight_until_the_boss_kills_the_lights() -> void:
	# Owner, 2026-09-15: the inside played at dusk whatever the town's clock
	# said, so the whole run was a night run. It is daylight in there now, and
	# the only dark is the one the boss makes.
	var inst := _enter()
	var lit := float(sim.clock.darkness().alpha)
	ok(lit < Config.DARK_ENOUGH, "the school is dark enough to need a torch: %.2f" % lit)
	inst.lights_out(sim)
	var dark := float(sim.clock.darkness().alpha)
	gt(dark, lit, "the boss killing the lights changed nothing: %.2f" % dark)
	gt(dark, Config.DARK_ENOUGH, "and it should be dark enough for a torch then")


func test_a_run_is_a_fresh_roll_every_time() -> void:
	var first := _enter().run_seed
	Instance.walk_out(sim, p)
	var second := _enter().run_seed
	ne(second, first)


# ------------------------------------------------------------ the rules in --

func test_nothing_can_be_built_in_here() -> void:
	_enter()
	p.bag.add("wood", 50)
	var t := Vector2i(floori(p.pos.x / Config.TILE) + 2, floori(p.pos.y / Config.TILE))
	eq(String(sim.structs.can_place(sim, "woodWall", t.x, t.y, p).reason), "Nothing can be built in here")


func test_the_stash_is_out_of_reach_inside() -> void:
	sim.stash = Slots.new(Config.STASH_SLOTS)
	sim.stash.add("wood", 100)
	ok(p.can_afford(sim, {"wood": 10}), "paid from the stash in town")
	_enter()
	ok(not p.can_afford(sim, {"wood": 10}), "not in here")
	Instance.walk_out(sim, p)
	ok(p.can_afford(sim, {"wood": 10}), "and there again when you are out")


func test_the_haul_is_closed_outside() -> void:
	p.bag.add("wood", 5)
	var i := -1
	for j in range(p.bag.size()):
		if p.bag.id_at(j) == "wood":
			i = j
	ok(not Equipment.move_stack(sim, p, "bag", i, "haul", 0), "no weightless second pack in town")
	eq(p.haul.count("wood"), 0)


func test_finds_go_in_the_haul_and_are_written_down() -> void:
	var inst := _enter()
	var bag := p.bag.count("ammoP")
	var weight := p.carried_weight()
	_find("ammoP", 20)
	eq(p.haul.count("ammoP"), 20)
	eq(p.bag.count("ammoP"), bag, "not the pack")
	near(p.carried_weight(), weight, 1e-6, "and none of it slows you down for the boss")
	eq(int(inst.gained[p.seat].ammoP), 20)


func test_your_own_things_picked_back_up_are_not_finds() -> void:
	var inst := _enter()
	p.bag.add("wood", 5)
	var i := -1
	for j in range(p.bag.size()):
		if p.bag.id_at(j) == "wood":
			i = j
	ok(Equipment.drop_stack(sim, p, "bag", i))
	var pile: Dictionary = sim.pickups.back()
	pile.inert_for = null
	pile.pos = p.pos
	run(sim, 0.3)
	eq(p.bag.count("wood"), 5, "back in the pack")
	eq(p.haul.count("wood"), 0)
	ok(not inst.gained.get(p.seat, {}).has("wood"), "and not counted as found")


# ------------------------------------------------------------- the ways out --

func test_walking_out_early_keeps_what_you_brought_and_not_what_you_found() -> void:
	# The design note's own example (§6.3): forty rounds brought, twenty found,
	# the found ones moved into the pack and ten fired. Thirty come out.
	p.bag.add("ammoP", 40 - p.bag.count("ammoP"))
	_enter()
	_find("ammoP", 20)
	eq(_haul_count("ammoP"), 20, "the found rounds are in the haul, not the pack")
	eq(p.bag.count("ammoP"), 40, "and what you brought is what you are shooting")
	p.bag.take("ammoP", 10)
	ok(Instance.walk_out(sim, p))
	eq(p.bag.count("ammoP"), 30)
	eq(p.haul.used(), 0, "and the haul is empty")


func test_a_found_medkit_stays_in_the_haul_and_is_forfeited_with_it() -> void:
	# It used to be draggable into the pack and usable on the way through.
	# The drag is gone (owner, 2026-09-15), so a find is something you carry
	# out or lose — never something that patches you up mid-run.
	var bandages := p.count_carried("bandage")
	_enter()
	_find("item:medkit", 1)
	eq(_haul_count("medkit"), 1, "the medkit is in the haul")
	eq(p.count_carried("medkit"), 0, "and not on you")
	Instance.walk_out(sim, p)
	eq(p.count_carried("bandage"), bandages, "what you brought is untouched")
	eq(p.count_carried("medkit"), 0, "and what you found is gone with the run")


func test_the_boss_lets_it_all_out_and_the_door_stays_chained_until_tomorrow() -> void:
	var scrap := p.count_carried("scrap")
	var inst := _enter()
	_find("scrap", 12)
	_find("weapon:rifle")
	Damage.kill_enemy(sim, inst.boss, p)
	run(sim, 0.1)
	eq(inst.state, "cleared")
	ok(Instance.walk_out(sim, p), "out the front with it")
	eq(p.count_carried("scrap"), scrap + 12, "every piece of scrap")
	ok(p.carries("rifle"), "and the rifle")
	eq(p.haul.used(), 0)
	eq(int(sim.cleared.school), sim.clock.day)
	_door()
	ok(Instance.refusal(sim, p, "school").contains("come back tomorrow"))
	ok(not Instance.enter(sim, p, "school"))
	sim.clock.day += 1
	eq(Instance.refusal(sim, p, "school"), "", "open again the next day")


func test_walking_out_on_the_key_ends_the_run_at_the_end_of_that_step() -> void:
	# Through the key, inside a real step — the path the smoke run took and no
	# test did. Leaving used to swap the map in the middle of the player's
	# tick, and the rest of that step then called into an instance that was
	# no longer there. The runner fails a test on any engine error, so the old
	# code fails this one.
	var inst := _enter()
	Damage.kill_enemy(sim, inst.boss, p)
	run(sim, 0.1)
	var exit := {}
	for f in sim.world.features:
		if String(f.kind) == "exit":
			exit = f
	p.pos = Vector2(exit.x, exit.y + 44.0)
	p.prev_pos = p.pos
	eq(String(Interact.best_target(sim, p).get("kind", "")), "exit")
	p.intent.interact = true
	sim.tick(1.0 / 60.0)
	eq(sim.instance, null, "out, on the step the key was pressed")
	ok(p.pos.distance_to(Instance.door_for(sim, "school").stand) < 1.0, "at the door")
	run(sim, 0.5)
	eq(sim.instance, null, "and the town goes on ticking")


func test_dying_inside_wakes_you_at_the_door_with_what_you_brought() -> void:
	p.god_mode = false
	p.bag.add("wood", 5)
	var wood := p.bag.count("wood")
	_enter()
	_find("scrap", 10)
	eq(_haul_count("scrap"), 10, "the find is in the haul")
	Damage.kill_player(sim, p)
	ok(p.dead)
	eq(sim.backpacks.size(), 0, "no pack left in a map that is about to go")
	run(sim, Config.PLAYER.respawn_time + 0.3)
	eq(sim.instance, null, "the run is over")
	ok(not p.dead, "awake")
	ok(p.pos.distance_to(Instance.door_for(sim, "school").stand) < 1.0, "outside the door")
	eq(p.bag.count("wood"), wood, "with what you brought")
	eq(p.count_carried("scrap"), 0, "and without what you found")
	eq(sim.backpacks.size(), 0, "and nothing to walk back for")


func test_a_save_written_inside_is_the_game_walked_out() -> void:
	p.bag.add("wood", 5)
	var wood := p.bag.count("wood")
	_enter()
	_find("scrap", 10)
	var d := SaveGame.to_dict(sim)
	ok(sim.instance != null and sim.world.layout == "school", "still inside: writing it changed nothing")
	eq(_haul_count("scrap"), 10, "and nothing was taken out of the haul to write it")
	eq(int(d.fingerprint), world().fingerprint(), "it is the town that was written")
	var again := GameSim.new()
	ok(SaveGame.apply(again, d, world()).ok)
	var q := again.players[0]
	ok(q.pos.distance_to(Instance.door_for(again, "school").stand) < 1.0, "at the door")
	eq(q.bag.count("wood"), wood)
	eq(q.count_carried("scrap"), 0)


# ------------------------------------------------------------ the building --

func test_the_key_in_the_principals_desk_opens_the_gym() -> void:
	var inst := _enter()
	var chained := {}
	for f in sim.world.features:
		if String(f.kind) == "chained":
			chained = f
	var t: Vector2i = chained.tiles[0]
	ok(sim.world.is_blocked_tile(t.x, t.y), "chained shut")
	p.pos = Vector2(chained.x, chained.y + 40.0)
	var target := Interact.best_target(sim, p)
	eq(String(target.get("kind", "")), "chained")
	ok(String(target.label).contains("key is somewhere"))
	ok(not inst.unlock(sim, chained), "not without the key")
	var desk := {}
	for c in sim.world.containers:
		if c.has("key"):
			desk = c
	ok(not desk.is_empty(), "the principal's desk")
	p.searching = {"container": desk, "t": 1.0, "dur": 1.0}
	Interact._finish_search(sim, p)
	ok(inst.keys.get("gym", false), "searching it finds the key")
	eq(String(Interact.best_target(sim, p).get("label", "")), "Unlock the gym")
	ok(inst.unlock(sim, chained))
	ok(not sim.world.is_blocked_tile(t.x, t.y), "open")


func test_the_school_is_the_same_for_a_seed_and_different_for_another() -> void:
	var a := World.new(7, "school")
	var b := World.new(7, "school")
	eq(a.fingerprint(), b.fingerprint())
	eq(a.containers.size(), b.containers.size())
	eq(a.enemy_spots.size(), b.enemy_spots.size())
	ne(World.new(8, "school").fingerprint(), a.fingerprint(), "another run, another roll")


func test_every_room_is_reachable_once_the_gym_is_open() -> void:
	var w := World.new(11, "school")
	var W := Config.WORLD_TILES
	for f in w.features:
		if String(f.kind) == "chained":
			for t: Vector2i in f.tiles:
				w.blocked[t.y * W + t.x] = 0
	var start := Vector2i(floori(w.entry_spot.x / Config.TILE), floori(w.entry_spot.y / Config.TILE))
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for n: Vector2i in [c + Vector2i.LEFT, c + Vector2i.RIGHT, c + Vector2i.UP, c + Vector2i.DOWN]:
			if not seen.has(n) and not w.is_blocked_tile(n.x, n.y):
				seen[n] = true
				todo.append(n)
	var stranded := 0
	for c in w.containers:
		var t := Vector2i(c.tx, c.ty)
		if not (seen.has(t + Vector2i.LEFT) or seen.has(t + Vector2i.RIGHT) or seen.has(t + Vector2i.UP) or seen.has(t + Vector2i.DOWN)):
			stranded += 1
	eq(stranded, 0, "every desk and locker can be reached")
	for at in w.enemy_spots:
		ok(seen.has(Vector2i(floori(at.x / Config.TILE), floori(at.y / Config.TILE))), "everybody can reach you")
	ok(seen.has(Vector2i(floori(w.boss_spot.x / Config.TILE), floori(w.boss_spot.y / Config.TILE))), "and the boss can")
	gt(w.containers.size(), 40, "a school's worth of lockers and desks")
	gt(w.enemy_spots.size(), 25, "and a school's worth of the dead")


func test_arriving_is_not_an_ambush() -> void:
	var w := World.new(11, "school")
	for at in w.enemy_spots:
		gt(at.distance_to(w.entry_spot), 300.0, "nobody waiting in the foyer")
