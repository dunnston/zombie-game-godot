class_name NoiseLensView
extends Node2D
## The noise lens (F2, or the F1 menu, in a dev build): each noise drawn as a
## dashed circle at its true radius, with the number that heard it.
##
## Not part of `FxView` because of where it has to live. `LightView`'s
## CanvasModulate multiplies the whole world canvas toward black at night, and
## a thin half-transparent ring under it simply vanished — a debugging view
## that only works at noon. `scenes/main.gd` puts this on its own CanvasLayer
## that follows the camera, which the night's tint does not reach.
## Cosmetic only, and fed nothing unless `Sound.debug` is on.

## What each kind of noise is drawn in. Landing a blow and whiffing are the
## pair worth telling apart at a glance, so they are the warm one and the cold
## one; work is the tool, and a gunshot is the loud mistake.
const TINT := {
	"hit": Color("#e8a13c"),
	"whiff": Color("#6f7d8c"),
	"work": Color("#7fa860"),
	"gun": Color("#d9584a"),
	"world": Color("#9a93a8"),
}
const LIFE := 1.1

var rings: Array[Dictionary] = []


## One switch for F2 and the dev menu, so the two can never disagree about
## what "on" says.
static func toggle(sim: GameSim) -> void:
	Sound.debug = not Sound.debug
	sim.notify("Noise overlay %s" % ("on" if Sound.debug else "off"), "#9ad0e8")


func on_event(ev: Dictionary) -> void:
	if ev.t != "noise":
		return
	# Drawn at the true radius and NOT expanding: the thing being debugged is
	# how far this reached, so the circle has to sit still long enough to
	# measure by eye. The fade is the only animation, and the dashes keep it
	# off the solid rings the game already uses for staggers and raids.
	rings.append({"pos": Vector2(ev.x, ev.y), "life": LIFE, "r": float(ev.r),
		"heard": int(ev.heard), "color": TINT.get(ev.src, TINT.world)})


func tick(dt: float) -> void:
	for i in range(rings.size() - 1, -1, -1):
		rings[i].life -= dt
		if rings[i].life <= 0.0:
			rings.remove_at(i)
	# Switched off mid-fade: the rings on screen go with it.
	if not Sound.debug:
		rings.clear()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for q in rings:
		var k: float = clampf(q.life / LIFE, 0.0, 1.0)
		var c: Color = q.color
		# Held near full for the first third, then dropped: long enough to
		# read, short enough not to litter during automatic fire.
		c.a = minf(1.0, k * 1.5) * 0.7
		var segs := 30
		var span := TAU / segs
		for i in segs:
			var a0: float = i * span
			draw_arc(q.pos, q.r, a0, a0 + span * 0.5, 3, c, 2.0)
		draw_circle(q.pos, 2.5, c)
		if q.heard > 0:
			var t := Color(c)
			t.a = minf(1.0, c.a * 1.4)
			draw_string(font, q.pos + Vector2(0, -q.r - 4.0), str(q.heard),
				HORIZONTAL_ALIGNMENT_CENTER, -1, 11, t)
