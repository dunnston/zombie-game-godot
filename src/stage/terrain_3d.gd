class_name Terrain3D
extends Node3D
## The town, standing up. The ground is one quad over the whole world whose
## shader looks every tile up in a cell texture (`shaders/ground.gdshader`);
## roof blocks (a building you cannot enter, the dark around an instance's
## rooms) and fences are one MultiMesh of boxes topped with the same atlas
## art (`shaders/block.gdshader`). Both read the tile's picture from
## `TerrainRenderer.cell_art`, so this is the 2D town's picture with height.
## House walls are `Buildings3D`'s, dressed with the building kit.
##
## Built once from the sim's tiles; `repaint` changes one tile (a house wall
## broken open) without touching the rest, exactly as the 2D layers do.

const W := Config.WORLD_TILES
const T = Config.T

var ground: MeshInstance3D
var blocks: MultiMeshInstance3D
var _cells: Image
var _cells_tex: ImageTexture
var _ground_mat: ShaderMaterial
var _block_mat: ShaderMaterial
## Tile index -> instance index in the block MultiMesh.
var _block_of := {}


func _init() -> void:
	var atlas := TileArt.texture()
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://src/stage/shaders/ground.gdshader")
	_ground_mat.set_shader_parameter("atlas", atlas)
	_ground_mat.set_shader_parameter("atlas_cells", TileArt.atlas_cells())
	_ground_mat.set_shader_parameter("tiles", float(W))
	_block_mat = ShaderMaterial.new()
	_block_mat.shader = load("res://src/stage/shaders/block.gdshader")
	_block_mat.set_shader_parameter("atlas", atlas)
	_block_mat.set_shader_parameter("atlas_cells", TileArt.atlas_cells())

	var plane := PlaneMesh.new()
	plane.size = Vector2(W, W)
	plane.material = _ground_mat
	ground = MeshInstance3D.new()
	ground.mesh = plane
	ground.position = Vector3(W / 2.0, 0.0, W / 2.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _block_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = box
	blocks = MultiMeshInstance3D.new()
	blocks.multimesh = mm
	add_child(blocks)


func build(world: World) -> void:
	var data := PackedByteArray()
	data.resize(W * W * 2)
	var standing: Array[Vector3i] = []   # tx, ty, tile index
	var S := Config.STAGE3D
	for ty in range(W):
		for tx in range(W):
			var i := ty * W + tx
			var art := TerrainRenderer.cell_art(world, tx, ty)
			var c: Vector2i = _ground_cell(world, tx, ty, art)
			data[i * 2] = c.x
			data[i * 2 + 1] = c.y
			if art.t == T.ROOF or art.t == T.FENCE:
				standing.append(Vector3i(tx, ty, i))
	_cells = Image.create_from_data(W, W, false, Image.FORMAT_RG8, data)
	_cells_tex = ImageTexture.create_from_image(_cells)
	_ground_mat.set_shader_parameter("cells", _cells_tex)

	var mm := blocks.multimesh
	_block_of.clear()
	mm.instance_count = standing.size()
	for n in range(standing.size()):
		var s := standing[n]
		_block_of[s.z] = n
		_place_block(world, n, s.x, s.y)
	# A MultiMesh's bounds are its mesh's unless told: without this the town's
	# walls are culled whenever the unit box at the origin leaves the view.
	mm.custom_aabb = AABB(Vector3(0, 0, 0), Vector3(W, float(S.roof_h) + 0.1, W))


## One tile, redrawn where it stands. A wall broken open becomes ground, and
## its block goes flat; nothing else is touched.
func repaint(world: World, tx: int, ty: int) -> void:
	if tx < 0 or ty < 0 or tx >= W or ty >= W or _cells == null:
		return
	var i := ty * W + tx
	var art := TerrainRenderer.cell_art(world, tx, ty)
	var c: Vector2i = _ground_cell(world, tx, ty, art)
	_cells.set_pixel(tx, ty, Color8(c.x, c.y, 0))
	_cells_tex.update(_cells)
	if _block_of.has(i):
		if art.t == T.ROOF or art.t == T.FENCE:
			_place_block(world, int(_block_of[i]), tx, ty)
		else:
			blocks.multimesh.set_instance_transform(int(_block_of[i]), Transform3D(Basis().scaled(Vector3.ZERO), Vector3(tx + 0.5, -1.0, ty + 0.5)))


## The ground under a tile. A house wall is a thin panel on its tile's outer
## edge now (`Buildings3D`), so the tile under it shows: it takes the floor
## beside it, and the room runs to the wall.
static func _ground_cell(world: World, tx: int, ty: int, art: Dictionary) -> Vector2i:
	if int(art.t) != T.WALL:
		return art.cell
	for d: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
		var n := world.tile(tx + d.x, ty + d.y)
		if n in [T.FLOOR_WOOD, T.FLOOR_TILE, T.DIRT, T.GRAVEL, T.LOT]:
			return TerrainRenderer.cell_art(world, tx + d.x, ty + d.y).cell
	return art.cell


func _place_block(world: World, n: int, tx: int, ty: int) -> void:
	var art := TerrainRenderer.cell_art(world, tx, ty)
	var S := Config.STAGE3D
	var h: float
	match int(art.t):
		T.ROOF:
			h = float(S.roof_h)
		T.FENCE:
			h = float(S.fence_h)
		_:
			h = float(S.wall_h)
	var mm := blocks.multimesh
	mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3(1.0, h, 1.0)), Vector3(tx + 0.5, h / 2.0, ty + 0.5)))
	var c: Vector2i = art.cell
	mm.set_instance_custom_data(n, Color(c.x, c.y, 0.0, 0.0))
