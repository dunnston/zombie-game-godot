extends "res://tests/test_case.gd"
## The Coach, the School's boss (PR C; `tasks/instanced-dungeons.md` §8). A
## phase boss is a script on top of the ordinary AI: pick a move off cooldown,
## telegraph it, do it, recover, and change the pattern at a threshold. Every
## assertion is on an outcome — where it hit, whom, and when — through the
## sim's own step.

var sim: GameSim
var p: PlayerSim
var inst: Instance
var coach: EnemySim
var brain: Boss
var B: Dictionary
const DT := 1.0 / 60.0


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	var f := Instance.door_for(sim, "school")
	p.pos = f.stand
	ok(Instance.enter(sim, p, "school"))
	inst = sim.instance
	coach = inst.boss
	brain = coach.brain
	B = Config.BOSSES[coach.type]
	# Just the two of you: the school's crowd would make every hit ambiguous.
	for i in range(sim.enemies.list.size() - 1, -1, -1):
		if sim.enemies.list[i] != coach:
			sim.enemies.list.remove_at(i)
	_put(Vector2(0, 220))


## The player, `off` from the Coach, standing still and whole.
func _put(off: Vector2) -> void:
	p.pos = coach.pos + off
	p.prev_pos = p.pos
	p.vel = Vector2.ZERO
	p.hp = p.max_hp
	p.invuln = 0.0


func _until(pred: Callable, cap := 5.0) -> bool:
	for i in range(int(cap / DT)):
		if pred.call():
			return true
		sim.tick(DT)
	return pred.call()


func _move(id: String) -> Dictionary:
	return B.moves[id]


# ----------------------------------------------------------- waking up --

func test_it_waits_in_its_gym_until_somebody_comes_in() -> void:
	p.pos = sim.world.entry_spot
	var at := coach.pos
	run(sim, 2.0)
	eq(brain.state, "asleep")
	ok(coach.pos.distance_to(at) < 1.0, "not a step toward you")
	_put(Vector2(0, 220))
	run(sim, 0.1)
	ne(brain.state, "asleep", "you walked into its gym")
	eq(events_of(sim, "boss_wake").size(), 1)


func test_shooting_it_from_the_doorway_wakes_it() -> void:
	p.pos = sim.world.entry_spot
	Damage.damage_enemy(sim, coach, 10.0, p.pos)
	run(sim, 0.05)
	ne(brain.state, "asleep", "a boss that slept through being shot is a target, not a fight")


func test_it_will_not_leave_its_gym() -> void:
	brain.force(sim, coach, p, "slam")
	coach.pos = sim.world.entry_spot
	sim.tick(DT)
	ok(brain.arena.has_point(coach.pos), "back at the edge of its room")


func test_every_telegraph_is_long_enough_to_see_and_to_get_out_of() -> void:
	# Sized against the dash (PR A: a 0.18s burst, 0.9s between) and against
	# walking: 176px/s leaves a 150px slam ring in under a second.
	ok(float(B.min_tell) >= 0.7, "the floor itself")
	for id: String in B.moves:
		ok(float(B.moves[id].tell) >= float(B.min_tell), "%s telegraphs for %.2fs" % [id, float(B.moves[id].tell)])
	ok(float(_move("slam").radius) / Config.PLAYER.speed <= float(_move("slam").tell) + 0.05,
		"a walk gets you out of a slam in time")


# --------------------------------------------------------------- moves --

func test_a_slam_lands_when_its_telegraph_ends_on_whoever_is_in_the_ring() -> void:
	var m := _move("slam")
	_put(Vector2(float(m.radius) - 40.0, 0))
	brain.force(sim, coach, p, "slam")
	run(sim, float(m.tell) - 0.1)
	eq(p.hp, p.max_hp, "nothing before the promise is kept")
	run(sim, 0.2)
	ok(p.hp < p.max_hp, "and then it is")
	eq(events_of(sim, "boss_slam").size(), 1)


func test_stepping_out_of_the_ring_before_it_lands_costs_nothing() -> void:
	var m := _move("slam")
	_put(Vector2(float(m.radius) - 40.0, 0))
	brain.force(sim, coach, p, "slam")
	run(sim, float(m.tell) * 0.5)
	p.pos = coach.pos + Vector2(float(m.radius) + 60.0, 0)
	run(sim, float(m.tell))
	eq(p.hp, p.max_hp, "the ring was the whole of it")


func test_a_charge_runs_the_lane_it_telegraphed_and_hits_once() -> void:
	var m := _move("charge")
	_put(Vector2(220, 0))
	var from := coach.pos
	brain.force(sim, coach, p, "charge")
	run(sim, float(m.tell) + 0.05)
	eq(brain.state, "charge")
	ok(_until(func() -> bool: return brain.state != "charge", 3.0))
	gt(coach.pos.x - from.x, 150.0, "down the lane toward where you stood")
	ok(p.hp < p.max_hp, "through you")
	eq(events_of(sim, "player_hit").size(), 1, "once, not once a frame")


func test_a_charge_into_a_wall_leaves_it_dazed_and_open() -> void:
	var m := _move("charge")
	p.god_mode = true
	# By the west wall, aimed at it.
	coach.pos = Vector2(brain.arena.position.x + 90.0, brain.arena.get_center().y)
	coach.prev_pos = coach.pos
	_put(Vector2(-60, 0))
	brain.force(sim, coach, p, "charge")
	ok(_until(func() -> bool: return brain.state == "stunned", float(m.tell) + 2.0), "into the wall")
	eq(events_of(sim, "boss_stunned").size(), 1)
	# The opening: stood beside it, nothing comes back.
	p.god_mode = false
	_put(Vector2(40, 0))
	run(sim, float(m.stun) * 0.7)
	eq(p.hp, p.max_hp, "dazed means dazed")


func test_dodgeball_throws_a_fan_of_balls_that_hurt() -> void:
	var m := _move("dodgeball")
	_put(Vector2(0, 260))
	brain.force(sim, coach, p, "dodgeball")
	run(sim, float(m.tell) + 0.02)
	var balls := 0
	for b in sim.bullets:
		if b.get("hostile", false):
			balls += 1
	eq(balls, int(m.count), "the whole fan")
	run(sim, 1.5)
	ok(p.hp < p.max_hp, "and the one down the middle was yours")


func test_the_whistle_calls_the_team_in_and_no_more_than_the_cap() -> void:
	var m := _move("whistle")
	p.god_mode = true
	brain.force(sim, coach, p, "whistle")
	run(sim, float(m.tell) + 0.02)
	var team := func() -> int:
		var n := 0
		for e in sim.enemies.list:
			if e.minion and not e.dead:
				n += 1
		return n
	eq(team.call(), int(m.adds))
	for i in range(3):
		brain.state = "fight"
		brain.force(sim, coach, p, "whistle")
		run(sim, float(m.tell) + 0.02)
	ok(team.call() <= int(m.cap), "%d on the floor, cap %d" % [team.call(), int(m.cap)])


# -------------------------------------------------------------- phases --

func test_it_changes_its_game_at_two_thirds_and_again_at_one_third() -> void:
	brain.force(sim, coach, p, "slam")
	coach.hp = coach.max_hp * 0.6
	sim.tick(DT)
	eq(brain.phase, 1)
	eq(brain.state, "shift")
	eq(Damage.damage_enemy(sim, coach, 50.0, p.pos), 0.0, "untouchable while it turns")
	ok(inst.dark, "and the lights are gone")
	eq(events_of(sim, "boss_phase").size(), 1)
	run(sim, float(B.transition) + 0.1)
	ne(brain.state, "shift", "then back to it")
	gt(Damage.damage_enemy(sim, coach, 1.0, p.pos), 0.0)
	coach.hp = coach.max_hp * 0.3
	sim.tick(DT)
	eq(brain.phase, 2)
	gt(coach.speed, brain.base_speed, "faster in overtime")


func test_a_burst_past_two_thresholds_still_runs_what_the_second_half_opens_with() -> void:
	brain.force(sim, coach, p, "slam")
	coach.hp = coach.max_hp * 0.2
	sim.tick(DT)
	eq(brain.phase, 2)
	ok(inst.dark, "the lights went out on the way past")


func test_no_burst_goes_through_a_phase() -> void:
	# Codex on PR #33: a volley that crossed a threshold after the script had
	# run killed it before the change could — a party's burst finished the
	# Coach from above a third without OVERTIME ever starting.
	var huge := coach.max_hp * 5.0
	var second := coach.max_hp * float(B.phases[1].at)
	near(Damage.damage_enemy(sim, coach, huge, p.pos), coach.max_hp - second, 1e-3, "it takes the hit down to the threshold")
	ok(not coach.dead, "more than its whole bar, and it is standing")
	near(coach.hp, second, 1e-3, "at the second half, exactly")
	sim.tick(DT)
	eq(brain.phase, 1)
	eq(brain.state, "shift", "and the change runs")
	run(sim, float(B.transition) + 0.1)
	Damage.damage_enemy(sim, coach, huge, p.pos)
	ok(not coach.dead, "the same again, and it is standing")
	sim.tick(DT)
	eq(brain.phase, 2, "into overtime")
	run(sim, float(B.transition) + 0.1)
	Damage.damage_enemy(sim, coach, huge, p.pos)
	ok(coach.dead, "past the last threshold, it can be finished")


func test_nothing_lands_through_the_shield_not_even_a_wound() -> void:
	# Codex on PR #33: the shield refused a blow's damage and let its bleed and
	# stagger through, so a cut made while it turned bit the moment it was done.
	coach.hp = coach.max_hp * 0.6
	sim.tick(DT)
	eq(brain.state, "shift")
	ok(not Damage.bleed_enemy(coach, 10.0, p), "no wound")
	eq(Damage.stagger_enemy(sim, coach, 2.0), 0.0, "no stagger")
	# And through a real swing, the path that found it.
	_put(Vector2(coach.r + 18.0, 0))
	p.angle = PI
	p.intent.aim = coach.pos
	Combat.melee_attack(sim, p, Config.WEAPONS.machete)
	eq(coach.bleed_t, 0.0, "a machete through the shield opens nothing")
	eq(coach.stagger_t, 0.0)


func test_a_telegraph_a_phase_change_cuts_off_stops_drawing() -> void:
	# Codex on PR #33: the shift replaces the move, so it never lands — and its
	# ring went on filling on screen as though it would.
	var view := BossView.new(sim)
	brain.force(sim, coach, p, "slam")
	for ev in events_of(sim, "boss_tell"):
		view.on_event(ev)
	eq(view.tells.size(), 1, "the ring is up")
	coach.hp = coach.max_hp * 0.6
	sim.tick(DT)
	for ev in events_of(sim, "boss_phase"):
		view.on_event(ev)
	eq(view.tells.size(), 0, "and gone the moment it turns")
	view.free()


func test_the_breaker_puts_the_lights_back() -> void:
	var before := float(sim.clock.darkness().alpha)
	inst.lights_out(sim)
	gt(float(sim.clock.darkness().alpha), before, "darker")
	var breaker := {}
	for f in sim.world.features:
		if String(f.kind) == "breaker":
			breaker = f
	p.god_mode = true
	p.pos = breaker.stand
	eq(String(Interact.best_target(sim, p).get("kind", "")), "breaker")
	p.intent.interact = true
	sim.tick(DT)
	ok(not inst.dark, "on the key")
	near(sim.clock.t, float(inst.def.clock_t), 1e-9, "back to the inside's own light")
	eq(String(Interact.best_target(sim, p).get("kind", "")), "", "and the switch stops asking")


func test_putting_it_down_clears_the_school() -> void:
	Damage.kill_enemy(sim, coach, p)
	run(sim, 0.1)
	eq(inst.state, "cleared")


# ------------------------------------------------------------- the screen --

func test_what_the_screen_draws_and_plays_is_decided_from_the_events() -> void:
	# On the events the real move produced, and on what the view and the
	# ears chose for them (§8: assert on the decision, not what fed it).
	var view := BossView.new(sim)
	_put(Vector2(0, 200))
	brain.force(sim, coach, p, "slam")
	var tells := events_of(sim, "boss_tell")
	eq(tells.size(), 1)
	eq(view.on_event(tells[0]), "slam")
	eq(view.tells.size(), 1)
	run(sim, float(_move("slam").tell) + 0.05)
	Sfx.build()
	eq(SfxView.new(sim).on_event(events_of(sim, "boss_slam")[0]), "slam")
	view.free()
