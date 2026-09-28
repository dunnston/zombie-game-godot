class_name Music
extends Node
## The score: one track at a time, crossfaded, chosen from what is happening.
##
## `pick` is a pure function of the game's state so a headless test can ask it
## the real question. The node only plays what `pick` says. A missing file or a
## machine with no audio device loses its music and keeps its game, like `Sfx`.
##
## The autoload is `Soundtrack`, not `Music`, for the reason `Sfx` is `Audio`.

static var _streams := {}
## mood -> the file it last played, so a mood does not repeat itself.
static var _last := {}

var _a := AudioStreamPlayer.new()
var _b := AudioStreamPlayer.new()
var _front: AudioStreamPlayer
var _current := ""
var _fade := 0.0
var _old: AudioStreamPlayer = null


func _ready() -> void:
	for pl in [_a, _b]:
		pl.bus = "Master"
		pl.volume_db = -80.0
		add_child(pl)
	_front = _a


## What should be playing. Title beats everything; then dead, a woken boss, a
## raid in progress, and otherwise the walk around the world.
static func pick(at_title: bool, dead: bool, boss_type: String, raiding: bool) -> String:
	if at_title:
		return "main_menu"
	if dead:
		return "game_over"
	if not boss_type.is_empty():
		return String(Config.MUSIC_BOSS.get(boss_type, "boss_1"))
	if raiding:
		return "horde"
	return "exploration"


## The type of the boss to fight to, or "" — awake and alive, so the school's
## hallways are still the walk and the gym is the fight.
static func boss_of(sim: GameSim) -> String:
	if sim == null or sim.instance == null:
		return ""
	var b := sim.instance.boss
	if b == null or b.dead or b.brain == null or String(b.brain.state) == "asleep":
		return ""
	return String(b.type)


## The file to play for a mood: one of its takes, other than the last one.
## `roll` (0..1) is the dice, a parameter so a test can hold it still.
static func variant(mood: String, roll := randf()) -> String:
	var files: Array = Config.MUSIC_VARIANTS.get(mood, [mood])
	var pool := files.filter(func(f): return f != _last.get(mood, ""))
	if pool.is_empty():
		pool = files
	var f: String = pool[mini(int(roll * pool.size()), pool.size() - 1)]
	_last[mood] = f
	return f


static func stream(name: String, once := false) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := "%s%s.mp3" % [Config.MUSIC_DIR, name]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if s is AudioStreamMP3:
			s.loop = not once
	_streams[name] = s
	return s


## Asks for a track. Asking for the one already playing does nothing, so this
## is cheap enough to call every frame.
func play(name: String) -> void:
	if name == _current:
		return
	_current = name
	var s := stream(variant(name), Config.MUSIC_ONCE.has(name))
	var old := _front
	_front = _b if _front == _a else _a
	if s == null:
		_front.stop()
	else:
		_front.stream = s
		_front.volume_db = -80.0
		_front.play()
	_fade = 0.0
	_old = old


## The score's own volume, master slider included — `Sfx` owns the sliders
## since `SOUND` on the title screen is one setting for both halves of the
## audio. Pulled out of `_process` so a test can check the mix without a
## speaker.
static func effective_gain() -> float:
	return Config.MUSIC_GAIN * Sfx.music_volume() * Sfx.master_volume()


func _process(dt: float) -> void:
	_fade = minf(1.0, _fade + dt / Config.MUSIC_FADE)
	var vol := effective_gain()
	var loud := -80.0 if (Sfx.muted() or vol <= 0.0001) else linear_to_db(clampf(vol, 0.0001, 1.0))
	if _front != null and _front.playing:
		_front.volume_db = lerpf(-80.0, loud, _fade) if loud > -80.0 else -80.0
	if _old != null:
		_old.volume_db = lerpf(loud, -80.0, _fade) if loud > -80.0 else -80.0
		if _fade >= 1.0:
			_old.stop()
			_old = null
