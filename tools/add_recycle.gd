extends SceneTree
## One-shot content write for the Recycler (Notion DL-86), run headless:
##
##   godot --headless --path . -s tools/add_recycle.gd
##
## Writes `data/recycle.json` from the owner's **Breaks down into** column on
## the Notion Items table, and adds the `recycler` row to `data/structures.json`.
## Everything goes through `DataTable.encode`, which is the only thing allowed
## to write a table (PROJECT.md §10) — this script is the editor's encoder with
## a list pasted into it, not a hand edit.
##
## Rows whose Notion entry says "(salvage, in game)" are buildings: taking one
## down already pays you back through `demolish`, and a Recycler must not be a
## second refund for the same wall. Rows with no Code ID are Planned or Cut.

const MATERIAL := {
	"Wood": "wood", "Sticks": "sticks", "Stone": "stone", "Scrap": "scrap",
	"Cloth": "cloth", "Electronics": "elec", "Weapon Parts": "parts",
	"Military": "mil", "Fiber": "fiber",
}

## `Code ID` -> what the owner's column says it breaks down into.
const BREAKDOWNS := {
	"largeWrench": "7 Scrap",
	"metalSpear": "4 Scrap, 2 Wood",
	"milHelm": "4 Scrap, 1 Military",
	"cleaver": "4 Scrap",
	"hammer": "1 Sticks, 3 Stone",
	"steelpick": "3 Wood, 13 Scrap, 1 Weapon Parts",
	"pick": "2 Sticks, 2 Stone",
	"armGuards": "2 Scrap, 1 Military",
	"workGloves": "4 Cloth",
	"flashlight": "5 Scrap, 3 Electronics",
	"workBoots": "5 Cloth, 3 Scrap",
	"spikedBat": "4 Wood, 4 Scrap",
	"crowbar": "5 Scrap",
	"baseballBat": "4 Wood",
	"paddedLegs": "12 Cloth, 5 Scrap",
	"crossbow": "8 Scrap, 2 Weapon Parts",
	"lightVest": "11 Cloth, 6 Scrap",
	"carbine": "42 Scrap, 9 Weapon Parts, 7 Military, 6 Electronics",
	"fireaxe": "4 Wood, 10 Scrap, 1 Weapon Parts",
	"huntingKnife": "3 Scrap",
	"pipe": "5 Scrap",
	"axe": "1 Sticks, 1 Stone",
	"gardenSpear": "2 Scrap, 2 Wood",
	"shovel": "3 Scrap, 2 Wood",
	"rifle": "31 Scrap, 6 Weapon Parts, 1 Military",
	"milGreaves": "3 Scrap, 1 Military",
	"riotHelm": "5 Scrap",
	"compoundBow": "6 Sticks, 2 Cloth",
	"smg": "24 Scrap, 4 Weapon Parts, 5 Electronics",
	"compactSmg": "18 Scrap, 4 Weapon Parts",
	"makeshiftConcreteClub": "4 Stone",
	"kitchenKnife": "2 Scrap",
	"heavyVest": "23 Scrap, 10 Cloth, 2 Military",
	"revolver": "10 Scrap, 2 Weapon Parts",
	"pistol": "14 Scrap, 2 Weapon Parts",
	"fryingPan": "3 Scrap",
	"arStyleRifle": "30 Scrap, 8 Weapon Parts, 4 Military",
	"policeBaton": "3 Scrap",
	"marksmanRifle": "34 Scrap, 8 Weapon Parts, 5 Military",
	"pitchfork": "3 Scrap, 2 Wood",
	"denimPants": "7 Cloth",
	"woodenSpear": "3 Sticks",
	"boltActionRifle": "24 Scrap, 5 Weapon Parts",
	"bow": "4 Sticks, 1 Cloth",
	"semiAutoShotgun": "20 Scrap, 4 Weapon Parts",
	"campingAxe": "4 Scrap, 2 Wood",
	"scopedHuntingRifle": "31 Scrap, 6 Weapon Parts, 1 Military",
	"mace": "6 Scrap",
	"katana": "8 Scrap",
	"sledge": "9 Wood, 19 Scrap, 1 Weapon Parts",
	"lmg": "50 Scrap, 14 Weapon Parts, 10 Military",
	"splittingAxe": "6 Scrap, 3 Wood",
	"milBoots": "2 Scrap, 1 Military",
	"hardHat": "7 Scrap",
	"doubleBarrelShotgun": "16 Scrap, 2 Weapon Parts",
	"scythe": "2 Sticks, 1 Stone",
	"makeshiftKnifeSpear": "3 Sticks, 1 Scrap",
	"akStyleRifle": "30 Scrap, 8 Weapon Parts, 4 Military",
	"shotgun": "22 Scrap, 3 Weapon Parts, 6 Wood",
	"milVest": "20 Scrap, 6 Military, 7 Cloth",
	"maul": "8 Scrap, 4 Wood",
	"kukri": "5 Scrap",
	"knife": "1 Stone",
	"leverActionRifle": "22 Scrap, 4 Weapon Parts",
	"machete": "12 Scrap",
}


func _init() -> void:
	_write_recycle()
	_add_recycler_row()
	quit()


func _write_recycle() -> void:
	var ids := BREAKDOWNS.keys()
	ids.sort()
	var rows := []
	var missing := []
	for id: String in ids:
		if not (Config.WEAPONS.has(id) or Config.GEAR.has(id) or Config.CONSUMABLES.has(id)):
			missing.append(id)
			continue
		var gives := {}
		for part in String(BREAKDOWNS[id]).split(","):
			var bits := part.strip_edges().split(" ", false, 1)
			if bits.size() != 2 or not MATERIAL.has(bits[1]):
				push_error("%s: cannot read '%s'" % [id, part])
				continue
			gives[MATERIAL[bits[1]]] = int(bits[0])
		rows.append({"id": id, "gives": gives})
	if not missing.is_empty():
		print("skipped, no such item in the game: ", ", ".join(missing))
	var doc := {
		"notes": "What the Recycler gives back for one of a thing, from the owner's "
			+ "Breaks down into column on Notion's Items table. Buildings are not in here: "
			+ "taking one down pays through salvage already. A row is what ONE of the item "
			+ "returns, before Config.RECYCLE_SHARE and before a worn tool's condition.",
		"shape": "by_id_bare",
		"fields": {"gives": {"type": "map<int>", "key_ref": "RES"}},
		"rows": rows,
	}
	var f := FileAccess.open("res://data/recycle.json", FileAccess.WRITE)
	f.store_string(DataTable.encode(doc))
	f.close()
	print("data/recycle.json: %d rows" % rows.size())


func _add_recycler_row() -> void:
	var path := "res://data/structures.json"
	var got := DataTable.decode(FileAccess.get_file_as_string(path))
	for e: String in got.errors:
		push_error(e)
	var doc: Dictionary = got.doc
	for row: Dictionary in doc.rows:
		if String(row.id) == "recycler":
			print("structures.json: recycler already there")
			return
	var at: int = doc.rows.size()
	for i in doc.rows.size():
		if String(doc.rows[i].id) == "chemStation":
			at = i + 1
	doc.rows.insert(at, {
		"id": "recycler",
		"name": "Recycler",
		"desc": "Breaks weapons, tools and armour back down into materials. Stand near it.",
		"notes": "Notion's fifth bench (Workbenches, \"Recycle\"): nothing is crafted here. "
			+ "What each item gives back is the item's own Breaks down into, in data/recycle.json. "
			+ "Tier 2 because a gun you no longer want is worth more than the scrap it holds "
			+ "until you have somewhere better to be.",
		"cost": {"scrap": 34, "wood": 20, "parts": 3},
		"hp": 280.0,
		"station": "recycle",
		"protect": true,
		"solid": true,
		"threat": 2.0,
		"tier": 2,
	})
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(DataTable.encode(doc))
	f.close()
	print("structures.json: recycler added")
