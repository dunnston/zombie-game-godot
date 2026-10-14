@tool
class_name LayoutScene
extends Node3D
## A layout laid out by hand in the Godot editor (2026-10-14): the root of
## a scene in `scenes/layouts/`. Walls, floor and doorways are painted on
## the `Tiles` GridMap (one tile a metre: wall, floor, doorway, opening);
## pieces are `LayoutProp` children dragged in from `scenes/layouts/palette/`
## and moved where they belong. **Export** turns the scene into a row of
## `data/layouts.json` (`LayoutFile`), checks it (`Layout.problems`,
## `Layout.playable`) and says what it found in `report`; **Check** does
## the checks without writing; **Load** fills the scene from the row named
## `layout_id`, to tweak one that exists. `tools\lab.cmd <layout_id>` then
## walks it. The scene is the thing you edit; the row is what the game
## stamps, and the two are the same by construction.

## GridMap item ids in `Tiles`' library, by map character.
const ITEMS := {Layout.WALL: 0, Layout.FLOOR: 1, Layout.DOOR: 2, Layout.GAP: 3}
const ITEM_NAMES := {0: "wall", 1: "floor", 2: "doorway", 3: "opening"}

@export var layout_id := "":
	set(v):
		layout_id = v
@export_enum("house", "farm", "shack", "cabin", "apartment", "store", "office", "other") var use := "house"
@export_enum("wood", "tile", "dirt", "gravel") var floor_kind := "wood"
@export_multiline var report := ""
@export_tool_button("Export to data/layouts.json", "Save") var export_button: Callable = export_row
@export_tool_button("Check without writing", "Search") var check_button: Callable = check
@export_tool_button("Load layout_id from data", "Load") var load_button: Callable = load_row


func tiles() -> GridMap:
	var g := get_node_or_null("Tiles") as GridMap
	if g == null:
		g = GridMap.new()
		g.name = "Tiles"
		g.cell_size = Vector3.ONE
		add_child(g)
		if is_inside_tree() and get_tree().edited_scene_root != null:
			g.owner = get_tree().edited_scene_root
	if g.mesh_library == null:
		g.mesh_library = library()
	return g


func props() -> Array[LayoutProp]:
	var out: Array[LayoutProp] = []
	for c in get_children():
		if c is LayoutProp:
			out.append(c)
	return out


## The row the scene describes. The map is the painted cells' rectangle,
## grown to take in any piece standing on the grass outside; a thing's
## tile is relative to that rectangle's top-left.
func row() -> Dictionary:
	var g := tiles()
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	var cells := {}
	for c: Vector3i in g.get_used_cells():
		var t := Vector2i(c.x, c.z)
		cells[t] = g.get_cell_item(c)
		lo = Vector2i(mini(lo.x, t.x), mini(lo.y, t.y))
		hi = Vector2i(maxi(hi.x, t.x), maxi(hi.y, t.y))
	for p in props():
		var f := Layout.footprint({"x": p.tile().x, "y": p.tile().y, "w": p.size().x, "h": p.size().y, "d": p.facing()})
		lo = Vector2i(mini(lo.x, f.position.x), mini(lo.y, f.position.y))
		hi = Vector2i(maxi(hi.x, f.end.x - 1), maxi(hi.y, f.end.y - 1))
	var out := {"id": layout_id, "use": use, "floor": floor_kind, "map": [], "things": []}
	if cells.is_empty():
		return out
	for y in range(lo.y, hi.y + 1):
		var line := ""
		for x in range(lo.x, hi.x + 1):
			var item: int = cells.get(Vector2i(x, y), -1)
			var ch := Layout.OUT
			for k in ITEMS:
				if ITEMS[k] == item:
					ch = k
			line += ch
		out.map.append(line)
	for p in props():
		var t := p.tile() - lo
		var outside := not cells.has(p.tile())
		out.things.append(p.entry(lo, outside))
	return out


## Writes the row and reports. The game sees it at once (`LayoutFile.refresh`).
func export_row() -> void:
	var r := row()
	if String(r.id).is_empty():
		report = "Give the layout an id first (layout_id in the inspector)."
		push_warning(report)
		return
	var problems := Layout.problems(r)
	r["notes"] = "Laid out in the Godot editor (scenes/layouts/%s.tscn) on %s." % [r.id, Time.get_date_string_from_system()]
	LayoutFile.write(r)
	LayoutFile.refresh()
	report = _report(r, problems)
	print(report)


func check() -> void:
	var r := row()
	report = _report(r, Layout.problems(r))
	print(report)


func _report(r: Dictionary, problems: PackedStringArray) -> String:
	var lines := PackedStringArray()
	lines.append("%s: %d x %d tiles, %d things" % [r.id, Layout.size(r).x, Layout.size(r).y, r.things.size()])
	for p in problems:
		lines.append("PROBLEM: " + p)
	if problems.is_empty():
		var ok := LayoutFile.playable(r)
		lines.append("playable: every room reachable, every piece searchable" if ok else "NOT PLAYABLE: a piece seals a room or a container has no free tile beside it")
	else:
		lines.append("(fix the problems above, then Check again)")
	lines.append("")
	for line in r.map:
		lines.append(line)
	return "\n".join(lines)


## Fills the scene from the row called `layout_id`: the tiles painted, a
## LayoutProp per thing, everything owned by the scene so it saves.
func load_row() -> void:
	var r := LayoutFile.read(layout_id)
	if r.is_empty():
		report = "No layout called '%s' in %s." % [layout_id, LayoutFile.PATH]
		push_warning(report)
		return
	fill(r)
	report = "Loaded %s: %d x %d tiles, %d things." % [layout_id, Layout.size(r).x, Layout.size(r).y, r.things.size()]
	print(report)


func fill(r: Dictionary) -> void:
	use = String(r.get("use", "house"))
	floor_kind = String(r.get("floor", "wood"))
	var g := tiles()
	g.clear()
	for p in props():
		remove_child(p)
		p.queue_free()
	var sz := Layout.size(r)
	for y in range(sz.y):
		for x in range(sz.x):
			var ch := Layout.at(r, x, y)
			if ITEMS.has(ch):
				g.set_cell_item(Vector3i(x, 0, y), ITEMS[ch])
	var root: Node = get_tree().edited_scene_root if is_inside_tree() and get_tree().edited_scene_root != null else self
	for t in r.get("things", []):
		var p := LayoutProp.new()
		p.kind = String(t.get("container", t.get("what", "")))
		p.name = p.kind
		add_child(p, true)
		p.owner = root
		p.place(Vector2i(int(t.x), int(t.y)), int(t.get("d", 0)))


## The four tiles the GridMap paints with: a wall a storey tall, a floor
## slab, a doorway (a floor slab marked green) and an opening (marked
## pale). Blocks, not the kit: this is for laying out, the lab shows the
## real thing. Saved to `scenes/layouts/tiles.tres` by `tools/make_layout_palette`.
static func library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var wall_h: float = Config.STAGE3D.wall_h
	_item(lib, 0, "wall", Vector3(1.0, wall_h, 1.0), Color(0.82, 0.8, 0.76), wall_h / 2.0)
	_item(lib, 1, "floor", Vector3(1.0, 0.05, 1.0), Color(0.45, 0.33, 0.22), 0.025)
	_item(lib, 2, "doorway", Vector3(1.0, 0.05, 1.0), Color(0.35, 0.7, 0.35), 0.025)
	_item(lib, 3, "opening", Vector3(1.0, 0.05, 1.0), Color(0.72, 0.6, 0.45), 0.025)
	return lib


static func _item(lib: MeshLibrary, id: int, name: String, size: Vector3, color: Color, y: float) -> void:
	lib.create_item(id)
	lib.set_item_name(id, name)
	var box := BoxMesh.new()
	box.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	box.material = mat
	lib.set_item_mesh(id, box)
	# A GridMap stands a mesh at its cell's centre; the box wants its foot on
	# the ground.
	lib.set_item_mesh_transform(id, Transform3D(Basis.IDENTITY, Vector3(0.0, y - 0.5, 0.0)))
