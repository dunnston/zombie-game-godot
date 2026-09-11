class_name TileArt
extends RefCounted
## The terrain atlas, generated in code at boot. Every ground tile in the
## prototype was drawn with rectangles, so an Image and fill_rect reproduce
## the look exactly. Variants bake the per-tile hash detail; neighbour-aware
## tiles (water lips, fence rails, bridge parapets, road markings) are keyed
## by a bitmask the renderer computes.

const TILE := 32
const COLS := 16
const T = Config.T

static var _tileset: TileSet
static var _coords := {}


static func tileset() -> TileSet:
	if _tileset == null:
		_build()
	return _tileset


static func coords(key: String) -> Vector2i:
	if _tileset == null:
		_build()
	return _coords[key]


static func _build() -> void:
	var keys: Array[String] = []
	for t in range(T.size()):
		# Walls and roofs are drawn on the wall layer from art of their own.
		if t == T.WALL or t == T.ROOF:
			continue
		for v in range(5):
			keys.append("t%d_v%d" % [t, v])
	for m in range(16):
		keys.append("water_m%d" % m)
	for m in range(16):
		keys.append("fence_m%d" % m)
	for p in range(1, 5):
		keys.append("side_p%d" % p)
	for v in range(4):
		keys.append("roadh_v%d" % v)
		keys.append("roadv_v%d" % v)
	for v in range(3):
		keys.append("wall_%d" % v)
	for v in range(3):
		keys.append("roof_%d" % v)
	keys.append("shadow")

	var rows := ceili(keys.size() / float(COLS))
	var img := Image.create(COLS * TILE, rows * TILE, false, Image.FORMAT_RGBA8)
	for i in range(keys.size()):
		var c := Vector2i(i % COLS, floori(i / float(COLS)))
		_coords[keys[i]] = c
		_paint(img, c.x * TILE, c.y * TILE, keys[i])

	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for key in keys:
		src.create_tile(_coords[key])
	_tileset = TileSet.new()
	_tileset.tile_size = Vector2i(TILE, TILE)
	_tileset.add_source(src, 0)


## A rectangle in tile-local coordinates, clipped to the tile, alpha-blended.
static func _rect(img: Image, ox: int, oy: int, x: int, y: int, w: int, h: int, c: Color) -> void:
	var x0 := maxi(0, x)
	var y0 := maxi(0, y)
	var x1 := mini(TILE, x + w)
	var y1 := mini(TILE, y + h)
	if x1 <= x0 or y1 <= y0:
		return
	if c.a >= 1.0:
		img.fill_rect(Rect2i(ox + x0, oy + y0, x1 - x0, y1 - y0), c)
		return
	for j in range(y0, y1):
		for i in range(x0, x1):
			var p := img.get_pixel(ox + i, oy + j)
			img.set_pixel(ox + i, oy + j, p.blend(c))


static func _paint(img: Image, ox: int, oy: int, key: String) -> void:
	var parts := key.split("_")
	match parts[0]:
		"shadow":
			_rect(img, ox, oy, 0, 0, TILE, TILE, Color(0, 0, 0, 0.333))
		"wall":
			var v := int(parts[1])
			_rect(img, ox, oy, 0, 0, TILE, TILE, Color("#655c51") if v == 0 else Color("#5f564c"))
			_rect(img, ox, oy, 0, 0, TILE, 4, Color("#7a7064"))
			_rect(img, ox, oy, 0, TILE - 4, TILE, 4, Color("#00000033"))
			if v == 2:
				_rect(img, ox, oy, 6, 10, 12, 7, Color("#4a4238"))
		"roof":
			# Slate, in shingle courses, darker than any wall: a building you
			# cannot walk into has to read as one from across the street
			# (pillar 4), and a wall-coloured block reads as rubble.
			var v := int(parts[1])
			var base: Color = Config.TERRAIN[T.ROOF].a
			_rect(img, ox, oy, 0, 0, TILE, TILE, base if v != 1 else base.lightened(0.05))
			for r in range(0, TILE, 8):
				_rect(img, ox, oy, 0, r, TILE, 2, Color("#23262b"))
				var off := 8 if (r / 8) % 2 == 0 else 0
				for x in range(off, TILE, 16):
					_rect(img, ox, oy, x, r, 2, 8, Color("#2a2d32"))
			if v == 2:
				_rect(img, ox, oy, 10, 12, 8, 6, Color("#4a4f57"))
		"water":
			# bit 1 up, 2 down, 4 left, 8 right: a pale lip where water meets land.
			var m := int(parts[1].substr(1))
			_rect(img, ox, oy, 0, 0, TILE, TILE, Config.TERRAIN[T.WATER].a)
			_rect(img, ox, oy, 4, 10, 12, 2, Color("#3a5c7288"))
			var lip := Color("#6d8fa055")
			if (m & 1) != 0:
				_rect(img, ox, oy, 0, 0, TILE, 3, lip)
			if (m & 2) != 0:
				_rect(img, ox, oy, 0, TILE - 3, TILE, 3, lip)
			if (m & 4) != 0:
				_rect(img, ox, oy, 0, 0, 3, TILE, lip)
			if (m & 8) != 0:
				_rect(img, ox, oy, TILE - 3, 0, 3, TILE, lip)
		"fence":
			# bit 1 left, 2 right, 4 up, 8 down: rails run toward fence neighbours.
			var m := int(parts[1].substr(1))
			_rect(img, ox, oy, 0, 0, TILE, TILE, Config.TERRAIN[T.GRASS].a)
			var l := (m & 1) != 0
			var r := (m & 2) != 0
			var u := (m & 4) != 0
			var d := (m & 8) != 0
			var rail := Color("#6b4e2e")
			if l or r:
				var x0 := 0 if l else 12
				var x1 := TILE if r else 20
				_rect(img, ox, oy, x0, 10, x1 - x0, 3, rail)
				_rect(img, ox, oy, x0, 19, x1 - x0, 3, rail)
			if u or d:
				var y0 := 0 if u else 12
				var y1 := TILE if d else 20
				_rect(img, ox, oy, 10, y0, 3, y1 - y0, rail)
				_rect(img, ox, oy, 19, y0, 3, y1 - y0, rail)
			_rect(img, ox, oy, 13, 11, 6, 12, Color("#4a3420"))
		"side":
			# A sidewalk beside water is a bridge parapet: 1 up, 2 down, 3 left, 4 right.
			var p := int(parts[1].substr(1))
			_rect(img, ox, oy, 0, 0, TILE, TILE, Config.TERRAIN[T.SIDEWALK].a)
			var par := Color("#8a8478")
			var post := Color("#5a554c")
			if p == 1:
				_rect(img, ox, oy, 0, 0, TILE, 4, par)
				_rect(img, ox, oy, 4, 0, 3, 8, post)
				_rect(img, ox, oy, 24, 0, 3, 8, post)
			elif p == 2:
				_rect(img, ox, oy, 0, TILE - 4, TILE, 4, par)
				_rect(img, ox, oy, 4, TILE - 8, 3, 8, post)
				_rect(img, ox, oy, 24, TILE - 8, 3, 8, post)
			elif p == 3:
				_rect(img, ox, oy, 0, 0, 4, TILE, par)
			else:
				_rect(img, ox, oy, TILE - 4, 0, 4, TILE, par)
		"roadh", "roadv":
			var v := int(parts[1].substr(1))
			_terrain(img, ox, oy, T.ROAD, v)
			var mk := Color("#b8a44a55")
			if parts[0] == "roadh":
				_rect(img, ox, oy, 4, 14, 20, 3, mk)
			else:
				_rect(img, ox, oy, 14, 4, 3, 20, mk)
		_:
			var t := int(parts[0].substr(1))
			var v := int(parts[1].substr(1))
			_terrain(img, ox, oy, t, v)


## Base colour plus the hash-driven detail. Variants 1-3 carry a detail patch
## at three representative hash values; 4 is the terrain's special (a grass
## tuft, field sprouts without a patch).
static func _terrain(img: Image, ox: int, oy: int, t: int, v: int) -> void:
	var pal: Dictionary = Config.TERRAIN[t]
	_rect(img, ox, oy, 0, 0, TILE, TILE, pal.a)
	var h := 0.0
	if v >= 1 and v <= 3:
		h = 0.62 + (v - 0.5) * (0.38 / 3.0)
	elif v == 4:
		h = 0.95 if t == T.GRASS else 0.5
	if h > 0.62:
		var s := 6.0 + h * 14.0
		var px := fmod(h * 97.0, TILE - s)
		var py := fmod(h * 53.0, TILE - s)
		_rect(img, ox, oy, roundi(px), roundi(py), roundi(s), roundi(s), pal.b)
	if t == T.FIELD:
		for r in range(4, TILE, 8):
			_rect(img, ox, oy, 0, r, TILE, 3, Color("#3b2c1c"))
		if h > 0.45:
			var sprout := Color("#6a8a3a")
			_rect(img, ox, oy, 6 + int(fmod(h * 41.0, 16.0)), 8, 2, 3, sprout)
			_rect(img, ox, oy, 14 + int(fmod(h * 73.0, 12.0)), 16, 2, 3, sprout)
	if t == T.GRASS and h > 0.9:
		var tuft := Color("#4a5c3399")
		_rect(img, ox, oy, 12, 12, 2, 5, tuft)
		_rect(img, ox, oy, 17, 14, 2, 4, tuft)
