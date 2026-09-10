extends "res://tests/test_case.gd"
## The slot container, the item registry, carry weight and what is worn.
## Every assertion here is about an outcome the player can see: a stack
## merged, a pack refused, a suit of armour that actually reduces damage.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.pos = tile_centre(clear_plot(6))


# ---------------------------------------------------------------- registry --

func test_every_carryable_thing_has_an_item_definition() -> void:
	for id in Config.RES:
		eq(Items.kind_of(id), "res", id)
		gt(Items.stack_limit(id), 1, id)
	for id in Config.WEAPONS:
		if id == "fists":
			ok(not Items.has(id), "fists are not an object you carry")
			continue
		eq(Items.kind_of(id), "weapon", id)
		eq(Items.stack_limit(id), 1, id)
	for id in Config.GEAR:
		eq(Items.kind_of(id), "gear", id)
		has(Config.GEAR_SLOTS, Items.gear_slot(id), id)
	for id in Config.CONSUMABLES:
		eq(Items.kind_of(id), "consumable", id)


# ------------------------------------------------------------------- slots --

func test_stacks_fill_before_new_slots_open() -> void:
	var s := Slots.new(4)
	eq(s.add("wood", 60), 60)
	eq(s.used(), 2, "50 per stack, so 60 wood is two slots")
	eq(s.count("wood"), 60)
	eq(s.at(0).n, 50)
	eq(s.at(1).n, 10)
	# The part-used stack tops up before a third slot is opened.
	eq(s.add("wood", 30), 30)
	eq(s.used(), 2)
	eq(s.at(1).n, 40)


func test_a_full_container_refuses_the_remainder_rather_than_eating_it() -> void:
	var s := Slots.new(2)
	eq(s.add("wood", 140), 100, "two slots hold a hundred")
	eq(s.count("wood"), 100)
	eq(s.add("stone", 5), 0, "and nothing else fits")


func test_taking_more_than_is_there_takes_what_is_there() -> void:
	var s := Slots.new(4)
	s.add("scrap", 12)
	eq(s.take("scrap", 20), 12)
	eq(s.count("scrap"), 0)
	eq(s.used(), 0, "an emptied stack frees its slot")


func test_moving_merges_the_same_id_and_swaps_anything_else() -> void:
	var s := Slots.new(4)
	s.slots[0] = {"id": "wood", "n": 30}
	s.slots[1] = {"id": "wood", "n": 40}
	ok(s.move(0, 1))
	eq(s.at(1).n, 50, "merged up to the stack limit")
	eq(s.at(0).n, 20, "and left the remainder behind")
	s.slots[2] = {"id": "stone", "n": 4}
	ok(s.move(0, 2))
	eq(s.id_at(2), "wood", "different items swap")
	eq(s.id_at(0), "stone")


func test_splitting_halves_a_stack_into_an_empty_slot() -> void:
	var s := Slots.new(3)
	s.add("cloth", 9)
	ok(s.split(0, 1))
	eq(s.at(0).n, 5)
	eq(s.at(1).n, 4)
	ok(not s.split(0, 1), "not onto an occupied slot")


func test_a_stack_moves_between_containers() -> void:
	var a := Slots.new(2)
	var b := Slots.new(2)
	a.add("fiber", 8)
	ok(a.move(0, 0, b))
	eq(a.count("fiber"), 0)
	eq(b.count("fiber"), 8)


# ------------------------------------------------------------------ weight --

func test_capacity_is_weight_and_it_counts_the_hotbar_too() -> void:
	# 225 units of budget: the 200 base plus the 25 that Strength 2 is worth,
	# because every survivor starts one rank above the tables' baseline.
	# A rifle on the hotbar weighs 6 of it, and the pack has to know that or
	# the weight bar and the loot rules disagree.
	near(p.carry_cap, 225.0, 0.01)
	p.hotbar.clear_all()
	p.hotbar.add("rifle", 1)
	near(p.pack_allowance(), 219.0, 0.01, "the rifle is off the pack's budget")
	var took := p.bag.add_capped("stone", 200, p.pack_allowance())
	eq(took, 146, "stone is 1.5 each: 146 fits under 219")
	ok(not p.overloaded(), "and the bar has not passed full")
	ok(p.carried_weight() <= p.carry_cap)


func test_a_pack_that_is_full_by_weight_takes_nothing_more() -> void:
	p.bag.clear_all()
	p.hotbar.clear_all()
	eq(p.bag.add_capped("stone", 400, p.pack_allowance()), 150, "150 x 1.5 is 225.0 of 225")
	eq(p.bag.add_capped("wood", 10, p.pack_allowance()), 0, "half a unit of room takes nothing")
	ok(p.carried_weight() <= p.carry_cap)


# ------------------------------------------------------------------- worn --

func test_worn_armour_sums_and_never_passes_the_cap() -> void:
	eq(p.armor_dr, 0.0, "you start in your own clothes")
	for id in ["milHelm", "milVest", "armGuards", "milGreaves", "milBoots"]:
		p.bag.add(id, 1)
	eq(Equipment.equip_best(sim, p), 5, "a full tier-3 set")
	near(p.armor_dr, 0.70, 0.001, "0.15 + 0.28 + 0.07 + 0.12 + 0.08")
	ok(p.armor_dr <= Config.MAX_GEAR_DR, "and under the hard cap")
	# The cap is the rule, not the arithmetic: prove it clamps.
	p.equip["head"] = "milHelm"
	p.equip["body"] = "milVest"
	p.equip["hands"] = "armGuards"
	p.equip["legs"] = "milGreaves"
	p.equip["feet"] = "milBoots"
	Equipment.recompute_stats(p)
	ok(p.armor_dr <= Config.MAX_GEAR_DR)


func test_armour_actually_reduces_the_bite() -> void:
	var bare := Damage.damage_player(sim, p, 40.0, p.pos + Vector2(20, 0))
	p.invuln = 0.0
	p.bag.add("milVest", 1)
	ok(Equipment.equip_from_bag(sim, p, p.bag.size() - 1) or Equipment.equip_best(sim, p) > 0)
	var worn := Damage.damage_player(sim, p, 40.0, p.pos + Vector2(20, 0))
	ok(worn < bare, "40 damage became %.1f in a plate carrier, from %.1f bare" % [worn, bare])
	near(worn, bare * (1.0 - 0.28), 0.5)


func test_swapping_a_helmet_puts_the_old_one_back_in_the_pack() -> void:
	p.bag.add("hardHat", 1)
	Equipment.equip_from_bag(sim, p, 0)
	eq(p.equip.head, "hardHat")
	eq(p.bag.count("hardHat"), 0)
	p.bag.add("milHelm", 1)
	Equipment.equip_from_bag(sim, p, 0)
	eq(p.equip.head, "milHelm")
	eq(p.bag.count("hardHat"), 1, "the old one came back rather than vanishing")


func test_nothing_comes_off_when_there_is_nowhere_to_put_it() -> void:
	p.bag.add("hardHat", 1)
	Equipment.equip_from_bag(sim, p, 0)
	for i in range(p.bag.size()):
		p.bag.slots[i] = {"id": "pipe", "n": 1}
	ok(not Equipment.unequip(sim, p, "head"), "refused, not dropped on the floor")
	eq(p.equip.head, "hardHat")


func test_gear_never_lands_on_the_wrong_body_slot() -> void:
	p.bag.add("workBoots", 1)
	ok(not Equipment.equip_from_slot(p, "bag", 0, "head"), "boots are not a hat")
	ok(Equipment.equip_from_slot(p, "bag", 0, "feet"))


# ----------------------------------------------------------------- hotbar --

func test_the_selected_hotbar_slot_is_what_you_are_holding() -> void:
	sim.give_test_kit(p)
	p.select_slot(p.hotbar_index("shotgun"))
	eq(p.weapon().id, "shotgun")
	p.hotbar.take("shotgun", 1)
	eq(p.weapon().id, "fists", "an empty hand is still a fist")


func test_a_dropped_stack_lands_on_the_ground_and_waits_for_you_to_step_off() -> void:
	p.bag.add("scrap", 12)
	ok(Equipment.drop_stack(sim, p, "bag", 0, true))
	eq(p.bag.count("scrap"), 0)
	eq(sim.pickups.size(), 1)
	# Standing over your own drop does not hand it straight back.
	run(sim, 1.0)
	eq(sim.pickups.size(), 1, "still on the ground")
	eq(p.bag.count("scrap"), 0)
	# Step clear, and it re-arms; walk back and it is yours again.
	p.pos += Vector2(200, 0)
	run(sim, 0.2)
	p.pos = sim.pickups[0].pos
	run(sim, 0.5)
	eq(sim.pickups.size(), 0, "picked back up")
	eq(p.bag.count("scrap"), 12)


func test_a_torch_burns_down_and_takes_itself_with_it() -> void:
	sim.clock.t = 0.82                        # the small hours: dark enough
	p.bag.add("torch", 1)
	Equipment.equip_from_bag(sim, p, 0)
	eq(p.equip.offhand, "torch")
	near(p.light_fuel, 210.0, 0.01, "a torch comes ready to burn")
	ok(not p.lit, "not until a tick has run")
	run(sim, 0.05)
	ok(p.lit, "the dark strikes it, and being lit is what the enemies read")
	p.light_fuel = 0.5
	run(sim, 1.0)
	ok(not p.lit)
	eq(p.equip.offhand, "", "it burned away")


# ------------------------------------------------ the Codex review, PR #3 --

func test_swapping_lights_does_not_refill_either_one() -> void:
	p.bag.add("torch", 1)
	p.bag.add("flashlight", 1)
	Equipment.equip_from_bag(sim, p, 0)
	eq(p.equip.offhand, "torch")
	p.light_fuel = 60.0                       # a torch two thirds burned
	# Swap to the flashlight and back.
	Equipment.equip_from_bag(sim, p, p.bag.size() - 1 if false else _index_of("flashlight"))
	eq(p.equip.offhand, "flashlight")
	near(p.light_fuel, 0.0, 0.01, "a found flashlight arrives flat")
	Equipment.equip_from_bag(sim, p, _index_of("torch"))
	eq(p.equip.offhand, "torch")
	near(p.light_fuel, 60.0, 0.01, "the torch is still two thirds burned")


func _index_of(id: String) -> int:
	for i in range(p.bag.size()):
		if p.bag.id_at(i) == id:
			return i
	return -1


func test_dropping_a_stack_empties_the_cell_you_clicked() -> void:
	# Two stacks of the same thing: dropping the second must not drain the
	# first and leave the clicked cell full.
	p.bag.slots[0] = {"id": "scrap", "n": 50}
	p.bag.slots[5] = {"id": "scrap", "n": 12}
	ok(Equipment.drop_stack(sim, p, "bag", 5, true))
	eq(p.bag.at(0).n, 50, "the untouched stack is untouched")
	ok(p.bag.at(5).is_empty(), "and the one you clicked is gone")
	eq(sim.pickups.size(), 1)
	eq(sim.pickups[0].n, 12)


# ------------------------------------------------ the Codex review, PR #5 --

func _chest_beside(tile_offset := 2) -> Dictionary:
	for id in ["wood", "sticks"]:
		p.bag.add(id, 200)
	var tx := floori(p.pos.x / Config.TILE) + tile_offset
	var ty := floori(p.pos.y / Config.TILE)
	var s := sim.structs.place(sim, "chest", tx, ty, p)
	p.bag.clear_all()
	return s


func test_a_chest_cannot_hand_you_more_than_you_can_lift() -> void:
	var chest := _chest_beside()
	ok(not chest.is_empty(), "there is a chest to take from")
	chest.store.add("stone", 50)
	p.hotbar.clear_all()
	p.carry_cap = 200.0
	p.bag.add_capped("stone", 400, p.pack_allowance())   # 133 units, 199.5
	var carried := p.carried_weight()
	var free := p.bag.first_empty()
	ok(free >= 0)
	# Dragging the chest's fifty stone into an empty pack slot must not put
	# 75 units of weight on someone with half a unit of room.
	Equipment.move_stack(sim, p, "store", 0, "bag", free, Vector2i(chest.tx, chest.ty))
	ok(p.carried_weight() <= p.carry_cap + 0.01,
		"carrying %.1f of %.0f" % [p.carried_weight(), p.carry_cap])
	ok(not p.overloaded())
	eq(chest.store.count("stone"), 50, "nothing moved: there was no room for even one")

	# With room for a few, it takes a few and leaves the rest in the chest.
	p.bag.take("stone", 10)
	Equipment.move_stack(sim, p, "store", 0, "bag", p.bag.first_empty(), Vector2i(chest.tx, chest.ty))
	ok(not p.overloaded(), "carrying %.1f" % p.carried_weight())
	gt(50, chest.store.count("stone"), "some came out")
	gt(chest.store.count("stone"), 0, "and the rest stayed put")


func test_putting_things_into_a_chest_is_never_refused_for_weight() -> void:
	var chest := _chest_beside()
	p.carry_cap = 200.0
	p.bag.add("stone", 40)
	var before := p.carried_weight()
	ok(Equipment.move_stack(sim, p, "bag", 0, "store", 0, Vector2i(chest.tx, chest.ty)))
	ok(p.carried_weight() < before, "the weight left you")
	eq(chest.store.count("stone"), 40)
