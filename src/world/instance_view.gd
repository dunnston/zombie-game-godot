class_name InstanceView
extends Node2D
## The doors that answer E instead of letting you through, drawn over the floor
## tile the terrain put under them: an instance's way in, in the town, and
## inside one the way out, the chained gym and the exit the boss guards. Read
## off `sim.world.features` every frame, so the swap in and out needs nothing
## rebuilt here.

var sim: GameSim


func _init(sim_: GameSim) -> void:
	sim = sim_


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var inst := sim.instance
	for f in sim.world.features:
		var r := _rect(f)
		match String(f.kind):
			"instance_door":
				_doors(r, Color("#5a3d28"))
				# Chained on the day you cleared it, so the reason it will not
				# open is on the door before the prompt says so.
				if sim.cleared.has(f.id) and int(sim.cleared[f.id]) == sim.clock.day:
					_chains(r)
				draw_string(font, Vector2(float(f.x) - 90.0, r.position.y - 8.0), Instance.title(String(f.id)).to_upper(),
					HORIZONTAL_ALIGNMENT_CENTER, 180.0, 12, Color("#d8c98a"))
			"leave":
				_doors(r, Color("#2f4a3a"))
			"chained":
				if not f.open:
					_doors(r, Color("#4a3a2a"))
					_chains(r)
			"breaker":
				# A box on the wall with its lever: down and red while the
				# lights are out, which is what makes it findable in the dark.
				var dark := inst != null and inst.dark
				var box := Rect2(Vector2(float(f.x) - 10.0, float(f.y) - 14.0), Vector2(20.0, 28.0))
				draw_rect(box, Color("#3a3f44"))
				draw_rect(box, Color("#1c1f22"), false, 2.0)
				draw_line(box.get_center(), box.get_center() + Vector2(0.0, 9.0 if dark else -9.0), Color("#c9b27a"), 3.0)
				draw_circle(box.position + Vector2(10.0, 4.0), 2.5, Color("#e05a4a") if dark else Color("#7ce08a"))
			"exit":
				var open := inst != null and inst.state == "cleared"
				_doors(r, Color("#2f6a3a") if open else Color("#26262a"))
				if open:
					draw_string(font, Vector2(r.position.x, r.position.y - 6.0), "EXIT", HORIZONTAL_ALIGNMENT_CENTER,
						r.size.x, 12, Color("#9fe8a0"))


static func _rect(f: Dictionary) -> Rect2:
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-1, -1)
	for t: Vector2i in f.tiles:
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	var tile := float(Config.TILE)
	return Rect2(Vector2(lo) * tile, Vector2(hi - lo + Vector2i.ONE) * tile)


## A pair of doors: two leaves split down the long side, with handles.
func _doors(r: Rect2, col: Color) -> void:
	draw_rect(r, col)
	draw_rect(r, col.darkened(0.45), false, 2.0)
	var c := r.get_center()
	if r.size.x >= r.size.y:
		draw_line(Vector2(c.x, r.position.y), Vector2(c.x, r.end.y), col.darkened(0.45), 2.0)
		draw_rect(Rect2(c.x - 6.0, c.y - 2.0, 3.0, 4.0), Color("#c9b27a"))
		draw_rect(Rect2(c.x + 3.0, c.y - 2.0, 3.0, 4.0), Color("#c9b27a"))
	else:
		draw_line(Vector2(r.position.x, c.y), Vector2(r.end.x, c.y), col.darkened(0.45), 2.0)
		draw_rect(Rect2(c.x - 2.0, c.y - 6.0, 4.0, 3.0), Color("#c9b27a"))
		draw_rect(Rect2(c.x - 2.0, c.y + 3.0, 4.0, 3.0), Color("#c9b27a"))


## Chains across it and a padlock: shut, and not by you.
func _chains(r: Rect2) -> void:
	var grey := Color("#9aa0a6")
	draw_line(r.position, r.end, grey, 3.0)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), grey, 3.0)
	var c := r.get_center()
	draw_rect(Rect2(c.x - 5.0, c.y - 4.0, 10.0, 9.0), Color("#6a6e72"))
	draw_arc(c + Vector2(0, -4), 4.0, PI, TAU, 8, grey, 2.0)
