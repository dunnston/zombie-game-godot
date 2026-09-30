extends SceneTree
## One-shot content write for the workbench ladder (progression step C,
## `tasks/progression-plan.md`), run headless:
##
##   godot --headless --path . -s tools/ladder.gd
##
## Moves every recipe and buildable to the bench tier its chapter gives it,
## and adds the recipes the chapters were missing: the three Riot pieces
## nothing could make, the four Military pieces, and the Marksman Rifle, Maul
## and Katana that were loot-only. Costs on the new rows are in materials the
## game has today; steps D, F and H recost them in each chapter's own. Every
## write goes through `DataTable.encode`, the only thing allowed to write a
## table (PROJECT.md §10) — this is the editor's encoder with a list pasted
## into it, not a hand edit.

## Recipe id -> the bench it belongs to. Anything not named keeps its tier.
const RECIPE_TIER := {
	# Chapter 2 — Steel
	"machete": 2, "fireaxe": 2, "steelpick": 2, "pistol": 2, "ammoP": 2, "ammoS": 2,
	"lockpick": 2, "compoundBow": 2, "doubleBitAxe": 2, "fuel": 2, "heavyVest": 2,
	# Chapter 3 — Power
	"flashlight": 3, "battery": 3, "crossbow": 3, "shotgun": 3, "smg": 3, "machinePistol": 3,
	"sledge": 3, "pistonHammer": 3, "leafSpringBlade": 3, "bladedPike": 3, "ammoR": 3,
	# Chapter 4 — Military
	"rifle": 4, "carbine": 4, "milVest": 4,
}

## Riot Armor is chapter 2 and Military Hardware is chapter 4's material.
const RECIPE_COST := {
	"heavyVest": {"cloth": 20, "scrap": 46, "parts": 2},
}

## The rows the chapters were missing, appended in this order.
const NEW_RECIPES := [
	{"id": "riotHelm", "bench": 2, "cost": {"scrap": 18, "cloth": 4}, "give": {"gear": "riotHelm"}, "xp": 20},
	{"id": "tacGloves", "bench": 2, "cost": {"scrap": 6, "cloth": 8}, "give": {"gear": "tacGloves"}, "xp": 12},
	{"id": "combatBoots", "bench": 2, "cost": {"scrap": 10, "cloth": 8}, "give": {"gear": "combatBoots"}, "xp": 14},
	{"id": "milHelm", "bench": 4, "cost": {"scrap": 20, "mil": 3, "cloth": 4}, "give": {"gear": "milHelm"}, "xp": 60},
	{"id": "armGuards", "bench": 4, "cost": {"scrap": 12, "mil": 2}, "give": {"gear": "armGuards"}, "xp": 40},
	{"id": "milGreaves", "bench": 4, "cost": {"scrap": 16, "mil": 3, "cloth": 8}, "give": {"gear": "milGreaves"}, "xp": 60},
	{"id": "milBoots", "bench": 4, "cost": {"scrap": 12, "mil": 2, "cloth": 4}, "give": {"gear": "milBoots"}, "xp": 40},
	{"id": "marksmanRifle", "bench": 4, "cost": {"scrap": 70, "parts": 12, "mil": 6, "elec": 4}, "give": {"weapon": "marksmanRifle"}, "xp": 140},
	{"id": "maul", "bench": 4, "cost": {"scrap": 50, "wood": 18, "parts": 2, "mil": 2}, "give": {"weapon": "maul"}, "xp": 60},
	{"id": "katana", "bench": 4, "cost": {"scrap": 40, "parts": 4, "mil": 4}, "give": {"weapon": "katana"}, "xp": 80},
]

## Buildable id -> the bench it needs. Anything not named keeps its tier.
const STRUCTURE_TIER := {
	"reinforcedWall": 2, "gate": 2, "locker": 2, "spike": 2, "watchtower": 2, "recycler": 2,
	"metalWall": 3, "turret": 3, "floodlight": 3, "chemStation": 3, "generator": 3,
}


func _init() -> void:
	_recipes()
	_structures()
	quit()


func _load(path: String) -> Dictionary:
	var got := DataTable.decode(FileAccess.get_file_as_string(path))
	for e: String in got.errors:
		push_error("%s: %s" % [path, e])
	return got.doc


func _save(path: String, doc: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(DataTable.encode(doc))
	f.close()


func _recipes() -> void:
	var path := "res://data/recipes.json"
	var doc := _load(path)
	var rows: Array = doc.rows
	var moved := 0
	var seen := {}
	for row: Dictionary in rows:
		var id := String(row.id)
		seen[id] = true
		if RECIPE_TIER.has(id) and int(row.bench) != int(RECIPE_TIER[id]):
			row.bench = int(RECIPE_TIER[id])
			moved += 1
		if RECIPE_COST.has(id):
			row.cost = RECIPE_COST[id].duplicate()
	var added := 0
	for n: Dictionary in NEW_RECIPES:
		if seen.has(n.id):
			print("recipes.json: %s already there" % n.id)
			continue
		var row := n.duplicate(true)
		var give: Dictionary = row.give
		row.name = String(Config.GEAR[give.gear].name) if give.has("gear") else String(Config.WEAPONS[give.weapon].name)
		rows.append(row)
		added += 1
	_save(path, doc)
	print("data/recipes.json: %d moved, %d added" % [moved, added])


func _structures() -> void:
	var path := "res://data/structures.json"
	var doc := _load(path)
	var moved := 0
	for row: Dictionary in doc.rows:
		var id := String(row.id)
		if STRUCTURE_TIER.has(id) and int(row.tier) != int(STRUCTURE_TIER[id]):
			row.tier = int(STRUCTURE_TIER[id])
			moved += 1
	_save(path, doc)
	print("data/structures.json: %d moved" % moved)
