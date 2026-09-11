extends "res://tests/test_case.gd"
## Bleed: what an edged weapon leaves behind.
##
## It was cut on 2026-09-08 because three weapons declared it and nothing read
## it, on the condition that it came back as a spec'd mechanic or not at all.
## This is the spec: the same three weapons, a rate per second on the wound
## rather than on the carrier, no stacking, and a kill that still belongs to
## whoever opened it.

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.intent.aim = plot + Vector2.RIGHT
	sim.give_test_kit(p)


## Puts the weapon in the hand outright — the test kit's hotbar holds none of
## the three blades this file is about.
func _hold(id: String) -> void:
	p.hotbar.slots[0] = {"id": id, "n": 1}
	p.slot = 0
	p.attack_cd = 0.0


## Plants an enemy the next swing can find. The tick is what puts it in the
## spatial hash, which is what `melee_targets` searches; without it a swing in
## the same frame as a spawn hits nothing.
func _plant(offset: Vector2, hp := 500.0) -> EnemySim:
	var e := sim.enemies.spawn("walker", plot + offset)
	sim.tick(1.0 / 60.0)
	e.hp = hp
	e.max_hp = maxf(e.max_hp, hp)
	return e


## Far enough that a walker cannot sense it (330px) and near enough that the
## cull leaves it alone. A wound must not be what makes something notice you.
func _bystander() -> EnemySim:
	return _plant(Vector2(600, 0))


# ------------------------------------------------------------------ tables --

func test_exactly_the_three_blades_bleed() -> void:
	var bleeders: Array[String] = []
	for id in Config.WEAPONS:
		if float(Config.WEAPONS[id].get("bleed", 0.0)) > 0.0:
			bleeders.append(id)
	bleeders.sort()
	eq(bleeders, ["bladedPike", "knife", "leafSpringBlade", "machete", "scythe"],
		"every weapon whose edge tears, and only those")
	for id in bleeders:
		ok(not Config.WEAPONS[id].has("stagger"), "%s is a blade, not a club" % id)
	gt(Config.WEAPONS.knife.bleed, Config.WEAPONS.machete.bleed,
		"a knapped edge tears where a brush blade cuts clean: bleed is the kind of edge, not the size")
	gt(Config.WEAPONS.machete.dmg, Config.WEAPONS.knife.dmg,
		"and the bigger blade still hits harder, so bleed is not a rider on damage")


# ------------------------------------------------------------- the wound --

func test_a_blade_opens_a_wound_and_a_fist_does_not() -> void:
	_hold("machete")
	var cut := _plant(Vector2(30, 0))
	p.angle = 0.0
	p.intent.aim = cut.pos
	Combat.melee_attack(sim, p, Config.WEAPONS.machete)
	near(cut.bleed_t, Config.BLEED.time, 1e-6)
	near(cut.bleed_dps, Config.WEAPONS.machete.bleed, 1e-6)
	eq(cut.bleed_by, p, "and it knows who cut it")

	var punched := _plant(Vector2(-30, 0))
	p.angle = PI
	Combat.melee_attack(sim, p, Config.WEAPONS.fists)
	eq(punched.bleed_t, 0.0, "fists do not cut")


func test_a_wound_empties_without_startling_what_it_is_in() -> void:
	var e := _bystander()
	run(sim, 0.2)
	ok(not e.aggro, "it has not seen anything")
	var hp := e.hp
	Damage.bleed_enemy(e, 6.0, p)
	run(sim, 1.0)
	near(hp - e.hp, 6.0, 0.4, "about a second's worth of bleeding")
	ok(not e.aggro, "a wound is not a reason to notice you")
	eq(events_of(sim, "hit").size(), 0, "and it does not throw blood sixty times a second")


func test_a_wound_runs_out() -> void:
	var e := _bystander()
	e.hp = 500.0
	var hp := e.hp
	Damage.bleed_enemy(e, 6.0, p)
	run(sim, Config.BLEED.time + 1.0)
	eq(e.bleed_t, 0.0, "the clock ran out")
	near(hp - e.hp, 6.0 * Config.BLEED.time, 0.5, "and it lost the whole wound, once")
	var settled := e.hp
	run(sim, 1.0)
	near(e.hp, settled, 1e-6, "then it stops")


func test_a_closed_wound_leaves_nothing_behind() -> void:
	# Codex, PR #23. The clock was zeroed and the rate and the owner were
	# left standing, so the *next* cut was measured against a wound that had
	# already finished: a Stone Knife opening something a Machete had bled dry
	# inherited the Machete's 6 dps, and the kill was credited to whoever had
	# swung the Machete.
	var e := _bystander()
	Damage.bleed_enemy(e, Config.WEAPONS.machete.bleed, p)
	run(sim, Config.BLEED.time + 0.5)
	eq(e.bleed_t, 0.0, "the wound closed")
	eq(e.bleed_dps, 0.0, "and the rate went with it")
	eq(e.bleed_by, null, "and so did the owner")

	# A weaker blade, seconds later, is its own wound and nobody else's.
	Damage.bleed_enemy(e, Config.WEAPONS.knife.bleed, null)
	near(e.bleed_dps, Config.WEAPONS.knife.bleed, 1e-6, "the knife's own rate")
	eq(e.bleed_by, null, "credited to whoever actually cut it")
	var hp := e.hp
	run(sim, 1.0)
	near(hp - e.hp, Config.WEAPONS.knife.bleed, 0.4, "and it bleeds like a knife wound")


func test_the_deepest_cut_is_the_one_that_is_bleeding() -> void:
	# The rule that stops a 0.28s Stone Knife multiplying itself into the
	# best weapon in the game against anything big.
	var e := _bystander()
	e.hp = 500.0
	Damage.bleed_enemy(e, 4.0, p)
	Damage.bleed_enemy(e, 6.0, p)
	near(e.bleed_dps, 6.0, 1e-6, "the deeper wound wins")
	run(sim, 1.0)
	Damage.bleed_enemy(e, 4.0, p)
	near(e.bleed_dps, 6.0, 1e-6, "a shallower one does not replace it")
	near(e.bleed_t, Config.BLEED.time, 1e-6, "but it does refresh the clock")


func test_a_kill_seconds_later_still_belongs_to_whoever_cut_it() -> void:
	var e := _bystander()
	e.hp = 4.0
	var xp := p.xp
	Damage.bleed_enemy(e, 6.0, p)
	run(sim, 1.5)
	ok(e.dead, "it bled out")
	eq(sim.stats.kills, 1)
	gt(p.xp, xp, "and the kill paid the person who opened it")


func test_a_machete_finishes_what_it_started() -> void:
	# The whole point of the mechanic in play: disengage and it still dies.
	_hold("machete")
	var e := _plant(Vector2(30, 0), 200.0)
	p.intent.aim = e.pos
	p.intent.fire = true
	run(sim, 0.5)
	p.intent.fire = false
	gt(e.bleed_t, 0.0, "it is bleeding")
	var hp := e.hp
	run(sim, 1.0)
	ok(e.hp < hp, "and still losing blood with nobody swinging")
