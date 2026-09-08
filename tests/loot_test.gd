extends "res://tests/test_case.gd"
## Loot: the tables, searching a container, what overflows, ground pickups,
## and the pack you leave behind when you die.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.pos = tile_centre(clear_plot(6))


static var _priv: World

## A private world, because searching a container marks it looted for good
## and the shared one is read by every other test. Generated once and reset
## between tests — a second generation costs a third of a second.
func _own_sim() -> GameSim:
	if _priv == null:
		_priv = World.new()
	for c in _priv.containers:
		c.looted = false
	var s := GameSim.new()
	s.start(_priv, 7)
	s.enemies.list.clear()
	s.events.clear()
	return s


func _container_of(s: GameSim, kind: String) -> Dictionary:
	for c in s.world.containers:
		if c.kind == kind and not c.looted:
			return c
	return {}


## Stands the player beside `c` and holds the interact key until whatever the
## sim decided to search is finished. Returns the container it actually
## searched, which is not always the one asked for: furniture stands
## shoulder to shoulder and the key goes to the nearest.
func _search_beside(s: GameSim, q: PlayerSim, c: Dictionary) -> Dictionary:
	q.pos = Vector2(c.x, c.y + 20)
	q.intent.interact = true
	q.intent.interact_held = true
	s.tick(1.0 / 60.0)
	if q.searching.is_empty():
		return {}
	var searched: Dictionary = q.searching.container
	for i in range(300):
		q.intent.interact_held = true
		s.tick(1.0 / 60.0)
		if searched.looted:
			break
	return searched


# ------------------------------------------------------------------ tables --

func test_every_loot_entry_names_something_that_exists() -> void:
	for table_id in Config.LOOT:
		var table: Array = Config.LOOT[table_id]
		ok(not table.is_empty(), table_id)
		for e in table:
			var d := Loot.entry_to_pickup(e.id)
			var known := Items.has(d.id)
			ok(known, "%s: %s" % [table_id, e.id])
			ok(e.min >= 1 and e.max >= e.min, "%s: %s range" % [table_id, e.id])
			ok(e.w > 0, "%s: %s weight" % [table_id, e.id])


func test_every_container_archetype_has_a_table() -> void:
	for kind in Config.CONTAINERS:
		var def: Dictionary = Config.CONTAINERS[kind]
		has(Config.LOOT, def.table, kind)
		ok(def.rolls[0] >= 1 and def.rolls[1] >= def.rolls[0], kind)


func test_the_entry_grammar_survives_a_round_trip() -> void:
	for id in ["scrap", "bandage", "rifle", "milVest"]:
		var entry := Loot.item_entry_id(id)
		var back := Loot.entry_to_pickup(entry)
		eq(back.id, id, entry)
		eq(Loot.pickup_entry_id({"kind": back.kind, "id": back.id}), entry)


func test_a_roll_is_repeatable_for_a_seed() -> void:
	var a := _own_sim()
	var b := _own_sim()
	var ca := _container_of(a, "toolbox")
	var cb := _container_of(b, "toolbox")
	eq(str(Loot.roll_container(a, ca)), str(Loot.roll_container(b, cb)))


# --------------------------------------------------------------- searching --

func test_searching_a_container_empties_it_once() -> void:
	var s := _own_sim()
	var q := s.players[0]
	var c := _container_of(s, "toolbox")
	ok(not c.is_empty(), "the world has a toolbox in it")
	var searched := _search_beside(s, q, c)
	ok(not searched.is_empty(), "holding E starts the search")
	ok(searched.looted, "and it finishes")
	gt(q.bag.used(), 0, "with something in the pack")
	eq(s.stats.looted, 1)

	# A looted container is never offered again.
	var again := Interact.best_target(s, q)
	ok(again.is_empty() or again.ref != searched, "that one is empty now")
	# And searching it a second time cannot pay twice.
	q.intent.interact = true
	q.intent.interact_held = true
	s.tick(1.0 / 60.0)
	if not q.searching.is_empty():
		ne(q.searching.container, searched)


func test_letting_go_of_the_key_abandons_the_search() -> void:
	var s := _own_sim()
	var q := s.players[0]
	var c := _container_of(s, "cabinet")
	q.pos = Vector2(c.x, c.y + 20)
	q.intent.interact = true
	q.intent.interact_held = true
	s.tick(1.0 / 60.0)
	ok(not q.searching.is_empty())
	for i in range(40):
		q.intent.interact_held = false
		s.tick(1.0 / 60.0)
	ok(q.searching.is_empty(), "the channel stopped")
	ok(not c.looted, "and the container is still full")


func test_walking_away_abandons_the_search() -> void:
	var s := _own_sim()
	var q := s.players[0]
	var c := _container_of(s, "cabinet")
	q.pos = Vector2(c.x, c.y + 20)
	q.intent.interact = true
	q.intent.interact_held = true
	s.tick(1.0 / 60.0)
	q.pos = Vector2(c.x + 600, c.y)
	q.intent.interact_held = true
	s.tick(1.0 / 60.0)
	ok(q.searching.is_empty())
	ok(not c.looted)


# ---------------------------------------------------------------- overflow --

func test_what_will_not_fit_lands_on_the_ground() -> void:
	var s := _own_sim()
	var q := s.players[0]
	# A pack with room for nothing: weight spent, every slot taken.
	for i in range(q.bag.size()):
		q.bag.slots[i] = {"id": "stone", "n": 50}
	var before := q.bag.count("stone")
	var result := Loot.grant_loot(s, q, [{"id": "scrap", "n": 10}, {"id": "weapon:rifle", "n": 1}], q.pos)
	eq(q.bag.count("stone"), before, "nothing was pushed out of the pack")
	var on_ground := 0
	for it in s.pickups:
		on_ground += it.n
	gt(on_ground, 0, "the haul is at your feet instead")
	ok(not result.lines.is_empty())


func test_harvesting_into_a_full_pack_drops_the_wood_rather_than_losing_it() -> void:
	var s := _own_sim()
	var q := s.players[0]
	for i in range(q.bag.size()):
		q.bag.slots[i] = {"id": "stone", "n": 50}
	Loot.give_res_or_drop(s, q, "wood", 8, q.pos)
	eq(q.bag.count("wood"), 0)
	var wood := 0
	for it in s.pickups:
		if it.id == "wood":
			wood += it.n
	eq(wood, 8, "all eight are on the ground")


# --------------------------------------------------------------- backpacks --

func test_dying_leaves_a_pack_you_can_walk_back_to() -> void:
	sim.give_test_kit(p)
	var carried := p.bag.count("ammoP")
	gt(carried, 0)
	p.bag.add("milVest", 1)
	Equipment.equip_best(sim, p)
	gt(p.armor_dr, 0.0)

	Damage.kill_player(sim, p)
	eq(sim.backpacks.size(), 1, "your pack is where you fell")
	eq(p.bag.used(), 0, "and you are carrying nothing")
	eq(p.armor_dr, 0.0, "losing the armour costs the mitigation")
	eq(p.weapon().id, "pipe", "you keep the pipe, so a respawn is not toothless")

	var pack: Dictionary = sim.backpacks[0]
	has(pack.held, "ammoP")
	has(pack.held, "milVest")
	p.dead = false
	p.pos = pack.pos
	eq(Loot.collect_backpack(sim, p, pack) > 0, true)
	eq(sim.backpacks.size(), 0, "recovered")
	eq(p.bag.count("ammoP"), carried)


func test_the_pack_is_what_the_interact_key_offers_first() -> void:
	sim.give_test_kit(p)
	Damage.kill_player(sim, p)
	p.dead = false
	p.pos = sim.backpacks[0].pos
	var target := Interact.best_target(sim, p)
	eq(target.get("kind", ""), "backpack")


# ------------------------------------------------------------- enemy drops --

func test_bodies_pay_out_often_enough_to_keep_a_gun_fed() -> void:
	var s := _own_sim()
	s.players[0].pos = Vector2(-9000, -9000)      # out of magnet range
	var dropped := 0
	for i in range(120):
		var e := s.enemies.spawn("walker", Vector2(2000 + i * 40, 2000), true)
		Damage.kill_enemy(s, e)
	for it in s.pickups:
		dropped += 1
	gt(dropped, 20, "120 walkers dropped %d piles" % dropped)


# ---------------------------------------------------------------- gathering --

func test_litter_is_picked_up_by_hand() -> void:
	var s := _own_sim()
	var q := s.players[0]
	var prop := {}
	for pr in s.world.props:
		if pr.get("hand", false) and pr.harvest.begins_with("litter"):
			prop = pr
			break
	ok(not prop.is_empty(), "the ground has litter on it")
	q.pos = Vector2(prop.x, prop.y + 20)
	var rule: Dictionary = Config.HARVEST[prop.harvest]
	var before := q.bag.count(rule.res)
	q.intent.interact = true
	s.tick(1.0 / 60.0)
	gt(q.bag.count(rule.res), before, "gathered %s" % rule.res)
	ok(s.world.prop_at_tile(prop.tx, prop.ty).is_empty(), "and it is gone from the ground")


# ------------------------------------------------ the Codex review, PR #3 --

func test_a_raid_payout_that_does_not_fit_lands_on_the_ground() -> void:
	var s := _own_sim()
	var q := s.players[0]
	for i in range(q.bag.size()):
		q.bag.slots[i] = {"id": "stone", "n": 50}
	var carried := q.carried_weight()
	s.raids_done = 0
	var raid := Raid.start(s)
	raid.killed = raid.total
	raid.force_end(s)
	near(q.carried_weight(), carried, 0.01, "the payout added nothing to a pack with no room")
	var scrap := 0
	for it in s.pickups:
		if it.id == "scrap":
			scrap += it.n
	eq(scrap, 30, "the salvage is at your feet instead")


func test_a_gun_you_cannot_carry_stays_on_the_ground() -> void:
	var s := _own_sim()
	var q := s.players[0]
	q.hotbar.clear_all()
	# 199.5 of 200 units: a free grid slot, but no room for a six-unit rifle.
	q.bag.add_capped("stone", 400, q.pack_allowance())
	near(q.carried_weight(), 199.5, 0.01)
	var r := Loot.give_entry(s, q, {"id": "weapon:rifle", "n": 1})
	ok(r.has("overflow"), "refused: %s" % r.text)
	eq(q.count_carried("rifle"), 0)
	ok(not q.overloaded(), "weight is the cap, for a gun as much as for scrap")


func test_two_rolls_of_one_weapon_are_two_weapons() -> void:
	var s := _own_sim()
	# A rack that can only produce pipes, three rolls of it. Aggregating those
	# into `{pipe, n: 3}` would hand over one pipe and destroy two, because a
	# weapon has no count.
	var rack := {"table": "toolrack", "rolls": [4, 4]}
	var seen_duplicate := false
	for attempt in range(300):
		var entries := Loot.roll_container(s, rack)
		var per_weapon := {}
		for e in entries:
			var d := Loot.entry_to_pickup(e.id)
			if Items.stack_limit(d.id) > 1:
				continue
			eq(e.n, 1, "%s came back as a stack of %d" % [e.id, e.n])
			per_weapon[e.id] = per_weapon.get(e.id, 0) + 1
		for id in per_weapon:
			if per_weapon[id] > 1:
				seen_duplicate = true
	ok(seen_duplicate, "a tool rack did roll the same tool twice, and gave both")


func test_a_duplicate_gun_pays_out_as_ammunition() -> void:
	var s := _own_sim()
	var q := s.players[0]
	Loot.grant_loot(s, q, [{"id": "weapon:rifle", "n": 1}], q.pos)
	eq(q.count_carried("rifle"), 1)
	var before := q.count_res("ammoR")
	Loot.grant_loot(s, q, [{"id": "weapon:rifle", "n": 1}], q.pos)
	eq(q.count_carried("rifle"), 1, "you do not carry two")
	gt(q.count_res("ammoR"), before, "the second paid out as ammunition")


func test_spare_ammo_that_does_not_fit_is_not_destroyed() -> void:
	var s := _own_sim()
	var q := s.players[0]
	q.hotbar.clear_all()
	q.bag.add("rifle", 1)
	# Fill the rest by weight, leaving no room for the 16 spare rounds.
	q.bag.add_capped("stone", 400, q.pack_allowance())
	var before := q.count_res("ammoR")
	Loot.give_entry(s, q, {"id": "weapon:rifle", "n": 1})
	var on_ground := 0
	for it in s.pickups:
		if it.id == "ammoR":
			on_ground += it.n
	eq(q.count_res("ammoR") - before + on_ground, 16, "all sixteen rounds went somewhere")
	gt(on_ground, 0, "and what did not fit is on the ground")


func test_the_magazine_goes_into_the_pack_with_the_gun() -> void:
	sim.give_test_kit(p)
	p.mag["pistol"] = 3
	Damage.kill_player(sim, p)
	var pack: Dictionary = sim.backpacks[0]
	eq(pack.mag.pistol, 3, "the pack remembers what was loaded")
	ok(not p.mag.has("pistol"), "and the corpse does not")

	# A replacement found before the pack is recovered comes as it was found.
	p.dead = false
	Loot.give_entry(sim, p, {"id": "weapon:pistol", "n": 1})
	eq(p.mag.pistol, Config.WEAPONS.pistol.mag, "a fresh pistol, not the dead one's three rounds")
