class_name PropRenderer
extends Node2D
## Draws the world's props — trees, scenery, litter, wrecks, containers,
## parked cars — with canvas primitives, the way the prototype did. Props are
## bucketed into 256px cells at build time; each frame the visible cells are
## gathered, sorted by y, and drawn. Two instances exist: one draws props
## behind the player (y at or above the player's feet), one in front.

const CELL := 256
const CELLS := Config.WORLD_SIZE / CELL

const CANOPY := [Color("#2f5a2a"), Color("#33612d"), Color("#2a5228"), Color("#376a30")]
const CAR_PAINT := [Color("#8a2f2f"), Color("#2f4f8a"), Color("#b0b0a8"), Color("#3d6b3d")]
const CONTAINER_PAINT := {
	"cabinet": "#7a5a3a", "toolbox": "#b03a2a", "shelf": "#8b8b80", "medcab": "#e8e8e0",
	"crate": "#a8865a", "safe": "#3d4048", "locker": "#5f6b7a", "trunk": "#444444",
	"milcrate": "#5b6b3e", "pump": "#c0392b", "drum": "#c9a227", "logs": "#7a5230",
	"bookshelf": "#6a4a2e", "dresser": "#8a6a48", "wardrobe": "#6e4f34", "desk": "#9a7b55",
	"filing": "#7c8288", "fridge": "#d8d8d2", "nightstand": "#8a6a48", "vanity": "#cfd6d8",
	"footlocker": "#4f5a3a", "vending": "#2f6fb0", "toolrack": "#6b5a45", "displaycase": "#9ec3d8",
}
const SHADOW := Color(0, 0, 0, 0.22)

var sim: GameSim
var above := false
var _buckets := {}


func _init(sim_: GameSim, above_: bool) -> void:
	sim = sim_
	above = above_


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	_buckets.clear()
	for p in sim.world.props:
		_add(p)
	for c in sim.world.containers:
		_add(c)
	for v in sim.world.vehicle_spawns:
		_add(v)


func _add(p: Dictionary) -> void:
	var key := int(p.y / CELL) * CELLS + int(p.x / CELL)
	if not _buckets.has(key):
		_buckets[key] = []
	_buckets[key].append(p)


func _draw() -> void:
	var inv := get_viewport().get_canvas_transform().affine_inverse()
	var tl := inv * Vector2.ZERO
	var br := inv * get_viewport_rect().size
	var pad := 80.0
	var py: float = sim.players[0].pos.y
	var list: Array[Dictionary] = []
	var c0 := Vector2i(maxi(0, int((tl.x - pad) / CELL)), maxi(0, int((tl.y - pad) / CELL)))
	var c1 := Vector2i(mini(CELLS - 1, int((br.x + pad) / CELL)), mini(CELLS - 1, int((br.y + pad) / CELL)))
	for cy in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var b = _buckets.get(cy * CELLS + cx)
			if b == null:
				continue
			for p in b:
				var y: float = p.y
				if (y > py) != above:
					continue
				var x: float = p.x
				if x < tl.x - pad or x > br.x + pad or y < tl.y - pad or y > br.y + pad:
					continue
				list.append(p)
	list.sort_custom(func(a, b): return a.y < b.y)
	for p in list:
		_draw_prop(p)


func _draw_prop(p: Dictionary) -> void:
	var c := Vector2(p.x, p.y)
	if p.has("looted"):
		_draw_container(c, p)
		return
	if p.has("tiles"):
		_draw_car(c, p)
		return
	match p.kind:
		"tree":
			_draw_tree(c, p.si)
		"pine":
			_draw_pine(c, p.si)
		"bush":
			draw_circle(c + Vector2(2, 3), 9, SHADOW)
			draw_circle(c, 9, Color("#3f6b2f"))
			draw_circle(c + Vector2(-3, -3), 5, Color("#4c7d38"))
		"rock":
			draw_colored_polygon(_poly(c, [Vector2(-7, 2), Vector2(-4, -5), Vector2(3, -6), Vector2(8, -1), Vector2(6, 5), Vector2(-2, 7)]), Color("#6f6b62"))
			draw_colored_polygon(_poly(c, [Vector2(-4, -3), Vector2(0, -5), Vector2(3, -2), Vector2(-1, 0)]), Color("#8a867c"))
		"boulder":
			draw_circle(c + Vector2(4, 5), 14, SHADOW)
			draw_colored_polygon(_poly(c, [Vector2(-14, 4), Vector2(-10, -9), Vector2(2, -14), Vector2(12, -8), Vector2(15, 3), Vector2(8, 12), Vector2(-5, 13)]), Color("#5d5952"))
			draw_colored_polygon(_poly(c, [Vector2(-8, -6), Vector2(0, -11), Vector2(6, -6), Vector2(-2, -2)]), Color("#7a766d"))
			draw_line(c + Vector2(-2, 0), c + Vector2(6, 8), Color("#3f3c37"), 1.5)
		"thicket":
			for off: Vector2 in [Vector2(-7, 2), Vector2(6, 3), Vector2(0, -6)]:
				draw_circle(c + off, 9, Color("#2c4a24"))
			draw_circle(c + Vector2(-3, -3), 5, Color("#3a5e2e"))
			draw_circle(c + Vector2(5, 0), 4, Color("#3a5e2e"))
		"litter":
			_draw_litter(c, p)
		"reed":
			for dx: float in [-6.0, -2.0, 2.0, 6.0]:
				draw_line(c + Vector2(dx, 8), c + Vector2(dx * 1.6, -10), Color("#5e8a3a"), 1.5)
		"hay":
			draw_rect(Rect2(c.x - 11, c.y - 7, 26, 20), SHADOW)
			draw_rect(Rect2(c.x - 13, c.y - 10, 26, 20), Color("#b8983f"))
			for dy: float in [-4.0, 2.0, 8.0]:
				draw_line(c + Vector2(-13, dy), c + Vector2(13, dy), Color("#8f7430"), 1.5)
		"silo":
			draw_circle(c + Vector2(4, 6), 30, SHADOW)
			draw_circle(c, 30, Color("#8c8c86"))
			draw_circle(c, 24, Color("#a0a099"))
			draw_circle(c, 8, Color("#6f6f69"))
			draw_arc(c, 27, 0, TAU, 32, Color("#77776f"), 1.5)
		"wreck":
			_draw_wreck(c, p.si)


func _poly(c: Vector2, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		out.append(c + v)
	return out


func _draw_tree(c: Vector2, si: int) -> void:
	draw_circle(c + Vector2(4, 6), 13, SHADOW)
	draw_rect(Rect2(c.x - 3, c.y - 4, 6, 10), Color("#4a3722"))
	var g: Color = CANOPY[si]
	draw_circle(c + Vector2(0, -8), 14, g.darkened(0.25))
	draw_circle(c + Vector2(-2, -10), 11, g)
	draw_circle(c + Vector2(-5, -13), 5, g.lightened(0.12))


func _draw_pine(c: Vector2, si: int) -> void:
	draw_circle(c + Vector2(4, 6), 11, SHADOW)
	draw_rect(Rect2(c.x - 2, c.y - 4, 4, 9), Color("#3a2c1c"))
	var d := Color("#1f3d22").lightened(si * 0.05)
	draw_colored_polygon(_poly(c, [Vector2(0, -30), Vector2(-14, -4), Vector2(14, -4)]), d)
	draw_colored_polygon(_poly(c, [Vector2(0, -34), Vector2(-10, -14), Vector2(10, -14)]), d.lightened(0.12))


func _draw_litter(c: Vector2, p: Dictionary) -> void:
	var rot: float = p.rot
	match p.res:
		"sticks":
			draw_line(c + Vector2(-8, -2).rotated(rot), c + Vector2(8, 2).rotated(rot), Color("#7a5a33"), 2.0)
			draw_line(c + Vector2(-5, 4).rotated(rot), c + Vector2(6, -3).rotated(rot), Color("#8c6a3d"), 2.0)
		"fiber":
			for dx: float in [-5.0, 0.0, 5.0]:
				draw_line(c + Vector2(dx, 5).rotated(rot), c + Vector2(dx - 2, -6).rotated(rot), Color("#b3a55c"), 1.5)
		_:
			draw_circle(c + Vector2(-3, 1), 3, Color("#7d7a70"))
			draw_circle(c + Vector2(4, -2), 2.5, Color("#8a877c"))


func _draw_wreck(c: Vector2, si: int) -> void:
	draw_rect(Rect2(c.x - 28, c.y - 8, 60, 24), SHADOW)
	draw_rect(Rect2(c.x - 30, c.y - 12, 60, 24), Color("#5a4033") if si == 0 else Color("#4f4a45"))
	draw_rect(Rect2(c.x - 12, c.y - 10, 26, 20), Color("#3a2e28"))
	draw_rect(Rect2(c.x - 11, c.y - 9, 5, 18), Color("#1c1c1c"))
	draw_rect(Rect2(c.x + 8, c.y - 9, 5, 18), Color("#1c1c1c"))
	draw_rect(Rect2(c.x - 24, c.y - 14, 8, 4), Color("#111111"))
	draw_rect(Rect2(c.x + 14, c.y + 10, 8, 4), Color("#111111"))


func _draw_car(c: Vector2, v: Dictionary) -> void:
	var paint: Color = CAR_PAINT[v.si]
	draw_rect(Rect2(c.x - 28, c.y - 8, 60, 24), SHADOW)
	draw_set_transform(c, v.rot, Vector2.ONE)
	draw_rect(Rect2(-30, -12, 60, 24), paint)
	draw_rect(Rect2(-14, -10, 26, 20), paint.darkened(0.35))
	draw_rect(Rect2(-14, -9, 5, 18), Color("#1f2a33"))
	draw_rect(Rect2(7, -9, 5, 18), Color("#1f2a33"))
	draw_rect(Rect2(28, -10, 2, 5), Color("#ffe9a3"))
	draw_rect(Rect2(28, 5, 2, 5), Color("#ffe9a3"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_container(c: Vector2, p: Dictionary) -> void:
	var paint := Color(CONTAINER_PAINT.get(p.sprite, "#888888"))
	if p.looted:
		paint = paint.darkened(0.45)
	draw_rect(Rect2(c.x - 10, c.y - 9, 24, 24), SHADOW)
	draw_rect(Rect2(c.x - 12, c.y - 12, 24, 24), paint)
	draw_rect(Rect2(c.x - 12, c.y - 12, 24, 24), paint.darkened(0.4), false, 2.0)
	draw_rect(Rect2(c.x - 10, c.y - 10, 20, 4), paint.lightened(0.2))
	match p.sprite:
		"logs":
			for off: Vector2 in [Vector2(-6, 4), Vector2(2, 4), Vector2(-2, -3)]:
				draw_circle(c + off, 4, Color("#c9a06a"))
		"drum":
			draw_circle(c, 8, paint.darkened(0.2))
		"pump":
			draw_rect(Rect2(c.x - 6, c.y - 6, 12, 8), Color("#eeeeee"))
		"safe":
			draw_circle(c, 4, Color("#9aa0a8"))
		"vending":
			draw_rect(Rect2(c.x - 8, c.y - 6, 10, 12), Color("#9fd0ff"))
