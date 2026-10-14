class_name FacadeArt
extends RefCounted
## The building parts' paint. The parts (`tools/build_kit.py` →
## `assets/models/buildings/parts.glb`) are flat-coloured, the Synty way,
## and export their materials by swatch name; the stage swaps each for a
## `facade.gdshader` material that knows whether the swatch is siding, trim
## or roof (then a house's style colours it) or a fixed colour (then
## `PALETTE` does). A style is three colours; a building's is picked by
## `BuildingPlan` from where it stands, and a yard wall has one of its own.

## The script's palette, by name. A part's material name is one of these,
## or starts with `siding`, `trim` or `roof`.
const PALETTE := {
	"siding_white": Color(0.90, 0.88, 0.84), "siding_cream": Color(0.85, 0.78, 0.62),
	"siding_blue": Color(0.60, 0.68, 0.74), "siding_sage": Color(0.65, 0.68, 0.55),
	"siding_grey": Color(0.52, 0.54, 0.52),
	"trim_white": Color(0.94, 0.92, 0.88), "trim_blue": Color(0.30, 0.43, 0.58),
	"trim_green": Color(0.29, 0.42, 0.29), "trim_brown": Color(0.40, 0.29, 0.21),
	"brick": Color(0.53, 0.29, 0.23), "plaster": Color(0.72, 0.69, 0.63), "concrete": Color(0.56, 0.55, 0.52),
	"roof_slate": Color(0.23, 0.24, 0.27), "roof_green": Color(0.31, 0.42, 0.31),
	"roof_terracotta": Color(0.60, 0.31, 0.23), "roof_charcoal": Color(0.18, 0.20, 0.21),
	"glass": Color(0.24, 0.30, 0.36), "door_red": Color(0.56, 0.23, 0.20), "door_blue": Color(0.21, 0.31, 0.48),
	"wood_raw": Color(0.55, 0.42, 0.28), "wood_dark": Color(0.35, 0.26, 0.19),
	"floor_wood": Color(0.48, 0.35, 0.23), "floor_tile_a": Color(0.81, 0.79, 0.74), "floor_tile_b": Color(0.37, 0.35, 0.33),
	"metal": Color(0.42, 0.42, 0.44),
}

## Siding, trim, roof. The last is the yard wall's: a compound's ring,
## concrete all through. `YARD` indexes it.
const STYLES := [
	{"siding": Color(0.90, 0.88, 0.84), "trim": Color(0.30, 0.43, 0.58), "roof": Color(0.23, 0.24, 0.27)},
	{"siding": Color(0.85, 0.78, 0.62), "trim": Color(0.29, 0.42, 0.29), "roof": Color(0.31, 0.42, 0.31)},
	{"siding": Color(0.60, 0.68, 0.74), "trim": Color(0.94, 0.92, 0.88), "roof": Color(0.18, 0.20, 0.21)},
	{"siding": Color(0.65, 0.68, 0.55), "trim": Color(0.40, 0.29, 0.21), "roof": Color(0.60, 0.31, 0.23)},
	{"siding": Color(0.52, 0.54, 0.52), "trim": Color(0.94, 0.92, 0.88), "roof": Color(0.23, 0.24, 0.27)},
	{"siding": Color(0.56, 0.55, 0.52), "trim": Color(0.42, 0.42, 0.44), "roof": Color(0.42, 0.42, 0.44)},
]
const YARD := 5
## How many styles a building can draw (the yard's is not one of them).
const HOUSE_STYLES := 5

## What a built wall is made of, by structure type: the siding tint and the
## trim tint of the same panels a house uses.
const BUILT := {
	"woodWall": {"siding": "wood_raw", "trim": "wood_dark"},
	"stoneWall": {"siding": "concrete", "trim": "metal"},
	"reinforcedWall": {"siding": "metal", "trim": "wood_dark"},
	"metalWall": {"siding": "metal", "trim": "metal"},
}

static var _mats := {}
static var _shader: Shader


## The shader's part for a material name.
static func part_of(name: String) -> int:
	if name.begins_with("siding"):
		return 0
	if name.begins_with("trim"):
		return 2
	if name.begins_with("roof"):
		return 5
	return 1


## The material for a part in a MultiMesh: its colours come per instance
## (`custom_for`). One per material name, shared.
static func instanced(name: String) -> ShaderMaterial:
	var key := "i:" + name
	if not _mats.has(key):
		var m := _material(name)
		m.resource_name = name
		m.set_shader_parameter("per_instance", true)
		_mats[key] = m
	return _mats[key]


## The material for a one-off mesh (a roof) in a given style.
static func styled(name: String, style: int) -> ShaderMaterial:
	var s: Dictionary = STYLES[style % STYLES.size()]
	var p := part_of(name)
	return tinted(name, s.roof if p == 5 else (s.trim if p == 2 else s.siding))


## The material for a one-off mesh with its own colour (a built wall).
static func tinted(name: String, color: Color) -> ShaderMaterial:
	var key := "t:%s:%s" % [name, color.to_html(false)]
	if not _mats.has(key):
		var m := _material(name)
		m.set_shader_parameter("tint", color)
		_mats[key] = m
	return _mats[key]


## What a MultiMesh instance carries for the shader: its style's index.
static func custom_for(style: int) -> Color:
	return Color(float(style % STYLES.size()), 0.0, 0.0, 0.0)


static func _material(name: String) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://src/stage/shaders/facade.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("part", part_of(name))
	m.set_shader_parameter("flat_color", PALETTE.get(name, PALETTE.plaster))
	for which in ["siding", "trim", "roof"]:
		var table := PackedColorArray()
		for s: Dictionary in STYLES:
			table.append((s[which] as Color).srgb_to_linear())
		while table.size() < 8:
			table.append(Color.WHITE)
		m.set_shader_parameter(which + "s", table)
	return m
