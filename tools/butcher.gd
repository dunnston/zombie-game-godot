extends SceneTree
## One-shot content write for chapter 1's boss (progression step E,
## `tasks/progression-plan.md` §6), run headless:
##
##   godot --headless --path . -s tools/butcher.gd
##
## The Butcher's body (ENEMIES), the Butcher's Saw (a boss item, CONSUMABLES),
## and what it drops besides (LOOT). The fight is `Config.BOSSES.butcher`; the
## barn is `Config.INSTANCES.barn` and `World._gen_barn`. Through
## `DataTable.encode`, the only thing allowed to write a table.

const ENEMY := {
	"id": "butcher", "name": "The Butcher", "boss": true,
	"hp": 700.0, "dmg": 20.0, "speed": 62.0, "r": 22.0, "sense": 900.0,
	"atk_cd": 1.3, "atk_range": 40.0, "knock_resist": 0.9, "struct_mul": 3.0, "threat": 2.0, "xp": 250,
	"body": "#7a4a3a", "dark": "#452a22", "loot_table": "butcherDrops",
	"notes": "Chapter 1's boss (step E), in the barn at Hollow Creek Farms. A placeholder name the owner can change here. What it does is `Config.BOSSES.butcher`: this row is only its body. Half the Coach's health: the first boss is the one that teaches you that bosses exist.",
}

const SAW := {
	"id": "butcherSaw", "name": "Butcher's Saw", "color": "#c8c0b0", "stack": 1, "wt": 0.0, "time": 0.0,
	"tool": true, "verb": "Keep",
	"notes": "A boss item (step E): what Workbench II is upgraded with. Never lost — once it has been in anyone's pack the run knows it (`Discovery`, \"key:butcherSaw\"), whatever happens to the object. Weightless and unusable: it is a fact wearing an item's icon.",
}

const DROPS := {
	"id": "butcherDrops",
	"entries": [
		{"id": "rations", "min": 3, "max": 6, "w": 80},
		{"id": "scrap", "min": 6, "max": 12, "w": 70},
		{"id": "item:medkit", "min": 1, "max": 1, "w": 40},
		{"id": "cloth", "min": 4, "max": 8, "w": 60},
	],
	"notes": "What the Butcher drops besides the Saw and, on the first kill, the Cleaver — both of those are `Config.BOSSES.butcher.first_drop`, given once and never rolled. **For a boss, `w` is a percentage and every entry rolls on its own.**",
}


func _init() -> void:
	_row("res://data/enemies.json", ENEMY)
	_row("res://data/consumables.json", SAW)
	_row("res://data/loot.json", DROPS)
	quit()


func _row(path: String, row: Dictionary) -> void:
	var got := DataTable.decode(FileAccess.get_file_as_string(path))
	for e: String in got.errors:
		push_error("%s: %s" % [path, e])
	var doc: Dictionary = got.doc
	for r: Dictionary in doc.rows:
		if String(r.id) == String(row.id):
			print("%s: %s already there" % [path, row.id])
			return
	doc.rows.append(row.duplicate(true))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(DataTable.encode(doc))
	f.close()
	print("%s: %s added" % [path, row.id])
