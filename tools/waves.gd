extends SceneTree
## One-shot content write for the recipe waves (progression step B,
## `tasks/progression-plan.md` §19), run headless:
##
##   godot --headless --path . -s tools/waves.gd
##
## Adds `wave` to every recipe and buildable — which of a chapter's five
## arrivals it belongs to (Foothold, Kit, Set, Second material, Defence) —
## and `found` to every material: one line on where it is best looked for,
## for the pinned recipe on the HUD. Two rows move rung: Padded Leggings is
## the Riot set's, and Fuel is chapter 3's chemistry. Through
## `DataTable.encode`, the only thing allowed to write a table.

## Recipe id -> wave. Anything not named is Kit (2); by-hand rows are 1.
const RECIPE_WAVE := {
	# tier 1
	"woodenSpear": 2, "pipe": 2, "makeshiftConcreteClub": 2, "bow": 2, "arrow": 2, "cordage": 2, "scythe": 2,
	"workGloves": 3, "denimPants": 3, "lightVest": 3, "workBoots": 3, "hardHat": 3, "medkit": 3, "rationPack": 3,
	"serum": 4, "jerky": 4, "hotMeal": 4, "cornRations": 4, "herbMed": 4, "hotMealVeg": 4, "compost": 4,
	# tier 2
	"machete": 2, "metalSpear": 2, "fireaxe": 2, "steelpick": 2, "lockpick": 2,
	"riotHelm": 3, "heavyVest": 3, "tacGloves": 3, "paddedLegs": 3, "combatBoots": 3, "doubleBitAxe": 3,
	"compoundBow": 4, "pipeShotgun": 4, "pistol": 4, "ammoP": 4, "ammoS": 4,
	# tier 3
	"flashlight": 2, "battery": 2, "crossbow": 2, "sledge": 2, "bladedPike": 2, "fuel": 2,
	"pistonHammer": 3, "leafSpringBlade": 3,
	"shotgun": 4, "smg": 4, "machinePistol": 4, "ammoR": 4,
	# tier 4
	"maul": 2, "katana": 2, "rifle": 2,
	"milHelm": 3, "armGuards": 3, "milGreaves": 3, "milBoots": 3, "milVest": 3, "carbine": 3, "marksmanRifle": 3,
}

const RECIPE_TIER := {"paddedLegs": 2, "fuel": 3}

## Buildable id -> wave.
const STRUCTURE_WAVE := {
	"workbench": 1, "bedroll": 2, "chest": 2, "stash": 3, "raisedBed": 4, "longBed": 4,
	"barricade": 5, "woodWall": 5, "stoneWall": 5, "bunk": 5,
	"reinforcedWall": 2, "locker": 3, "recycler": 4, "gate": 5, "spike": 5, "watchtower": 5,
	"generator": 1, "floodlight": 2, "chemStation": 2, "metalWall": 5, "turret": 5,
}

## Material id -> where it is best looked for. One line, for the HUD.
const FOUND := {
	"wood": "trees, with a hatchet",
	"sticks": "under trees, and in bushes",
	"stone": "rocks by the roadside",
	"fiber": "bushes and long grass",
	"scrap": "houses and cars, everywhere",
	"cloth": "wardrobes and dressers, or cut from fiber",
	"elec": "parts bins in the Dock Yard, the Mall and Crown Heights",
	"battery": "desks, glove boxes and parts bins",
	"med": "medicine cabinets, and St. Martha Hospital",
	"parts": "toolboxes and gun safes past the Suburbs",
	"mil": "Checkpoint Delta and Downtown",
	"fuel": "the Fuel Stop's pumps and drums",
	"rations": "kitchens, vending machines and the Farms",
	"seedPotato": "the Farms",
	"seedCorn": "the Farms",
	"seedHerb": "the Farms and the Forest cabins",
	"compost": "the workbench, from fiber and sticks",
	"sludge": "the Chemistry Station",
	"arrow": "the workbench",
	"ammoP": "the Precinct, gun safes, or the bench",
	"ammoS": "the Precinct, gun safes, or the bench",
	"ammoR": "the Precinct, the Checkpoint, or the bench",
	"precision": "Pine Hollow High",
}


func _init() -> void:
	_recipes()
	_structures()
	_res()
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
	doc.fields["wave"] = {"type": "int"}
	var n := 0
	for row: Dictionary in doc.rows:
		var id := String(row.id)
		if RECIPE_TIER.has(id):
			row.bench = int(RECIPE_TIER[id])
		if int(row.bench) == 0 or row.has("station"):
			row.wave = 1
		else:
			row.wave = int(RECIPE_WAVE.get(id, 2))
		n += 1
	_save(path, doc)
	print("data/recipes.json: %d rows given a wave" % n)


func _structures() -> void:
	var path := "res://data/structures.json"
	var doc := _load(path)
	doc.fields["wave"] = {"type": "int"}
	for row: Dictionary in doc.rows:
		row.wave = int(STRUCTURE_WAVE.get(String(row.id), 2))
	_save(path, doc)
	print("data/structures.json: waves written")


func _res() -> void:
	var path := "res://data/res.json"
	var doc := _load(path)
	doc.fields["found"] = {"type": "string"}
	for row: Dictionary in doc.rows:
		row.found = String(FOUND.get(String(row.id), ""))
	_save(path, doc)
	print("data/res.json: found written")
