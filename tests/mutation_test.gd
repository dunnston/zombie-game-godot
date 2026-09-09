extends "res://tests/test_case.gd"
## The Mutation meter: the rate, what accelerates it, what the bands do to the
## player, what a dose takes off, and what happens at the top.
##
## The rule this file is really guarding is the same one `progression_test`
## guards from the other side: a band changes stats **only** by changing
## `mut_band` and letting `recompute_stats` run. Nothing here writes a
## modifier, and the tests below check the stats by comparing recomputes.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


## Every derived stat, as one comparable snapshot.
func _stats(q: PlayerSim) -> Dictionary:
	var out := {}
	for key in Config.STAT_BASE:
		out[key] = q.get(key)
	return out


# ------------------------------------------------------------------ tables --

func test_the_band_and_effect_tables_name_real_stats() -> void:
	# `_apply_mods` uses set(), which is silent about a typo: a mistyped key
	# here would be a modifier that never arrives and never complains.
	var tables: Array = []
	for b in Config.MUTATION.bands:
		tables.append(b)
	for id in Config.EFFECTS:
		tables.append(Config.EFFECTS[id])
	for t in tables:
		for group in ["add", "mul"]:
			for key in t.get(group, {}):
				ok(Config.STAT_BASE.has(key), "%s.%s names '%s', which is not a stat" % [t.id, group, key])
				ok(typeof(Config.STAT_BASE[key]) == TYPE_FLOAT, "'%s' is not a number, so %s cannot modify it" % [key, t.id])


func test_the_bands_are_ordered_and_start_at_zero() -> void:
	var bands: Array = Config.MUTATION.bands
	gt(bands.size(), 1, "one band is not a meter")
	eq(float(bands[0].at), 0.0, "the first band has to cover a fresh survivor")
	for i in range(1, bands.size()):
		gt(float(bands[i].at), float(bands[i - 1].at), "band %d starts before the one under it" % i)
		ok(float(bands[i].at) < float(Config.MUTATION.max), "band %d starts at or past the top" % i)


func test_every_brain_drop_names_a_real_item() -> void:
	for type in Config.BRAIN_DROPS:
		has(Config.ENEMIES, type, "BRAIN_DROPS has a row for %s, which is not an enemy" % type)
		var d: Dictionary = Config.BRAIN_DROPS[type]
		has(Config.CONSUMABLES, d.id, type)
		ok(int(d.min) >= 1 and int(d.max) >= int(d.min), type)
		if d.has("also"):
			has(Config.CONSUMABLES, d.also.id, type)
	# Every *zombie*. The living carry nothing worth eating — that is what
	# keeps the supply line running through the dead, so killing people can
	# never be a way to hold the meter down.
	for type in Config.ENEMIES:
		if Config.ENEMIES[type].get("human", false):
			ok(not Config.BRAIN_DROPS.has(type), "%s is a person and is dropping brain matter" % type)
		else:
			has(Config.BRAIN_DROPS, type, "%s drops no brain matter at all" % type)


func test_a_suppressant_is_a_consumable_with_a_number_on_it() -> void:
	var found := 0
	for id in Config.CONSUMABLES:
		if Mutation.is_suppressant(id):
			found += 1
			gt(float(Config.CONSUMABLES[id].mut), 0.0, id)
			gt(float(Config.CONSUMABLES[id].time), 0.0, "%s is instant, so it cannot be interrupted" % id)
			if Config.CONSUMABLES[id].has("effect"):
				has(Config.EFFECTS, Config.CONSUMABLES[id].effect, id)
	gt(found, 1, "there is no chain if there is only one dose")
	# Neural Tissue is an ingredient. Eating it would make the chemistry
	# pointless, so the `tool` flag has to keep it out.
	ok(not Mutation.is_suppressant("brainSpec"), "Neural Tissue is being eaten")


# -------------------------------------------------------------- the climb --

func test_it_takes_days_and_not_minutes() -> void:
	# The pillar this whole feature has to obey: one meter, and it is not a
	# chore. A full cycle is days of play, so it is a supply line.
	var seconds: float = Config.MUTATION.max / Mutation.rate_per_sec()
	near(seconds, float(Config.MUTATION.days_to_full) * Config.DAY_LENGTH, 0.001)
	gt(seconds, 2.0 * Config.DAY_LENGTH, "a full cycle is under two days")


func test_standing_still_turns_you_slowly() -> void:
	p.god_mode = true                       # this is about the clock, not the horde
	var before := p.mutation
	run(sim, 60.0)
	gt(p.mutation, before, "the meter did not move at all")
	# A minute is a minute: never more than a twentieth of the bar, whatever
	# tier the spawn happened to be in.
	ok(p.mutation - before < Config.MUTATION.max * 0.05,
		"a minute of standing still moved the meter %.1f points" % (p.mutation - before))


func test_worse_ground_turns_you_faster() -> void:
	var muls: Array = Config.MUTATION.tier_mul
	for i in range(1, muls.size()):
		ok(float(muls[i]) >= float(muls[i - 1]), "tier %d is not worse than tier %d" % [i, i - 1])
	gt(float(muls[muls.size() - 1]), float(muls[1]), "the deep end is no worse than the shallow")


func test_the_dark_turns_you_faster() -> void:
	p.god_mode = true
	var day := Mutation.rate_multiplier(sim, p)
	sim.clock.t = 0.85                      # the middle of the night
	var night := Mutation.rate_multiplier(sim, p)
	gt(night, day, "night is no worse than noon")


func test_a_bite_is_worth_more_than_a_bullet() -> void:
	# Bites are rolled, so this asks the question over enough hits for the
	# chance to show rather than asserting on one swing.
	var bitten := 0
	for i in range(200):
		var before := p.mutation
		p.invuln = 0.0
		Damage.damage_player(sim, p, 8.0, p.pos + Vector2(20, 0), "Walker", true)
		p.hp = p.max_hp
		if p.mutation > before + 1.0:
			bitten += 1
	gt(bitten, 5, "200 zombie hits and not one of them was a bite")
	ok(bitten < 120, "%d of 200 hits were bites — that is a second health bar" % bitten)


func test_a_light_hit_from_something_without_teeth_does_nothing() -> void:
	var before := p.mutation
	Damage.damage_player(sim, p, 8.0, p.pos + Vector2(20, 0), "spikes")
	near(p.mutation, before, 0.001, "a scratch moved the meter")


func test_a_heavy_hit_moves_it_whatever_hit_you() -> void:
	var before := p.mutation
	Damage.damage_player(sim, p, float(Config.MUTATION.heavy_damage) + 5.0, p.pos + Vector2(20, 0), "Behemoth")
	near(p.mutation, before + float(Config.MUTATION.per_heavy), 0.001)


func test_going_down_moves_it() -> void:
	sim.join_player("guest")                # somebody to be downed in front of
	var before := p.mutation
	Damage.down_player(sim, p)
	ok(p.downed, "the test needs a downed player, not a dead one")
	near(p.mutation, before + float(Config.MUTATION.per_down), 0.001)


# --------------------------------------------------------------- the bands --

func test_a_band_change_is_what_moves_a_stat() -> void:
	var human := _stats(p)
	eq(p.mut_band, 0)
	# A tenth of a point inside the same band changes nothing at all.
	Mutation.add(sim, p, 0.1)
	eq(_stats(p), human, "the meter moved and a stat moved with it inside one band")
	# Crossing into TURNING does.
	Mutation.add(sim, p, float(Config.MUTATION.bands[1].at))
	eq(p.mut_band, 1)
	var turning := _stats(p)
	ne(turning, human, "crossing a band changed nothing")
	gt(turning.melee_mul, human.melee_mul, "TURNING is not stronger")
	ok(turning.spread_mul > human.spread_mul, "TURNING shoots no worse")
	ok(turning.sense_mul < human.sense_mul, "TURNING is noticed just as easily")


func test_feral_is_the_bargain_stated_plainly() -> void:
	Mutation.add(sim, p, float(Config.MUTATION.bands[2].at))
	eq(p.mut_band, 2)
	var feral := _stats(p)
	var fresh := PlayerSim.new()
	var human := _stats(fresh)
	gt(feral.melee_mul, human.melee_mul, "no stronger")
	gt(feral.speed_mul, human.speed_mul, "no faster")
	ok(feral.sense_mul < human.sense_mul * 0.8, "the dead notice you just as well")
	ok(feral.stagger_mul < human.stagger_mul, "it still rocks you")
	ok(feral.gun_mul < human.gun_mul, "guns are no worse")
	ok(feral.spread_mul > human.spread_mul, "aim is no worse")


func test_the_band_survives_a_recompute_from_anywhere_else() -> void:
	Mutation.add(sim, p, 80.0)
	var feral := _stats(p)
	# Anything at all that rebuilds stats — equipping, a perk, a save — must
	# not quietly hand a Feral character a human's numbers back.
	Equipment.recompute_stats(p)
	eq(_stats(p), feral, "a recompute forgot what the player is becoming")


func test_falling_back_below_a_threshold_gives_the_stats_back() -> void:
	Mutation.add(sim, p, 80.0)
	eq(p.mut_band, 2)
	Mutation.suppress(sim, p, 80.0)
	eq(p.mut_band, 0)
	eq(_stats(p), _stats(PlayerSim.new()), "coming back down left a modifier behind")


func test_a_feral_player_is_harder_to_notice() -> void:
	# The reward has to be visible in the thing it is supposed to change: the
	# radius an enemy actually senses you at.
	var human_r := 330.0 * p.sense_mul
	Mutation.add(sim, p, 80.0)
	var feral_r := 330.0 * p.sense_mul
	ok(feral_r < human_r * 0.75, "Feral is sensed at %.0f against a human's %.0f" % [feral_r, human_r])


# --------------------------------------------------------------- the doses --

func test_the_dose_you_reach_for_fits_the_hole() -> void:
	p.bag.add("brainRaw", 5)
	p.bag.add("serum", 2)
	# Four points in, a Serum would be thirty points of waste.
	p.mutation = 4.0
	eq(Mutation.pick_suppressant(p), "brainRaw")
	# Forty in, it is exactly the right tool.
	p.mutation = 40.0
	eq(Mutation.pick_suppressant(p), "serum")
	# And with nothing in the pack there is nothing to reach for.
	p.bag.clear_all()
	eq(Mutation.pick_suppressant(p), "")


func test_taking_a_dose_spends_it_and_moves_the_meter() -> void:
	p.bag.add("serum", 1)
	p.mutation = 60.0
	p.intent.suppress = true
	sim.tick(1.0 / 60.0)
	ok(not p.using.is_empty(), "the dose never started")
	eq(String(p.using.id), "serum")
	run(sim, float(Config.CONSUMABLES.serum.time) + 0.2)
	eq(p.count_carried("serum"), 0, "the dose was not spent")
	ok(p.mutation <= 60.0 - float(Config.CONSUMABLES.serum.mut) + 0.5, "the meter barely moved")
	ok(p.effects.is_empty(), "the clean dose left a side effect behind")


func test_raw_brain_matter_costs_you_something() -> void:
	p.bag.add("brainRaw", 1)
	p.mutation = 30.0
	var clean := _stats(p)
	Mutation.take_dose(sim, p, "brainRaw")
	ok(p.effects.has("nausea"), "raw tissue went down without a complaint")
	ok(p.speed_mul < clean.speed_mul, "nausea is not slowing you")
	ok(p.spread_mul > clean.spread_mul, "nausea is not spoiling your aim")


func test_an_effect_wears_off_and_gives_the_stats_back() -> void:
	var clean := _stats(p)
	Mutation.give_effect(sim, p, "nausea")
	ne(_stats(p), clean)
	p.effects["nausea"] = 0.05
	Mutation.tick_effects(sim, p, 0.1)
	ok(p.effects.is_empty(), "the clock did not run out")
	eq(_stats(p), clean, "the effect wore off and left a modifier behind")


func test_an_effect_refreshes_rather_than_stacking() -> void:
	Mutation.give_effect(sim, p, "nausea")
	Mutation.tick_effects(sim, p, 20.0)
	var half := float(p.effects.nausea)
	Mutation.give_effect(sim, p, "nausea")
	near(float(p.effects.nausea), float(Config.EFFECTS.nausea.dur), 0.001, "a second dose did not reset the clock")
	gt(float(Config.EFFECTS.nausea.dur), half)


# --------------------------------------------------------------- the top --

func test_filling_the_meter_turns_you() -> void:
	var seen := 0
	Mutation.add(sim, p, float(Config.MUTATION.max) + 10.0)
	ok(p.dead, "the meter filled and nothing happened")
	for ev in sim.events:
		if ev.t == "turned":
			seen += 1
	eq(seen, 1, "turning did not announce itself")
	near(p.mutation, float(Config.MUTATION.after_turn), 0.001, "you came back clean")
	ok(p.mutation > 0.0, "letting it fill is the cheap way to empty it")


func test_turning_says_what_it_was() -> void:
	Mutation.add(sim, p, 200.0)
	var deaths := events_of(sim, "player_died")
	eq(deaths.size(), 1)
	eq(String(deaths[0].get("cause", "")), "turned", "turning reads as an ordinary death")


func test_an_ordinary_death_leaves_the_meter_where_it_was() -> void:
	p.mutation = 22.0
	Damage.kill_player(sim, p)
	near(p.mutation, 22.0, 0.001, "dying is a cure")


func test_a_dead_player_stops_changing() -> void:
	Damage.kill_player(sim, p)
	var at_death := p.mutation
	Mutation.tick(sim, p, 30.0)
	near(p.mutation, at_death, 0.001, "a corpse kept mutating")


# ------------------------------------------------------------ the outside --

func test_it_survives_a_save() -> void:
	p.mutation = 74.0
	Mutation.sync_band(p)
	Mutation.give_effect(sim, p, "nausea")
	var payload := SaveGame.to_dict(sim)
	var fresh := GameSim.new()
	var r := SaveGame.apply(fresh, payload, world())
	ok(r.ok, r.get("reason", ""))
	var q: PlayerSim = fresh.players[0]
	near(q.mutation, 74.0, 0.01, "the meter did not survive the save")
	eq(q.mut_band, p.mut_band, "the band was not rebuilt from the value")
	ok(q.effects.has("nausea"), "what was working through you was forgotten")
	eq(_stats(q), _stats(p), "loading gave a Feral character a human's stats")


func test_it_crosses_the_wire() -> void:
	var packed := NetProtocol.pack_player(p)
	eq(packed.n.size(), NetProtocol.PL_STRIDE, "the stride and the packer disagree")
	Mutation.add(sim, p, 66.0 - p.mutation)
	Mutation.give_effect(sim, p, "nausea")
	packed = NetProtocol.pack_player(p)
	near(packed.n[NetProtocol.PL_MUT], 66.0, 0.11)
	ok(String(packed.s[3]).begins_with("nausea:"), "the effect clocks did not go out")

	# And the guest end: a mirrored player picks up the band, and with it the
	# stats it predicts its own footsteps from.
	var guest := PlayerSim.new()
	guest.mutation = packed.n[NetProtocol.PL_MUT]
	Mutation.sync_band(guest)
	Mutation.unpack_effects(guest, String(packed.s[3]))
	eq(guest.mut_band, Mutation.band_index(66.0))
	ok(guest.effects.has("nausea"))
	near(guest.speed_mul, p.speed_mul, 0.001, "the guest is predicting a different speed to the host")


func test_a_brute_is_worth_walking_toward() -> void:
	var haul := {}
	for type in ["walker", "brute"]:
		var got := 0
		for i in range(60):
			var e := sim.enemies.spawn(type, p.pos + Vector2(300, 0))
			Damage.kill_enemy(sim, e)
		for it in sim.pickups:
			if Mutation.is_suppressant(String(it.id)) or String(it.id) == "brainSpec":
				got += int(it.n) * (10 if String(it.id) == "brainMut" else 1)
		haul[type] = got
		sim.pickups.clear()
	gt(haul.walker, 0, "sixty walkers dropped no brain matter at all")
	gt(haul.brute, haul.walker, "a Brute is worth no more than a Walker")
