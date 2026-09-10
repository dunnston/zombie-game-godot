extends "res://tests/test_case.gd"
## The dash (`Config.DASH`, 2026-09-10). The first piece of the instanced
## dungeons: every boss telegraph will be sized against it, so what it does
## has to be exact — how far, how long, what it spends and what it refuses.
## `tasks/instanced-dungeons.md` §8.3 has the argument for having one at all.

var sim: GameSim
var p: PlayerSim
var D: Dictionary
const DT := 1.0 / 60.0


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.pos = tile_centre(clear_plot(8))
	p.prev_pos = p.pos
	p.vel = Vector2.ZERO
	p.intent.aim = p.pos + Vector2(300, 0)
	D = Config.DASH
	sim.events.clear()


## One step with the key pressed on it, holding (mx, my). The edge is cleared
## by the tick, exactly as a keypress is.
func _press(mx := 0.0, my := 0.0) -> void:
	p.intent.mx = mx
	p.intent.my = my
	p.intent.dash = true
	sim.tick(DT)


## Steps until the burst is spent, and says how many steps it took including
## the one it started on.
func _finish() -> int:
	var steps := 1
	while p.dash_t > 0.0 and steps < 120:
		sim.tick(DT)
		steps += 1
	return steps


# ------------------------------------------------------------- the burst --

func test_a_dash_covers_its_distance_in_its_time_and_no_more() -> void:
	var start := p.pos
	_press(1.0, 0.0)
	ok(p.dash_t > 0.0, "the burst begins on the step the key is pressed")
	p.intent.mx = 0.0                     # letting go does not cut it short
	var steps := _finish()
	near(p.pos.x - start.x, float(D.dist), 0.5, "the whole burst and nothing else")
	near(p.pos.y, start.y, 0.01, "straight")
	near(steps * DT, float(D.time), DT + 1e-6, "in the time it says")
	# A burst and not a sprint: well over twice as fast as running.
	gt(float(D.dist) / float(D.time), Config.PLAYER.speed * Config.PLAYER.sprint_mul * 2.0)


func test_standing_still_it_goes_where_you_are_aiming() -> void:
	# A dodge from a standstill has to go somewhere you chose, and the only
	# direction you have given the game is the mouse.
	var start := p.pos
	p.intent.aim = p.pos + Vector2(0, -250)
	_press()
	_finish()
	near(start.y - p.pos.y, float(D.dist), 0.5, "up, toward the cursor")
	near(p.pos.x, start.x, 0.01)


func test_a_diagonal_dash_is_the_same_length_as_a_straight_one() -> void:
	var start := p.pos
	_press(0.7071, 0.7071)
	_finish()
	near(p.pos.distance_to(start), float(D.dist), 0.5)


func test_a_wall_stops_a_dash_the_way_it_stops_a_walk() -> void:
	# Two tiles east, three high: a dash is movement, not a teleport, and
	# `move_circle` is the same door both collision maps are asked through.
	p.bag = Slots.new(60)
	p.carry_cap = 100000.0
	p.bag.add("wood", 200)
	var t := Vector2i(floori(p.pos.x / Config.TILE), floori(p.pos.y / Config.TILE))
	for dy in range(-1, 2):
		clear_ground(sim, t.x + 2, t.y + dy)
		var s := sim.structs.place(sim, "woodWall", t.x + 2, t.y + dy, p)
		ok(not s.is_empty(), "a wall at (%d, %d)" % [t.x + 2, t.y + dy])
	var start := p.pos
	var face := float((t.x + 2) * Config.TILE) - p.r
	_press(1.0, 0.0)
	_finish()
	ok(p.pos.x <= face + 0.5, "stopped at the wall: x=%.1f, face=%.1f" % [p.pos.x, face])
	gt(p.pos.x - start.x, 20.0, "and got as far as it")


# ------------------------------------------------------------ the i-frames --

func test_nothing_lands_during_the_burst() -> void:
	_press(1.0, 0.0)
	var hp := p.hp
	eq(Damage.damage_player(sim, p, 40.0, p.pos + Vector2(20, 0), "bite", true), 0.0, "a bite mid-dash lands nothing")
	eq(p.hp, hp)
	_finish()
	eq(Damage.damage_player(sim, p, 40.0, p.pos + Vector2(20, 0), "bite"), 0.0, "nor in the grace after it")


func test_the_i_frames_end_when_the_grace_does() -> void:
	_press(1.0, 0.0)
	run(sim, float(D.time) + float(D.grace) + 0.05)
	near(p.invuln, 0.0, 1e-6, "vulnerable again")
	gt(Damage.damage_player(sim, p, 40.0, p.pos, "bite"), 0.0, "and the next one lands")


# ------------------------------------------------------ what it costs you --

func test_a_dash_is_paid_for_in_stamina_up_front() -> void:
	var before := p.stam
	_press(1.0, 0.0)
	near(before - p.stam, float(D.stam), 0.01)
	_finish()
	near(before - p.stam, float(D.stam), 0.01, "and nothing comes back during the burst")


func test_a_press_inside_the_cooldown_is_not_heard_and_says_nothing() -> void:
	_press(1.0, 0.0)
	_finish()
	sim.events.clear()
	_press(1.0, 0.0)
	eq(p.dash_t, 0.0, "no second burst")
	eq(events_of(sim, "notify").size(), 0, "mashing the key does not fill the screen")
	eq(events_of(sim, "dash").size(), 0)
	run(sim, float(D.cd))
	_press(1.0, 0.0)
	gt(p.dash_t, 0.0, "after the cooldown it is heard again")


func _refused(why: String) -> void:
	var at := p.pos
	sim.events.clear()
	_press()
	eq(p.dash_t, 0.0, why)
	var said := false
	for ev in events_of(sim, "notify"):
		if String(ev.text) == why:
			said = true
	ok(said, "the refusal says why: " + why)
	ok(p.pos.distance_to(at) < 1.0, "and nobody went anywhere")
	eq(events_of(sim, "dash").size(), 0)


func test_winded_you_cannot_dash_and_are_told_so() -> void:
	p.winded = true
	p.stam = p.max_stam * 0.4
	_refused("Too winded to dash")


func test_short_of_stamina_it_is_refused_rather_than_half_done() -> void:
	p.stam = float(D.stam) - 1.0
	_refused("Not enough stamina to dash")


func test_not_in_the_middle_of_healing() -> void:
	p.bag.add("bandage", 2)
	p.using = {"id": "bandage", "t": 0.0, "dur": 5.0}
	_refused("Not in the middle of that")


func test_not_while_the_lurch_has_your_legs() -> void:
	# Straight through `move`, which is the function a guest runs too: the
	# Lurch clock itself belongs to `Mutation` and has its own tests.
	p.lurch_t = 1.0
	p.intent.dash = true
	p.move(sim.world, DT, false, sim.structs)
	eq(p.dash_t, 0.0)
	eq(p.dash_refused, "Your legs are not yours")


func test_nobody_dashes_off_the_floor() -> void:
	Damage.down_player(sim, p)
	ok(p.downed)
	var at := p.pos
	_press(1.0, 0.0)
	eq(p.dash_t, 0.0)
	ok(p.pos.distance_to(at) < 0.01)


# --------------------------------------------------------- guest and ears --

func test_a_guest_predicts_its_own_dash_with_the_same_code() -> void:
	# `NetGuest._predict_self` runs `move` and nothing else of the tick. A dash
	# living anywhere but `move` would snap a guest back 130px on every press.
	var g := PlayerSim.new()
	g.pos = p.pos
	g.intent.aim = g.pos + Vector2(0, 300)
	g.intent.dash = true
	var start := g.pos
	g.move(sim.world, DT, false, sim.structs)
	g.intent.dash = false
	var steps := 1
	while g.dash_t > 0.0 and steps < 120:
		g.move(sim.world, DT, false, sim.structs)
		steps += 1
	near(g.pos.y - start.y, float(D.dist), 0.5, "the same burst, off the same function")


func test_the_everyone_else_screen_is_told_somebody_is_dashing() -> void:
	_press(1.0, 0.0)
	var f := int(NetProtocol.pack_player(p).n[NetProtocol.PL_FLAGS])
	ok(f & NetProtocol.PF_DASH, "mid-dash on the wire")
	_finish()
	f = int(NetProtocol.pack_player(p).n[NetProtocol.PL_FLAGS])
	ok(not (f & NetProtocol.PF_DASH), "and not after")


func test_a_real_dash_is_heard_as_a_dash() -> void:
	# On the event the press actually produced, and on the cue the ears chose
	# for it (§8: assert on the decision, not on what fed it).
	Sfx.build()
	_press(1.0, 0.0)
	var evs := events_of(sim, "dash")
	eq(evs.size(), 1, "one burst, one event")
	if evs.size() == 1:
		eq(SfxView.new(sim).on_event(evs[0]), "dash")
