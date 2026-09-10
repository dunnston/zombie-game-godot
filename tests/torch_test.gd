extends "res://tests/test_case.gd"
## The owner's second playtest, in one sentence: *"I waited for it to get
## dark. I had my torch equipped. It never got so dark that I couldn't see.
## The torch did not appear to do anything."*
##
## Two separate faults behind that, and this file holds both fixed.
##
## 1. **The dark had a floor.** `LightView` darkened the canvas with a grey
##    `CanvasModulate` and put the night's colour back as an additive
##    `DirectionalLight2D`, on the theory that an overlay is a multiply plus
##    an add. Godot's canvas shader multiplies every light pass by the
##    surface's own colour, so that "add" was a second multiply and the map
##    still came through at about a seventh of daylight. `canvas_tint_at` is
##    now the one number the world is multiplied by, and these tests are
##    about how small it gets.
##
## 2. **The torch needed a keystroke nobody pressed.** Equipping a light left
##    it unlit until T. Now the dark strikes it and the dawn puts it out, and
##    T is for going dark on purpose.

var sim: GameSim
var p: PlayerSim

## Deep night, where the curve peaks.
const NIGHT := 0.82
## Midday, where it is nothing at all.
const NOON := 0.35


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.pos = tile_centre(clear_plot(6))


func _wear_torch() -> void:
	p.bag.add("torch", 1)
	Equipment.equip_from_bag(sim, p, _index_of("torch"))
	eq(p.equip.offhand, "torch")


func _index_of(id: String) -> int:
	for i in range(p.bag.size()):
		if p.bag.id_at(i) == id:
			return i
	return -1


## The brightest channel of what the canvas is multiplied by — the generous
## reading of "can you see anything", because one bright channel is enough.
static func _brightest(at: float) -> float:
	var c := DayNight.canvas_tint_at(at)
	return maxf(c.r, maxf(c.g, c.b))


# ------------------------------------------------------ 1. the dark is dark --

func test_full_night_is_black_and_not_merely_blue() -> void:
	# 6% of daylight, on the brightest channel, against ground art that is
	# itself a quarter to a half of white: the map lands under 3% and there is
	# nothing to see past your own light. The old curve reached 0.146 here.
	ok(_brightest(NIGHT) <= 0.07, "the small hours: %.3f of daylight" % _brightest(NIGHT))
	# And it stays there until dawn starts giving it back.
	for t in [0.82, 0.84, 0.88, 0.92, 0.96]:
		ok(_brightest(float(t)) <= 0.11, "t=%.2f is %.3f of daylight" % [t, _brightest(float(t))])
	# Night falls between 0.74 and 0.82 rather than snapping, so the early
	# hours are dim and not yet blind — that is 54 seconds of walking home.
	ok(_brightest(0.80) <= 0.20, "early night: %.3f" % _brightest(0.80))
	ok(_brightest(0.74) <= 0.40, "nightfall: %.3f" % _brightest(0.74))


func test_noon_is_not_darkened_at_all() -> void:
	# Pillar 4, readability: the multiply has to be exactly 1 in the daytime,
	# or every colour in the game is quietly wrong all day.
	eq(DayNight.canvas_tint_at(NOON), Color.WHITE)
	eq(DayNight.canvas_tint_at(Config.DAY_START), Color.WHITE)


func test_the_dark_arrives_as_a_ramp_and_so_does_its_colour() -> void:
	# The alpha ramp has its own test in daynight_test; this is the colour,
	# which used to step to whichever key was nearer. That step was invisible
	# while the tint only tinted. Now it is a step in what you can see.
	# 800 samples: the steepest stretch is dawn breaking between 0.96 and
	# 1.00, which moves 0.31 of the blue channel in 0.04 of a day.
	var prev := DayNight.canvas_tint_at(0.0)
	for i in range(1, 801):
		var c := DayNight.canvas_tint_at(i / 800.0)
		var jump: float = maxf(absf(c.r - prev.r), maxf(absf(c.g - prev.g), absf(c.b - prev.b)))
		ok(jump < 0.02, "the light jumped %.3f at t=%.4f" % [jump, i / 800.0])
		prev = c


func test_it_gets_darker_through_the_evening_and_lighter_after() -> void:
	# Dusk into night only ever takes light away, and dawn only ever gives it
	# back. A key entered in the wrong order would read as a flicker.
	var last := _brightest(0.56)
	for i in range(1, 27):
		var t: float = 0.56 + i * 0.01
		ok(_brightest(t) <= last + 1e-6, "brighter at t=%.2f than at %.2f" % [t, t - 0.01])
		last = _brightest(t)
	last = _brightest(0.90)
	for i in range(1, 27):
		var t: float = 0.90 + i * 0.01
		ok(_brightest(fmod(t, 1.0)) >= last - 1e-6, "darker at t=%.2f" % t)
		last = _brightest(fmod(t, 1.0))


func test_a_torch_is_worth_more_than_the_night_it_stands_in() -> void:
	# The point of the whole round: what the torch adds has to dwarf what is
	# left of the sky, or a lit torch is invisible against it — which is what
	# the owner's *first* playtest photographs showed.
	var l: Dictionary = Config.GEAR.torch.light
	gt(float(l.strength), _brightest(NIGHT) * 10.0, "the torch against the sky")
	gt(float(l.radius), 200.0, "and a puddle you can walk in")


# --------------------------------------- 2. the dark strikes what you wear --

func test_wearing_a_torch_at_noon_does_not_light_it_or_spend_it() -> void:
	sim.clock.t = NOON
	_wear_torch()
	near(p.light_fuel, 210.0, 0.01, "a torch comes ready to burn")
	run(sim, 2.0)
	ok(not p.lit, "nothing to see by in daylight")
	near(p.light_fuel, 210.0, 0.01, "and not a second of it burned")


func test_the_dark_lights_a_torch_you_are_already_wearing() -> void:
	# The report, exactly: worn, then waited on. No key is pressed anywhere
	# in this test.
	sim.clock.t = NOON
	_wear_torch()
	run(sim, 1.0)
	ok(not p.lit)
	sim.clock.t = NIGHT
	run(sim, 0.1)
	ok(p.lit, "night struck the torch by itself")
	ok(p.light_on)
	ok(p.light_fuel < 210.0, "and it is burning down")


func test_the_dawn_puts_it_out_rather_than_burning_through_the_morning() -> void:
	sim.clock.t = NIGHT
	_wear_torch()
	run(sim, 1.0)
	ok(p.lit)
	var left := p.light_fuel
	sim.clock.t = NOON
	run(sim, 2.0)
	ok(not p.lit, "out with the light")
	near(p.light_fuel, left, 0.01, "and fuel is what the daylight saves you")


func test_one_torch_is_about_one_night() -> void:
	# 210 seconds of burn against the span the clock spends over DARK_ENOUGH.
	# This is why `burn` is 210 and not a round number, and the auto-douse is
	# what makes the comparison mean anything: fuel is only spent in the dark.
	var dark := 0.0
	for i in range(2000):
		if float(DayNight.darkness_at(i / 2000.0).alpha) > Config.DARK_ENOUGH:
			dark += 1.0 / 2000.0
	var seconds := dark * Config.DAY_LENGTH
	ok(seconds >= 190.0 and seconds <= 240.0, "the dark is %.0f seconds long" % seconds)
	var burn := float(Config.GEAR.torch.burn)
	ok(burn >= seconds * 0.85 and burn <= seconds * 1.15,
		"a torch is %.0fs against a %.0fs night" % [burn, seconds])


func test_t_is_going_dark_on_purpose_and_the_night_does_not_undo_it() -> void:
	sim.clock.t = NIGHT
	_wear_torch()
	run(sim, 0.1)
	ok(p.lit)
	ok(Equipment.toggle_light(sim, p))
	ok(not p.lit, "out")
	run(sim, 3.0)
	ok(not p.lit, "and it stays out — the dark does not relight it")
	var kept := p.light_fuel
	run(sim, 1.0)
	near(p.light_fuel, kept, 0.01, "a doused torch burns nothing")
	ok(Equipment.toggle_light(sim, p))
	ok(p.lit, "T again is how you come back")


func test_daybreak_forgives_a_dousing_so_tomorrow_night_lights_itself() -> void:
	sim.clock.t = NIGHT
	_wear_torch()
	run(sim, 0.1)
	Equipment.toggle_light(sim, p)
	ok(p.light_doused)
	sim.clock.t = NOON
	run(sim, 0.1)
	ok(not p.light_doused, "the morning forgets it")
	sim.clock.t = NIGHT
	run(sim, 0.1)
	ok(p.lit, "and the next night lights it again")


func test_a_torch_taken_off_and_put_back_on_strikes_itself_again() -> void:
	sim.clock.t = NIGHT
	_wear_torch()
	run(sim, 0.1)
	ok(p.lit)
	ok(Equipment.unequip(sim, p, "offhand"))
	run(sim, 0.1)
	ok(not p.lit, "nothing in the off-hand, nothing lit")
	Equipment.equip_from_bag(sim, p, _index_of("torch"))
	run(sim, 0.1)
	ok(p.lit, "and back on is back alight")
	ok(p.light_fuel < 210.0, "with what was left of it, not a fresh one")


# ------------------------------- the light is a clock, not an action (PR #29) --
#
# `Equipment.update_light` sat at the bottom of `PlayerSim.tick`, below the
# early returns for downed and driving. Codex caught it on review: the states
# where the clock keeps running are exactly the states the light stopped
# hearing about it. A torch carried into a car before dark never struck, and a
# lit one hung there for free — `LightView` draws a downed player's light and
# a driver's follows the car — burning no fuel and never doused by the dawn.

func test_the_dark_lights_a_torch_you_carried_into_a_car() -> void:
	sim.clock.t = NOON
	_wear_torch()
	var v := _drive()
	run(sim, 1.0)
	ok(not p.lit, "daylight, and driving")
	sim.clock.t = NIGHT
	run(sim, 0.2)
	ok(p.lit, "the dark strikes it through the windscreen too")
	ok(p.light_fuel < 210.0, "and driving does not burn it for free")
	sim.cars.exit(sim, p)
	ok(v.id > 0)


func test_a_lit_torch_burns_down_and_goes_out_at_dawn_while_you_are_down() -> void:
	sim.clock.t = NIGHT
	_wear_torch()
	run(sim, 0.1)
	ok(p.lit)
	Damage.down_player(sim, p)
	ok(p.downed and not p.dead, "on the ground, not gone")
	var left := p.light_fuel
	run(sim, 1.0)
	ok(p.lit, "your torch is still lighting the scene of it")
	ok(p.light_fuel < left - 0.5, "and still burning down")
	sim.clock.t = NOON
	run(sim, 0.2)
	ok(not p.lit, "and the dawn puts it out where you lie")


func test_a_torch_burns_away_to_nothing_while_you_are_down() -> void:
	# The end of the same rule: the clock can take the light off you at the
	# worst possible moment, which is the whole point of carrying a spare.
	sim.clock.t = NIGHT
	_wear_torch()
	run(sim, 0.1)
	Damage.down_player(sim, p)
	p.light_fuel = 0.5
	run(sim, 1.0)
	ok(not p.lit)
	eq(p.equip.offhand, "", "it burned away under you")


## In whatever car the generator put in this world, where it stands: entering
## releases its tiles and leaving re-claims them at the same place, so the
## shared `blocked` bitmap comes out of this exactly as it went in.
func _drive() -> Dictionary:
	ok(not sim.cars.list.is_empty(), "the world has a car in it")
	var v: Dictionary = sim.cars.list[0]
	v.locked = false
	v.hotwired = false
	v.destroyed = false
	v.fuel = Config.CAR.fuel_max
	v.hp = v.max_hp
	p.pos = v.pos
	ok(sim.cars.enter(sim, p, v), "behind the wheel")
	return v


func test_pressing_t_in_daylight_is_refused_rather_than_wasted() -> void:
	# On a flashlight that keystroke used to cost a battery for one frame of
	# light nobody needed.
	sim.clock.t = NOON
	p.bag.add("flashlight", 1)
	p.bag.add("battery", 1)
	Equipment.equip_from_bag(sim, p, _index_of("flashlight"))
	ok(not Equipment.toggle_light(sim, p), "refused")
	eq(p.bag.count("battery"), 1, "and the battery is still in the pack")


# ------------------------------------------------------ the flashlight, too --

func test_a_flat_flashlight_waits_for_a_battery_and_not_for_the_dark() -> void:
	sim.clock.t = NIGHT
	p.bag.add("flashlight", 1)
	Equipment.equip_from_bag(sim, p, _index_of("flashlight"))
	near(p.light_fuel, 0.0, 0.01, "a found flashlight arrives flat")
	run(sim, 0.5)
	ok(not p.lit, "the dark cannot strike an empty battery")
	p.bag.add("battery", 1)
	ok(Equipment.toggle_light(sim, p), "T spends one")
	eq(p.bag.count("battery"), 0)
	run(sim, 0.5)
	ok(p.lit)


func test_the_flashlight_is_a_cone_and_that_is_what_the_batteries_buy() -> void:
	var f: Dictionary = Config.GEAR.flashlight.light
	var t: Dictionary = Config.GEAR.torch.light
	ok(f.has("cone_len"), "a cone as well as a puddle")
	gt(float(f.cone_len), float(t.radius), "and it reaches further than a torch")
	ok(f.radius < t.radius, "while lighting less of what is beside you")
	gt(float(f.cone_spread), 0.0)


func after_each() -> void:
	# A test that failed part way through must not leave a car's tiles
	# released in the world every other test shares.
	if p != null and p.driving_id > 0:
		sim.cars.exit(sim, p)
