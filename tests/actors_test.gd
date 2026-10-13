extends "res://tests/test_case.gd"
## What the 3D stage decides a body is doing (`Actors3D`), read off the
## state and the clip the body resolved it to. The sim is run for real and
## the stage framed after it; the clips never advance on their own here (no
## frames are drawn), so a one-shot is pushed to its end by hand where a test
## needs it over.

const DT := 1.0 / 60.0

var sim: GameSim
var p: PlayerSim
var plot: Vector2
var actors: Actors3D


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	plot = tile_centre(clear_plot(12))
	p.pos = plot
	p.prev_pos = plot
	p.intent.aim = plot + Vector2.RIGHT * 100.0
	sim.give_test_kit(p)
	actors = Actors3D.new(sim)
	# In the tree, so the animation players resolve their tracks.
	tree.root.add_child(actors)
	# One frame, so the bodies exist before the sim makes its first edge.
	actors.frame(DT)


func after_each() -> void:
	actors.get_parent().remove_child(actors)
	actors.free()


## Steps the sim and frames the stage after every step, so the stage sees
## each edge the sim makes.
func _play(seconds: float) -> void:
	for i in int(round(seconds / DT)):
		sim.tick(DT)
		actors.frame(DT)


func _me() -> ActorModel:
	return actors.player_node(p.seat)


## Runs the body's current one-shot out, as drawn frames would.
func _finish(node: ActorModel) -> void:
	node.anim.advance(10.0)


func _hold(id: String) -> void:
	var i := p.hotbar_index(id)
	ok(i >= 0, "the kit has a %s" % id)
	p.select_slot(i)
	p.attack_cd = 0.0


func test_a_walk_is_a_walk_a_sprint_is_a_run_and_standing_is_the_idle() -> void:
	p.intent.mx = 1.0
	_play(0.5)
	eq(_me().state, "walk", "walking")
	eq(_me().clip, "walk")
	p.intent.sprint = true
	_play(0.5)
	eq(_me().state, "run", "sprinting")
	p.intent.mx = 0.0
	p.intent.sprint = false
	_play(1.0)
	eq(_me().state, "idle", "standing")
	eq(_me().clip, "idle")


func test_the_walk_keeps_a_walking_pace_however_fast_the_body_goes() -> void:
	# 5.5 m/s on a 1.55 m/s stroll: paced to the ground the feet would blur.
	p.intent.mx = 1.0
	_play(0.5)
	ok(_me().anim.speed_scale <= Actors3D.WALK_PACE + 1e-6, "walk at %.2fx" % _me().anim.speed_scale)
	gt(_me().anim.speed_scale, 1.0, "but brisker than the clip")


func test_the_gait_follows_the_weapon_in_hand() -> void:
	_hold("rifle")
	_play(0.2)
	eq(_me().clip, "rifle_idle", "a rifle is carried at the ready")
	p.intent.mx = 1.0
	_play(0.3)
	eq(_me().state, "walk")
	eq(_me().clip, "rifle_walk")
	_hold("pistol")
	_play(0.2)
	eq(_me().clip, "pistol_walk", "a handgun has its own walk")
	_hold("pipe")
	_play(0.2)
	eq(_me().clip, "walk", "a pipe is swung, so the body walks bare")


func test_the_bow_is_drawn_from_the_back_and_put_away() -> void:
	_hold("bow")
	_play(0.1)
	eq(_me().state, "equip")
	eq(_me().clip, "bow_equip")
	_finish(_me())
	_play(0.1)
	eq(_me().clip, "bow_idle", "then stands with it")
	_hold("pipe")
	_play(0.1)
	eq(_me().state, "disarm")
	eq(_me().clip, "bow_disarm", "and puts it away for something else")


func test_space_is_a_jump() -> void:
	p.intent.dash = true
	_play(DT)
	gt(p.dash_t, 0.0, "the dash began")
	eq(_me().state, "jump")
	eq(_me().clip, "jump")
	# The hop outlives the burst: it is drawn over JUMP_TIME, not 0.18 s.
	_play(float(Config.DASH.time) + 0.05)
	eq(_me().state, "jump", "still in the air after the burst")


func test_ctrl_is_a_crouch() -> void:
	p.intent.sneak = true
	_play(0.3)
	eq(_me().state, "crouch", "down on one knee while still")
	eq(_me().clip, "crouch")
	p.intent.mx = 1.0
	_play(0.3)
	eq(_me().state, "walk", "and the walk, slowly, on the move")
	ok(_me().anim.speed_scale < 1.0, "at %.2fx" % _me().anim.speed_scale)


func test_a_shot_kicks_and_says_so_on_the_wire() -> void:
	_hold("rifle")
	p.mag["rifle"] = 5
	_play(0.2)
	p.intent.fire_pressed = true
	p.intent.fire = true
	_play(DT)
	ok(not p.shot.is_empty(), "a round left")
	eq(_me().state, "shoot")
	eq(_me().clip, "shoot")
	ok(int(NetProtocol.pack_player(p).n[NetProtocol.PL_FLAGS]) & NetProtocol.PF_SHOT, "the flag is up")
	p.intent.fire = false
	_play(float(p.weapon().cd) + 0.1)
	ok(p.shot.is_empty(), "and the kick is over with the cycle")
	ok(not (int(NetProtocol.pack_player(p).n[NetProtocol.PL_FLAGS]) & NetProtocol.PF_SHOT))


func test_the_bow_releases_and_its_reload_is_the_draw() -> void:
	_hold("bow")
	p.mag["bow"] = 1
	_play(0.1)
	_finish(_me())
	p.intent.fire_pressed = true
	p.intent.fire = true
	_play(DT)
	eq(_me().state, "shoot")
	eq(_me().clip, "bow_shoot", "the release")
	_finish(_me())
	p.intent.fire = false
	p.shot = {}
	Combat.start_reload(sim, p, p.weapon())
	ok(not p.reloading.is_empty(), "nocking the next arrow")
	_play(DT)
	eq(_me().state, "reload")
	eq(_me().clip, "bow_reload", "is the draw")


func test_a_gun_reload_has_no_clip_and_does_not_freeze_the_body() -> void:
	_hold("rifle")
	p.intent.mx = 1.0
	_play(0.3)
	p.mag["rifle"] = 0
	Combat.start_reload(sim, p, p.weapon())
	ok(not p.reloading.is_empty())
	_play(0.2)
	eq(_me().state, "walk", "still walking through it")


func test_the_dead_fall_and_leave_a_body_where_they_fell() -> void:
	var where := p.pos
	Damage.kill_player(sim, p)
	_play(DT)
	eq(_me().state, "die")
	eq(_me().clip, "die")
	_play(float(Config.PLAYER.respawn_time) + 0.5)
	ok(not p.dead, "up again")
	ne(_me().state, "die", "on their feet")
	ok(actors._corpses.has("p0"), "a body stayed behind")
	var body: ActorModel = actors._corpses["p0"].node
	eq(body.state, "die")
	ok(Units.to2(body.position).distance_to(where) < 48.0, "where they fell")


func test_a_zombie_takes_turns_with_its_swings() -> void:
	var w := sim.enemies.spawn("walker", plot + Vector2(30, 0), true)
	w.alert_t = 999.0
	p.god_mode = true
	var clips := []
	for i in 300:
		sim.tick(DT)
		actors.frame(DT)
		var node := actors.enemy_node(w.id)
		if node != null and node.state == "attack" and (clips.is_empty() or clips.back() != node.clip):
			clips.append(node.clip)
		if clips.size() >= 3:
			break
	gt(clips.size(), 2, "three swings in five seconds: %s" % [clips])
	ne(clips[0], clips[1], "the second is not the first")
	eq(clips[0], clips[2], "and the third is the first again")
	ok("attack" in clips and "bite" in clips, "the swipe and the neck bite: %s" % [clips])


func test_a_zombie_bends_down_to_eat_you() -> void:
	var w := sim.enemies.spawn("walker", plot + Vector2(30, 0), true)
	_play(DT)
	Damage.kill_player(sim, p)
	_play(DT)
	eq(actors.enemy_node(w.id).state, "eat")
	eq(actors.enemy_node(w.id).clip, "eat")
	# Hit mid-meal: the sim ends it at once, and so does the body, however
	# much of the clip was left.
	Damage.damage_enemy(sim, w, 1.0, plot)
	eq(w.feed_t, 0.0)
	_play(DT)
	ne(actors.enemy_node(w.id).state, "eat", "looked up when hit")


func test_half_the_horde_dies_the_other_way() -> void:
	var a := sim.enemies.spawn("walker", plot + Vector2(300, 0))
	var b := sim.enemies.spawn("walker", plot + Vector2(300, 60))
	eq(b.id, a.id + 1)
	_play(DT)
	Damage.kill_enemy(sim, a)
	Damage.kill_enemy(sim, b)
	_play(DT)
	ok(actors._corpses.has(a.id) and actors._corpses.has(b.id), "both bodies stayed")
	var ca: ActorModel = actors._corpses[a.id].node
	var cb: ActorModel = actors._corpses[b.id].node
	eq(ca.state, "die")
	eq(cb.state, "die")
	ne(ca.clip, cb.clip, "%s and %s" % [ca.clip, cb.clip])


func test_a_boss_seen_only_mid_fight_never_lies_back_down() -> void:
	# A guest outside the interest radius when the wake was relayed: it
	# meets the Coach at full health, standing still, and sees only tells.
	var coach := sim.enemies.spawn("coach", plot + Vector2(400, 0))
	_play(DT)
	eq(actors.enemy_node(coach.id).state, "asleep", "untouched and unseen: on the floor")
	eq(actors.on_event({"t": "boss_tell", "id": coach.id, "move": "slam", "dur": 0.3}), "slam")
	_play(DT)
	eq(actors.enemy_node(coach.id).state, "slam")
	_finish(actors.enemy_node(coach.id))
	_play(0.5)
	ne(actors.enemy_node(coach.id).state, "asleep", "up between its moves")
	# The same for a stun, with no wake before it either.
	actors._awake.clear()
	eq(actors.on_event({"t": "boss_stunned", "id": coach.id, "dur": 0.2}), "stun")
	_play(0.4)
	ne(actors.enemy_node(coach.id).state, "asleep")
