class_name GameSim
extends RefCounted
## The whole simulation: the world and everyone in it, stepped by tick().
## Owns no nodes. Presentation reads it; input reaches it only through each
## player's Intent.

var world: World
var players: Array[PlayerSim] = []
var time := 0.0
var rng: Rng


func new_game(world_seed: int = 20240917, run_seed: int = 1) -> void:
	world = World.new(world_seed)
	rng = Rng.new(run_seed)
	time = 0.0
	players.clear()
	var p := PlayerSim.new()
	p.seat = 0
	p.display_name = Config.PLAYER.names[0]
	# The first morning starts by the Roadside Camp, not in a field across
	# the river.
	var camp: Rect2i = world.locations[0].rect
	var centre := Vector2(camp.position.x + camp.size.x / 2.0, camp.position.y + camp.size.y / 2.0) * Config.TILE
	p.pos = pick_random_spawn(centre, 30.0 * Config.TILE)
	p.intent.aim = p.pos + Vector2.RIGHT
	players.append(p)


## A random open tile in tier-1 land. With `near`, only tiles within `radius`
## pixels of that point are considered (falling back to all of them).
func pick_random_spawn(near: Vector2 = Vector2.INF, radius: float = 0.0) -> Vector2:
	var tiles := world.spawn_tiles
	if near != Vector2.INF:
		var close: Array[Vector2i] = []
		var r2 := radius * radius
		for t in tiles:
			var c := Vector2(t.x * Config.TILE + 16, t.y * Config.TILE + 16)
			if c.distance_squared_to(near) <= r2:
				close.append(t)
		if not close.is_empty():
			tiles = close
	if tiles.is_empty():
		return Vector2(160 * Config.TILE, 160 * Config.TILE)
	var t: Vector2i = rng.pick(tiles)
	return Vector2(t.x * Config.TILE + 16, t.y * Config.TILE + 16)


func tick(dt: float) -> void:
	time += dt
	for p in players:
		p.tick(world, dt)
	for p in players:
		p.intent.clear_edges()
