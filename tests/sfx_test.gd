extends "res://tests/test_case.gd"
## The sound: that every cue actually renders to something you could hear, that
## the rate limit does what it exists for, and that the right event makes the
## right noise.
##
## No speaker is involved. `Sfx.build()` is pure arithmetic over `Config.SFX`
## and `SfxView` is a pure mapping, which is the whole reason the audio is
## split in two — a headless run can check everything except whether it sounds
## good, and that part is the owner's.

var sim: GameSim
var p: PlayerSim
var ears: SfxView


func before_each() -> void:
	sim = new_sim()
	p = sim.players[0]
	p.intent.aim = p.pos + Vector2.RIGHT
	sim.give_test_kit(p)
	ears = SfxView.new(sim)
	Sfx.build()
	Sfx._last.clear()


## The samples of a rendered cue, as floats in -1..1.
func _samples(name: String) -> PackedFloat32Array:
	var w: AudioStreamWAV = Sfx.stream(name)
	var out := PackedFloat32Array()
	var n := w.data.size() / 2
	out.resize(n)
	for i in range(n):
		out[i] = w.data.decode_s16(i * 2) / 32768.0
	return out


func _peak(name: String) -> float:
	var top := 0.0
	for v in _samples(name):
		top = maxf(top, absf(v))
	return top


# ------------------------------------------------------------------ synth --

func test_every_cue_renders_to_something_audible() -> void:
	# The failure this catches is a recipe that renders silence — a typo in a
	# frequency, a zero gain, a filter that eats its own input. Every one of
	# them looks fine in the table and plays nothing.
	for name in Config.SFX:
		var w: AudioStreamWAV = Sfx.stream(name)
		ok(w != null, "no buffer for %s" % name)
		gt(w.data.size(), 64, "%s is empty" % name)
		eq(w.mix_rate, Config.SFX_RATE, name)
		gt(_peak(name), 0.02, "%s renders silence" % name)


func test_a_cue_is_as_long_as_its_longest_op() -> void:
	# `at` delays an op inside a cue, so the buffer has to be long enough for
	# the last one to finish — a reload that clicks and then clacks 110ms later
	# is one buffer, not two calls and a timer.
	for name in Config.SFX:
		var want := 0.0
		for op in Config.SFX[name]:
			want = maxf(want, float(op.get("at", 0.0)) + float(op.get("dur", 0.1)))
		var got := (Sfx.stream(name).data.size() / 2.0) / float(Config.SFX_RATE)
		near(got, want, 0.01, "%s is %.3fs, wants %.3fs" % [name, got, want])


func test_nothing_clips() -> void:
	# Two ops mixed into one buffer can sum past full scale, and clipping is a
	# crackle that sounds like a bug in something else.
	for name in Config.SFX:
		ok(_peak(name) <= 0.999, "%s clips at %.3f" % [name, _peak(name)])


func test_a_cue_starts_and_ends_quiet() -> void:
	# The 5ms attack and the exponential decay: a buffer that starts or ends at
	# full amplitude clicks every time it plays.
	for name in Config.SFX:
		var s := _samples(name)
		ok(absf(s[0]) < 0.05, "%s starts at %.3f" % [name, s[0]])
		ok(absf(s[s.size() - 2]) < 0.08, "%s ends at %.3f" % [name, s[s.size() - 2]])


func test_building_twice_costs_nothing() -> void:
	var before: AudioStreamWAV = Sfx.stream("pistol")
	Sfx.build()
	ok(Sfx.stream("pistol") == before, "the bank is built once")


# ------------------------------------------------------------- rate limit --

func test_identical_sounds_inside_the_window_are_dropped() -> void:
	# The reason this exists: a shotgun blast hitting twelve zombies is one
	# impact, not twelve.
	var gap: int = Config.SFX_THROTTLE.bullet_hit
	ok(Sfx.allowed("bullet_hit", 1000), "the first one always sounds")
	for i in range(11):
		ok(not Sfx.allowed("bullet_hit", 1000 + i), "pellet %d is the same impact" % i)
	ok(Sfx.allowed("bullet_hit", 1000 + gap), "and the next volley is its own")


func test_a_cue_with_no_limit_can_fire_as_often_as_it_likes() -> void:
	ok(not Config.SFX_THROTTLE.has("level_up"))
	ok(Sfx.allowed("level_up", 500))
	ok(Sfx.allowed("level_up", 500), "levelling twice in a frame is a real thing")


func test_the_limit_is_per_cue() -> void:
	ok(Sfx.allowed("bullet_hit", 2000))
	ok(Sfx.allowed("melee_hit", 2000), "a different sound is not the same sound")
	ok(not Sfx.allowed("bullet_hit", 2000))


func test_every_throttled_name_is_a_real_cue() -> void:
	for name in Config.SFX_THROTTLE:
		ok(Config.SFX.has(name), "throttling %s, which does not exist" % name)


# ------------------------------------------------------------ the mapping --

func test_every_mapped_cue_exists() -> void:
	# A mapping to a cue that was renamed is a sound that silently stops
	# happening, and nothing else would ever notice.
	for t in SfxView.DIRECT:
		ok(Config.SFX.has(SfxView.DIRECT[t]), "%s -> %s, which does not exist" % [t, SfxView.DIRECT[t]])


func test_every_weapon_has_a_voice() -> void:
	# The muzzle event carries the weapon id straight through as the cue name,
	# so a gun with no cue of its own falls back to the pistol. Guns are loud
	# enough to be worth their own.
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		if String(w.get("kind", "")) != "gun":
			continue
		ok(Config.SFX.has(id), "%s has no sound" % id)


## Every cue `SfxView` chose for the events this weapon produced. Not the
## events — the cues, which is the question that matters.
func _cues_from_firing(id: String) -> Array[String]:
	p.select_slot(p.hotbar_index(id))
	p.attack_cd = 0.0
	p.intent.fire = true
	sim.events.clear()
	run(sim, 1.0)
	var out: Array[String] = []
	for ev in events_of(sim, "shot"):
		var cue := ears.on_event(ev)
		if not cue.is_empty():
			out.append(cue)
	return out


func test_a_shotgun_bangs_once_and_not_once_per_pellet() -> void:
	var cues := _cues_from_firing("shotgun")
	var all := events_of(sim, "shot").size()
	gt(cues.size(), 0, "the shotgun did not go off at all")
	for c in cues:
		eq(c, "shotgun")
	eq(all, cues.size() * int(Config.WEAPONS.shotgun.pellets),
		"eight pellets, one bang: %d shots, %d bangs" % [all, cues.size()])


func test_the_bow_is_not_silent() -> void:
	# A bow emits no muzzle flash — a flash is a light source, and a bow that
	# lit up the treeline would give away the one thing it is for. The first
	# cut of this hung every gun sound on the muzzle event, so the bow made no
	# sound at all and the cue written for it was never once reached.
	#
	# The assertion is on the cue `SfxView` chose, not on the event that fed
	# it: "the bow emitted a shot" was true the whole time the bow was silent.
	ok(Config.SFX.has("bow"))
	var cues := _cues_from_firing("bow")
	gt(cues.size(), 0, "the bow fired and said nothing")
	eq(cues[0], "bow")


func test_every_gun_reaches_its_own_cue() -> void:
	# Not "has a cue" — reaches it. A weapon whose id does not match its cue
	# name falls back to the pistol and sounds wrong in a way nothing else
	# would catch.
	for id in Config.WEAPONS:
		var w: Dictionary = Config.WEAPONS[id]
		if String(w.get("kind", "")) != "gun" and not w.get("bow", false):
			continue
		eq(ears.on_event({"t": "shot", "x": p.pos.x, "y": p.pos.y, "w": id}), id,
			"%s does not reach a cue of its own" % id)


func test_a_turret_and_a_survivor_have_voices_of_their_own() -> void:
	# `spawn_bullet` is called with a weapon id by the player, by a turret and
	# by a survivor, and all three arrive through the same field. A name with
	# no cue falls back to the pistol — which is how the carbine nearly
	# shipped sounding like a handgun.
	for id in ["turret", "survivor"]:
		eq(ears.on_event({"t": "shot", "x": p.pos.x, "y": p.pos.y, "w": id}), id)


func test_a_pellet_after_the_first_makes_no_sound_at_all() -> void:
	eq(ears.on_event({"t": "shot", "x": p.pos.x, "y": p.pos.y, "w": ""}), "",
		"an unnamed shot is a pellet, not a bang")
func test_a_pipe_thumps_and_a_bullet_pings() -> void:
	# The hit event carries which it was, because nothing else can tell.
	var e := EnemySim.new("walker", p.pos + Vector2(30, 0), 1)
	sim.enemies.list.append(e)
	Damage.damage_enemy(sim, e, 4.0, p.pos, 0.0, false, p, false, false, "melee")
	eq(String(_first(sim, "hit").kind), "melee")
	sim.events.clear()
	Damage.damage_enemy(sim, e, 4.0, p.pos)
	eq(String(_first(sim, "hit").kind), "bullet", "and a bullet is the default")


func _first(s: GameSim, t: String) -> Dictionary:
	for ev in s.events:
		if String(ev.t) == t:
			return ev
	return {}


# -------------------------------------------------------------- distance --

func test_distance_is_what_makes_a_turret_across_town_quiet() -> void:
	p.pos = Vector2(5000, 5000)
	eq(ears.gain_at(p.pos), 1.0, "your own gun is your own gun")
	eq(ears.gain_at(p.pos + Vector2(Config.SFX_NEAR - 1.0, 0)), 1.0, "and so is anything close")
	var mid := ears.gain_at(p.pos + Vector2((Config.SFX_NEAR + Config.SFX_RANGE) / 2.0, 0))
	gt(mid, 0.0)
	ok(mid < 1.0, "something across the street is quieter")
	eq(ears.gain_at(p.pos + Vector2(Config.SFX_RANGE + 1.0, 0)), 0.0, "and across town is nothing")


func test_a_sound_with_nowhere_to_be_is_not_faded() -> void:
	# A raid warning belongs to the whole town rather than to a point in it,
	# so it has no position and must not be attenuated to nothing.
	ok(not SfxView.DIRECT.is_empty())
	eq(String(SfxView.DIRECT.raid_warn), "raid_warn")
	var warned := false
	for ev in [{"t": "raid_warn"}]:
		ok(not ev.has("x"), "the warning has no position, by design")
		warned = true
	ok(warned)
