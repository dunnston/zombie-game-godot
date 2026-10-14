class_name LayoutFile
extends RefCounted
## The one reader and writer of `data/layouts.json` for the tools that make
## layouts: the scene editor (`LayoutScene`) and the plan importer
## (`tools/import_layout.gd`). Every write goes through `DataTable.encode`,
## the only thing allowed to write a table (PROJECT.md §10); a first write
## makes the table with its schema. `reload` is how a tool that just wrote
## a row makes the game see it (`Config.LAYOUTS` loads once, at boot).

const TABLE := "layouts"
const PATH := DataTable.DIR + TABLE + ".json"

## The table as a new file is born: the schema, no rows. A field named here
## is what a row may carry; see `Layout` for what each means.
const SCHEMA := {
	"fields": {
		"use": {"type": "string"},
		"floor": {"type": "string", "one_of": ["wood", "tile", "dirt", "gravel"]},
		"map": {"type": "list<string>"},
		"things": {"type": "list<object>", "fields": {
			"what": {"type": "string"},
			"container": {"type": "string", "ref": "CONTAINERS"},
			"kind": {"type": "string"},
			"x": {"type": "int"},
			"y": {"type": "int"},
			"w": {"type": "int"},
			"h": {"type": "int"},
			"d": {"type": "int"},
			"solid": {"type": "bool"},
		}},
	},
	"notes": "Hand-laid buildings (Layout). `map` is one string per row of tiles: # wall, . floor, + a doorway in the outer wall, - an opening in a partition, space for nothing. A thing is its top-left tile `x`,`y` in the map, `w` across its face and `h` deep in tiles, `d` the way it faces in quarter turns from south (0 S, 1 E, 2 N, 3 W); `container` makes it a searchable container of that kind, `kind` \"wall\" hangs it on a wall tile facing the room, \"yard\" stands it on the grass outside, `solid` false lets you walk over it. Rows are made in the Godot editor (scenes/layouts, LayoutScene) or by tools/import_layout from a plan in metres, and looked at in the lab (tools/lab) before the town stamps them.",
	"rows": [],
	"shape": "by_id",
}


## The whole document, decoded, or the schema when there is no file yet.
static func document() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return SCHEMA.duplicate(true)
	var got := DataTable.decode(FileAccess.get_file_as_string(PATH))
	for e in got.errors:
		push_error("%s: %s" % [PATH, e])
	return got.doc


## One row, fresh from the file (not the copy the game loaded at boot), or
## empty when there is none by that id.
static func read(id: String) -> Dictionary:
	for row in document().get("rows", []):
		if row.get("id") == id:
			return row
	return {}


## The row into the table, replacing one with its id, through the encoder.
static func write(row: Dictionary) -> void:
	var doc := document()
	var rows: Array = doc.rows
	var placed := false
	for i in range(rows.size()):
		if rows[i].get("id") == row.id:
			rows[i] = row
			placed = true
	if not placed:
		rows.append(row)
	save(doc)


static func save(doc: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DataTable.DIR))
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(DataTable.encode(doc))
	f.close()


## Makes the game see the file as it is now. (Not `reload`: every script
## object has Godot's own `reload()`, and `LayoutFile.reload()` called that
## and quietly did nothing of ours.)
static func refresh() -> void:
	Config.LAYOUTS = DataTable.load_table(TABLE)


## Whether a stamped copy of `row` is playable (`Layout.playable`): the row
## is put in the table the game reads, a lab world is built on it, and the
## table is put back.
static func playable(row: Dictionary) -> bool:
	var was: Dictionary = Config.LAYOUTS
	var table := was.duplicate()
	table[row.id] = row
	Config.LAYOUTS = table
	var world := World.new(1, "lab:" + String(row.id))
	Config.LAYOUTS = was
	return not world.buildings.is_empty() and Layout.playable(world, world.buildings[0])
