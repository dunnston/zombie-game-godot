class_name PropModels
extends RefCounted
## Which of the owner's static props draws what on the 3D stage. A view
## table, never content: the sim says a bedroom has a bed against its
## north wall, this says the bed is `furniture/bed_single.glb` fitted into
## a metre by two and eighty centimetres tall. Every path is a file in
## `assets/models/props/` (the catalog is its README); every box is in
## metres, x across the thing's face, y up, z front to back, and is the
## space the model is fitted inside (`StaticModel.transform_for`), never
## the model's own size, which Meshy normalises away.
##
## A spec is `{"path", "box", "yaw", "at"}`: `yaw` turns the export so its
## front faces +z (south) at rest, for the few that were modelled sideways;
## `at` moves it inside its footprint, in metres, +z toward the front and
## +y up, which is how a lamp stands on a nightstand. `{"parts": [...]}` is
## several specs drawn as one thing (a desk with its chair). A kind may list
## variants, chosen by the prop's `si`. A kind with no entry, or whose file
## is missing, draws as the stand-in shape in `Props3D`.

const P := "res://assets/models/props/"

const TREE_BOX := Vector3(1.8, 3.4, 1.8)
const PINE_BOX := Vector3(1.6, 3.8, 1.6)

## By prop kind (`World` props), a spec, or variants by `si`.
const KINDS := {
	"tree": [
		{"path": "nature/oak.glb", "box": TREE_BOX},
		{"path": "nature/oak_2.glb", "box": TREE_BOX},
		{"path": "nature/oak_autumn.glb", "box": TREE_BOX},
		{"path": "nature/oak.glb", "box": TREE_BOX},
	],
	"pine": [
		{"path": "nature/pine.glb", "box": PINE_BOX},
		{"path": "nature/pine_tall.glb", "box": PINE_BOX},
		{"path": "nature/pine.glb", "box": PINE_BOX},
		{"path": "nature/cypress.glb", "box": PINE_BOX},
	],
	"bush": [
		{"path": "nature/bush_clover.glb", "box": Vector3(0.9, 0.8, 0.9)},
		{"path": "nature/bush_red_berry.glb", "box": Vector3(0.9, 0.8, 0.9)},
		{"path": "nature/shrub_golden.glb", "box": Vector3(0.9, 0.8, 0.9)},
	],
	"rock": {"path": "nature/boulder_pale.glb", "box": Vector3(0.55, 0.35, 0.55)},
	"boulder": [
		{"path": "nature/boulder_mossy.glb", "box": Vector3(1.1, 0.9, 1.1)},
		{"path": "nature/boulder_mossy_2.glb", "box": Vector3(1.1, 0.9, 1.1)},
		{"path": "nature/boulder_mossy_3.glb", "box": Vector3(1.1, 0.9, 1.1)},
	],
	"thicket": [
		{"path": "nature/bush_clover.glb", "box": Vector3(1.4, 1.2, 1.4)},
		{"path": "nature/shrub_golden.glb", "box": Vector3(1.4, 1.2, 1.4)},
		{"path": "nature/bush_pink_blossom.glb", "box": Vector3(1.4, 1.2, 1.4)},
	],
	"stump": [
		{"path": "nature/tree_stump_mossy.glb", "box": Vector3(0.9, 0.7, 0.9)},
		{"path": "nature/tree_stump_ancient.glb", "box": Vector3(0.9, 0.7, 0.9)},
		{"path": "nature/tree_stump_mossy.glb", "box": Vector3(0.9, 0.7, 0.9)},
	],
	"log": [
		{"path": "nature/log.glb", "box": Vector3(1.0, 0.5, 1.0)},
		{"path": "nature/log_branched.glb", "box": Vector3(1.0, 0.5, 1.0)},
		{"path": "nature/driftwood.glb", "box": Vector3(1.0, 0.5, 1.0)},
	],
	"corn": {"path": "nature/corn_stalk.glb", "box": Vector3(0.7, 1.7, 0.7)},
	"tractor": {"path": "vehicles/tractor.glb", "box": Vector3(2.0, 1.7, 1.0)},
	"wreck": [
		{"path": "vehicles/pickup_rusty.glb", "box": Vector3(2.0, 1.3, 1.0)},
		{"path": "vehicles/box_truck.glb", "box": Vector3(2.0, 1.6, 1.0)},
	],
	# hay, silo and reed: no model yet, the stand-in shapes stay.
}

## Ground litter, by what it gives (`res`).
const LITTER := {
	"sticks": [
		{"path": "nature/stick_bundle.glb", "box": Vector3(0.7, 0.3, 0.7)},
		{"path": "nature/branch_forked.glb", "box": Vector3(0.7, 0.3, 0.7)},
		{"path": "nature/branch_forked_2.glb", "box": Vector3(0.7, 0.3, 0.7)},
	],
	"fiber": {"path": "nature/straw_patch.glb", "box": Vector3(0.6, 0.12, 0.6)},
	"stone": {"path": "nature/boulder_pale.glb", "box": Vector3(0.3, 0.2, 0.3)},
}

## Furniture, yard and street pieces, by what the sim says stands there
## (`what`). Wall pieces (`kind` "wall") hang at the height their `at.y` says.
const THINGS := {
	# bedroom
	"bed_single": {"path": "furniture/bed_single.glb", "box": Vector3(1.0, 0.8, 2.0)},
	"bed_double": [
		{"path": "furniture/bed_ivory.glb", "box": Vector3(2.0, 0.9, 2.0)},
		{"path": "furniture/bed_rustic.glb", "box": Vector3(2.0, 0.9, 2.0)},
	],
	"bunk_bed": [
		{"path": "furniture/bunk_bed.glb", "box": Vector3(1.0, 1.8, 2.0)},
		{"path": "furniture/bunk_bed_2.glb", "box": Vector3(1.0, 1.8, 2.0)},
	],
	"crib": {"path": "furniture/crib.glb", "box": Vector3(1.0, 1.0, 1.0)},
	# living
	"sofa": {"path": "furniture/sofa.glb", "box": Vector3(2.0, 0.9, 1.0)},
	"loveseat": {"path": "furniture/loveseat.glb", "box": Vector3(1.0, 0.9, 1.0)},
	"armchair": [
		{"path": "furniture/armchair_cozy.glb", "box": Vector3(0.9, 0.9, 0.9)},
		{"path": "furniture/armchair_green.glb", "box": Vector3(0.9, 0.9, 0.9)},
		{"path": "furniture/armchair_modern.glb", "box": Vector3(0.9, 0.9, 0.9)},
	],
	"coffee_table": [
		{"path": "furniture/table_glass.glb", "box": Vector3(0.9, 0.45, 0.9)},
		{"path": "furniture/table_glass_yellow.glb", "box": Vector3(0.9, 0.45, 0.9)},
	],
	"tv_stand": {"parts": [
		{"path": "furniture/media_console.glb", "box": Vector3(1.7, 0.5, 0.45), "at": Vector3(0, 0, -0.2)},
		{"path": "electronics/tv_flat.glb", "box": Vector3(1.3, 0.75, 0.15), "at": Vector3(0, 0.5, -0.2)},
	]},
	"tv_retro": {"path": "electronics/tv_retro.glb", "box": Vector3(0.7, 0.6, 0.6)},
	"fireplace": {"path": "furniture/fireplace.glb", "box": Vector3(1.0, 1.5, 0.7), "at": Vector3(0, 0, -0.15)},
	"piano": {"path": "furniture/piano.glb", "box": Vector3(2.0, 1.3, 0.8), "at": Vector3(0, 0, -0.1)},
	"rug": {"path": "decor/rug.glb", "box": Vector3(1.8, 0.05, 1.8)},
	"houseplant": [
		{"path": "decor/houseplant.glb", "box": Vector3(0.6, 1.1, 0.6)},
		{"path": "decor/plant_potted.glb", "box": Vector3(0.6, 1.1, 0.6)},
		{"path": "decor/plant_snake.glb", "box": Vector3(0.6, 1.1, 0.6)},
		{"path": "decor/plant_terracotta.glb", "box": Vector3(0.6, 1.1, 0.6)},
	],
	"floor_speaker": {"path": "electronics/floor_speaker.glb", "box": Vector3(0.4, 1.0, 0.4)},
	# kitchen
	"stove": {"parts": [
		{"path": "kitchen/stove.glb", "box": Vector3(0.9, 1.0, 0.7)},
		{"path": "kitchen/range_hood.glb", "box": Vector3(0.8, 0.5, 0.5), "at": Vector3(0, 1.5, -0.2)},
	]},
	"sink": {"path": "kitchen/sink_rusty.glb", "box": Vector3(0.9, 0.9, 0.6)},
	"island": {"parts": [
		{"path": "kitchen/island.glb", "box": Vector3(2.0, 0.95, 1.0)},
		{"path": "kitchen/fruit_bowl.glb", "box": Vector3(0.4, 0.15, 0.4), "at": Vector3(0.5, 0.95, 0)},
	]},
	"dining": {"parts": [
		{"path": "furniture/table.glb", "box": Vector3(1.8, 0.8, 0.9)},
		{"path": "furniture/chair_folding.glb", "box": Vector3(0.5, 0.9, 0.5), "at": Vector3(-0.5, 0, 0.45), "yaw": PI},
		{"path": "furniture/chair_folding_2.glb", "box": Vector3(0.5, 0.9, 0.5), "at": Vector3(0.5, 0, 0.45), "yaw": PI},
		{"path": "furniture/stool.glb", "box": Vector3(0.45, 0.6, 0.45), "at": Vector3(-0.5, 0, -0.45)},
		{"path": "kitchen/table_setting.glb", "box": Vector3(0.5, 0.1, 0.5), "at": Vector3(0.4, 0.8, 0)},
	]},
	"table_small": [
		{"path": "furniture/table_2.glb", "box": Vector3(1.0, 0.8, 1.0)},
		{"path": "furniture/table_rustic_2.glb", "box": Vector3(1.0, 0.8, 1.0)},
	],
	"high_chair": {"path": "furniture/high_chair.glb", "box": Vector3(0.5, 1.0, 0.5)},
	# bathroom
	"toilet": [
		{"path": "bathroom/toilet.glb", "box": Vector3(0.6, 0.8, 0.8)},
		{"path": "bathroom/toilet_rusty.glb", "box": Vector3(0.6, 0.8, 0.8)},
		{"path": "bathroom/toilet_rusty_2.glb", "box": Vector3(0.6, 0.8, 0.8)},
	],
	"bathtub": [
		{"path": "bathroom/bathtub.glb", "box": Vector3(1.0, 0.6, 2.0)},
		{"path": "bathroom/bathtub_clawfoot.glb", "box": Vector3(1.0, 0.6, 2.0)},
	],
	"shower": [
		{"path": "bathroom/shower_stall.glb", "box": Vector3(1.0, 2.1, 1.0)},
		{"path": "bathroom/shower_enclosure.glb", "box": Vector3(1.0, 2.1, 1.0)},
	],
	"sink_pedestal": {"path": "bathroom/sink_pedestal.glb", "box": Vector3(0.6, 0.9, 0.5)},
	"towels": {"path": "bathroom/towels.glb", "box": Vector3(0.5, 0.4, 0.4)},
	"washer": [
		{"path": "utility/washing_machine.glb", "box": Vector3(0.8, 1.0, 0.7)},
		{"path": "utility/washing_machine_top_load.glb", "box": Vector3(0.8, 1.0, 0.7)},
		{"path": "utility/washing_machine_rusty.glb", "box": Vector3(0.8, 1.0, 0.7)},
	],
	"dryer": {"path": "utility/dryer.glb", "box": Vector3(0.8, 1.0, 0.7)},
	"laundry_basket": {"path": "utility/laundry_basket.glb", "box": Vector3(0.5, 0.5, 0.5)},
	"radiator": {"path": "utility/radiator.glb", "box": Vector3(0.9, 0.6, 0.2), "at": Vector3(0, 0, -0.35)},
	# office and school
	"school_desk": {"path": "office/school_desk.glb", "box": Vector3(0.8, 0.8, 0.8)},
	"water_cooler": {"path": "utility/water_cooler.glb", "box": Vector3(0.5, 1.4, 0.5)},
	"office_chair": {"path": "office/office_chair.glb", "box": Vector3(0.5, 0.9, 0.5)},
	# store
	"grocery_shelf": [
		{"path": "store/grocery_shelf_stocked.glb", "box": Vector3(1.0, 1.8, 0.8)},
		{"path": "store/grocery_shelf_stocked_2.glb", "box": Vector3(1.0, 1.8, 0.8)},
		{"path": "store/grocery_shelf.glb", "box": Vector3(1.0, 1.8, 0.8)},
		{"path": "store/market_shelf.glb", "box": Vector3(1.0, 1.8, 0.8)},
	],
	"pantry_shelf": [
		{"path": "store/pantry_shelf.glb", "box": Vector3(1.0, 1.8, 0.6)},
		{"path": "store/pantry_shelf_rusty.glb", "box": Vector3(1.0, 1.8, 0.6)},
	],
	"display_fridge": [
		{"path": "store/display_fridge_stocked.glb", "box": Vector3(1.0, 1.9, 0.8)},
		{"path": "store/display_fridge.glb", "box": Vector3(1.0, 1.9, 0.8)},
	],
	"postcard_rack": {"path": "store/postcard_rack.glb", "box": Vector3(0.5, 1.6, 0.5)},
	"snack_display": {"path": "store/snack_display.glb", "box": Vector3(1.0, 1.1, 0.8)},
	# workshop, barn and barracks
	"pegboard": {"path": "utility/pegboard.glb", "box": Vector3(1.0, 1.2, 0.3), "at": Vector3(0, 0.6, -0.3)},
	"shelf_metal": {"path": "utility/shelf_metal.glb", "box": Vector3(1.0, 1.8, 0.5)},
	"craftsman_bench": {"path": "utility/craftsman_bench.glb", "box": Vector3(2.0, 0.9, 0.7)},
	"propane_tank": {"path": "utility/propane_tank.glb", "box": Vector3(0.6, 1.0, 0.6)},
	"space_heater": {"path": "utility/space_heater.glb", "box": Vector3(0.5, 0.6, 0.4)},
	"cardboard_box": {"path": "small/cardboard_box.glb", "box": Vector3(0.6, 0.5, 0.6)},
	"wheelbarrow": {"path": "yard/wheelbarrow.glb", "box": Vector3(0.7, 0.7, 1.2)},
	# yard
	"swing_set": {"path": "yard/swing_set.glb", "box": Vector3(2.0, 2.2, 1.2)},
	"slide": [
		{"path": "yard/slide.glb", "box": Vector3(2.0, 1.6, 1.0)},
		{"path": "yard/slide_rainbow.glb", "box": Vector3(2.0, 1.6, 1.0)},
	],
	"trampoline": {"path": "yard/trampoline.glb", "box": Vector3(2.2, 0.9, 2.2)},
	"pool": {"path": "yard/pool_above_ground.glb", "box": Vector3(2.4, 1.1, 2.4)},
	"hot_tub": {"path": "yard/hot_tub.glb", "box": Vector3(2.2, 0.9, 2.2)},
	"merry_go_round": {"path": "yard/merry_go_round.glb", "box": Vector3(2.2, 1.0, 2.2)},
	"picnic_table": [
		{"path": "yard/picnic_table.glb", "box": Vector3(2.0, 1.0, 1.2)},
		{"path": "yard/picnic_table_shaded.glb", "box": Vector3(2.0, 2.2, 1.2)},
	],
	"patio_set": {"parts": [
		{"path": "furniture/table_glass_yellow.glb", "box": Vector3(0.8, 0.7, 0.8)},
		{"path": "yard/patio_chair_olive.glb", "box": Vector3(0.6, 0.9, 0.6), "at": Vector3(-0.65, 0, 0), "yaw": PI / 2.0},
		{"path": "yard/patio_chair_white.glb", "box": Vector3(0.6, 0.9, 0.6), "at": Vector3(0.65, 0, 0), "yaw": -PI / 2.0},
	]},
	"sun_lounger": {"path": "yard/sun_lounger.glb", "box": Vector3(0.9, 0.5, 0.9)},
	"beach_chair": {"path": "yard/beach_chair.glb", "box": Vector3(0.7, 0.9, 0.7)},
	"dog_house": {"path": "yard/dog_house.glb", "box": Vector3(1.0, 0.9, 1.0)},
	"clothesline": [
		{"path": "yard/clothesline_rotary.glb", "box": Vector3(1.6, 2.0, 1.6)},
		{"path": "yard/clothesline_rotary_2.glb", "box": Vector3(1.6, 2.0, 1.6)},
	],
	"drying_rack": {"path": "yard/drying_rack.glb", "box": Vector3(1.0, 1.0, 0.6)},
	"sandbox": {"path": "yard/sandbox.glb", "box": Vector3(1.2, 0.3, 1.2)},
	"basketball_hoop": {"path": "yard/basketball_hoop.glb", "box": Vector3(0.9, 3.0, 0.9)},
	"birdbath": {"path": "yard/birdbath.glb", "box": Vector3(0.6, 1.0, 0.6)},
	"fountain": {"path": "yard/fountain.glb", "box": Vector3(2.4, 2.0, 2.4)},
	"wagon": {"path": "yard/wagon.glb", "box": Vector3(0.6, 0.5, 0.9)},
	"lawn_flamingo": {"path": "yard/lawn_flamingo.glb", "box": Vector3(0.3, 0.9, 0.3)},
	"garden_pot": [
		{"path": "yard/garden_pot.glb", "box": Vector3(0.6, 0.6, 0.6)},
		{"path": "yard/planter_square.glb", "box": Vector3(0.6, 0.6, 0.6)},
		{"path": "decor/plant_yellow_flowers.glb", "box": Vector3(0.5, 0.7, 0.5)},
	],
	"patio_heater": {"path": "yard/patio_heater.glb", "box": Vector3(0.6, 2.2, 0.6)},
	"kiln": {"path": "yard/kiln.glb", "box": Vector3(1.0, 1.2, 1.0)},
	"wheelie_bin": {"path": "street/wheelie_bin.glb", "box": Vector3(0.6, 1.0, 0.6)},
	"trash_can": {"path": "street/trash_can.glb", "box": Vector3(0.5, 0.9, 0.5)},
	"cooler": {"path": "small/cooler.glb", "box": Vector3(0.6, 0.5, 0.4)},
	# street
	"streetlamp": [
		{"path": "street/streetlamp.glb", "box": Vector3(0.6, 4.0, 0.6)},
		{"path": "street/streetlamp_vintage.glb", "box": Vector3(0.6, 4.0, 0.6)},
		{"path": "street/lamp_post_twin.glb", "box": Vector3(0.9, 4.0, 0.9)},
	],
	"sign_stop": {"path": "street/sign_stop.glb", "box": Vector3(0.5, 2.4, 0.5)},
	"sign_yield": {"path": "street/sign_yield.glb", "box": Vector3(0.5, 2.4, 0.5)},
	"signpost": {"path": "street/signpost.glb", "box": Vector3(0.5, 2.6, 0.5)},
	"bench": [
		{"path": "street/bench_wooden.glb", "box": Vector3(1.6, 0.9, 0.6)},
		{"path": "street/park_bench.glb", "box": Vector3(1.6, 0.9, 0.6)},
	],
	"parking_meter": {"path": "street/parking_meter.glb", "box": Vector3(0.3, 1.4, 0.3)},
	"payphone": {"path": "street/payphone.glb", "box": Vector3(0.6, 2.0, 0.5)},
	"ev_charger": {"path": "street/ev_charger.glb", "box": Vector3(0.5, 1.5, 0.4)},
	"satellite_dish": {"path": "utility/satellite_dish.glb", "box": Vector3(0.8, 0.9, 0.6)},
	# on a wall: hung at `at.y`
	"chalkboard": {"path": "office/chalkboard.glb", "box": Vector3(1.8, 1.2, 0.12), "at": Vector3(0, 0.9, 0)},
	"painting": [
		{"path": "decor/painting_coastal.glb", "box": Vector3(0.8, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/painting_skyline.glb", "box": Vector3(0.8, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/painting_abstract_red.glb", "box": Vector3(0.8, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/painting_triangles.glb", "box": Vector3(0.8, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/painting_primary_shapes.glb", "box": Vector3(0.8, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/portrait_gentleman.glb", "box": Vector3(0.6, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/portrait_red_scarf.glb", "box": Vector3(0.6, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
		{"path": "decor/painting_portrait_faceless.glb", "box": Vector3(0.6, 0.7, 0.08), "at": Vector3(0, 1.4, 0)},
	],
	"portrait": {"path": "decor/portrait_business.glb", "box": Vector3(0.6, 0.7, 0.08), "at": Vector3(0, 1.5, 0)},
	"wall_clock": {"path": "decor/wall_clock.glb", "box": Vector3(0.4, 0.5, 0.1), "at": Vector3(0, 1.8, 0)},
	"mirror": [
		{"path": "decor/mirror_arched.glb", "box": Vector3(0.6, 0.8, 0.08), "at": Vector3(0, 1.3, 0)},
		{"path": "decor/mirror_brass.glb", "box": Vector3(0.6, 0.8, 0.08), "at": Vector3(0, 1.3, 0)},
		{"path": "decor/mirror_wide.glb", "box": Vector3(0.9, 0.6, 0.08), "at": Vector3(0, 1.4, 0)},
	],
	"ac_wall": {"path": "utility/ac_wall.glb", "box": Vector3(0.9, 0.35, 0.3), "at": Vector3(0, 2.2, 0)},
	"light_switch": {"path": "utility/light_switch.glb", "box": Vector3(0.12, 0.12, 0.03), "at": Vector3(0, 1.2, 0)},
}

## Searchable furniture, by container kind. A kind not here falls back to
## its sprite (`SPRITES`), the way the 2D paint does.
const CONTAINERS := {
	"fridge": {"path": "kitchen/refrigerator.glb", "box": Vector3(0.85, 1.9, 0.8)},
	"kitchen": {"parts": [
		{"path": "kitchen/cabinets_cream.glb", "box": Vector3(1.0, 2.2, 0.65)},
		{"path": "kitchen/coffee_maker.glb", "box": Vector3(0.3, 0.35, 0.3), "at": Vector3(0.25, 0.92, 0.05)},
	]},
	"cabinet": [
		{"path": "furniture/cabinet_brown.glb", "box": Vector3(1.0, 1.6, 0.6)},
		{"path": "furniture/cabinet_beige.glb", "box": Vector3(1.0, 1.6, 0.6)},
		{"path": "furniture/cabinet_wooden.glb", "box": Vector3(1.0, 1.6, 0.6)},
	],
	"dresser": {"parts": [
		{"path": "furniture/dresser.glb", "box": Vector3(1.0, 1.0, 0.6)},
		{"path": "decor/vase_tulips.glb", "box": Vector3(0.3, 0.4, 0.3), "at": Vector3(0.25, 1.0, 0)},
	]},
	"wardrobe": [
		{"path": "furniture/cabinet_sliding_door.glb", "box": Vector3(1.0, 2.0, 0.65)},
		{"path": "furniture/cabinet_wooden.glb", "box": Vector3(1.0, 2.0, 0.65)},
		{"path": "furniture/cabinet_storage.glb", "box": Vector3(1.0, 2.0, 0.65)},
	],
	"nightstand": [
		{"parts": [
			{"path": "furniture/nightstand.glb", "box": Vector3(0.6, 0.7, 0.6)},
			{"path": "decor/lamp_table.glb", "box": Vector3(0.35, 0.5, 0.35), "at": Vector3(0, 0.7, 0)},
		]},
		{"parts": [
			{"path": "furniture/bedside_cabinet.glb", "box": Vector3(0.6, 0.7, 0.6)},
			{"path": "decor/book_stack.glb", "box": Vector3(0.3, 0.2, 0.3), "at": Vector3(0, 0.7, 0)},
		]},
		{"parts": [
			{"path": "furniture/bedside_table.glb", "box": Vector3(0.6, 0.7, 0.6)},
			{"path": "decor/lamp_table.glb", "box": Vector3(0.35, 0.5, 0.35), "at": Vector3(0, 0.7, 0)},
		]},
	],
	"bookshelf": [
		{"path": "furniture/bookshelf.glb", "box": Vector3(1.0, 1.9, 0.5)},
		{"path": "furniture/bookshelf_2.glb", "box": Vector3(1.0, 1.9, 0.5)},
		{"path": "furniture/bookshelf_3.glb", "box": Vector3(1.0, 1.9, 0.5)},
		{"path": "furniture/bookshelf_leaning.glb", "box": Vector3(1.0, 1.9, 0.5)},
	],
	"desk": {"parts": [
		{"path": "office/desk_classic.glb", "box": Vector3(1.0, 0.8, 0.6), "at": Vector3(0, 0, -0.2)},
		{"path": "office/monitor.glb", "box": Vector3(0.5, 0.45, 0.2), "at": Vector3(0, 0.8, -0.3)},
		{"path": "office/office_chair.glb", "box": Vector3(0.5, 0.9, 0.5), "at": Vector3(0, 0, 0.4)},
	]},
	"teacherDesk": {"parts": [
		{"path": "office/desk_classic.glb", "box": Vector3(1.0, 0.8, 0.6), "at": Vector3(0, 0, -0.2)},
		{"path": "decor/book_stack.glb", "box": Vector3(0.3, 0.2, 0.3), "at": Vector3(0.3, 0.8, -0.2)},
		{"path": "furniture/chair_folding.glb", "box": Vector3(0.5, 0.9, 0.5), "at": Vector3(0, 0, 0.4)},
	]},
	"principalDesk": {"parts": [
		{"path": "office/desk_executive.glb", "box": Vector3(1.0, 0.8, 0.7), "at": Vector3(0, 0, -0.15)},
		{"path": "decor/globe.glb", "box": Vector3(0.3, 0.4, 0.3), "at": Vector3(0.3, 0.8, -0.2)},
		{"path": "office/office_chair.glb", "box": Vector3(0.5, 0.9, 0.5), "at": Vector3(0, 0, 0.45)},
	]},
	"filing": {"path": "office/filing_cabinet.glb", "box": Vector3(0.6, 1.3, 0.6)},
	"vanity": {"parts": [
		{"path": "bathroom/vanity_sink.glb", "box": Vector3(0.9, 0.9, 0.6)},
		{"path": "decor/mirror_arched.glb", "box": Vector3(0.5, 0.7, 0.05), "at": Vector3(0, 1.2, -0.28)},
	]},
	"medcab": [
		{"path": "furniture/cabinet_white.glb", "box": Vector3(1.0, 1.8, 0.5)},
		{"path": "furniture/cabinet_glass_door.glb", "box": Vector3(1.0, 1.8, 0.5)},
	],
	"pharmacy": {"path": "furniture/cabinet_glass_door.glb", "box": Vector3(1.0, 1.8, 0.5)},
	"nurseCabinet": {"path": "furniture/cabinet_white.glb", "box": Vector3(1.0, 1.8, 0.5)},
	"hospitalCrate": {"path": "furniture/cabinet_white.glb", "box": Vector3(1.0, 1.8, 0.5)},
	"shelf": {"path": "utility/shelf_metal.glb", "box": Vector3(1.0, 1.8, 0.5)},
	"toolrack": {"path": "utility/pegboard.glb", "box": Vector3(1.0, 1.2, 0.3), "at": Vector3(0, 0.6, -0.3)},
	"toolbox": {"path": "small/storage_box.glb", "box": Vector3(0.7, 0.5, 0.5)},
	"electronics": {"parts": [
		{"path": "small/storage_box.glb", "box": Vector3(0.7, 0.5, 0.5)},
		{"path": "electronics/radio.glb", "box": Vector3(0.35, 0.25, 0.2), "at": Vector3(0, 0.5, 0)},
	]},
	"crate": {"path": "small/crate_wooden.glb", "box": Vector3(0.8, 0.7, 0.8)},
	"militaryCrate": {"path": "small/crate_wooden.glb", "box": Vector3(0.9, 0.6, 0.9)},
	"supplyCache": {"path": "small/crate_wooden.glb", "box": Vector3(0.9, 0.6, 0.9)},
	"footlocker": {"path": "utility/storage_chest_striped.glb", "box": Vector3(0.9, 0.5, 0.6)},
	"safe": {"path": "furniture/cabinet_modern.glb", "box": Vector3(0.8, 1.5, 0.7)},
	"gunSafe": {"path": "furniture/cabinet_modern.glb", "box": Vector3(0.8, 1.8, 0.7)},
	"locker": {"path": "office/lockers.glb", "box": Vector3(1.0, 1.9, 0.5)},
	"policeLocker": {"path": "office/lockers.glb", "box": Vector3(1.0, 1.9, 0.5)},
	"schoolLocker": {"path": "office/lockers.glb", "box": Vector3(1.0, 1.9, 0.5)},
	"vending": {"path": "street/vending_machine.glb", "box": Vector3(0.9, 1.9, 0.8)},
	"fuelPump": [
		{"path": "street/fuel_pump_retro.glb", "box": Vector3(0.7, 1.8, 0.5)},
		{"path": "street/fuel_pump_retro_2.glb", "box": Vector3(0.7, 1.8, 0.5)},
		{"path": "street/fuel_pump_rusty.glb", "box": Vector3(0.7, 1.8, 0.5)},
	],
	"fuelDrum": {"path": "utility/propane_tank.glb", "box": Vector3(0.6, 1.0, 0.6)},
	"logPile": {"parts": [
		{"path": "nature/log.glb", "box": Vector3(1.0, 0.35, 1.0), "at": Vector3(0, 0, -0.2)},
		{"path": "nature/log.glb", "box": Vector3(1.0, 0.35, 1.0), "at": Vector3(0, 0, 0.2)},
		{"path": "nature/log_branched.glb", "box": Vector3(0.9, 0.35, 0.9), "at": Vector3(0, 0.3, 0)},
	]},
	"displaycase": [
		{"path": "store/display_fridge_stocked.glb", "box": Vector3(1.0, 1.9, 0.8)},
		{"path": "store/display_fridge.glb", "box": Vector3(1.0, 1.9, 0.8)},
	],
	"lunchCounter": {"path": "store/snack_display.glb", "box": Vector3(1.0, 1.1, 0.8)},
}

## By 2D sprite, for a container kind with no row of its own.
const SPRITES := {
	"cabinet": "cabinet", "toolbox": "toolbox", "shelf": "shelf", "medcab": "medcab",
	"crate": "crate", "safe": "safe", "locker": "locker", "milcrate": "militaryCrate",
	"pump": "fuelPump", "drum": "fuelDrum", "logs": "logPile", "bookshelf": "bookshelf",
	"dresser": "dresser", "wardrobe": "wardrobe", "desk": "desk", "filing": "filing",
	"fridge": "fridge", "nightstand": "nightstand", "vanity": "vanity", "footlocker": "footlocker",
	"vending": "vending", "toolrack": "toolrack", "displaycase": "displaycase",
}

## Parked and driven cars, by the car's `si`. The box is a multiple of the
## sim's car (`Vehicles3D`): width, height in metres, length.
const CARS := [
	{"path": "vehicles/roadster.glb", "box": Vector3(1.0, 1.0, 1.0)},
	{"path": "vehicles/pickup_blue.glb", "box": Vector3(1.0, 1.2, 1.0)},
	{"path": "vehicles/pickup_rusty.glb", "box": Vector3(1.0, 1.2, 1.0)},
	{"path": "vehicles/flatbed_truck.glb", "box": Vector3(1.0, 1.4, 1.0)},
]


## The parts that draw a world prop, or an empty list for the stand-in.
static func for_prop(p: Dictionary) -> Array:
	var kind := String(p.get("kind", ""))
	var si := int(p.get("si", 0))
	match kind:
		"litter":
			return resolve(LITTER.get(String(p.get("res", "")), null), si)
		"furniture", "yard", "street", "wall", "decor":
			return resolve(THINGS.get(String(p.get("what", "")), null), si)
		_:
			return resolve(KINDS.get(kind, null), si)


## The parts that draw a container, or an empty list for the stand-in.
static func for_container(c: Dictionary) -> Array:
	var kind := String(c.get("kind", ""))
	if not CONTAINERS.has(kind):
		kind = String(SPRITES.get(String(c.get("sprite", "")), ""))
	return resolve(CONTAINERS.get(kind, null), int(c.get("si", c.get("tx", 0))))


static func for_car(si: int) -> Array:
	return resolve(CARS, si)


## An entry's parts for variant `si`: the variant's own parts, each with
## `box`, `yaw` and `at` filled in and the path made absolute.
static func resolve(entry, si: int) -> Array:
	if entry == null:
		return []
	var variant = entry
	if entry is Array:
		var list: Array = entry
		if list.is_empty():
			return []
		variant = list[posmod(si, list.size())]
	var specs: Array = variant.parts if variant.has("parts") else [variant]
	var out := []
	for s in specs:
		out.append({
			"path": P + String(s.path),
			"box": s.get("box", Vector3(1, 1, 1)),
			"yaw": float(s.get("yaw", 0.0)),
			"at": s.get("at", Vector3.ZERO),
		})
	return out


## Every file the tables name, relative to the props folder, for the test
## that holds them against the catalog.
static func every_path() -> PackedStringArray:
	var seen := {}
	for table in [KINDS, LITTER, THINGS, CONTAINERS]:
		for key in table:
			_paths_of(table[key], seen)
	_paths_of(CARS, seen)
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


static func _paths_of(entry, seen: Dictionary) -> void:
	if entry is Array:
		for e in entry:
			_paths_of(e, seen)
	elif entry is Dictionary:
		if entry.has("parts"):
			_paths_of(entry.parts, seen)
		elif entry.has("path"):
			seen[String(entry.path)] = true
