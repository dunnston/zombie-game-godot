class_name FacadeArt
extends RefCounted
## The building kit's paint: the siding, brick and shingle textures, painted
## in code at boot as `TileArt` paints the ground, and the materials the
## stage puts on the kit's pieces in place of the names Blender exported
## (`tools/build_kit.py`). A house's look is a style: a siding colour, a trim
## colour and a roof colour, chosen by where it stands; the siding and
## shingle textures are painted grey and tinted, so every style shares them.
##
## Textures are 128 px to the metre and tile per metre (brick per half
## metre), which is what the kit's UVs count in. Nearest-filtered: the
## bible wants flat paint, not blur.

const PX := 128

## Siding, trim, roof — the bible's weathered clapboard town. Styles are
## picked by `BuildingPlan` with a hash of the building's corner.
const STYLES := [
	{"siding": Color("#d9c9a3"), "trim": Color("#4f6f94"), "roof": Color("#3a3d44")},
	{"siding": Color("#e3dfd3"), "trim": Color("#4c6b4a"), "roof": Color("#4f6a4e")},
	{"siding": Color("#9fb2bf"), "trim": Color("#e8e3d8"), "roof": Color("#2f3236")},
	{"siding": Color("#a9b08e"), "trim": Color("#6a4b35"), "roof": Color("#9a4e3a")},
	{"siding": Color("#dccb8a"), "trim": Color("#5a6a78"), "roof": Color("#44474f")},
]
const PLASTER := Color("#b9b0a1")
const GLASS := Color("#3c4a58")

## Material name (as the kit exports it) -> the shader's part.
const PARTS := {"siding": 0, "brick": 1, "trim": 2, "glass": 3, "plaster": 4, "shingle": 5}

static var _tex := {}
static var _mats := {}
static var _shader: Shader


## The texture a part samples, painted once.
static func texture(part: String) -> Texture2D:
	if not _tex.has(part):
		var img: Image
		match part:
			"siding":
				img = _siding()
			"brick":
				img = _brick()
			"shingle":
				img = _shingle()
			_:
				return null
		_tex[part] = ImageTexture.create_from_image(img)
	return _tex[part]


## The material for a kit piece in a MultiMesh: its colours come per
## instance (`custom_for`). One per material name, shared.
static func instanced(name: String) -> ShaderMaterial:
	var key := "i:" + name
	if not _mats.has(key):
		var m := _material(name)
		m.set_shader_parameter("per_instance", true)
		_mats[key] = m
	return _mats[key]


## The material for a one-off mesh (a roof) in a given style.
static func styled(name: String, style: int) -> ShaderMaterial:
	var key := "s:%s:%d" % [name, style]
	if not _mats.has(key):
		var m := _material(name)
		var s: Dictionary = STYLES[style % STYLES.size()]
		m.set_shader_parameter("tint", s.roof if name == "shingle" else (s.trim if name == "trim" else s.siding))
		_mats[key] = m
	return _mats[key]


## What a MultiMesh instance carries for the shader: the siding colour
## (linear, since INSTANCE_CUSTOM is raw floats) and the trim index.
static func custom_for(style: int) -> Color:
	var i := style % STYLES.size()
	var c: Color = (STYLES[i].siding as Color).srgb_to_linear()
	return Color(c.r, c.g, c.b, float(i))


static func _material(name: String) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://src/stage/shaders/facade.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("part", int(PARTS.get(name, 4)))
	var t := texture(name)
	if t != null:
		m.set_shader_parameter("tex", t)
	m.set_shader_parameter("flat_color", GLASS if name == "glass" else PLASTER)
	var trims := PackedColorArray()
	for s: Dictionary in STYLES:
		trims.append((s.trim as Color).srgb_to_linear())
	while trims.size() < 8:
		trims.append(Color.WHITE)
	m.set_shader_parameter("trims", trims)
	return m


## Clapboard: five courses to the metre, a shadow under each board's lip, a
## lighter line along its top, a little grime. Grey: the house tints it.
static func _siding() -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGB8)
	var course := PX / 5
	for y in range(PX):
		var in_course := y % course
		var board := y / course
		for x in range(PX):
			var v := 0.93
			var h := Util.hash2(x, y)
			if in_course >= course - 3:
				v = 0.66 + 0.04 * (in_course - (course - 3))
			elif in_course == 0:
				v = 1.0
			else:
				v += (Util.hash2(board, x / 16) - 0.5) * 0.05
			if h < 0.02:
				v -= 0.15
			elif h < 0.035:
				v -= 0.06
			img.set_pixel(x, y, Color(v, v, v))
	return img


## Brick, its own colour: eight courses to the half metre, mortar a pale
## line, every brick a shade of its own, the odd one darker.
static func _brick() -> Image:
	var img := Image.create(PX, PX / 2, false, Image.FORMAT_RGB8)
	var course := 8
	var length := 32
	var base := Color("#8a4a3c")
	var mortar := Color("#a79a88")
	for y in range(PX / 2):
		var row := y / course
		var off := (length / 2) if row % 2 == 1 else 0
		for x in range(PX):
			var bx := (x + off) % length
			var brick := (x + off) / length + row * 7
			var c := mortar
			if y % course != course - 1 and bx != length - 1:
				var hv := Util.hash2(brick, row)
				c = base.lightened(0.18 * (hv - 0.5))
				if hv > 0.9:
					c = c.darkened(0.25)
				if Util.hash2(x, y) < 0.03:
					c = c.darkened(0.12)
			img.set_pixel(x, y, c)
	return img


## Shingles: eight courses to the metre, a dark line under each, the gaps
## between shingles staggered course by course. Grey: the roof tints it.
static func _shingle() -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGB8)
	var course := PX / 8
	var width := PX / 4
	for y in range(PX):
		var row := y / course
		var off := (width / 2) if row % 2 == 1 else 0
		for x in range(PX):
			var sx := (x + off) % width
			var v := 0.95 + (Util.hash2((x + off) / width, row) - 0.5) * 0.12
			if y % course >= course - 3:
				v = 0.55
			elif sx < 2:
				v = 0.62
			img.set_pixel(x, y, Color(v, v, v))
	return img
