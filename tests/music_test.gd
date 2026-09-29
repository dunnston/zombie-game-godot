extends "res://tests/test_case.gd"
## The score: which track plays when, and that every track the game can ask for
## is a real file that will load and loop the way it should.


func test_the_title_beats_everything() -> void:
	eq(Music.pick(true, true, "coach", true), "main_menu")


func test_death_beats_a_fight_and_a_raid() -> void:
	eq(Music.pick(false, true, "coach", true), "game_over")


func test_a_boss_beats_a_raid() -> void:
	eq(Music.pick(false, false, "coach", true), "boss_1")


func test_a_boss_with_no_row_still_gets_a_boss_track() -> void:
	eq(Music.pick(false, false, "nobody", false), "boss_1")


func test_a_raid_is_the_horde_and_quiet_is_exploration() -> void:
	eq(Music.pick(false, false, "", true), "horde")
	eq(Music.pick(false, false, "", false), "exploration")


func test_the_boss_is_not_music_until_it_wakes_and_not_after_it_dies() -> void:
	var sim := new_sim()
	eq(Music.boss_of(sim), "", "the town has no boss")
	var p := sim.players[0]
	p.god_mode = true
	var f := Instance.door_for(sim, "school")
	p.pos = f.stand
	p.prev_pos = p.pos
	ok(Instance.enter(sim, p, "school"), "the door opens")
	var b := sim.instance.boss
	ok(b != null and b.brain != null, "the school seats a boss with a brain")
	eq(Music.boss_of(sim), "", "asleep is still the walk")
	b.brain.state = "fight"
	eq(Music.boss_of(sim), "coach")
	b.dead = true
	eq(Music.boss_of(sim), "", "dead is over")


func test_every_track_the_game_can_pick_is_a_file_that_loads() -> void:
	var moods := ["main_menu", "exploration", "horde", "game_over", "boss_1", "boss_2", "final_boss"]
	for boss in Config.MUSIC_BOSS.values():
		has(moods, boss)
	for m in moods:
		for n in Config.MUSIC_VARIANTS.get(m, [m]):
			var once: bool = Config.MUSIC_ONCE.has(m)
			var s := Music.stream(n, once)
			ok(s != null, "%s.mp3 is missing or failed to import" % n)
			if s is AudioStreamMP3:
				gt(s.get_length(), 20.0, "%s is a sting, not a track" % n)
				eq(s.loop, not once, "%s loop flag" % n)


func test_a_mood_with_two_takes_alternates_and_never_repeats() -> void:
	Music._last.clear()
	var seen := {}
	var prev := ""
	for i in range(20):
		var f := Music.variant("horde", randf())
		ne(f, prev, "the same take twice running")
		seen[f] = true
		prev = f
	eq(seen.size(), 2, "both takes get played")


func test_a_mood_with_one_take_plays_it() -> void:
	Music._last.clear()
	eq(Music.variant("boss_1", 0.9), "boss_1")
	eq(Music.variant("boss_1", 0.1), "boss_1")
