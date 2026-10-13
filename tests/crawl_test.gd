extends "res://tests/test_case.gd"
## Knocked down, not dead: a stagger can put a walker or a runner on the
## ground, where it crawls slowly, can still be hit, gets up after a while, and
## is a zombie again. Some of the town's own spawns start that way for good.

var sim: GameSim
var p: PlayerSim
var plot: Vector2


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.intent.aim = plot + Vector2.RIGHT


func _plant(type: String, offset: Vector2) -> EnemySim:
	var e := sim.enemies.spawn(type, plot + offset)
	sim.tick(1.0 / 60.0)
	e.hp = 500.0
	e.max_hp = 500.0
	return e


func _chase_speed(e: EnemySim, seconds: float) -> float:
	var from := e.pos
	e.aggro = true
	e.alert_t = 999.0
	run(sim, seconds)
	return from.distance_to(e.pos) / seconds


func test_a_walker_can_be_put_on_the_ground_and_a_boss_cannot() -> void:
	var w := _plant("walker", Vector2(400, 0))
	ok(Damage.knock_down(w), "a walker goes down")
	gt(w.crawl_t, 0.0)
	ok(not Damage.knock_down(w), "and cannot go down twice")
	var boss := _plant("coach", Vector2(0, 400))
	ok(not Damage.knock_down(boss), "a boss never does")
	eq(boss.crawl_t, 0.0)
	var brute := _plant("brute", Vector2(-400, 0))
	ok(not Damage.knock_down(brute), "and only the kinds the table names")


func test_a_crawler_is_slower_and_reaches_less() -> void:
	var up := _plant("walker", Vector2(600, 0))
	var down := _plant("walker", Vector2(600, 200))
	Damage.knock_down(down, 60.0)
	near(down.atk_range, float(down.def.atk_range) * float(Config.CRAWL.reach_mul), 1e-6)
	var v_up := _chase_speed(up, 1.5)
	var v_down := _chase_speed(down, 1.5)
	gt(v_up, v_down * 2.0, "walking %.0f px/s, crawling %.0f px/s" % [v_up, v_down])
	gt(v_down, 1.0, "but it does come")


func test_it_gets_up_and_is_a_zombie_again() -> void:
	var e := _plant("walker", Vector2(600, 0))
	Damage.knock_down(e, 1.0)
	run(sim, 1.1)
	eq(e.crawl_t, 0.0, "the crawl is over")
	gt(e.getup_t, 0.0, "it is getting up")
	near(e.atk_range, float(e.def.atk_range), 1e-6, "its reach is back")
	var at := e.pos
	e.aggro = true
	e.alert_t = 999.0
	run(sim, 1.0)
	near(e.pos.distance_to(at), 0.0, 3.0, "getting up it goes nowhere")
	run(sim, float(Config.CRAWL.getup))
	eq(e.getup_t, 0.0, "up")
	gt(_chase_speed(e, 1.0), float(e.def.speed) * 0.5, "and walking")


func test_a_crawler_can_still_be_killed() -> void:
	var e := _plant("walker", Vector2(60, 0))
	Damage.knock_down(e, 60.0)
	e.hp = 5.0
	p.angle = 0.0
	sim.give_test_kit(p)
	p.hotbar.slots[0] = {"id": "hammer", "n": 1}
	p.slot = 0
	p.attack_cd = 0.0
	Combat.melee_attack(sim, p, Config.WEAPONS.hammer)
	run(sim, 0.3)
	ok(e.dead, "it died on the ground")


func test_a_heavy_blow_sometimes_puts_it_down() -> void:
	# The roll has a stream of its own, so a run of staggers is the
	# chance made visible: a third, give or take, and never all or none.
	var down := 0
	var n := 120
	for i in n:
		var e := sim.enemies.spawn("walker", plot + Vector2(0, 600))
		e.hp = 500.0
		Damage.stagger_enemy(sim, e, 1.0)
		if e.crawl_t > 0.0:
			down += 1
		e.dead = true
	gt(down, n * 0.15, "%d of %d" % [down, n])
	gt(n * 0.5, down, "%d of %d" % [down, n])


func test_a_boss_is_rocked_but_never_floored() -> void:
	var boss := _plant("coach", Vector2(0, 400))
	boss.knock_resist = 0.0
	Damage.stagger_enemy(sim, boss, 1.0)
	eq(boss.crawl_t, 0.0)


func test_some_of_the_towns_own_spawns_start_on_the_ground_for_good() -> void:
	var crawlers := 0
	var walkers := 0
	var n := 400
	for i in n:
		var e := sim.enemies._spawn_ambient("walker", plot + Vector2(float(i % 20) * 40.0, 900.0))
		walkers += 1
		if e.crawl_t > 0.0:
			crawlers += 1
			ok(is_inf(e.crawl_t), "and it never gets up")
	gt(crawlers, int(n * float(Config.CRAWL.spawn_chance) * 0.5), "%d of %d" % [crawlers, walkers])
	gt(int(n * float(Config.CRAWL.spawn_chance) * 2.0), crawlers)
	var raider := sim.enemies._spawn_ambient("raider", plot)
	eq(raider.crawl_t, 0.0, "only the kinds that go down")


func test_a_raid_or_a_plain_spawn_is_never_a_crawler() -> void:
	for i in 100:
		eq(sim.enemies.spawn("walker", plot + Vector2(float(i) * 8.0, 700.0)).crawl_t, 0.0)


func test_the_wire_says_who_is_down_and_who_is_getting_up() -> void:
	var a := _plant("walker", Vector2(100, 0))
	var b := _plant("walker", Vector2(100, 100))
	Damage.knock_down(a, 60.0)
	b.getup_t = 1.0
	var rec := NetProtocol.pack_enemies(sim, plot, 800.0)
	var flags := {}
	for i in range(0, rec.size(), NetProtocol.EN_STRIDE):
		flags[int(rec[i])] = int(rec[i + 7])
	ok(flags[a.id] & NetProtocol.EF_CRAWL != 0, "down")
	ok(flags[a.id] & NetProtocol.EF_GETUP == 0)
	ok(flags[b.id] & NetProtocol.EF_GETUP != 0, "getting up")
	ok(flags[b.id] & NetProtocol.EF_CRAWL == 0)
	var infinite := _plant("walker", Vector2(100, 200))
	Damage.knock_down(infinite, INF)
	rec = NetProtocol.pack_enemies(sim, plot, 800.0)
	var found := false
	for i in range(0, rec.size(), NetProtocol.EN_STRIDE):
		if int(rec[i]) == infinite.id:
			found = int(rec[i + 7]) & NetProtocol.EF_CRAWL != 0
	ok(found, "a permanent crawler is still just a flag")
