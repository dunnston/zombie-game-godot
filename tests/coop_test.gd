extends TestCase
## Two people in one simulation, before any wire is involved: seats, parking,
## and downed-not-dead. The net tests build on these.


func _two(sim: GameSim) -> PlayerSim:
	var g := sim.join_player("guest-a", "Bex")
	g.pos = sim.players[0].pos + Vector2(40, 0)
	g.prev_pos = g.pos
	return g


func test_join_takes_the_next_seat_beside_the_host() -> void:
	var sim := TestCase.new_sim()
	var host := sim.players[0]
	var g := _two(sim)
	ne(g, null)
	eq(g.seat, 1)
	eq(g.identity, "guest-a")
	eq(g.display_name, "Bex")
	ok(g.hotbar.count("pipe") > 0, "a joiner wakes with the starting kit")
	ok(g.pos.distance_to(host.pos) < 8.0 * Config.TILE, "spawned beside the host")
	eq(sim.present_players().size(), 2)
	var third := sim.join_player("guest-b")
	var fourth := sim.join_player("guest-c")
	eq(fourth.seat, 3)
	eq(sim.join_player("guest-d"), null, "four seats and no more")
	ne(third, null)


func test_parked_player_is_out_of_the_world() -> void:
	var sim := TestCase.new_sim()
	var g := _two(sim)
	g.intent.mx = 1.0
	var before := g.pos
	sim.park_player(g)
	ok(g.away)
	TestCase.run(sim, 1.0)
	eq(g.pos, before, "a parked player does not walk")
	eq(sim.living_players().size(), 1)
	eq(sim.nearest_player(g.pos + Vector2(1, 0)), sim.players[0], "not a target while away")
	eq(sim.player_by_identity("guest-a"), g)
	sim.unpark_player(g, "Bex again")
	ok(not g.away)
	eq(g.display_name, "Bex again")


func test_alone_you_die_with_a_teammate_you_go_down() -> void:
	var sim := TestCase.new_sim()
	var host := sim.players[0]
	host.invuln = 0.0
	Damage.damage_player(sim, host, 9999.0, host.pos + Vector2(10, 0))
	ok(host.dead, "solo death is unchanged")
	ok(not host.downed)

	var sim2 := TestCase.new_sim()
	var h2 := sim2.players[0]
	var g := _two(sim2)
	h2.invuln = 0.0
	Damage.damage_player(sim2, h2, 9999.0, h2.pos + Vector2(10, 0))
	ok(h2.downed, "with somebody standing you go down instead")
	ok(not h2.dead)
	eq(h2.hp, 0.0)
	near(h2.down_t, Config.PLAYER.downed_time, 1e-6)
	ok(TestCase.events_of(sim2, "player_down").size() == 1)
	# Down is not a target, and not a punching bag either.
	eq(sim2.nearest_player(h2.pos), g)
	eq(Damage.damage_player(sim2, h2, 50.0, h2.pos), 0.0)
	# And you cannot walk.
	h2.intent.mx = 1.0
	var at := h2.pos
	TestCase.run(sim2, 0.5)
	eq(h2.pos, at)


func test_bleed_out_ends_in_the_usual_death() -> void:
	var sim := TestCase.new_sim()
	var h := sim.players[0]
	_two(sim)
	h.invuln = 0.0
	Damage.damage_player(sim, h, 9999.0, h.pos)
	ok(h.downed)
	TestCase.run(sim, Config.PLAYER.downed_time + 0.2)
	ok(h.dead, "nobody came")
	ok(not h.downed)
	ok(TestCase.events_of(sim, "player_died").size() >= 1)


func test_a_held_key_beside_them_gets_them_up() -> void:
	var sim := TestCase.new_sim()
	var h := sim.players[0]
	var g := _two(sim)
	h.invuln = 0.0
	Damage.damage_player(sim, h, 9999.0, h.pos)
	ok(h.downed)
	var target := Interact.best_target(sim, g)
	eq(target.get("kind", ""), "revive_player", "the key offers the teammate first")
	g.intent.interact = true
	g.intent.interact_held = true
	sim.tick(1.0 / 60.0)
	ok(not g.reviving.is_empty(), "the channel started")
	# Letting go stops it.
	g.intent.interact_held = false
	TestCase.run(sim, 0.3)
	ok(g.reviving.is_empty(), "let go and it stops")
	ok(h.downed)
	# Holding it through gets them up.
	g.intent.interact = true
	g.intent.interact_held = true
	sim.tick(1.0 / 60.0)
	g.intent.interact_held = true
	var stood_at := g.pos
	TestCase.run(sim, Config.PLAYER.revive_time + 0.1)
	ok(not h.downed, "revived")
	ok(not h.dead)
	near(h.hp, roundf(h.max_hp * Config.PLAYER.revive_hp_frac), 1.0)
	eq(g.pos, stood_at, "getting somebody up roots you")
	ok(TestCase.events_of(sim, "player_up").size() == 1)


func test_leaving_while_down_is_death_and_the_save_keeps_the_seat() -> void:
	var sim := TestCase.new_sim()
	var h := sim.players[0]
	var g := _two(sim)
	g.level = 4
	g.invuln = 0.0
	Damage.damage_player(sim, g, 9999.0, g.pos)
	ok(g.downed)
	sim.park_player(g)
	ok(g.dead, "walking out mid-bleed-out is not a rescue")
	ok(g.away)
	# Round trip through the payload: the parked guest is still there, still
	# level 4, still away; the host is never away.
	var data := SaveGame.to_dict(sim)
	var sim2 := GameSim.new()
	var r := SaveGame.apply(sim2, data)
	ok(r.ok, r.reason)
	eq(sim2.players.size(), 2)
	var back := sim2.player_by_identity("guest-a")
	ne(back, null)
	eq(back.level, 4)
	ok(back.away)
	ok(not sim2.players[0].away)
	ok(h != null)
