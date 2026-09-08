extends Node2D
## Placeholder root. Phase 1 replaces this with the real world and player.
## It exists so the smoke path has something to photograph.

const TILE := 32

func _draw() -> void:
	for y in range(0, 24):
		for x in range(0, 40):
			var c := Color(0.16, 0.22, 0.14) if (x + y) % 2 == 0 else Color(0.18, 0.25, 0.16)
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), c)
	draw_circle(Vector2(640, 360), 12, Color(0.9, 0.85, 0.6))

func smoke_state() -> Dictionary:
	return {"scene": "placeholder", "tile": TILE}
