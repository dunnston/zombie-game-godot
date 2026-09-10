extends "res://tests/test_case.gd"
## Raised beds. Most of these assert the promise rather than the plumbing: a
## dry bed stalls and never dies, a fed bed pays more, a harvest hands a seed
## back, and a garden survives being written down and sent over a wire.
##
## The three that matter most are the pillar-1 ones — `a_dry_bed_stalls`,
## `a_dry_bed_never_kills` and `nothing_here_is_a_hunger_meter`. Farming was
## on §7's "deliberately not building" list, and those are the assertions the
## amendment is worth.

var sim: GameSim
var p: PlayerSim
var plot: Vector2i

const DAY := Config.DAY_LENGTH


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = clear_plot(8)
	p.pos = tile_centre(plot)
	p.bag = Slots.new(200)
	p.carry_cap = 1000000.0


## A bed beside the player, with a full larder of seed, feed and water.
func _bed(dx := 1) -> Dictionary:
	for id in ["seedPotato", "seedCorn", "seedHerb", "compost", "sludge", "wood", "sticks", "fiber"]:
		p.bag.add(id, 40)
	p.bag.add("water", 40)
	return sim.structs.place(sim, "raisedBed", plot.x + dx, plot.y, p)


## Steps only the beds. `run` ticks the whole simulation, and a day and a half
## of that per assertion is most of the fast tier's ten-second budget.
func _grow(seconds: float) -> void:
	var dt := 1.0 / 30.0
	for i in range(int(round(seconds / dt))):
		Farming.tick(sim, dt)


# -------------------------------------------------------------- the bed --

func test_a_bed_costs_what_the_table_says_and_blocks_nobody() -> void:
	var before := p.count_res("wood")
	var s := _bed()
	ok(not s.is_empty(), "the bed went down")
	eq(p.count_res("wood"), before + 40 - int(Config.STRUCTURES.raisedBed.cost.wood))
	ok(not s.solid, "you can walk through your own garden")
	ok(not sim.structs.solid_at(s.tx, s.ty))
	# A vegetable patch is not a fortification: marking it `protect` would
	# widen the base radius around the allotment and pull a raid at the
	# lettuce, and neither is what a bed is for.
	ok(not s.def.get("protect", false), "a bed does not claim ground")


func test_an_empty_bed_says_what_it_is_for() -> void:
	var s := _bed()
	ok(Farming.prompt(s).contains("Plant"), Farming.prompt(s))
	eq(Farming.stage(s), -1)
	ok(not Farming.ready(s))


# ------------------------------------------------------------- planting --

func test_planting_spends_one_seed_and_starts_the_clock() -> void:
	var s := _bed()
	ok(Farming.plant(sim, p, s, "seedPotato"))
	eq(p.count_res("seedPotato"), 39, "exactly one seed went in")
	eq(String(s.seed), "seedPotato")
	near(float(s.grow), 0.0)
	near(Farming.grow_time(s), DAY, 0.01)


func test_a_bed_takes_one_planting_at_a_time() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	ok(not Farming.plant(sim, p, s, "seedCorn"), "the second seed is refused")
	eq(String(s.seed), "seedPotato")


func test_the_slots_are_typed() -> void:
	var s := _bed()
	ok(not Farming.accepts("seed", "machete"))
	ok(not Farming.accepts("seed", "compost"), "feed is not seed")
	ok(Farming.accepts("seed", "seedCorn"))
	ok(not Farming.accepts("fert", "seedCorn"), "seed is not feed")
	ok(Farming.accepts("fert", "sludge"))
	ok(not Farming.plant(sim, p, s, "machete"), "a weapon cannot be planted")
	ok(not Farming.fertilize(sim, p, s, "seedCorn"))


func test_planting_needs_a_seed_you_actually_have() -> void:
	var s := _bed()
	p.bag.take("seedHerb", 99)
	ok(not Farming.plant(sim, p, s, "seedHerb"))
	eq(String(s.seed), "")


# ---------------------------------------------------------------- water --

func test_one_bottle_is_half_a_bed() -> void:
	var s := _bed()
	ok(Farming.water(sim, p, s))
	near(float(s.water), float(Config.FARM.water_per_bottle), 0.01)
	eq(p.count_res("water"), 39)
	ok(Farming.water(sim, p, s))
	near(float(s.water), float(Config.FARM.water_max), 0.01, "two bottles fill it")
	ok(not Farming.water(sim, p, s), "and a third is refused rather than wasted")
	eq(p.count_res("water"), 38)


func test_a_full_bed_runs_dry_in_the_time_the_table_says() -> void:
	var s := _bed()
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(float(Config.FARM.dry_days) * DAY * 0.5)
	near(Farming.water_frac(s), 0.5, 0.02, "half the tank at half the time")
	_grow(float(Config.FARM.dry_days) * DAY * 0.6)
	near(float(s.water), 0.0, 0.001, "and empty at the end of it")


## Pillar 1, asserted. Dry soil is a throttle, not a threat.
func test_a_dry_bed_stalls() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	_grow(DAY * 2.0)
	near(float(s.grow), 0.0, 0.001, "no water, no growth")
	ok(not Farming.ready(s))


func test_a_dry_bed_never_kills_what_is_in_it() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	# One bottle is half a tank, and half a tank is less growing time than a
	# potato needs — so this planting runs dry part-grown, which is exactly
	# the situation the pillar is about.
	Farming.water(sim, p, s)
	_grow(DAY * 3.0)
	var banked := float(s.grow)
	gt(banked, 0.0, "it grew while it had water")
	ok(banked < DAY, "and stopped short of ripe when the water ran out")
	near(float(s.water), 0.0, 0.001)
	# Three more days bone dry. Nothing anywhere takes the planting away.
	_grow(DAY * 3.0)
	eq(String(s.seed), "seedPotato", "the plant is still in the ground")
	near(float(s.grow), banked, 0.001, "and it kept every second it had banked")
	# Water it again and it picks up exactly where it stopped.
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(DAY - banked + 1.0)
	ok(Farming.ready(s), "watering it again finishes the job")


# --------------------------------------------------------------- growth --

func test_a_watered_bed_ripens_on_time_and_not_before() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(DAY * 0.9)
	ok(not Farming.ready(s), "not ready at nine tenths")
	# "Ready" is the last stage and it means ready: nine tenths is still
	# Growing, so a bed can never look harvestable while it is refusing.
	eq(Farming.stage(s), 2, "still growing")
	_grow(DAY * 0.2)
	ok(Farming.ready(s))
	near(Farming.progress(s), 1.0, 0.001)


func test_the_stages_walk_up_in_order() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	eq(Farming.stage(s), 0)
	eq(Farming.stage_name(s), "Seeded")
	_grow(DAY * 0.4)
	eq(Farming.stage(s), 1)
	_grow(DAY * 0.3)
	eq(Farming.stage(s), 2)
	_grow(DAY * 0.4)
	eq(Farming.stage(s), 3)
	eq(Farming.stage_name(s), "Ready")


func test_corn_is_the_long_one() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedCorn")
	near(Farming.grow_time(s), DAY * 2.0, 0.01, "twice a potato, and worth twice as much")


# -------------------------------------------------------------- harvest --

func test_harvest_pays_inside_the_band_and_hands_a_seed_back() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	var seeds_after_planting := p.count_res("seedPotato")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(DAY + 1.0)
	var n := Farming.harvest(sim, p, s)
	var row: Dictionary = Config.CROPS.seedPotato
	ok(n >= int(row.min) and n <= int(row.max), "%d is outside %d-%d" % [n, row.min, row.max])
	eq(p.count_carried("potato"), n, "and all of it reached the pack")
	# Without this a farm dead-ends the first time the loot tables stop
	# offering seed, which is a worse outcome than an economy that grows.
	gt(p.count_res("seedPotato"), seeds_after_planting, "a seed came back")
	# And the bed is genuinely empty again, so one planting cannot be
	# harvested twice.
	eq(String(s.seed), "")
	eq(Farming.harvest(sim, p, s), 0)


func test_an_unripe_bed_refuses_to_be_harvested() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	_grow(DAY * 0.5)
	eq(Farming.harvest(sim, p, s), 0)
	eq(String(s.seed), "seedPotato", "and the crop is still standing")


# ----------------------------------------------------------- fertilizer --

func test_compost_pays_more_and_changes_nothing_else() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	ok(Farming.fertilize(sim, p, s, "compost"))
	eq(p.count_res("compost"), 39)
	near(Farming.grow_time(s), DAY, 0.01, "compost is yield, not speed")
	ok(not Farming.fertilize(sim, p, s, "sludge"), "one dose per bed")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(DAY + 1.0)
	var n := Farming.harvest(sim, p, s)
	var row: Dictionary = Config.CROPS.seedPotato
	var mul: float = float(Config.FERTILIZER.compost.yield_mul)
	ok(n >= floori(int(row.min) * mul) and n <= floori(int(row.max) * mul),
		"%d is outside the fed band" % n)
	eq(String(s.fert), "", "and the dose was spent on the crop")


func test_sludge_is_faster_and_far_more_of_it() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedCorn")
	Farming.fertilize(sim, p, s, "sludge")
	near(Farming.grow_time(s), DAY * 2.0 * float(Config.FERTILIZER.sludge.speed_mul), 0.01)
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(Farming.grow_time(s) + 1.0)
	ok(Farming.ready(s))
	var n := Farming.harvest(sim, p, s)
	gt(n, int(Config.CROPS.seedCorn.max), "the whole point of paying brain matter")


func test_a_bed_can_be_fed_after_it_was_planted() -> void:
	# Forgiving on purpose: feeding yesterday's planting still counts, which
	# costs nothing to allow and is one less thing to get wrong.
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	_grow(DAY * 0.5)
	ok(Farming.fertilize(sim, p, s, "compost"))
	eq(String(s.fert), "compost")


# -------------------------------------------------------- losing a bed --

func test_salvage_hands_the_planting_back_and_a_brute_does_not() -> void:
	var a := _bed(1)
	Farming.plant(sim, p, a, "seedPotato")
	Farming.fertilize(sim, p, a, "compost")
	var seeds := p.count_res("seedPotato")
	var feed := p.count_res("compost")
	sim.structs.demolish(sim, a, p)
	eq(p.total_res(sim, "seedPotato") + _on_ground("seedPotato"), seeds + 1, "the seed came back")
	eq(p.total_res(sim, "compost") + _on_ground("compost"), feed + 1, "and so did the feed")

	var b := _bed(3)
	Farming.plant(sim, p, b, "seedCorn")
	var corn_seeds := p.total_res(sim, "seedCorn")
	sim.structs.destroy(sim, b)
	eq(p.total_res(sim, "seedCorn") + _on_ground("seedCorn"), corn_seeds,
		"a brute through the beds takes the crop with it")


func _on_ground(id: String) -> int:
	var n := 0
	for it in sim.pickups:
		if String(it.id) == id:
			n += int(it.n)
	return n


# --------------------------------------------------------------- reach --

func test_a_bed_out_of_reach_is_no_bed_at_all() -> void:
	var s := _bed()
	ok(not Farming.reachable_bed(sim, p, s.tx, s.ty).is_empty())
	p.pos += Vector2(600, 0)
	ok(Farming.reachable_bed(sim, p, s.tx, s.ty).is_empty())
	# The command a guest sends is checked by the same function, so naming a
	# tile on the other side of town buys nothing.
	ok(not Actions.execute(sim, p, "plant", {"tx": s.tx, "ty": s.ty, "id": "seedPotato"}))
	ok(not Actions.execute(sim, p, "water_bed", {"tx": s.tx, "ty": s.ty}))
	ok(not Actions.execute(sim, p, "harvest", {"tx": s.tx, "ty": s.ty}))
	eq(String(s.seed), "")


func test_the_commands_are_the_functions_the_screen_calls() -> void:
	var s := _bed()
	ok(Actions.execute(sim, p, "plant", {"tx": s.tx, "ty": s.ty, "id": "seedHerb"}))
	eq(String(s.seed), "seedHerb")
	ok(Actions.execute(sim, p, "fertilize", {"tx": s.tx, "ty": s.ty, "id": "compost"}))
	eq(String(s.fert), "compost")
	ok(Actions.execute(sim, p, "water_bed", {"tx": s.tx, "ty": s.ty}))
	gt(float(s.water), 0.0)


# ----------------------------------------------------- interact and save --

func test_the_key_offers_the_bed_and_harvests_a_ripe_one_where_you_stand() -> void:
	var s := _bed()
	p.pos = s.pos + Vector2(20, 0)
	var t := Interact.best_target(sim, p)
	eq(String(t.get("kind", "")), "bed")
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	_grow(DAY + 1.0)
	ok(Interact.best_target(sim, p).label.contains("Harvest"), "the prompt says what the key does")
	p.intent.interact = true
	sim.tick(1.0 / 60.0)
	gt(p.count_carried("potato"), 0, "and the key did it, without a screen")


func test_a_garden_survives_being_written_down() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedCorn")
	Farming.fertilize(sim, p, s, "sludge")
	Farming.water(sim, p, s)
	_grow(DAY * 0.4)
	var progress := Farming.progress(s)
	var wet := Farming.water_frac(s)

	var out := GameSim.new()
	var r := SaveGame.apply(out, SaveGame.to_dict(sim), world())
	ok(r.ok, r.reason)
	var back := out.structs.at_tile(s.tx, s.ty)
	ok(not back.is_empty(), "the bed came back")
	eq(String(back.seed), "seedCorn")
	eq(String(back.fert), "sludge")
	near(Farming.progress(back), progress, 0.001, "at the same stage")
	near(Farming.water_frac(back), wet, 0.001, "and as wet as it was")


func test_a_guest_sees_the_same_garden() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedHerb")
	Farming.fertilize(sim, p, s, "compost")
	Farming.water(sim, p, s)
	_grow(DAY * 0.5)

	# The wire's own record, applied to a bed built from nothing but the
	# structure table — which is exactly what a joining guest has.
	var mirror := new_sim()
	var copy := mirror.structs.make(mirror, "raisedBed", s.tx, s.ty)
	var rec := NetProtocol.pack_structure(s)
	copy.seed = String(rec.sd)
	copy.fert = String(rec.ft)
	copy.water = float(rec.wt)
	copy.grow = float(rec.gr)
	near(Farming.progress(copy), Farming.progress(s), 0.01, "the same stage on both machines")
	eq(Farming.stage(copy), Farming.stage(s))
	# The wire's water is floored to a twentieth of a tank, so a guest is
	# within one step and always on the drier side. That coarseness is the
	# whole reason a garden does not re-send itself twice a second.
	var step: float = float(Config.FARM.wire_water_step) / float(Config.FARM.water_max)
	near(Farming.water_frac(copy), Farming.water_frac(s), step + 0.001)
	ok(Farming.water_frac(copy) <= Farming.water_frac(s) + 0.001, "and never wetter than the host's")
	# The stage itself is never sent: both derive it, so neither can hold a
	# stale one.
	ok(not rec.has("stage"))


## The world diff re-sends a structure whose packed record has changed, and a
## bed's water and growth move every frame. Sent at full precision a garden
## would re-send itself every half second for the rest of the run.
func test_a_growing_bed_does_not_chatter_on_the_wire() -> void:
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	var seen := {}
	# Two in-game minutes, sampled at the rate the host actually diffs at.
	for i in range(240):
		_grow(Config.NET.sync_interval)
		seen[var_to_str(NetProtocol.pack_structure(s))] = true
	# 120 seconds of growth over a four-second step is thirty records, plus a
	# handful for the water draining. Without the flooring it would be 240.
	ok(seen.size() < 60, "the bed sent %d different records in two minutes" % seen.size())
	gt(seen.size(), 1, "and it does still move")


func test_a_guest_is_never_ahead_of_the_host() -> void:
	# Floored, not rounded to nearest. A guest that reached ripe first would
	# offer a harvest the host then refuses.
	var s := _bed()
	Farming.plant(sim, p, s, "seedPotato")
	Farming.water(sim, p, s)
	Farming.water(sim, p, s)
	for i in range(200):
		_grow(2.7)
		var rec := NetProtocol.pack_structure(s)
		ok(float(rec.gr) <= float(s.grow) + 0.001, "the wire is ahead of the bed")
		ok(float(rec.wt) <= float(s.water) + 0.001, "the wire is wetter than the bed")
		if Farming.ready(s):
			break


# ------------------------------------------------------------ the economy --

func test_what_a_garden_is_for() -> void:
	# Corn feeds the crew and herbs keep the medicine going. Both are bench
	# work, so a farm without a base is only ever raw vegetables.
	var found := {}
	for r in Config.RECIPES:
		found[String(r.id)] = r
	has(found, "cornRations")
	eq(int(found.cornRations.bench), 1)
	has(found.cornRations.give.res, "rations")
	has(found, "herbMed")
	has(found.herbMed.give.res, "med")
	# And the fertilizer that costs brain matter is chemistry, not metalwork:
	# no amount of Workbench II ever produces it.
	has(found, "sludge")
	eq(String(found.sludge.get("station", "")), "chem")
	eq(int(found.sludge.bench), 0)
	# Compost is bench 0, or the first bed is a thing you build and cannot use.
	eq(int(found.compost.bench), 0)


func test_every_seed_grows_something_real() -> void:
	for seed_id in Config.CROPS:
		var row: Dictionary = Config.CROPS[seed_id]
		ok(Config.RES.has(seed_id), "%s is not an item" % seed_id)
		ok(Config.CONSUMABLES.has(String(row.crop)), "%s grows nothing" % seed_id)
		ok(Config.CONSUMABLES[row.crop].get("food", false), "%s is not food" % row.crop)
		gt(int(row.max), int(row.min) - 1)
		gt(float(row.days), 0.0)
	for id in Config.FERTILIZER:
		ok(Config.RES.has(id), "%s is not an item" % id)
		gt(float(Config.FERTILIZER[id].yield_mul), 1.0, "%s does nothing" % id)


func test_nothing_here_is_a_hunger_meter() -> void:
	# The amendment to §7 is worth exactly this much: a garden may not become
	# the chore the list was written against. No field, and no crop that the
	# game ever asks you for.
	for field in ["hunger", "thirst", "fatigue", "nutrition"]:
		eq(p.get(field), null, "a %s field appeared on the player" % field)
	for seed_id in Config.CROPS:
		var c: Dictionary = Config.CONSUMABLES[Config.CROPS[seed_id].crop]
		ok(Config.EFFECTS[c.effect].get("good", false), "%s is a debuff" % c.id)
		near(float(c.get("mut", 0.0)), 0.0, 0.001, "food does not touch the meter")
