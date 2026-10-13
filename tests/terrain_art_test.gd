extends "res://tests/test_case.gd"
## `TerrainRenderer.cell_art`: the one answer both stages draw a tile from.
## The cases `_paint` always had — a wall, a roof, water with a lip, a fence
## with rails, a road with its marking, plain ground — now asked without a
## renderer, which is how the 3D stage asks.

const T = Config.T

var sim: GameSim
var town: World


func before_each() -> void:
	sim = new_sim()
	town = sim.world


func _first_tile_of(t: int) -> Vector2i:
	for ty in range(Config.WORLD_TILES):
		for tx in range(Config.WORLD_TILES):
			if town.tiles[ty * Config.WORLD_TILES + tx] == t:
				return Vector2i(tx, ty)
	return Vector2i(-1, -1)


func test_a_wall_and_a_roof_stand_and_the_rest_lies_flat() -> void:
	var w := _first_tile_of(T.WALL)
	ok(w.x >= 0, "the town has a wall")
	var art := TerrainRenderer.cell_art(town, w.x, w.y)
	ok(art.standing, "a wall stands")
	eq(art.t, T.WALL)
	ok(art.cell in [TileArt.coords("wall_0"), TileArt.coords("wall_1"), TileArt.coords("wall_2")], "a wall's cell is wall art")
	var r := _first_tile_of(T.ROOF)
	ok(r.x >= 0, "the town has a roof")
	ok(TerrainRenderer.cell_art(town, r.x, r.y).standing, "a roof stands")
	var g := _first_tile_of(T.GRASS)
	var ga := TerrainRenderer.cell_art(town, g.x, g.y)
	ok(not ga.standing, "grass lies flat")
	eq(ga.t, T.GRASS)


func test_water_meets_land_with_a_lip_on_the_land_side() -> void:
	# A water tile whose northern neighbour is land draws the north-lip cell.
	var found := false
	for ty in range(1, Config.WORLD_TILES - 1):
		for tx in range(1, Config.WORLD_TILES - 1):
			if town.tile(tx, ty) == T.WATER and town.tile(tx, ty - 1) != T.WATER \
				and town.tile(tx, ty + 1) == T.WATER and town.tile(tx - 1, ty) == T.WATER and town.tile(tx + 1, ty) == T.WATER:
				eq(TerrainRenderer.cell_art(town, tx, ty).cell, TileArt.coords("water_m1"))
				found = true
				break
		if found:
			break
	ok(found, "the river has a northern bank somewhere")


func test_a_fence_runs_its_rails_toward_its_neighbours() -> void:
	var found := false
	for ty in range(1, Config.WORLD_TILES - 1):
		for tx in range(1, Config.WORLD_TILES - 1):
			if town.tile(tx, ty) == T.FENCE and town.tile(tx - 1, ty) == T.FENCE and town.tile(tx + 1, ty) == T.FENCE \
				and town.tile(tx, ty - 1) != T.FENCE and town.tile(tx, ty + 1) != T.FENCE:
				eq(TerrainRenderer.cell_art(town, tx, ty).cell, TileArt.coords("fence_m3"), "left and right: mask 3")
				found = true
				break
		if found:
			break
	ok(found, "a fence runs east-west somewhere")


func test_the_same_tile_answers_the_same_every_time() -> void:
	var w := _first_tile_of(T.WALL)
	eq(TerrainRenderer.cell_art(town, w.x, w.y), TerrainRenderer.cell_art(town, w.x, w.y))
	var g := _first_tile_of(T.ROAD)
	eq(TerrainRenderer.cell_art(town, g.x, g.y), TerrainRenderer.cell_art(town, g.x, g.y))
