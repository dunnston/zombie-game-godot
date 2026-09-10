extends "res://tests/test_case.gd"
## Stagger: the blow that interrupts a committed swing.
##
## The mechanic is one sentence — a hard enough hit takes the bite away — and
## three rules that stop it being either useless or a lock: resistance scales
## it, a floor makes the biggest bodies immune without naming them, and an
## immunity window means an interrupt is something you spend rather than
## something you hold.

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


## Puts the weapon in the hand outright. The test kit's hotbar is six rows
## long and holds none of the melee weapons this file is about, so asking for
## a hammer by index would quietly leave a Steel Pipe in your hand.
func _hold(id: String) -> void:
	p.hotbar.slots[0] = {"id": id, "n": 1}
	p.slot = 0
	p.attack_cd = 0.0


## Plants an enemy that the next swing can actually find, with enough health
## that no test here turns on whether a critical happened to land.
##
## The tick is the point: `melee_targets` and every bullet ask the spatial
## hash, and the hash is rebuilt on tick — so a swing in the same frame as a
## spawn reaches into an empty index and hits nothing at all.
func _plant(type: String, offset: Vector2, hp := 500.0) -> EnemySim:
	var e := sim.enemies.spawn(type, plot + offset)
	sim.tick(1.0 / 60.0)
	e.hp = hp
	e.max_hp = maxf(e.max_hp, hp)
	return e


## Steps until this enemy commits to a swing, and says whether it did. The
## wind-up is 0.24s and the bite lands at the end of it, so catching the frame
## it starts is what makes "the bite never landed" a real assertion.
func _wait_for_windup(e: EnemySim, seconds := 5.0) -> bool:
	for i in range(int(seconds * 60)):
		sim.tick(1.0 / 60.0)
		if e.windup > 0.0:
			return true
	return false


# ------------------------------------------------------------------ tables --

func test_blunt_things_stagger_and_edged_things_bleed() -> void:
	# The content design, asserted: no weapon does both, and the split is not
	# an accident of which rows happened to get a field.
	var staggers: Array[String] = []
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		var s: float = w.get("stagger", 0.0)
		var b: float = w.get("bleed", 0.0)
		ok(not (s > 0.0 and b > 0.0), "%s both staggers and bleeds" % id)
		if s > 0.0:
			staggers.append(id)
	for id in ["pipe", "hammer", "sledge", "axe", "fireaxe", "pick", "steelpick", "shotgun", "rifle"]:
		has(staggers, id, "%s is blunt and should rock something" % id)
	for id in ["machete", "knife", "scythe", "fists", "pistol", "smg", "carbine", "bow"]:
		ok(not staggers.has(id), "%s should not stagger" % id)
	ok(Config.WEAPONS.sledge.stagger > Config.WEAPONS.pipe.stagger, "the sledgehammer is the big one")


func test_no_weapon_carries_a_stagger_too_small_to_do_anything() -> void:
	# A number under the floor against the softest body in the game would be
	# a field that reads as a feature and never once fires — worse than not
	# having it (pillar 5).
	for id in Config.WEAPONS:
		var s: float = Config.WEAPONS[id].get("stagger", 0.0)
		if s > 0.0:
			ok(s * (1.0 - Config.ENEMIES.walker.knock_resist) >= Config.STAGGER.min,
				"%s cannot stagger even a walker" % id)


# ---------------------------------------------------------- the interrupt --

func test_a_blunt_swing_cancels_a_committed_bite() -> void:
	_hold("hammer")
	var e := _plant("walker", Vector2(28, 0))
	p.intent.aim = e.pos
	ok(_wait_for_windup(e), "the walker committed to a bite")
	var hp := p.hp
	p.angle = 0.0
	ok(Combat.melee_attack(sim, p, Config.WEAPONS.hammer), "the hammer swung")
	eq(e.windup, 0.0, "the wind-up is gone")
	ok(e.pending_struct.is_empty() and e.pending_survivor == null, "and so is whatever it was aimed at")
	gt(e.stagger_t, 0.0, "it is reeling")
	run(sim, 0.4)
	near(p.hp, hp, 1e-6, "the bite never landed")
	ok(events_of(sim, "stagger").size() >= 1, "and the view was told")


func test_an_edged_swing_leaves_the_bite_coming() -> void:
	# The other half of the test above: the harness is real, and a machete
	# genuinely does not interrupt — it opens a wound instead.
	_hold("machete")
	var e := _plant("walker", Vector2(28, 0))
	p.intent.aim = e.pos
	ok(_wait_for_windup(e), "the walker committed to a bite")
	var hp := p.hp
	p.angle = 0.0
	ok(Combat.melee_attack(sim, p, Config.WEAPONS.machete), "the machete swung")
	eq(e.stagger_t, 0.0, "a blade does not rock it")
	gt(e.bleed_t, 0.0, "it cuts")
	gt(e.windup, 0.0, "the bite is still coming")
	run(sim, 0.4)
	ok(p.hp < hp, "and it landed")


func test_a_staggered_enemy_neither_walks_nor_swings() -> void:
	p.god_mode = true
	var rocked := _plant("walker", Vector2(150, 0))
	var control := _plant("walker", Vector2(-150, 0))
	run(sim, 0.5)
	ok(rocked.aggro and control.aggro, "both are hunting")
	gt(Damage.stagger_enemy(sim, rocked, 1.5), 0.0)
	var r0 := rocked.pos.distance_to(p.pos)
	var c0 := control.pos.distance_to(p.pos)
	run(sim, 1.0)
	var r_closed := r0 - rocked.pos.distance_to(p.pos)
	var c_closed := c0 - control.pos.distance_to(p.pos)
	gt(c_closed, 40.0, "the control walker closed %.0f px" % c_closed)
	ok(r_closed < c_closed * 0.35, "the staggered one covered %.0f px against %.0f" % [r_closed, c_closed])
	# And it is a stagger, not a death: it gets up and comes on.
	run(sim, 1.0)
	eq(rocked.stagger_t, 0.0, "the clock ran out")
	var r1 := rocked.pos.distance_to(p.pos)
	run(sim, 1.0)
	gt(r1 - rocked.pos.distance_to(p.pos), 30.0, "and it is walking again")


# ------------------------------------------------- resistance and the floor --

func test_a_heavy_body_is_harder_to_rock() -> void:
	var walker := _plant("walker", Vector2(200, 0))
	var brute := _plant("brute", Vector2(-200, 0))
	var secs: float = Config.WEAPONS.sledge.stagger
	near(Damage.stagger_enemy(sim, walker, secs), secs, 1e-6, "nothing resists it")
	near(Damage.stagger_enemy(sim, brute, secs), secs * (1.0 - Config.ENEMIES.brute.knock_resist), 1e-6)
	gt(walker.stagger_t, brute.stagger_t)
	gt(brute.stagger_t, 0.0, "a brute still goes down on its heel to a sledgehammer")


func test_a_boss_shrugs_off_the_biggest_weapon_in_the_game() -> void:
	# Immunity through the floor alone. Nothing anywhere names a Behemoth;
	# 0.95 resistance and a 0.12 floor are the whole rule.
	var boss := _plant("behemoth", Vector2(220, 0))
	eq(Damage.stagger_enemy(sim, boss, Config.WEAPONS.sledge.stagger), 0.0)
	eq(boss.stagger_t, 0.0)
	eq(boss.stagger_cd, 0.0, "a refused stagger does not start the immunity either")
	gt(Config.WEAPONS.sledge.stagger * (1.0 - Config.ENEMIES.behemoth.knock_resist), 0.0,
		"and it is the floor doing it, not a zero")


func test_a_critical_rocks_it_harder() -> void:
	var a := _plant("walker", Vector2(200, 0))
	var b := _plant("walker", Vector2(-200, 0))
	near(Damage.stagger_enemy(sim, a, 0.3), 0.3, 1e-6)
	near(Damage.stagger_enemy(sim, b, 0.3, true), 0.3 * Config.STAGGER.crit_mul, 1e-6)
	gt(b.stagger_t, a.stagger_t)


# ---------------------------------------------------------- the anti-lock --

func test_the_immunity_window_stops_a_fast_weapon_locking() -> void:
	var e := _plant("walker", Vector2(300, 0))
	gt(Damage.stagger_enemy(sim, e, 0.4), 0.0, "the first blow rocks it")
	eq(Damage.stagger_enemy(sim, e, 0.4), 0.0, "a second inside the window does nothing")
	run(sim, 0.6)
	eq(e.stagger_t, 0.0, "it is back on its feet")
	eq(Damage.stagger_enemy(sim, e, 0.4), 0.0, "and still cannot be rocked again")
	gt(e.stagger_cd, 0.0)
	run(sim, Config.STAGGER.immune)
	gt(Damage.stagger_enemy(sim, e, 0.4), 0.0, "once the window has run out, it can be")


func test_a_shotgun_spread_is_one_shove_not_eight() -> void:
	_hold("shotgun")
	var e := _plant("walker", Vector2(58, 0))
	e.aggro = true
	p.angle = 0.0
	p.mag["shotgun"] = 6
	ok(Combat.fire_gun(sim, p, Config.WEAPONS.shotgun), "fired")
	run(sim, 0.25)
	gt(sim.stats.damage_dealt, Config.WEAPONS.shotgun.dmg, "more than one pellet connected")
	eq(events_of(sim, "stagger").size(), 1, "and they rocked it once between them")


func test_a_rifle_round_rocks_what_it_goes_through() -> void:
	# Pierce keeps the round at full stagger for the body behind: two enemies,
	# two staggers, and the per-enemy immunity is why that is not a problem.
	_hold("rifle")
	var near_e := _plant("walker", Vector2(70, 0))
	var far_e := _plant("walker", Vector2(110, 0))
	near_e.aggro = true
	far_e.aggro = true
	p.angle = 0.0
	p.mag["rifle"] = 8
	ok(Combat.fire_gun(sim, p, Config.WEAPONS.rifle), "fired")
	run(sim, 0.3)
	gt(near_e.stagger_cd, 0.0, "the first one was rocked")
	gt(far_e.stagger_cd, 0.0, "and so was the one behind it")
