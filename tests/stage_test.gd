extends "res://tests/test_case.gd"
## The Stage seam (2026-10-13, `tasks/3d-conversion.md`): what main asks of
## whatever draws the world, and the camera maths the stages share.

var sim: GameSim
var stage: Stage


func before_each() -> void:
	sim = new_sim()
	stage = Stage.new()
	stage.sim = sim
	# The town carries the gym's arena rect; the lead test wants open ground.
	sim.world.arena = Rect2i()


func after_each() -> void:
	stage.free()


func test_the_stage_is_the_config_word_unless_the_command_line_says() -> void:
	# The test runner passes no `--stage=`, so this is the const — and the
	# const is what a rollback flips, so it has to be one of the two words.
	eq(Stage.pick(), Config.STAGE)
	ok(Config.STAGE == "2d" or Config.STAGE == "3d", "Config.STAGE is '%s'" % Config.STAGE)


func test_the_camera_leads_toward_the_cursor_and_no_further_than_lead_max() -> void:
	var p := sim.players[0]
	p.pos = Vector2(1000, 1000)
	p.prev_pos = p.pos
	var C := Config.CAMERA
	var near_cursor := p.pos + Vector2(100, 0)
	var f := stage.frame_for(p, near_cursor, null)
	near(f.focus.x, p.pos.x + 100 * C.lead, 1e-4, "a close cursor leads by its share")
	near(f.focus.y, p.pos.y, 1e-4)
	eq(f.zoom_mul, 1.0, "no arena, no zoom")
	var far_cursor := p.pos + Vector2(0, 5000)
	f = stage.frame_for(p, far_cursor, null)
	near(f.focus.y, p.pos.y + C.lead_max, 1e-4, "a far cursor is clamped to lead_max")


func test_an_arena_pulls_the_camera_out_and_toward_the_boss() -> void:
	var p := sim.players[0]
	p.pos = Vector2(1000, 1000)
	p.prev_pos = p.pos
	var C := Config.CAMERA
	var tile := Config.TILE
	sim.world.arena = Rect2i(Vector2i(20, 20), Vector2i(40, 40))   # tiles 20..60: holds (1000, 1000)
	var f := stage.frame_for(p, p.pos, null)
	eq(f.zoom_mul, float(C.arena_zoom), "inside the arena the camera pulls out")
	near(f.focus.x, p.pos.x, 1e-4, "no boss: framed on you")
	var boss := EnemySim.new("walker", p.pos + Vector2(400, 0))
	f = stage.frame_for(p, p.pos, boss)
	near(f.focus.x, p.pos.x + 400 * C.arena_frame, 1e-4, "a boss pulls the frame its way")
	p.pos = Vector2(tile * 5, tile * 5)
	p.prev_pos = p.pos
	f = stage.frame_for(p, p.pos, boss)
	eq(f.zoom_mul, 1.0, "outside the arena the zoom is back")


func test_the_base_stage_answers_every_call_with_nothing() -> void:
	# A stage that forgets a method inherits these. None of them may crash,
	# and the two that return something return the zero of it.
	stage.build()
	stage.rebuild()
	stage.rebuild_props()
	stage.repaint(0, 0)
	stage.on_event({"t": "hit"})
	stage.tick(0.016)
	stage.frame()
	stage.snap(Vector2(1, 1))
	stage.follow(0.016, sim.players[0], null, 0.0)
	eq(stage.cursor_world(), Vector2.ZERO)
	eq(stage.to_screen(Vector2(5, 5)), Vector2.ZERO)
	eq(stage.view_radius(), 0.0)
	stage.set_local(sim.players[0])
	eq(stage.local, sim.players[0])
