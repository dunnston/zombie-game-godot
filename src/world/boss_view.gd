class_name BossView
extends Node2D
## A boss's telegraphs, drawn from its events: the ring a slam will fill, the
## lane a charge will run, the fan a throw will cover, the whistle. Driven by
## events rather than by the boss's script, so a guest — whose copy of the
## boss has no script at all — draws exactly what the host does. A telegraph
## is a promise about where something will land; the fill says when.

var sim: GameSim
var tells: Array[Dictionary] = []
var stuns: Array[Dictionary] = []
## Enemy id -> the phase it is in, for the aura.
var phase_of := {}

const PHASE_COLOR := [Color("#e0a040"), Color("#e05a4a")]


func _init(sim_: GameSim) -> void:
	sim = sim_


## Takes one event, and returns what it will draw for it — or "" — so a test
## can assert on the decision rather than on what fed it (§8).
func on_event(ev: Dictionary) -> String:
	match String(ev.t):
		"boss_tell":
			tells.append({"move": String(ev.move), "id": int(ev.id), "at": Vector2(ev.x, ev.y),
				"to": Vector2(ev.tx, ev.ty), "dur": maxf(0.01, float(ev.dur)), "t": 0.0,
				"r": float(ev.get("r", 0.0)), "dist": float(ev.get("dist", 0.0)),
				"fan": float(ev.get("fan", 0.0)), "n": int(ev.get("n", 1))})
			return String(ev.move)
		"boss_stunned":
			stuns.append({"id": int(ev.id), "t": float(ev.dur), "max": float(ev.dur)})
			return "stunned"
		"boss_phase":
			var id := int(ev.id)
			phase_of[id] = int(ev.phase)
			# A change of phase takes over whatever it was doing (Codex, PR #33):
			# `Boss._shift` replaces a telegraph mid-fill, so that move never
			# lands, and its ring must not go on filling as though it would.
			# A stun ends the same way.
			for i in range(tells.size() - 1, -1, -1):
				if int(tells[i].id) == id:
					tells.remove_at(i)
			for i in range(stuns.size() - 1, -1, -1):
				if int(stuns[i].id) == id:
					stuns.remove_at(i)
			return "phase"
	return ""


func tick(dt: float) -> void:
	for i in range(tells.size() - 1, -1, -1):
		tells[i].t += dt
		if tells[i].t >= tells[i].dur:
			tells.remove_at(i)
	for i in range(stuns.size() - 1, -1, -1):
		stuns[i].t -= dt
		if stuns[i].t <= 0.0:
			stuns.remove_at(i)


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var red := Color(0.95, 0.3, 0.2)
	for tl in tells:
		var k := clampf(float(tl.t) / float(tl.dur), 0.0, 1.0)
		var at: Vector2 = tl.at
		var to: Vector2 = tl.to
		var d := (to - at).normalized() if (to - at).length_squared() > 1.0 else Vector2.RIGHT
		match String(tl.move):
			"slam":
				# The whole ring from the first frame — where to stand is the
				# question — and the fill says how long you have to get there.
				draw_circle(at, tl.r, Color(red, 0.10))
				draw_arc(at, tl.r, 0.0, TAU, 56, Color(red, 0.85), 3.0)
				draw_circle(at, tl.r * k, Color(red, 0.26))
			"charge":
				var end := at + d * float(tl.dist)
				draw_line(at, end, Color(red, 0.16), 56.0)
				draw_line(at, at + d * float(tl.dist) * k, Color(red, 0.32), 56.0)
				draw_line(end + d.orthogonal() * 28.0, end - d.orthogonal() * 28.0, Color(red, 0.85), 3.0)
			"dodgeball":
				var n: int = tl.n
				for i in range(n):
					var off: float = 0.0 if n <= 1 else (i - (n - 1) / 2.0) * float(tl.fan) / (n - 1)
					var ray := d.rotated(off)
					draw_line(at + ray * 30.0, at + ray * (60.0 + 200.0 * k), Color(red, 0.55), 3.0)
			"whistle":
				draw_arc(at, 30.0 + 70.0 * k, 0.0, TAU, 40, Color("#ffe08a", 1.0 - k), 3.0)
				draw_string(font, at + Vector2(-8, -44), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("#ffe08a"))
	# A boss past its first threshold wears it: an aura in the phase's colour.
	for e in sim.enemies.list:
		if e.dead or not e.def.get("boss", false):
			continue
		var c := Util.render_pos(e.prev_pos, e.pos)
		var ph: int = phase_of.get(e.id, 0)
		if ph > 0:
			var col: Color = PHASE_COLOR[mini(ph, PHASE_COLOR.size()) - 1]
			draw_arc(c, e.r + 8.0 + sin(e.anim * 3.0) * 2.0, 0.0, TAU, 36, Color(col, 0.8), 3.0)
		for s in stuns:
			if int(s.id) == e.id:
				# Dazed: stars round the head, for as long as the opening lasts.
				for j in range(3):
					var a := float(s.t) * 4.0 + j * TAU / 3.0
					draw_circle(c + Vector2(cos(a) * 18.0, -e.r - 10.0 + sin(a) * 5.0), 3.0, Color("#ffe08a"))
