class_name Sfx
extends Node
## Every sound in the game, synthesised at boot. No asset files, no loading.
##
## The prototype built a WebAudio graph — oscillator, gain envelope, biquad —
## on every single sound. Godot has no cheap equivalent, and it does not need
## one: these cues are short and fixed, so each `Config.SFX` recipe is rendered
## to a small PCM buffer **once**, and playing it afterwards costs a `play()`.
## Thirty-odd cues come to about a third of a megabyte at 22kHz mono.
##
## Static state on a `class_name`, not autoload-only fields: an autoload does
## not exist under `godot --headless -s`, and audio you cannot test is audio
## that silently stops working. Every entry point is guarded, because a
## machine with no audio device must lose its sound and keep its game.
##
## The autoload is called `Audio`, not `Sfx`, for the same reason `Bindings`
## is not called `KeyBinds`: an autoload whose name matches a `class_name`
## shadows the class with the instance, and under `-s` — where there is no
## autoload — the name then resolves to a bare GDScript resource with no
## static methods on it at all.

## Fills before the first cue can be heard.
static var _bank := {}
## group -> its recorded takes, when any were cut. A cue whose group is not
## here, or whose group has no file on disk, plays its synth recipe instead.
static var _files := {}
## group -> the take last played, so a shotgun's own file does not repeat.
static var _file_last := {}
## cue -> last play time in milliseconds, for the throttle.
static var _last := {}
static var _players: Array[AudioStreamPlayer] = []
static var _next := 0
static var _muted := false
static var _built := false
## The three sliders: master, music and effects, each 0..1 and multiplied
## into whatever plays. `Music` reads the first two; `play` reads the first
## and third. Muting is still its own switch — the quick toggle on the title
## screen and the pause menu — rather than the sliders remembering silence.
static var _master := 1.0
static var _music_vol := 1.0
static var _sfx_vol := 1.0

## How many cues can overlap. A raid is the busy case: several guns, a dozen
## impacts and a horde. Past this the oldest voice is taken, which is the right
## answer — the sound you are stealing is already a third of a second old.
const VOICES := 24

## The white noise in a cue comes from here, not from `randf()`. A cue is a
## fixed recipe rendered once at boot, so it should be the same waveform every
## launch — with the global RNG it was whatever the engine had been asked for
## beforehand, which made `test_nothing_clips` a coin flip on any cue mixed
## near full scale (boltActionRifle peaks at 0.999). Seeded here, the bank is
## a build artifact and that test means something.
static var _noise_rng := RandomNumberGenerator.new()
## Where the mute setting lives. A `static var` rather than a `const` for the
## same reason `KeyBinds.STORE` is one: `user://` is shared with the real game,
## and a smoke run that wrote its own muting into it would silence the player.
static var STORE := "user://audio.json"


func _ready() -> void:
	# Checked here rather than read off the `Smoke` autoload: autoloads run in
	# declaration order and `Smoke` has not loaded yet. The setting must be
	# redirected before `load_settings` reads and `set_muted` writes.
	for a in OS.get_cmdline_user_args():
		if a == "--smoke":
			STORE = "user://audio_smoke.json"
	build()
	attach(self)
	load_settings()


# ------------------------------------------------------------------- bank --

## Renders every cue. Idempotent: the second call is free, which is what lets a
## test ask for the bank without caring whether the autoload got there first.
static func build() -> void:
	if _built:
		return
	for name in Config.SFX:
		_bank[name] = _render(Config.SFX[name])
	_load_files()
	_built = true


## One load per group, not per cue: `rifle` is five cues sharing one file.
static func _load_files() -> void:
	var groups := {}
	for g in Config.SFX_FILES.values():
		groups[g] = true
	for g in groups:
		var loaded: Array = []
		for take in Config.SFX_VARIANTS.get(g, [g]):
			var path := "%s%s.wav" % [Config.SFX_DIR, take]
			if ResourceLoader.exists(path):
				var s: AudioStream = load(path)
				if s != null:
					loaded.append(s)
		if not loaded.is_empty():
			_files[g] = loaded


## The voices have to hang off a node in the tree, and `Sfx` is an autoload in
## the game and nothing at all under `-s`. So the pool is built on demand from
## whatever parent is given, and a headless run simply never asks.
static func attach(parent: Node) -> void:
	if not _players.is_empty():
		return
	for i in range(VOICES):
		var pl := AudioStreamPlayer.new()
		pl.bus = "Master"
		parent.add_child(pl)
		_players.append(pl)


static func has(name: String) -> bool:
	return _bank.has(name)


static func stream(name: String) -> AudioStreamWAV:
	return _bank.get(name)


## What `play` actually puts on a voice: a recorded take when the cue's group
## has one on disk, its synth recipe otherwise. Public so a test can ask what
## a cue will sound like without a speaker. `roll` is the dice, a parameter
## for the same reason `Music.variant`'s is.
static func chosen(name: String, roll := randf()) -> AudioStream:
	var g: String = Config.SFX_FILES.get(name, "")
	var files: Array = _files.get(g, [])
	if files.is_empty():
		return _bank.get(name)
	var pool: Array = files.filter(func(f): return f != _file_last.get(g))
	if pool.is_empty():
		pool = files
	var f: AudioStream = pool[mini(int(roll * pool.size()), pool.size() - 1)]
	_file_last[g] = f
	return f


# ---------------------------------------------------------------- synthesis --

## One cue: every op mixed into a buffer long enough to hold the latest of
## them, then clipped. `at` is what lets a reload be a click and then a clack
## without two calls and a timer.
static func _render(ops: Array) -> AudioStreamWAV:
	var rate: int = Config.SFX_RATE
	var end := 0.0
	for op in ops:
		end = maxf(end, float(op.get("at", 0.0)) + float(op.get("dur", 0.1)))
	var n := int(end * rate) + 2
	var buf := PackedFloat32Array()
	buf.resize(n)

	for op in ops:
		if String(op.kind) == "tone":
			_tone(buf, rate, op)
		else:
			_noise(buf, rate, op)

	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var v := int(clampf(buf[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	return w


## The envelope both op kinds share: a 5ms attack so nothing clicks on, then an
## exponential decay to silence — the prototype's
## `exponentialRampToValueAtTime` from 0.0001, which is why it is `exp` and not
## a straight line.
##
## Stepped rather than evaluated. `exp(-9k)` per sample is one transcendental
## per sample per op, and multiplying by a constant ratio gives the identical
## curve for a multiply. That, and the same trick on the pitch glide below,
## took the whole bank from 205ms to 91ms at boot.
static func _decay_step(n: int, attack: int) -> float:
	return exp(-9.0 / maxf(1.0, float(n - attack)))


## Frequency at fraction `k` through the op: an exponential glide, because
## pitch is heard in ratios. A missing or zero `to` means "hold". Returned as a
## per-sample multiplier for the same reason the envelope is.
static func _glide_step(from: float, to: float, n: int) -> float:
	if to <= 0.0 or from <= 0.0:
		return 1.0
	return pow(maxf(to, 20.0) / maxf(from, 20.0), 1.0 / maxf(1.0, float(n)))


static func _tone(buf: PackedFloat32Array, rate: int, op: Dictionary) -> void:
	var start := int(float(op.get("at", 0.0)) * rate)
	var n := int(float(op.dur) * rate)
	var gain: float = op.gain
	var wave := String(op.get("wave", "square"))
	var attack := maxi(1, int(0.005 * rate))
	var decay := _decay_step(n, attack)
	var f: float = op.freq
	var glide := _glide_step(f, float(op.get("to", 0.0)), n)
	var phase := 0.0
	var env := 0.0
	for i in range(n):
		var at := start + i
		if at >= buf.size():
			break
		env = float(i) / float(attack) if i < attack else env * decay
		phase += TAU * f / float(rate)
		f *= glide
		buf[at] += _wave(wave, phase) * gain * env


## Square, saw, triangle, sine — the four the prototype used, and no more:
## every cue is built from them, so adding a fifth means a cue that wants it.
static func _wave(kind: String, phase: float) -> float:
	var t := fposmod(phase, TAU) / TAU
	match kind:
		"square":
			return 1.0 if t < 0.5 else -1.0
		"saw":
			return t * 2.0 - 1.0
		"tri":
			return 1.0 - absf(t * 4.0 - 2.0)
		_:
			return sin(phase)


## White noise through a Chamberlin state-variable filter, which gives the
## lowpass, highpass and bandpass the prototype's biquad gave — from one loop,
## and able to sweep its cutoff per sample the way `hit` and `struct_break` do.
static func _noise(buf: PackedFloat32Array, rate: int, op: Dictionary) -> void:
	# Per op, not per bank: otherwise adding a cue to the table would change
	# the sound of every cue rendered after it.
	_noise_rng.seed = 0x50f7
	var start := int(float(op.get("at", 0.0)) * rate)
	var n := int(float(op.dur) * rate)
	var gain: float = op.gain
	var mode := String(op.get("filter", "lp"))
	var q: float = maxf(0.35, float(op.get("q", 1.0)))
	var damp := 1.0 / q
	var low := 0.0
	var band := 0.0
	var attack := maxi(1, int(0.005 * rate))
	var decay := _decay_step(n, attack)
	var env := 0.0
	# The SVF goes unstable as its cutoff approaches a quarter of the rate, so
	# it is clamped there rather than allowed to scream.
	var top := float(rate) * 0.24
	var fc: float = op.get("freq", 1200.0)
	var glide := _glide_step(fc, float(op.get("to", 0.0)), n)
	for i in range(n):
		var at := start + i
		if at >= buf.size():
			break
		env = float(i) / float(attack) if i < attack else env * decay
		var f := 2.0 * sin(PI * clampf(fc, 20.0, top) / float(rate))
		fc *= glide
		var x := _noise_rng.randf() * 2.0 - 1.0
		low += f * band
		var high := x - low - damp * band
		band += f * high
		var out := low if mode == "lp" else (high if mode == "hp" else band)
		buf[at] += out * gain * env


# ------------------------------------------------------------------- play --

## Whether a cue is allowed to sound right now. Public because it is the whole
## point of the rate limit and it is worth testing without a speaker.
static func allowed(name: String, at_ms: int) -> bool:
	var gap: int = Config.SFX_THROTTLE.get(name, 0)
	if gap <= 0:
		return true
	var last: int = _last.get(name, -1000000)
	if at_ms - last < gap:
		return false
	_last[name] = at_ms
	return true


## Plays a cue, or does nothing. `pitch` is what gives a horde a dozen voices
## out of one growl.
##
## Never raises: a machine with a broken or missing audio device loses its
## sound and keeps its game, which is the one rule the prototype's audio had.
static func play(name: String, pitch := 1.0, gain := 1.0) -> bool:
	if _muted or _players.is_empty():
		return false
	if not _bank.has(name):
		return false
	if not allowed(name, Time.get_ticks_msec()):
		return false
	var pl := _players[_next]
	_next = (_next + 1) % _players.size()
	pl.stream = chosen(name)
	pl.pitch_scale = clampf(pitch, 0.05, 4.0)
	pl.volume_db = linear_to_db(effective_gain(gain))
	pl.play()
	return true


## What a cue at `gain` actually comes out at, master and effects sliders
## included. Pulled out of `play` so a test can check the mix without a
## speaker.
static func effective_gain(gain := 1.0) -> float:
	return clampf(Config.SFX_GAIN * gain * _sfx_vol * _master, 0.0001, 1.0)


static func set_muted(on: bool) -> void:
	_muted = on
	if on:
		for pl in _players:
			pl.stop()
	save_settings()


static func muted() -> bool:
	return _muted


static func master_volume() -> float:
	return _master


static func music_volume() -> float:
	return _music_vol


static func sfx_volume() -> float:
	return _sfx_vol


## `persist` is false while a slider is still being dragged: the value takes
## effect immediately either way, but a drag is a lot of calls a second and
## only the value it is released on is worth a write to disk.
static func set_master_volume(v: float, persist := true) -> void:
	_master = clampf(v, 0.0, 1.0)
	if persist:
		save_settings()


static func set_music_volume(v: float, persist := true) -> void:
	_music_vol = clampf(v, 0.0, 1.0)
	if persist:
		save_settings()


static func set_sfx_volume(v: float, persist := true) -> void:
	_sfx_vol = clampf(v, 0.0, 1.0)
	if persist:
		save_settings()


# --------------------------------------------------------------- settings --

## Per machine, like the key bindings and for the same reason: whether your
## speakers are on is not a property of the world you are playing.
static func save_settings() -> bool:
	var f := FileAccess.open(STORE, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({
		"muted": _muted, "master": _master, "music": _music_vol, "sfx": _sfx_vol,
	}))
	f.close()
	return true


static func load_settings() -> void:
	if not FileAccess.file_exists(STORE):
		return
	var f := FileAccess.open(STORE, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		_muted = bool(data.get("muted", false))
		_master = clampf(float(data.get("master", 1.0)), 0.0, 1.0)
		_music_vol = clampf(float(data.get("music", 1.0)), 0.0, 1.0)
		_sfx_vol = clampf(float(data.get("sfx", 1.0)), 0.0, 1.0)
