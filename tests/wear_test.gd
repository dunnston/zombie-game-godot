extends "res://tests/test_case.gd"
## Weapons wearing out, breaking, and being mended at the bench that made
## them. The table, the one writer, the gate, the bill, and the two places
## wear has to survive a round trip: a save and a death.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(8)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0


func _stock(n := 400) -> void:
	for id in ["wood", "stone", "sticks", "fiber", "scrap", "cloth", "elec", "parts", "mil", "med"]:
		p.bag.add(id, n)


func _hold(id: String) -> Dictionary:
	p.hotbar.slots[0] = {"id": id, "n": 1}
	p.slot = 0
	return Config.WEAPONS[id]


# ------------------------------------------------------------------ tables --

func test_every_weapon_that_wears_can_be_mended_somewhere() -> void:
	# The one rule that has to hold across the two tables: if a weapon wears
	# out, something has to be able to fix it, or it is a trap. Fists are the
	# deliberate exception and they carry no `dur` at all.
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		if id == "fists":
			ok(not Wear.wears(id), "fists do not wear")
			continue
		ok(Wear.wears(id), "%s has no durability" % id)
		gt(Wear.max_of(id), 0, id)
		ok(not Wear.recipe_for(id).is_empty(),
			"%s wears out and nothing in RECIPES makes it" % id)
		# A gun gets far more uses than a club because it spends one per
		# round, and an SMG empties a magazine in two seconds.
		if w.kind == "gun":
			gt(Wear.max_of(id), 200, id)


func test_a_weapon_nobody_makes_is_mended_nowhere() -> void:
	# What a unique, found-only weapon would lean on: no recipe, so no bench,
	# and a bigger `dur` to pay for it. There is no such weapon in the game
	# today — every weapon but Fists is craftable, and the table test above
	# holds that line — so this proves the rule from the pieces it is built
	# out of rather than from content that does not exist yet.
	#
	# `RECIPES` is a const the engine will not let a test edit, which is why
	# this is not done by taking the Machete's recipe away for a moment.
	ok(Wear.recipe_for("fists").is_empty(), "nothing makes fists")
	ok(Wear.repair_cost(p, "fists").is_empty(), "so there is no bill to pay")
	ok(not Wear.repair_status(sim, p, "fists", 2).ok,
		"and no bench tier is the one that mends it")


# ------------------------------------------------------------------ wearing --

func test_a_swing_that_connects_costs_a_use_and_one_at_air_costs_nothing() -> void:
	var w := _hold("pipe")
	var full := Wear.max_of("pipe")
	eq(Wear.left(p, "pipe"), full, "unknown means whole")

	Combat.melee_attack(sim, p, w)
	eq(Wear.left(p, "pipe"), full, "a swing at nothing is free")

	sim.enemies.spawn("walker", p.pos + Vector2(30, 0), true)
	sim.enemies.rebuild_spatial()
	p.angle = 0.0
	Combat.melee_attack(sim, p, w)
	eq(Wear.left(p, "pipe"), full - 1, "a swing that bites costs one")


func test_a_shot_costs_a_use() -> void:
	var w := _hold("pistol")
	p.mag["pistol"] = 12
	var full := Wear.max_of("pistol")
	ok(Combat.fire_gun(sim, p, w))
	eq(Wear.left(p, "pistol"), full - 1)
	# A dry trigger is not a shot: it starts a reload and spends nothing.
	p.mag["pistol"] = 0
	ok(not Combat.fire_gun(sim, p, w))
	eq(Wear.left(p, "pistol"), full - 1, "an empty gun does not wear")


func test_chopping_costs_more_than_fighting() -> void:
	eq(int(Config.WEAR.chop_mul), 2, "work is harder on a tool than a walker")
	var before := Wear.left(p, "axe")
	Wear.use(sim, p, "axe", int(Config.WEAR.chop_mul))
	eq(Wear.left(p, "axe"), before - 2)


func test_wear_stops_at_zero_and_never_goes_under() -> void:
	Wear.use(sim, p, "knife", Wear.max_of("knife") + 500)
	eq(Wear.left(p, "knife"), 0)
	ok(Wear.is_broken(p, "knife"))
	Wear.use(sim, p, "knife", 5)
	eq(Wear.left(p, "knife"), 0, "a broken thing does not get more broken")


func test_fists_never_wear() -> void:
	Wear.use(sim, p, "fists", 50)
	ok(not p.wear.has("fists"), "nothing was written")
	ok(not Wear.is_broken(p, "fists"), "and you can always punch")
	eq(Wear.frac(p, "fists"), 1.0, "something that cannot wear reads as whole")


func test_the_warnings_fire_once_per_crossing() -> void:
	var cap := Wear.max_of("pipe")
	# Down to just above the worn mark: nothing said yet.
	p.wear["pipe"] = int(cap * Config.WEAR.worn_at) + 2
	sim.events.clear()
	Wear.use(sim, p, "pipe", 1)
	eq(events_of(sim, "notify").size(), 0, "still above the mark, still quiet")
	Wear.use(sim, p, "pipe", 2)
	eq(events_of(sim, "notify").size(), 1, "crossing it says so once")
	Wear.use(sim, p, "pipe", 1)
	eq(events_of(sim, "notify").size(), 1, "and does not keep saying it")


func test_breaking_says_so_and_emits() -> void:
	p.wear["pipe"] = 1
	sim.events.clear()
	Wear.use(sim, p, "pipe", 1)
	eq(events_of(sim, "broke").size(), 1, "the view is told")


# ------------------------------------------------------------------ broken --

func test_a_broken_weapon_refuses_rather_than_swinging_badly() -> void:
	var w := _hold("pipe")
	sim.enemies.spawn("walker", p.pos + Vector2(30, 0), true)
	sim.enemies.rebuild_spatial()
	p.angle = 0.0
	var e: EnemySim = sim.enemies.list[0]
	var hp := e.hp

	p.wear["pipe"] = 0
	ok(not Combat.melee_attack(sim, p, w), "it refuses")
	eq(e.hp, hp, "and the walker is untouched")

	# Mended, the same swing lands. Nothing about the weapon's numbers
	# changed on the way down — it is whole or it is broken.
	Wear.mend(p, "pipe")
	ok(Combat.melee_attack(sim, p, w))
	ok(e.hp < hp, "the same swing bites again")


func test_a_broken_gun_does_not_fire() -> void:
	var w := _hold("pistol")
	p.mag["pistol"] = 12
	p.wear["pistol"] = 0
	ok(not Combat.fire_gun(sim, p, w))
	eq(p.mag["pistol"], 12, "and it does not eat the round either")


# ------------------------------------------------------------------ mending --

func test_mending_costs_a_share_of_the_recipe_scaled_by_the_damage() -> void:
	_stock()
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	# The Machete costs 24 scrap and 1 weapon part. Half gone, at a half
	# share, is 24 * 0.5 * 0.5 = 6 scrap.
	p.wear["machete"] = Wear.max_of("machete") / 2
	var cost := Wear.repair_cost(p, "machete")
	eq(cost.get("scrap", 0), 6)
	# A part is 1 * 0.5 * 0.5 = 0.25, which rounds away — a scratch does not
	# cost a weapon part, exactly as it does not on a wall.
	ok(not cost.has("parts"), "the trimming a light repair would not use")

	var scrap := p.count_res("scrap")
	ok(Actions.repair_weapon(sim, p, "machete", 1))
	eq(Wear.left(p, "machete"), Wear.max_of("machete"), "back to new")
	eq(p.count_res("scrap"), scrap - 6, "and it was paid for")


func test_the_repair_bill_ignores_the_building_discount() -> void:
	# `Structures.repair_cost` takes `build_cost_mul` and this deliberately
	# does not: that multiplier is Engineer and the Intelligence ladder making
	# what you *construct* cheaper, and crafting a Machete already ignores it.
	# A high-INT survivor must not find mending cheaper than making.
	_stock()
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.wear["machete"] = Wear.max_of("machete") / 2
	var plain := Wear.repair_cost(p, "machete")
	p.build_cost_mul = 0.5
	eq(Wear.repair_cost(p, "machete"), plain, "the engineer mends at the same price")


func test_a_repair_is_never_free() -> void:
	_stock()
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.wear["machete"] = Wear.max_of("machete") - 1     # one swing's worth
	var cost := Wear.repair_cost(p, "machete")
	eq(cost.get("scrap", 0), 1, "the main material is always at least one")


func test_mending_happens_at_the_bench_that_makes_it_and_nowhere_else() -> void:
	_stock()
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.wear["machete"] = 10

	var st := Wear.repair_status(sim, p, "machete", 0)
	ok(not st.ok, "a Machete is bench-1 work")
	eq(st.reason, "Needs a Workbench")
	ok(not Actions.repair_weapon(sim, p, "machete", 0), "and asking anyway fails")
	eq(Wear.left(p, "machete"), 10, "nothing was mended")

	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	ok(Wear.repair_status(sim, p, "machete", Crafting.bench_tier_at(sim, p)).ok,
		"beside the bench that makes it, yes")


func test_a_hatchet_is_mended_by_hand_because_it_is_made_by_hand() -> void:
	# The gate is the recipe's own, so bench-0 work needs no bench to mend.
	_stock()
	p.hotbar.slots[0] = {"id": "axe", "n": 1}
	p.wear["axe"] = 10
	ok(Wear.repair_status(sim, p, "axe", 0).ok, "in a field, with your hands")
	ok(Actions.repair_weapon(sim, p, "axe", 0))
	eq(Wear.left(p, "axe"), Wear.max_of("axe"))


func test_mending_something_you_are_not_carrying_is_refused() -> void:
	_stock()
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	p.wear["machete"] = 5
	var st := Wear.repair_status(sim, p, "machete", 1)
	ok(not st.ok)
	eq(st.reason, "You are not carrying one")


func test_mending_without_the_materials_is_refused() -> void:
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.wear["machete"] = 1
	var st := Wear.repair_status(sim, p, "machete", 1)
	ok(not st.ok)
	eq(st.reason, "Missing materials")
	ok(not Actions.repair_weapon(sim, p, "machete", 1))
	eq(Wear.left(p, "machete"), 1, "and it stayed broken rather than half-mending")


func test_an_intact_weapon_is_not_listed_and_not_mendable() -> void:
	_stock()
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	eq(Wear.worn_carried(p).size(), 0, "nothing worn, nothing to list")
	ok(not Wear.repair_status(sim, p, "machete", 1).ok)
	ok(Wear.repair_cost(p, "machete").is_empty(), "and it costs nothing to do nothing")


func test_the_worn_list_is_what_you_carry_in_either_container() -> void:
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.bag.add("axe", 1)
	p.bag.add("pistol", 1)
	p.wear["machete"] = 5
	p.wear["axe"] = 5
	var worn := Wear.worn_carried(p)
	eq(worn.size(), 2, "the worn two, not the whole pistol")
	ok(worn.has("machete") and worn.has("axe"))


# ---------------------------------------------------------------- it travels --

func test_wear_survives_a_save() -> void:
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.wear["machete"] = 42
	var payload := SaveGame.to_dict(sim)
	var fresh := new_sim()
	var r := SaveGame.apply(fresh, payload)
	ok(r.ok, r.reason)
	eq(Wear.left(fresh.players[0], "machete"), 42, "the bench still has work to do")


func test_wear_goes_into_the_pack_you_drop_and_comes_back_with_it() -> void:
	# Otherwise walking back to your own corpse would be the cheapest bench
	# in the game.
	p.hotbar.slots[0] = {"id": "machete", "n": 1}
	p.wear["machete"] = 7
	var pack := Loot.drop_backpack(sim, p)
	ok(not pack.is_empty(), "there was something to drop")
	eq(int(pack.wear.get("machete", -1)), 7, "the wear went with it")
	ok(not p.wear.has("machete"), "and did not stay on the player")

	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	Loot.collect_backpack(sim, p, pack)
	eq(Wear.left(p, "machete"), 7, "recovered exactly as worn as it was")


func test_wear_crosses_the_wire_with_the_pack() -> void:
	p.wear["machete"] = 13
	var rec := NetProtocol.pack_inventory(p)
	var other := new_sim()
	var guest: PlayerSim = other.players[0]
	NetProtocol.apply_inventory(guest, rec)
	eq(Wear.left(guest, "machete"), 13, "a guest knows what its own axe has left")
