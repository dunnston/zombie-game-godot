extends "res://tests/test_case.gd"
## What fire will and will not take hold of.
##
## The rest of fire — spread, burning away, standing in it, and the invariant
## that it can never reach a player structure — is in `fire_slow_test.gd`.
## Those tests plant scenery and burn it down, which needs a world of their
## own to avoid scribbling on the shared one, and a second world generation is
## more than the ten-second loop should carry. `tools\test.cmd --all` runs them.


func test_only_the_right_scenery_catches() -> void:
	for kind in Config.FLAMMABLE:
		ok(Fire.is_flammable({"kind": kind}), "%s burns" % kind)
	for kind in ["rock", "boulder", "silo", "wreck"]:
		ok(not Fire.is_flammable({"kind": kind}), "%s does not" % kind)
	ok(not Fire.is_flammable({}), "and nothing at all does not")


func test_a_structure_can_never_read_as_flammable() -> void:
	# A structure definition has no `kind` at all, so the one gate every
	# ignition goes through refuses it by construction. The dynamic version of
	# this — a compound ringed with fire, taking no damage — is in the slow
	# tier; this is the cheap half that runs on every commit.
	for type in Config.STRUCTURES:
		var def: Dictionary = Config.STRUCTURES[type]
		ok(not Fire.is_flammable(def), "%s is not scenery" % type)


func test_the_burn_timer_is_the_one_from_the_spec() -> void:
	var f := Fire.new()
	var e := EnemySim.new("walker", Vector2.ZERO)
	eq(e.burn_t, 0.0, "nothing starts alight")
	ok(f.ignite(e))
	near(e.burn_t, Config.FIRE.burn_time, 1e-9)
	near(e.burn_spread_t, Config.FIRE.spread_every, 1e-9)

	# Re-lighting refreshes the timer without restarting the spread clock —
	# otherwise a crowd of burning walkers, relighting each other, would never
	# get a spread roll away from the group.
	e.burn_t = 1.0
	e.burn_spread_t = 0.2
	ok(f.ignite(e))
	near(e.burn_t, Config.FIRE.burn_time, 1e-9, "refreshed")
	near(e.burn_spread_t, 0.2, 1e-9, "and the spread clock kept running")


func test_the_dead_do_not_catch() -> void:
	var f := Fire.new()
	var e := EnemySim.new("walker", Vector2.ZERO)
	e.dead = true
	ok(not f.ignite(e))
	eq(e.burn_t, 0.0)
