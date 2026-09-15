class_name TerrainRenderer
extends Node2D
## Draws the world's tiles: a ground layer, a wall-shadow layer offset a few
## pixels so walls read as extruded from above, and the walls themselves.
## Built once from the sim's tile array; player structures are drawn elsewhere.
##
## One tile does change at runtime: a house wall punched through becomes
## rubble (2026-09-15), and `repaint` is how the picture catches up without
## rebuilding a hundred thousand cells.

const T = Config.T
const W := Config.WORLD_TILES

var ground: TileMapLayer
var shadow: TileMapLayer
var walls: TileMapLayer


func _init() -> void:
	var ts := TileArt.tileset()
	ground = TileMapLayer.new()
	ground.tile_set = ts
	add_child(ground)
	shadow = TileMapLayer.new()
	shadow.tile_set = ts
	shadow.position = Vector2(3, 5)
	add_child(shadow)
	walls = TileMapLayer.new()
	walls.tile_set = ts
	add_child(walls)


## The atlas coordinates, looked up once: string formatting per tile is slow,
## and `repaint` wants the same table `build` used.
var _tv := []
var _water: Array[Vector2i] = []
var _fence: Array[Vector2i] = []
var _side: Array[Vector2i] = []
var _roadh: Array[Vector2i] = []
var _roadv: Array[Vector2i] = []
var _wall: Array[Vector2i] = []
var _roof: Array[Vector2i] = []
var _shadow_c := Vector2i.ZERO


func _tables() -> void:
	if not _tv.is_empty():
		return
	for t in range(T.size()):
		var row: Array[Vector2i] = []
		for v in range(5):
			row.append(TileArt.coords("t%d_v%d" % [t, v]) if t != T.WALL and t != T.ROOF else Vector2i.ZERO)
		_tv.append(row)
	for m in range(16):
		_water.append(TileArt.coords("water_m%d" % m))
		_fence.append(TileArt.coords("fence_m%d" % m))
	_side = [Vector2i.ZERO]
	for p in range(1, 5):
		_side.append(TileArt.coords("side_p%d" % p))
	for v in range(4):
		_roadh.append(TileArt.coords("roadh_v%d" % v))
		_roadv.append(TileArt.coords("roadv_v%d" % v))
	for v in range(3):
		_wall.append(TileArt.coords("wall_%d" % v))
		_roof.append(TileArt.coords("roof_%d" % v))
	_shadow_c = TileArt.coords("shadow")


func build(world: World) -> void:
	_tables()
	ground.clear()
	shadow.clear()
	walls.clear()
	for ty in range(W):
		for tx in range(W):
			_paint(world, tx, ty)


## One tile, redrawn where it stands. A wall broken open clears the wall layer
## and its shadow and paints the rubble underneath.
func repaint(world: World, tx: int, ty: int) -> void:
	if tx < 0 or ty < 0 or tx >= W or ty >= W:
		return
	_tables()
	var cell := Vector2i(tx, ty)
	ground.erase_cell(cell)
	shadow.erase_cell(cell)
	walls.erase_cell(cell)
	_paint(world, tx, ty)


func _paint(world: World, tx: int, ty: int) -> void:
	var i := ty * W + tx
	var t := world.tiles[i]
	var cell := Vector2i(tx, ty)
	if t == T.WALL or t == T.ROOF:
		var hw := Util.hash2(tx * 3, ty * 7)
		var art := _wall if t == T.WALL else _roof
		walls.set_cell(cell, 0, art[0 if hw <= 0.5 else (1 if hw <= 0.78 else 2)])
		shadow.set_cell(cell, 0, _shadow_c)
		return
	var h := Util.hash2(tx, ty)
	var c: Vector2i
	if t == T.WATER:
		var m := 0
		if world.tile(tx, ty - 1) != T.WATER:
			m |= 1
		if world.tile(tx, ty + 1) != T.WATER:
			m |= 2
		if world.tile(tx - 1, ty) != T.WATER:
			m |= 4
		if world.tile(tx + 1, ty) != T.WATER:
			m |= 8
		c = _water[m]
	elif t == T.FENCE:
		var m := 0
		if world.tile(tx - 1, ty) == T.FENCE:
			m |= 1
		if world.tile(tx + 1, ty) == T.FENCE:
			m |= 2
		if world.tile(tx, ty - 1) == T.FENCE:
			m |= 4
		if world.tile(tx, ty + 1) == T.FENCE:
			m |= 8
		c = _fence[m]
	elif t == T.SIDEWALK and _parapet(world, tx, ty) > 0:
		c = _side[_parapet(world, tx, ty)]
	elif t == T.ROAD and world.mark[i] == 1 and tx % 3 != 2:
		c = _roadh[_variant(t, h)]
	elif t == T.ROAD and world.mark[i] == 2 and ty % 3 != 2:
		c = _roadv[_variant(t, h)]
	else:
		c = _tv[t][_variant(t, h)]
	ground.set_cell(cell, 0, c)


static func _parapet(world: World, tx: int, ty: int) -> int:
	if world.tile(tx, ty - 1) == T.WATER:
		return 1
	if world.tile(tx, ty + 1) == T.WATER:
		return 2
	if world.tile(tx - 1, ty) == T.WATER:
		return 3
	if world.tile(tx + 1, ty) == T.WATER:
		return 4
	return 0


## Which baked variant a tile's hash lands on. Mirrors the prototype's
## thresholds: a detail patch above 0.62, a grass tuft above 0.9, field
## sprouts above 0.45.
static func _variant(t: int, h: float) -> int:
	var v := 0
	if h > 0.62:
		v = 1 + mini(2, int((h - 0.62) / 0.38 * 3.0))
	if t == T.GRASS and h > 0.9:
		v = 4
	elif t == T.FIELD and v == 0 and h > 0.45:
		v = 4
	return v
