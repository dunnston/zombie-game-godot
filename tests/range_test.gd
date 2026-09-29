extends "res://tests/test_case.gd"
## The Target Range (`TargetRange`, `tasks/target-range.md`, Notion DL-109),
## PR A: the map, its lockers, and going in and out. Every rule the owner set
## is asserted on an outcome — what is in your pack and what your build is on
## each side of the door, where you stand, and what a guest can do.

const DT := 1.0 / 60.0

static var _guest_world: World

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.god_mode = true
	Actions.dev = true


func after_each() -> void:
	Actions.dev = false
	Actions.guest = null
	NetGuest.reuse_world = null


func _enter() -> Instance:
	ok(TargetRange.control(sim, p, "enter"), "the range opens")
	return sim.instance


func _leave() -> void:
	ok(TargetRange.control(sim, p, "leave"), "the way out takes the party")
	run(sim, 0.05)


func _slot_of(cont: Slots, id: String) -> int:
	for i in range(cont.size()):
		if cont.id_at(i) == id:
			return i
	return -1


func _locker_ids() -> Dictionary:
	var ids := {}
	for t: Vector2i in sim.world.range_lockers:
		var s := sim.structs.at_tile(t.x, t.y)
		if s.is_empty() or s.store == null:
			continue
		for id in (s.store as Slots).entries():
			ids[id] = int(ids.get(id, 0)) + (s.store as Slots).count(id)
	return ids


## A built-up character, so every part of the build is something to lose.
func _veteran() -> void:
	p.level = 7
	p.xp = 123.0
	p.xp_next = Config.xp_for_level(7)
	p.skill_points = 2
	p.perks[String(Config.PERKS[0].id)] = 1
	p.mutation = 30.0
	p.mut_band = Mutation.band_index(p.mutation)
	p.bag.add("scrap", 17)
	Equipment.recompute_stats(p)


# --------------------------------------------------------------- the town --

func test_the_town_has_no_door_to_the_range() -> void:
	ok(Instance.door_for(sim, "range").is_empty(), "the range is not a building in the town")
	ok(not Instance.door_for(sim, "school").is_empty(), "and the School still is")


# ---------------------------------------------------------------- going in --

func test_going_in_puts_the_party_in_the_range_on_a_baseline() -> void:
	_veteran()
	var inst := _enter()
	ok(inst != null and inst.kind == "range")
	eq(sim.world.layout, "range")
	ok(p.pos.distance_to(sim.world.entry_spot) < 64.0, "standing in the hall")
	eq(p.level, 1, "level 1")
	eq(p.perks.size(), 0, "no perks")
	near(p.mutation, 0.0, 1e-9, "the meter clear")
	eq(p.mut_band, 0)
	eq(p.bag.used() + p.hotbar.used(), 0, "empty-handed: your own things wait outside")
	near(p.hp, p.max_hp, 1e-6, "at full health")


func test_nobody_goes_in_from_a_car_or_the_floor() -> void:
	p.downed = true
	ok(not TargetRange.control(sim, p, "enter"))
	ok(sim.instance == null)


func test_the_lockers_hold_every_weapon_ammo_gear_and_consumable() -> void:
	_enter()
	var ids := _locker_ids()
	for id: String in Config.WEAPONS:
		if id != "fists":
			eq(int(ids.get(id, 0)), 1, "one %s" % id)
	for id: String in Config.AMMO_IDS:
		eq(int(ids.get(id, 0)), int(Items.registry()[id].stack) * int(Config.RANGE.ammo_stacks), "a stock of %s" % id)
	for id: String in Config.GEAR:
		eq(int(ids.get(id, 0)), 1, "one %s" % id)
	for id: String in Config.CONSUMABLES:
		eq(int(ids.get(id, 0)), int(Config.RANGE.consumable_n), "%d %s" % [int(Config.RANGE.consumable_n), id])


func test_every_weapon_in_the_lockers_is_level_one_and_new() -> void:
	_enter()
	for t: Vector2i in sim.world.range_lockers:
		var store: Slots = sim.structs.at_tile(t.x, t.y).store
		for i in range(store.size()):
			if Config.WEAPONS.has(store.id_at(i)):
				ok(store.level_at(i) <= 1, "%s at level 1" % store.id_at(i))
				ok(not store.at(i).has("w"), "%s new" % store.id_at(i))


func test_a_restock_puts_back_what_was_taken() -> void:
	_enter()
	var t: Vector2i = sim.world.range_lockers[0]
	var store: Slots = sim.structs.at_tile(t.x, t.y).store
	var id := store.id_at(0)
	store.take(id, 1)
	eq(int(_locker_ids().get(id, 0)), 0)
	ok(TargetRange.control(sim, p, "restock"))
	eq(int(_locker_ids().get(id, 0)), 1, "back after a restock")


func test_finds_in_the_range_go_to_the_pack_not_the_haul() -> void:
	_enter()
	ok(not Instance.haul_open(sim), "no haul in the range")
	Loot.give_entry(sim, p, {"id": "scrap", "n": 5}, true)
	eq(p.haul.count("scrap"), 0)
	eq(p.bag.count("scrap") + p.hotbar.count("scrap"), 5, "straight into the pack")


# ------------------------------------------------------------- coming out --

func test_leaving_gives_back_exactly_what_you_walked_in_with() -> void:
	_veteran()
	var bag_before := p.bag.to_record()
	var hot_before := p.hotbar.to_record()
	var perks_before := p.perks.duplicate()
	_enter()
	# Take a rifle out of the ranged locker, and get bitten a little.
	var t: Vector2i = sim.world.range_lockers[2]
	var store: Slots = sim.structs.at_tile(t.x, t.y).store
	var gun := store.id_at(0)
	p.hotbar.add(gun, 1)
	Mutation.add(sim, p, 10.0, "test")
	_leave()
	ok(sim.instance == null, "out")
	eq(sim.world.layout, "town")
	eq(p.bag.to_record(), bag_before, "the pack you walked in with")
	eq(p.hotbar.to_record(), hot_before, "the hotbar you walked in with")
	eq(p.hotbar.count(gun) + p.bag.count(gun), 0, "and nothing from the range")
	eq(p.level, 7)
	eq(p.skill_points, 2)
	eq(p.perks, perks_before)
	near(p.mutation, 30.0, 0.01, "the meter as it was: what happened inside stays inside")


func test_leaving_puts_you_where_a_new_game_starts() -> void:
	var start := TargetRange.main_spawn(sim)
	p.pos = start + Vector2(2000, 0)
	_enter()
	_leave()
	ok(p.pos.distance_to(start) < 64.0, "at the main spawn, not where you went in")


func test_the_exit_door_leaves_too() -> void:
	_enter()
	var f := {}
	for g in sim.world.features:
		if String(g.kind) == "range_exit":
			f = g
	ok(not f.is_empty(), "the range has a way out")
	p.pos = f.stand + Vector2(0, -24)
	p.prev_pos = p.pos
	var target := Interact.best_target(sim, p)
	eq(String(target.get("kind", "")), "range_exit", "E at the door offers the way out")


# ------------------------------------------------------------------ dying --

func test_dying_in_the_range_gets_you_up_at_its_entrance_with_your_things() -> void:
	_enter()
	p.hotbar.add("pistol", 1)
	p.pos = sim.world.entry_spot + Vector2(900, -400)
	Damage.kill_player(sim, p)
	ok(p.dead)
	run(sim, float(Config.PLAYER.respawn_time) + 0.2)
	ok(not p.dead, "back on your feet")
	ok(sim.instance != null and sim.instance.kind == "range", "still in the range")
	ok(p.pos.distance_to(sim.world.entry_spot) < 64.0, "at the entrance")
	eq(p.hotbar.count("pistol"), 1, "carrying what you had")


# ------------------------------------------------------------- controls --

func _wearing_weapon() -> String:
	for id: String in Config.WEAPONS:
		if Wear.wears(id):
			return id
	return ""


func test_wear_is_off_in_the_range_until_it_is_switched_on() -> void:
	_enter()
	var id := _wearing_weapon()
	p.hotbar.add(id, 1)
	p.slot = _slot_of(p.hotbar, id)
	var before := Wear.left(p.hotbar, p.slot)
	Wear.use(sim, p, p.hotbar, p.slot, 5)
	eq(Wear.left(p.hotbar, p.slot), before, "no uses spent")
	ok(TargetRange.control(sim, p, "wear"))
	ok(sim.instance.range_wear)
	Wear.use(sim, p, p.hotbar, p.slot, 5)
	eq(Wear.left(p.hotbar, p.slot), before - 5, "spent once it is on")


func test_the_level_control_moves_the_held_weapon_between_one_and_the_max() -> void:
	_enter()
	p.hotbar.add("pistol", 1)
	p.slot = _slot_of(p.hotbar, "pistol")
	ok(TargetRange.control(sim, p, "level", {"d": 1}))
	eq(p.hotbar.level_at(p.slot), 2)
	for i in range(10):
		TargetRange.control(sim, p, "level", {"d": 1})
	eq(p.hotbar.level_at(p.slot), int(Config.UPGRADE.max), "no higher than the max")
	for i in range(10):
		TargetRange.control(sim, p, "level", {"d": -1})
	ok(p.hotbar.level_at(p.slot) <= 1, "no lower than 1")


func test_controls_do_nothing_outside_the_range() -> void:
	for verb in ["leave", "restock", "wear", "level"]:
		ok(not TargetRange.control(sim, p, verb), verb)


func test_a_release_host_refuses_a_guests_range_control() -> void:
	Actions.dev = false
	ok(not Actions.execute(sim, p, "range", {"verb": "enter"}))
	ok(sim.instance == null)
	Actions.dev = true
	ok(Actions.execute(sim, p, "range", {"verb": "enter"}))
	ok(sim.instance != null)


# ------------------------------------------------------------------ walls --

func test_the_range_walls_cannot_be_broken() -> void:
	_enter()
	var w := sim.world
	var r: Rect2i = w.range_rooms[0]
	var wall := Vector2i(r.position.x + 3, r.position.y)
	eq(w.tiles[wall.y * World.W + wall.x], Config.T.WALL, "a room's wall")
	for i in range(50):
		ok(not w.damage_wall(wall.x, wall.y, 10000.0))
	eq(w.tiles[wall.y * World.W + wall.x], Config.T.WALL, "still a wall")


func test_the_lane_is_long_enough_to_hear_a_shot_fade() -> void:
	_enter()
	gt(float(sim.world.range_lane.size.x * Config.TILE), Config.SFX_RANGE, "longer than a sound carries")


func test_every_live_room_has_one_doorway() -> void:
	_enter()
	var w := sim.world
	eq(w.range_rooms.size(), 6)
	for r: Rect2i in w.range_rooms:
		var gaps := 0
		for x in range(r.position.x, r.end.x):
			for y in [r.position.y, r.end.y - 1]:
				if not w.blocked[y * World.W + x]:
					gaps += 1
		for y in range(r.position.y + 1, r.end.y - 1):
			for x in [r.position.x, r.end.x - 1]:
				if not w.blocked[y * World.W + x]:
					gaps += 1
		eq(gaps, 2, "one doorway, two tiles wide")


# ----------------------------------------------------------------- saving --

func test_a_save_from_inside_writes_what_you_walked_in_with() -> void:
	_veteran()
	var bag_before := p.bag.to_record()
	_enter()
	p.hotbar.add("pistol", 1)
	var data := SaveGame.to_dict(sim)
	ok(sim.instance != null and sim.world.layout == "range", "still in the range after writing it")
	var rec: Dictionary = data.players[0]
	eq(rec.bag, bag_before, "the pack you walked in with")
	eq(int(rec.level), 7, "your own level")
	near(float(rec.mutation), 30.0, 1e-6)
	near(float(rec.x), sim.instance.door.x, 1e-3, "written at the spot you would come out")
	var back := new_sim()
	ok(SaveGame.apply(back, data).ok, "and it loads")
	eq(back.players[0].level, 7)
	ok(back.instance == null, "into the town")


# ------------------------------------------------------------------ co-op --

func _table() -> Dictionary:
	if _guest_world == null:
		_guest_world = World.new()
	NetGuest.reuse_world = _guest_world
	var host := NetHost.new(sim, "Ryan", NetProtocol.hash_password(""))
	var ends: Array = NetLink.Loopback.pair(0.0, 0.0)
	host.attach(ends[0])
	var guest := NetGuest.new(ends[1], "guest-a", "Bex", NetProtocol.hash_password(""))
	var t := {"host": host, "guest": guest, "gp": null}
	_pump(t, 0.1)
	t.gp = sim.player_by_identity("guest-a")
	(t.gp as PlayerSim).god_mode = true
	return t


func _pump(t: Dictionary, seconds: float) -> void:
	for i in range(int(round(seconds / DT))):
		var guest: NetGuest = t.guest
		var host: NetHost = t.host
		guest.poll()
		guest.tick(DT)
		host.poll()
		sim.tick(DT)
		host.after_tick(DT)
		sim.events.clear()
		host.on_events_cleared()


func test_a_guest_can_take_the_party_in_and_sees_the_lockers() -> void:
	var t := _table()
	var g: NetGuest = t.guest
	Actions.guest = g
	Actions.range_control(g.sim, g.me, "enter")
	_pump(t, 0.6)
	ok(sim.instance != null and sim.instance.kind == "range", "the host ran the guest's F1")
	ok(g.sim.instance != null and g.sim.world.layout == "range", "the guest's mirror followed")
	eq(g.sim.world.fingerprint(), sim.world.fingerprint(), "the same range")
	var tl: Vector2i = sim.world.range_lockers[2]
	var mine: Dictionary = g.sim.structs.at_tile(tl.x, tl.y)
	ok(not mine.is_empty() and mine.store != null, "the guest has the locker")
	eq((mine.store as Slots).to_record(), (sim.structs.at_tile(tl.x, tl.y).store as Slots).to_record(),
		"with what the host has in it")


func test_a_guest_can_switch_wear_and_level_and_leave() -> void:
	var t := _table()
	var gp: PlayerSim = t.gp
	gp.bag.add("scrap", 9)
	var bag_before := gp.bag.to_record()
	var g: NetGuest = t.guest
	Actions.guest = g
	Actions.range_control(g.sim, g.me, "enter")
	_pump(t, 0.6)
	eq(gp.bag.used(), 0, "the guest went in empty-handed too")
	Actions.range_control(g.sim, g.me, "wear")
	_pump(t, 0.6)
	ok(sim.instance.range_wear, "the guest's wear switch reached the host")
	ok(g.sim.instance.range_wear, "and came back on the record")
	gp.hotbar.add("pistol", 1)
	gp.slot = _slot_of(gp.hotbar, "pistol")
	Actions.range_control(g.sim, g.me, "level", {"d": 1})
	_pump(t, 0.3)
	eq(gp.hotbar.level_at(gp.slot), 2, "the guest's held weapon went up a level")
	(t.gp as PlayerSim).pos = p.pos + Vector2(20, 0)
	Actions.range_control(g.sim, g.me, "leave")
	_pump(t, 0.6)
	ok(sim.instance == null, "the guest took the party out")
	ok(g.sim.instance == null, "and the mirror came out with it")
	eq(gp.bag.to_record(), bag_before, "with the guest's own pack back")
