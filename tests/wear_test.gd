extends "res://tests/test_case.gd"
## Weapons wearing out, breaking, and being mended at the bench that made
## them. The table, the one writer, the gate, the bill — and the thing the
## whole design turns on: **condition belongs to the weapon, not the
## carrier**, so it has to survive every way a weapon changes hands.

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


func _hold(id: String, wear := -1) -> Dictionary:
	p.hotbar.slots[0] = {"id": id, "n": 1}
	if wear >= 0:
		p.hotbar.set_wear_at(0, wear)
	p.slot = 0
	return Config.WEAPONS[id]


func _recipe(id: String) -> Dictionary:
	for r in Config.RECIPES:
		if r.id == id:
			return r
	return {}


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
	ok(Wear.recipe_for("fists").is_empty(), "nothing makes fists")
	_hold("fists")
	ok(Wear.repair_cost(p.hotbar, 0).is_empty(), "so there is no bill to pay")
	ok(not Wear.repair_status(sim, p, "hotbar", 0, 2).ok,
		"and no bench tier is the one that mends it")


# ------------------------------------------------------------------ wearing --

func test_a_swing_that_connects_costs_a_use_and_one_at_air_costs_nothing() -> void:
	var w := _hold("pipe")
	var full := Wear.max_of("pipe")
	eq(Wear.left(p.hotbar, 0), full, "an unset slot is a whole weapon")

	Combat.melee_attack(sim, p, w)
	eq(Wear.left(p.hotbar, 0), full, "a swing at nothing is free")

	sim.enemies.spawn("walker", p.pos + Vector2(30, 0), true)
	sim.enemies.rebuild_spatial()
	p.angle = 0.0
	Combat.melee_attack(sim, p, w)
	eq(Wear.left(p.hotbar, 0), full - 1, "a swing that bites costs one")


func test_a_shot_costs_a_use() -> void:
	var w := _hold("pistol")
	p.mag["pistol"] = 12
	var full := Wear.max_of("pistol")
	ok(Combat.fire_gun(sim, p, w))
	eq(Wear.left(p.hotbar, 0), full - 1)
	# A dry trigger is not a shot: it starts a reload and spends nothing.
	p.mag["pistol"] = 0
	ok(not Combat.fire_gun(sim, p, w))
	eq(Wear.left(p.hotbar, 0), full - 1, "an empty gun does not wear")


func test_wear_lands_on_the_slot_in_hand_and_not_on_its_twin() -> void:
	# The reason condition is on the object: two of a kind are two things.
	_hold("axe")
	p.hotbar.slots[1] = {"id": "axe", "n": 1}
	sim.enemies.spawn("walker", p.pos + Vector2(30, 0), true)
	sim.enemies.rebuild_spatial()
	p.angle = 0.0
	Combat.melee_attack(sim, p, Config.WEAPONS.axe)
	eq(Wear.left(p.hotbar, 0), Wear.max_of("axe") - 1, "the one you swung")
	eq(Wear.left(p.hotbar, 1), Wear.max_of("axe"), "the one in the next slot is untouched")


func test_a_hatchet_fells_about_a_hundred_trees() -> void:
	# The owner's first session: a Hatchet that felled seventeen trees broke
	# "much too fast". Measured through the real swing, not the table.
	eq(int(Config.WEAR.chop_mul), 1, "a chop wears a tool as much as a blow")
	var axe: Dictionary = Config.WEAPONS.axe
	var per_swing: float = axe.dmg * p.melee_mul * Combat.chop_multiplier(axe, p, Config.HARVEST.wood)
	var swings_per_tree := ceili(470.0 / per_swing)
	var trees := Wear.max_of("axe") / (swings_per_tree * int(Config.WEAR.chop_mul))
	ok(trees >= 90 and trees <= 110, "a Hatchet fells %d trees" % trees)


func test_wear_stops_at_zero_and_never_goes_under() -> void:
	_hold("knife")
	Wear.use_held(sim, p, Wear.max_of("knife") + 500)
	eq(Wear.left(p.hotbar, 0), 0)
	ok(Wear.is_broken(p.hotbar, 0))
	Wear.use_held(sim, p, 5)
	eq(Wear.left(p.hotbar, 0), 0, "a broken thing does not get more broken")


func test_fists_never_wear() -> void:
	_hold("fists")
	Wear.use_held(sim, p, 50)
	ok(not Wear.is_broken(p.hotbar, 0), "and you can always punch")
	eq(Wear.frac(p.hotbar, 0), 1.0, "something that cannot wear reads as whole")


func test_the_warnings_fire_once_per_crossing() -> void:
	var cap := Wear.max_of("pipe")
	# Down to just above the worn mark: nothing said yet.
	_hold("pipe", int(cap * Config.WEAR.worn_at) + 2)
	sim.events.clear()
	Wear.use_held(sim, p, 1)
	eq(events_of(sim, "notify").size(), 0, "still above the mark, still quiet")
	Wear.use_held(sim, p, 2)
	eq(events_of(sim, "notify").size(), 1, "crossing it says so once")
	Wear.use_held(sim, p, 1)
	eq(events_of(sim, "notify").size(), 1, "and does not keep saying it")


func test_breaking_says_so_and_emits() -> void:
	_hold("pipe", 1)
	sim.events.clear()
	Wear.use_held(sim, p, 1)
	eq(events_of(sim, "broke").size(), 1, "the view is told")


# ------------------------------------------------------------------ broken --

func test_a_broken_weapon_refuses_rather_than_swinging_badly() -> void:
	var w := _hold("pipe", 0)
	sim.enemies.spawn("walker", p.pos + Vector2(30, 0), true)
	sim.enemies.rebuild_spatial()
	p.angle = 0.0
	var e: EnemySim = sim.enemies.list[0]
	var hp := e.hp

	ok(not Combat.melee_attack(sim, p, w), "it refuses")
	eq(e.hp, hp, "and the walker is untouched")

	# Mended, the same swing lands. Nothing about the weapon's numbers
	# changed on the way down — it is whole or it is broken.
	Wear.mend(p.hotbar, 0)
	ok(Combat.melee_attack(sim, p, w))
	ok(e.hp < hp, "the same swing bites again")


func test_a_broken_gun_does_not_fire() -> void:
	var w := _hold("pistol", 0)
	p.mag["pistol"] = 12
	ok(not Combat.fire_gun(sim, p, w))
	eq(p.mag["pistol"], 12, "and it does not eat the round either")


func test_a_broken_tool_is_not_a_tool() -> void:
	# "Broken weapons do nothing until mended" has to mean the bench too, or
	# a zero-condition knife still cuts cordage.
	_stock()
	p.bag.add("knife", 1)
	var knife_at := -1
	for i in range(p.bag.size()):
		if p.bag.id_at(i) == "knife":
			knife_at = i
	ok(Crafting.status(sim, p, _recipe("cordage"), 1).ok, "a whole knife cuts cordage")
	p.bag.set_wear_at(knife_at, 0)
	var st := Crafting.status(sim, p, _recipe("cordage"), 1)
	ok(not st.ok, "a broken one does not")
	eq(st.reason, "Needs a Stone Knife")


func test_every_tool_a_recipe_names_is_mendable_by_hand() -> void:
	# The deadlock rule: a broken tool must never be needed to mend itself.
	for r in Config.RECIPES:
		if r.has("tool"):
			eq(int(Wear.recipe_for(String(r.tool)).get("bench", -1)), 0, "%s needs a %s" % [r.id, r.tool])


# ------------------------------------------------------------------ mending --

func test_mending_costs_a_share_of_the_recipe_scaled_by_the_damage() -> void:
	_stock()
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	_hold("machete", Wear.max_of("machete") / 2)
	# The Machete costs 24 scrap and 1 weapon part. Half gone, at a half
	# share, is 24 * 0.5 * 0.5 = 6 scrap.
	var cost := Wear.repair_cost(p.hotbar, 0)
	eq(cost.get("scrap", 0), 6)
	# A part is 1 * 0.5 * 0.5 = 0.25, which rounds away — a scratch does not
	# cost a weapon part, exactly as it does not on a wall.
	ok(not cost.has("parts"), "the trimming a light repair would not use")

	var scrap := p.count_res("scrap")
	ok(Actions.repair_weapon(sim, p, "hotbar", 0, 1))
	eq(Wear.left(p.hotbar, 0), Wear.max_of("machete"), "back to new")
	eq(p.count_res("scrap"), scrap - 6, "and it was paid for")


func test_the_repair_bill_ignores_the_building_discount() -> void:
	# `Structures.repair_cost` takes `build_cost_mul` and this deliberately
	# does not: that multiplier is Engineer and the Intelligence ladder making
	# what you *construct* cheaper, and crafting a Machete already ignores it.
	# A high-INT survivor must not find mending cheaper than making.
	_stock()
	_hold("machete", Wear.max_of("machete") / 2)
	var plain := Wear.repair_cost(p.hotbar, 0)
	p.build_cost_mul = 0.5
	eq(Wear.repair_cost(p.hotbar, 0), plain, "the engineer mends at the same price")


func test_a_repair_is_never_free() -> void:
	_stock()
	_hold("machete", Wear.max_of("machete") - 1)     # one swing's worth
	eq(Wear.repair_cost(p.hotbar, 0).get("scrap", 0), 1,
		"the main material is always at least one")


func test_mending_happens_at_the_bench_that_makes_it_and_nowhere_else() -> void:
	_stock()
	_hold("machete", 10)

	var st := Wear.repair_status(sim, p, "hotbar", 0, 0)
	ok(not st.ok, "a Machete is bench-1 work")
	eq(st.reason, "Needs a Workbench")
	ok(not Actions.repair_weapon(sim, p, "hotbar", 0, 0), "and asking anyway fails")
	eq(Wear.left(p.hotbar, 0), 10, "nothing was mended")

	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	ok(Wear.repair_status(sim, p, "hotbar", 0, Crafting.bench_tier_at(sim, p)).ok,
		"beside the bench that makes it, yes")


func test_a_hatchet_is_mended_by_hand_because_it_is_made_by_hand() -> void:
	# The gate is the recipe's own, so bench-0 work needs no bench to mend.
	_stock()
	_hold("axe", 10)
	ok(Wear.repair_status(sim, p, "hotbar", 0, 0).ok, "in a field, with your hands")
	ok(Actions.repair_weapon(sim, p, "hotbar", 0, 0))
	eq(Wear.left(p.hotbar, 0), Wear.max_of("axe"))


func test_a_repair_may_not_name_a_chest() -> void:
	# A bench mends what you brought to it. On a guest this is also what stops
	# a slot index naming somebody else's locker.
	_stock()
	var st := Wear.repair_status(sim, p, "store", 0, 1)
	ok(not st.ok)
	eq(st.reason, "Not something you are carrying")


func test_mending_without_the_materials_is_refused() -> void:
	sim.structs.place(sim, "workbench", plot.x + 2, plot.y, p)
	_hold("machete", 1)
	var st := Wear.repair_status(sim, p, "hotbar", 0, 1)
	ok(not st.ok)
	eq(st.reason, "Missing materials")
	ok(not Actions.repair_weapon(sim, p, "hotbar", 0, 1))
	eq(Wear.left(p.hotbar, 0), 1, "and it stayed broken rather than half-mending")


func test_an_intact_weapon_is_not_listed_and_not_mendable() -> void:
	_stock()
	_hold("machete")
	eq(Wear.worn_carried(p).size(), 0, "nothing worn, nothing to list")
	ok(not Wear.repair_status(sim, p, "hotbar", 0, 1).ok)
	ok(Wear.repair_cost(p.hotbar, 0).is_empty(), "and it costs nothing to do nothing")


func test_two_of_a_kind_worn_differently_are_two_rows() -> void:
	_hold("axe", 10)
	p.bag.add("axe", 1, 40)
	var worn := Wear.worn_carried(p)
	eq(worn.size(), 2, "each one is its own job")
	eq(String(worn[0].c), "hotbar")
	eq(String(worn[1].c), "bag")
	# And mending one leaves the other alone.
	_stock()
	ok(Actions.repair_weapon(sim, p, String(worn[0].c), int(worn[0].i), 0))
	eq(Wear.left(p.hotbar, 0), Wear.max_of("axe"), "the one you mended")
	eq(Wear.left(p.bag, int(worn[1].i)), 40, "and only that one")


# --------------------------------------------------- it goes with the weapon --

func test_a_freshly_crafted_weapon_is_new_even_beside_a_broken_one() -> void:
	# The bug the player-keyed version had: your Hatchet breaks, you craft a
	# replacement, and it is born broken.
	_stock()
	_hold("axe", 0)
	ok(Crafting.craft(sim, p, _recipe("axe"), 0))
	var fresh := -1
	for i in range(p.hotbar.size()):
		if p.hotbar.id_at(i) == "axe" and i != 0:
			fresh = i
	gt(fresh, 0, "the new one went somewhere")
	eq(Wear.left(p.hotbar, fresh), Wear.max_of("axe"), "and it came off the bench whole")
	eq(Wear.left(p.hotbar, 0), 0, "without mending the broken one for free")


func test_a_broken_weapon_left_in_a_chest_is_still_broken_to_whoever_takes_it() -> void:
	# Codex's case: condition may not stay behind with the previous owner.
	_stock()
	sim.structs.place(sim, "chest", plot.x + 2, plot.y, p)
	var store := sim.structs.reachable_store(p, plot.x + 2, plot.y)
	ok(store != null, "the chest is in reach")
	_hold("machete", 5)

	ok(Equipment.move_stack(sim, p, "hotbar", 0, "store", 0, Vector2i(plot.x + 2, plot.y)))
	eq(store.id_at(0), "machete", "it is in the chest")
	eq(Wear.left(store, 0), 5, "and it took its condition with it")

	# Somebody else opens the chest. Their pack has never seen a Machete.
	var other := sim.join_player("guest-a", "Bex")
	other.pos = p.pos
	other.bag = Slots.new(200)
	other.carry_cap = 1000000.0
	ok(Equipment.move_stack(sim, other, "store", 0, "bag", 0, Vector2i(plot.x + 2, plot.y)))
	eq(Wear.left(other.bag, 0), 5, "and it is still the worn Machete it was")


func test_a_broken_weapon_dropped_on_the_ground_stays_broken() -> void:
	_hold("machete", 5)
	ok(Equipment.drop_stack(sim, p, "hotbar", 0, true))
	var pile := {}
	for it in sim.pickups:
		if it.get("id", "") == "machete":
			pile = it
	ok(not pile.is_empty(), "it is on the ground")
	eq(int(pile.get("w", -1)), 5, "with its condition")

	# Walk back onto it.
	p.hotbar.clear_all()
	pile.inert_for = null
	pile.pos = p.pos
	Loot.update_pickups(sim, 1.0 / 60.0)
	var back := p.hotbar.count("machete") + p.bag.count("machete")
	eq(back, 1, "and it comes back")
	var at := -1
	for i in range(p.hotbar.size()):
		if p.hotbar.id_at(i) == "machete":
			at = i
	eq(Wear.left(p.hotbar, at), 5, "still worn — the ground is not a bench")


func test_wear_goes_into_the_pack_you_drop_and_comes_back_with_it() -> void:
	# Otherwise walking back to your own corpse would be the cheapest bench
	# in the game.
	_hold("machete", 7)
	var pack := Loot.drop_backpack(sim, p)
	ok(not pack.is_empty(), "there was something to drop")
	eq(int(pack.wear.get("machete", -1)), 7, "the wear went with it")

	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0
	Loot.collect_backpack(sim, p, pack)
	var at := -1
	for i in range(p.bag.size()):
		if p.bag.id_at(i) == "machete":
			at = i
	gt(at, -1, "recovered")
	eq(Wear.left(p.bag, at), 7, "exactly as worn as it was")


func test_a_flattened_backpack_keeps_the_worse_of_two() -> void:
	# `held` is a flat id -> count and always has been, so two Machetes come
	# back as one condition. Keeping the worse of them means the flattening
	# can never quietly mend something.
	_hold("machete", 60)
	p.bag.add("machete", 1, 9)
	var pack := Loot.drop_backpack(sim, p)
	eq(int(pack.wear.get("machete", -1)), 9, "the worse one sets the price")


# ---------------------------------------------------------------- it travels --

func test_wear_survives_a_save() -> void:
	_hold("machete", 42)
	var payload := SaveGame.to_dict(sim)
	var fresh := new_sim()
	var r := SaveGame.apply(fresh, payload)
	ok(r.ok, r.reason)
	eq(Wear.left(fresh.players[0].hotbar, 0), 42, "the bench still has work to do")


func test_a_worn_weapon_on_the_ground_survives_a_save() -> void:
	_hold("machete", 5)
	ok(Equipment.drop_stack(sim, p, "hotbar", 0, true))
	var payload := SaveGame.to_dict(sim)
	var fresh := new_sim()
	ok(SaveGame.apply(fresh, payload).ok)
	var pile := {}
	for it in fresh.pickups:
		if it.get("id", "") == "machete":
			pile = it
	ok(not pile.is_empty(), "the pile came back")
	eq(int(pile.get("w", -1)), 5, "and so did its condition")


func test_a_worn_weapon_in_a_chest_survives_a_save() -> void:
	# Chests, car boots, the stash and both packs all record through
	# `Slots.to_record`, so putting condition on the slot carried it into
	# every one of them at once. This is the container Codex's case named.
	_stock()
	sim.structs.place(sim, "chest", plot.x + 2, plot.y, p)
	var store := sim.structs.reachable_store(p, plot.x + 2, plot.y)
	_hold("machete", 21)
	ok(Equipment.move_stack(sim, p, "hotbar", 0, "store", 0, Vector2i(plot.x + 2, plot.y)))

	var payload := SaveGame.to_dict(sim)
	var fresh := new_sim()
	ok(SaveGame.apply(fresh, payload).ok)
	var back := fresh.structs.reachable_store(fresh.players[0], plot.x + 2, plot.y)
	ok(back != null, "the chest came back")
	eq(back.id_at(0), "machete")
	eq(Wear.left(back, 0), 21, "and so did what was left of the Machete")


func test_wear_crosses_the_wire_with_the_pack() -> void:
	_hold("machete", 13)
	var rec := NetProtocol.pack_inventory(p)
	var other := new_sim()
	var guest: PlayerSim = other.players[0]
	NetProtocol.apply_inventory(guest, rec)
	eq(Wear.left(guest.hotbar, 0), 13, "a guest knows what its own axe has left")


func test_a_slot_record_round_trips_its_condition() -> void:
	var a := Slots.new(4)
	a.add("machete", 1, 11)
	a.add("wood", 20)
	var b := Slots.new(4)
	b.from_record(a.to_record())
	eq(Wear.left(b, 0), 11, "the weapon kept its condition")
	eq(b.count("wood"), 20, "and an ordinary stack is untouched")
	ok(not b.at(1).has("w"), "which writes nothing it does not need")
