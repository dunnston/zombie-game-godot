extends "res://tests/test_case.gd"
## The clock and what the dark is worth: the curve, the phases, the four
## multipliers the rest of the simulation has been reading since Phase 2, and
## the fact that a day rolls over into the next one.

var sim: GameSim
var p: PlayerSim


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]


# ------------------------------------------------------------------ the day --

func test_a_run_starts_mid_morning_on_day_one() -> void:
	eq(sim.clock.day, 1)
	near(sim.clock.t, Config.DAY_START, 1e-9)
	eq(sim.clock.phase, "day", "a new survivor gets a working day before dark")
	near(float(sim.clock.darkness().alpha), 0.0, 1e-9, "and full light to use it in")


func test_the_phases_tile_the_whole_day_without_a_gap() -> void:
	var prev := 0.0
	for ph in Config.PHASES:
		near(float(ph.from), prev, 1e-9, "%s starts where the last one ended" % ph.id)
		prev = float(ph.to)
	near(prev, 1.0, 1e-9, "and the last one closes the day")
	# Every instant belongs to exactly one phase.
	for i in range(120):
		var t := i / 120.0
		var hits := 0
		for ph in Config.PHASES:
			if t >= ph.from and t < ph.to:
				hits += 1
		eq(hits, 1, "t=%f belongs to one phase" % t)


func test_the_clock_rolls_over_into_the_next_day() -> void:
	sim.clock.t = 0.999
	sim.clock.day = 3
	# One full day of ticking has to land on day 4, not day 3 again.
	sim.clock.tick(sim, Config.DAY_LENGTH * 0.002)
	eq(sim.clock.day, 4)
	ok(sim.clock.t >= 0.0 and sim.clock.t < 1.0, "and wraps rather than running past one")
	ok(events_of(sim, "notify").any(func(e: Dictionary) -> bool: return e.text.contains("DAY 4")),
		"and says so")


func test_a_phase_is_announced_once_and_not_every_frame() -> void:
	# Park just before dusk and walk over the boundary.
	sim.clock.t = Config.PHASES[2].from - 0.0005
	sim.clock.phase = "day"
	sim.events.clear()
	for i in range(400):
		sim.clock.tick(sim, 1.0 / 60.0)
		if sim.clock.phase != "day":
			break
	eq(sim.clock.phase, "dusk")
	var said := 0
	for e in events_of(sim, "notify"):
		if e.text.contains("light is going"):
			said += 1
	eq(said, 1, "dusk announces itself exactly once")
	# And staying in dusk says nothing more.
	sim.events.clear()
	for i in range(120):
		sim.clock.tick(sim, 1.0 / 60.0)
	eq(events_of(sim, "notify").size(), 0, "and then keeps quiet")


func test_a_day_is_nine_minutes() -> void:
	near(Config.DAY_LENGTH, 540.0, 1e-9)
	var c := DayNight.new()
	c.t = 0.0
	c.tick(null, Config.DAY_LENGTH * 0.5)
	near(c.t, 0.5, 1e-6, "half a day of seconds is half a day of clock")


# ------------------------------------------------------------- the darkness --

func test_darkness_is_a_ramp_and_not_a_staircase() -> void:
	# The whole point of the key curve is that dusk creeps in. Sampled finely,
	# no two neighbouring instants may differ by much.
	# 400 samples is 1.35 s of game clock apart — fine enough to catch a step,
	# coarse enough to keep the file cheap.
	var prev: float = float(DayNight.darkness_at(0.0).alpha)
	for i in range(1, 401):
		var t := i / 400.0
		var a: float = float(DayNight.darkness_at(t).alpha)
		ok(absf(a - prev) < 0.02, "darkness jumped %f at t=%f" % [absf(a - prev), t])
		prev = a


func test_it_is_dark_at_night_and_not_at_noon() -> void:
	near(float(DayNight.darkness_at(0.35).alpha), 0.0, 1e-9, "midday is not dark at all")
	gt(float(DayNight.darkness_at(0.82).alpha), Config.DARK_ENOUGH, "the small hours are")
	var c := DayNight.new()
	c.t = 0.35
	ok(not c.is_dark())
	c.t = 0.82
	ok(c.is_dark())
	c.phase = String(DayNight.phase_at(0.82).id)
	ok(c.is_night())


func test_darkness_never_leaves_the_range_it_promises() -> void:
	for i in range(201):
		var a: float = float(DayNight.darkness_at(i / 200.0).alpha)
		ok(a >= 0.0 and a <= 1.0, "alpha %f at %f" % [a, i / 200.0])


# --------------------------------------------------- what the dark is worth --

func test_noon_changes_nothing() -> void:
	var f := DayNight.factors_at(0.35)
	near(f.density, 1.0, 1e-9)
	near(f.sense, 1.0, 1e-9)
	near(f.speed, 1.0, 1e-9)
	near(f.threat, 1.0, 1e-9)


func test_night_multiplies_exactly_what_the_spec_says() -> void:
	# At full darkness k is 1 and each factor is 1 + its share.
	var f := DayNight.factors_at(0.82)
	var k: float = clampf(float(DayNight.darkness_at(0.82).alpha) / Config.DARKNESS_FULL, 0.0, 1.0)
	near(f.density, 1.0 + k * 0.85, 1e-9)
	near(f.sense, 1.0 + k * 0.55, 1e-9)
	near(f.speed, 1.0 + k * 0.10, 1e-9)
	near(f.threat, 1.0 + k * 0.9, 1e-9)
	gt(f.density, 1.7, "night is worth most of a doubling of the crowd")


func test_the_factors_never_invert() -> void:
	# Nothing about the dark may ever make the world *safer* than noon.
	for i in range(201):
		var f := DayNight.factors_at(i / 200.0)
		ok(f.density >= 1.0 and f.sense >= 1.0 and f.speed >= 1.0 and f.threat >= 1.0,
			"at t=%f" % (i / 200.0))


func test_threat_climbs_faster_after_dark() -> void:
	# The same act, done at noon and at midnight.
	sim.clock.t = 0.35
	var before := sim.threat.value
	sim.threat.add(sim, 10.0, p)
	var by_day := sim.threat.value - before

	sim.threat.value = 0.0
	sim.clock.t = 0.82
	sim.threat.add(sim, 10.0, p)
	var by_night := sim.threat.value

	gt(by_night, by_day * 1.5, "day %f, night %f" % [by_day, by_night])


func test_the_spawner_and_the_senses_read_the_clock() -> void:
	# Not a unit of the formula — a check that the wiring that has existed
	# since Phase 2 is now actually connected to something that moves.
	sim.clock.t = 0.35
	near(sim.night_factors().density, 1.0, 1e-9)
	sim.clock.t = 0.82
	gt(sim.night_factors().density, 1.5)
	gt(sim.night_factors().sense, 1.3)


# ------------------------------------------------------------------ the HUD --

func test_the_clock_reads_as_a_time_of_day() -> void:
	var c := DayNight.new()
	c.t = 0.0
	eq(c.clock_string(), "06:00", "dawn sits at six so the numbers match the sky")
	c.t = 0.25
	eq(c.clock_string(), "12:00")
	c.t = 0.75
	eq(c.clock_string(), "00:00")
	# Never anything but a valid 24h reading.
	for i in range(120):
		c.t = i / 120.0
		var s := c.clock_string()
		eq(s.length(), 5, s)
		var h := int(s.substr(0, 2))
		var m := int(s.substr(3, 2))
		ok(h >= 0 and h < 24 and m >= 0 and m < 60, s)


func test_the_phase_has_a_name_for_the_hud() -> void:
	var c := DayNight.new()
	for t in [0.05, 0.3, 0.65, 0.9]:
		c.t = t
		ok(not c.phase_name().is_empty(), "t=%f" % t)
		eq(c.phase_name(), c.phase_name().to_upper())


# ----------------------------------------------------------------- the save --

func test_the_clock_survives_a_save() -> void:
	sim.clock.t = 0.7
	sim.clock.day = 5
	var d := SaveGame.to_dict(sim)
	near(float(d.day_t), 0.7, 1e-9)
	eq(int(d.day), 5)


func test_loading_into_dusk_does_not_announce_dusk_again() -> void:
	# The phase is set directly on load rather than run through tick(), so a
	# player who saved at dusk is not told the light is going all over again.
	sim.clock.t = 0.65
	sim.clock.day = 2
	var d := SaveGame.to_dict(sim)

	var fresh := new_sim()
	fresh.clock.t = float(d.day_t)
	fresh.clock.day = int(d.day)
	fresh.clock.phase = String(DayNight.phase_at(fresh.clock.t).id)
	fresh.events.clear()
	eq(fresh.clock.phase, "dusk")
	fresh.clock.tick(fresh, 1.0 / 60.0)
	eq(events_of(fresh, "notify").size(), 0, "nothing announced on the first tick after a load")
