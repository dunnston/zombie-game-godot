extends "res://tests/test_case.gd"
## The compound raid harness: a fixed base at roughly first-raid strength,
## and a raid thrown at it. This is what the prototype measured against, and
## the figures below are the ones §9 of PROJECT.md tracks.
##
## `_slow_test.gd`, so `tools\test` skips it and stays under ten seconds.
## Run it with `tools\test --all`, once per branch, beside the smoke run.
##
## What matters is not the duration — the browser build produced 67s and
## 172s for the same raid on the same code — but that no raid reaches the
## 300s backstop, and that what the compound loses is stable.

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
	sim.view_radius = 600.0


func test_the_compound_holds_a_running_horde() -> void:
	var before := build_compound(sim, p)
	gt(before.built, 30, "the compound is %d pieces" % before.built)
	var r := play_raid(sim, p, 1, "shotgun")
	var after := compound_report(sim, before)
	print("compound harness [1 RUNNING HORDE]: %.0fs, %d kills, %d pieces lost, walls at %d%%"
		% [r.seconds, r.kills, after.lost, after.walls_pct])
	ok(r.done, "the raid ended rather than running to the backstop")
	ok(r.seconds < Config.RAID.max_seconds, "in %.0fs" % r.seconds)
	eq(after.lost, 0, "the perimeter held")


func test_a_siege_gets_through_the_compound() -> void:
	var before := build_compound(sim, p)
	var r := play_raid(sim, p, 3, "shotgun")
	var after := compound_report(sim, before)
	print("compound harness [3 SIEGE]: %.0fs, %d kills, %d pieces lost, walls at %d%%"
		% [r.seconds, r.kills, after.lost, after.walls_pct])
	ok(r.done, "the raid ended rather than running to the backstop")
	ok(r.seconds < Config.RAID.max_seconds, "in %.0fs" % r.seconds)
	gt(after.lost, 0, "a siege against a first-raid compound gets inside it")
