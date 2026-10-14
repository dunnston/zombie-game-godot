# Props

The owner's static Meshy exports, sorted by **where the thing stands** so dressing a
scene is a matter of opening one folder. Every file is a `.glb` with its three
textures embedded (base colour, metallic/roughness, normal), about 5 MB each.

**The `.glb` files are not in git.** 1.4 GB is past the free LFS quota, so
`.gitignore` keeps them out and only these folders and this README are tracked.
`tools\pack_props.cmd` zips them into `props.zip` in the project folder to send
to a teammate, who unzips it into `assets\models\` so the files land here. A
checkout without them still plays: a missing model draws as a box.

**Nothing here has a real-world size.** Meshy normalises every export to a unit box
(the longest side is 0.95), so a tissue box and a fire truck are the same size on
disk. The view sizes them: `StaticModel.fit(path, footprint)` scales a model so its
longer side fills the tiles it stands on and lifts it onto the ground, and that is
the only place a prop's size is decided. Pick the footprint from what the thing is,
never from the file.

## Conventions

- One folder per place. A thing that could stand in two places goes where it is
  most often found; the table below is the answer when it is not obvious.
- `snake_case` game names, the Meshy prefix and timestamp gone. Variants of the same
  thing are `name`, `name_2`, `name_3` in the order Meshy made them.
- The *Meshy export* column is the file as it landed in `Meshy Models/` (the inbox,
  not in git), so a re-export can be matched to its game name. Ten exports had no
  name at all; those were named from their textures and say so in *Note*.
- **Adding one:** copy the export from `Meshy Models/` into the folder it belongs
  in under a game name, and add a row here. Never load one by its Meshy name.

## Folders

| Folder | Files | What goes there |
| --- | ---: | --- |
| `nature/` | 29 | Trees, bushes, boulders, stumps, logs and branches: what grows or lies on the ground outside town. |
| `street/` | 20 | What stands on a pavement or a roadside: signs, lamps, meters, pumps, bins, benches, the payphone. |
| `vehicles/` | 10 | Cars, trucks and buses, parked or wrecked. |
| `yard/` | 32 | What stands on a lot outside the house: playground kit, pools, patio furniture, clotheslines, planters, the dog house. |
| `furniture/` | 43 | What a room is furnished with: seating, beds, tables, cabinets, bookshelves, the piano, the staircase. |
| `kitchen/` | 17 | Appliances, the island and counters, cookware and food. |
| `bathroom/` | 12 | Toilets, sinks, tubs, showers and what sits beside them. |
| `utility/` | 29 | The utility room, the basement and the outside wall: washers, dryers, heaters, AC units, tanks, panels, switches and outlets, metal shelving. |
| `store/` | 11 | Shop fittings: shelving, display fridges, racks, the hanging sign. |
| `office/` | 8 | Desks, the office chair, the filing cabinet, the monitor, school desks, lockers and the chalkboard. |
| `electronics/` | 7 | Televisions, the radio, the speaker, the microphone, controllers and remotes. |
| `decor/` | 27 | What hangs on a wall or sits on a surface for looks: art, mirrors, clocks, lamps, plants, vases, books, the rug. |
| `small/` | 9 | Hand-sized clutter to scatter: boxes, the cooler, the backpack, the toy train, the pet bowl. |

254 props in all.

## `nature/`

| File | Meshy export | Note |
| --- | --- | --- |
| `ancient_tree.glb` | `Meshy_AI_Ancient_Forest_Guardi_1014141439_texture.glb` |  |
| `boulder_mossy.glb` | `Meshy_AI_Mossy_Boulder_1014141347_texture.glb` |  |
| `boulder_mossy_2.glb` | `Meshy_AI_Mossy_Boulder_1014141616_texture.glb` |  |
| `boulder_mossy_3.glb` | `Meshy_AI_Mossy_Stone_Boulder_1014141610_texture.glb` |  |
| `boulder_pale.glb` | `Meshy_AI_Moonstone_Boulder_1014125002_texture.glb` |  |
| `branch_forked.glb` | `Meshy_AI_Forked_Branch_1014141558_texture.glb` |  |
| `branch_forked_2.glb` | `Meshy_AI_Forked_Branch_1014141604_texture.glb` |  |
| `bush_clover.glb` | `Meshy_AI_Sunlit_Clover_Bush_1014141652_texture.glb` |  |
| `bush_pink_blossom.glb` | `Meshy_AI_Pink_Blossom_Bush_1014141642_texture.glb` |  |
| `bush_red_berry.glb` | `Meshy_AI__1014141454_texture.glb` | no name in the export; named from its texture |
| `corn_stalk.glb` | `Meshy_AI_Golden_Corn_Stalk_1014135351_texture.glb` |  |
| `cypress.glb` | `Meshy_AI_Spanish_Moss_Cypress_1014141425_texture.glb` |  |
| `driftwood.glb` | `Meshy_AI_Branching_Driftwood_1014141545_texture.glb` |  |
| `log.glb` | `Meshy_AI_Timber_Log_1014141659_texture.glb` |  |
| `log_branched.glb` | `Meshy_AI_Branched_Log_1014141539_texture.glb` |  |
| `oak.glb` | `Meshy_AI_Sunlit_Oak_1014141500_texture.glb` |  |
| `oak_2.glb` | `Meshy_AI_Verdant_Oak_1014141506_texture.glb` |  |
| `oak_autumn.glb` | `Meshy_AI_Autumn_Oak_1014141512_texture.glb` |  |
| `palm_tree.glb` | `Meshy_AI__1014141432_texture.glb` | no name in the export; named from its texture |
| `pine.glb` | `Meshy_AI_Majestic_Pine_Tree_1014132936_texture.glb` |  |
| `pine_tall.glb` | `Meshy_AI_Evergreen_Sentinel_1014141523_texture.glb` |  |
| `shrub_golden.glb` | `Meshy_AI_Golden_Garden_Shrub_1014141710_texture.glb` |  |
| `stick_bundle.glb` | `Meshy_AI_Bundle_of_Sticks_1014141552_texture.glb` |  |
| `stone_slab.glb` | `Meshy_AI_Weathered_Stone_Slab_1014141404_texture.glb` |  |
| `straw_patch.glb` | `Meshy_AI__1014135343_texture.glb` | no name in the export; named from its texture; a flat square of straw |
| `tree_bare.glb` | `Meshy_AI_Bare_Branches_1014141447_texture.glb` |  |
| `tree_blossom.glb` | `Meshy_AI_Blossom_Tree_1014141419_texture.glb` |  |
| `tree_stump_ancient.glb` | `Meshy_AI_Ancient_Tree_Stump_1014141529_texture.glb` |  |
| `tree_stump_mossy.glb` | `Meshy_AI_Mossy_Tree_Stump_1014141517_texture.glb` |  |

## `street/`

| File | Meshy export | Note |
| --- | --- | --- |
| `bench_wooden.glb` | `Meshy_AI_Wooden_Bench_1014124646_texture.glb` |  |
| `ev_charger.glb` | `Meshy_AI_Electric_Vehicle_Char_1014142617_texture.glb` |  |
| `fuel_pump_retro.glb` | `Meshy_AI_Retro_Fuel_Pump_1014125016_texture.glb` |  |
| `fuel_pump_retro_2.glb` | `Meshy_AI_Retro_Fuel_Pump_1014130447_texture.glb` |  |
| `fuel_pump_rusty.glb` | `Meshy_AI_Rusty_Vintage_Gas_Pum_1014131052_texture.glb` |  |
| `lamp_post_twin.glb` | `Meshy_AI_Rustworn_Twin_Lamp_Po_1014131009_texture.glb` |  |
| `park_bench.glb` | `Meshy_AI_Parkside_Rest__1014130658_texture.glb` |  |
| `parking_meter.glb` | `Meshy_AI_Parking_Meter_1014130453_texture.glb` |  |
| `payphone.glb` | `Meshy_AI_Blue_Payphone_1014125601_texture.glb` |  |
| `pillar_rusted.glb` | `Meshy_AI_Rustworn_Pillar_1014131023_texture.glb` |  |
| `sign_blank.glb` | `Meshy_AI_Blank_Road_Sign_1014142527_texture.glb` |  |
| `sign_right_turn.glb` | `Meshy_AI_Right_Turn_Sign_1014142509_texture.glb` |  |
| `sign_stop.glb` | `Meshy_AI_Stop_Sign_1014125527_texture.glb` |  |
| `sign_yield.glb` | `Meshy_AI_Yield_Sign_1014125510_texture.glb` |  |
| `signpost.glb` | `Meshy_AI_Blue_Signpost_1014125453_texture.glb` |  |
| `streetlamp.glb` | `Meshy_AI_Twilight_Streetlamp_1014130650_texture.glb` |  |
| `streetlamp_vintage.glb` | `Meshy_AI_Vintage_Streetlamp_1014124742_texture.glb` |  |
| `trash_can.glb` | `Meshy_AI_Silver_Trash_Can_1014141956_texture.glb` |  |
| `vending_machine.glb` | `Meshy_AI_Beverage_Vending_Mach_1014125612_texture.glb` |  |
| `wheelie_bin.glb` | `Meshy_AI_Green_Wheeled_Trash_B_1014130712_texture.glb` |  |

## `vehicles/`

| File | Meshy export | Note |
| --- | --- | --- |
| `box_truck.glb` | `Meshy_AI_Box_Truck_1014125126_texture.glb` |  |
| `city_bus.glb` | `Meshy_AI_Blue_City_Bus_1014125119_texture.glb` |  |
| `fire_truck.glb` | `Meshy_AI_Ladder_Fire_Truck_1014125205_texture.glb` |  |
| `flatbed_truck.glb` | `Meshy_AI_Flatbed_Delivery_Truc_1014125135_texture.glb` |  |
| `garbage_truck.glb` | `Meshy_AI_Green_Garbage_Truck_1014125151_texture.glb` |  |
| `pickup_blue.glb` | `Meshy_AI_Blue_Vintage_Pickup_T_1014125212_texture.glb` |  |
| `pickup_rusty.glb` | `Meshy_AI_Rusty_Red_Pickup_1014131036_texture.glb` |  |
| `roadster.glb` | `Meshy_AI_Crimson_Roadster_1014125159_texture.glb` |  |
| `school_bus.glb` | `Meshy_AI_Golden_School_Bus_1014125144_texture.glb` |  |
| `tractor.glb` | `Meshy_AI_Red_Tractor_1014135335_texture.glb` |  |

## `yard/`

| File | Meshy export | Note |
| --- | --- | --- |
| `basketball_hoop.glb` | `Meshy_AI_Portable_Basketball_H_1014125650_texture.glb` |  |
| `basketball_hoop_wall.glb` | `Meshy_AI_Backboard_and_Hoop_1014130550_texture.glb` |  |
| `beach_chair.glb` | `Meshy_AI_Beach_Chair_1014125553_texture.glb` |  |
| `birdbath.glb` | `Meshy_AI_Stone_Birdbath_1014141948_texture.glb` |  |
| `clothesline_rotary.glb` | `Meshy_AI_Rotary_Clothesline_1014125852_texture.glb` |  |
| `clothesline_rotary_2.glb` | `Meshy_AI_Rotary_Clothesline_1014125901_texture.glb` |  |
| `crawlspace_doors.glb` | `Meshy_AI_crawalspace_doors_1014130326_texture.glb` |  |
| `dog_house.glb` | `Meshy_AI_Cozy_Canine_Cabin_1014125934_texture.glb` |  |
| `drying_rack.glb` | `Meshy_AI_Clothesline_Drying_Ra_1014125908_texture.glb` |  |
| `fountain.glb` | `Meshy_AI_Tiered_Stone_Fountain_1014130732_texture.glb` |  |
| `garden_pot.glb` | `Meshy_AI_Terracotta_Garden_Pot_1014142419_texture.glb` |  |
| `hot_tub.glb` | `Meshy_AI_Octagonal_Wooden_Hot__1014124933_texture.glb` |  |
| `kiln.glb` | `Meshy_AI_Desert_Kiln_1014124905_texture.glb` |  |
| `lawn_flamingo.glb` | `Meshy_AI_Pink_Flamingo_Lawn_Or_1014142700_texture.glb` |  |
| `merry_go_round.glb` | `Meshy_AI_Rainbow_Merry_Go_Roun_1014125916_texture.glb` |  |
| `patio_chair_olive.glb` | `Meshy_AI_Olive_Patio_Chair_1014125332_texture.glb` |  |
| `patio_chair_white.glb` | `Meshy_AI_White_Patio_Chair_1014125426_texture.glb` |  |
| `patio_heater.glb` | `Meshy_AI_outdoor_hearter_1014125826_texture.glb` |  |
| `picnic_table.glb` | `Meshy_AI_Colorful_Picnic_Table_1014130000_texture.glb` |  |
| `picnic_table_shaded.glb` | `Meshy_AI_Shaded_Picnic_Haven_1014130012_texture.glb` |  |
| `planter_square.glb` | `Meshy_AI_Terracotta_Square_Pla_1014142432_texture.glb` |  |
| `pool.glb` | `Meshy_AI_Serene_Pool_1014132912_texture.glb` |  |
| `pool_above_ground.glb` | `Meshy_AI_above_ground_pool_1014132850_texture.glb` |  |
| `pool_float_chicken.glb` | `Meshy_AI_Chicken_Float_1014125224_texture.glb` |  |
| `sandbox.glb` | `Meshy_AI_Sandbox_Solitude_1014130020_texture.glb` |  |
| `slide.glb` | `Meshy_AI_Playground_Slide_1014125925_texture.glb` |  |
| `slide_rainbow.glb` | `Meshy_AI_Rainbow_Playground_Sl_1014125943_texture.glb` |  |
| `sun_lounger.glb` | `Meshy_AI_Cream_Cushioned_Loung_1014125706_texture.glb` |  |
| `swing_set.glb` | `Meshy_AI_Double_Swing_Set_1014124721_texture.glb` |  |
| `trampoline.glb` | `Meshy_AI_Blue_Trampoline_1014124709_texture.glb` |  |
| `wagon.glb` | `Meshy_AI_Red_Wagon_1014142010_texture.glb` |  |
| `wheelbarrow.glb` | `Meshy_AI_Wheelbarrow_1014125620_texture.glb` |  |

## `furniture/`

| File | Meshy export | Note |
| --- | --- | --- |
| `armchair_cozy.glb` | `Meshy_AI_Cozy_Armchair_1014130925_texture.glb` |  |
| `armchair_green.glb` | `Meshy_AI_Green_Armchair_1014125950_texture.glb` |  |
| `armchair_modern.glb` | `Meshy_AI_Modern_Armchair_1014125420_texture.glb` |  |
| `bed_ivory.glb` | `Meshy_AI_Ivory_Dream_Bed_1014130126_texture.glb` |  |
| `bed_rustic.glb` | `Meshy_AI_Rustic_Wooden_Bed_1014130146_texture.glb` |  |
| `bed_single.glb` | `Meshy_AI_Wooden_Single_Bed_1014130119_texture.glb` |  |
| `bedside_cabinet.glb` | `Meshy_AI_Wooden_Bedside_Cabine_1014130824_texture.glb` |  |
| `bedside_table.glb` | `Meshy_AI_Golden_Bedside_Table_1014130911_texture.glb` |  |
| `bookshelf.glb` | `Meshy_AI_Wooden_Bookshelf_1014130057_texture.glb` |  |
| `bookshelf_2.glb` | `Meshy_AI_Wooden_Bookshelf_1014130110_texture.glb` |  |
| `bookshelf_3.glb` | `Meshy_AI_Wooden_Bookshelf_1014130903_texture.glb` |  |
| `bookshelf_leaning.glb` | `Meshy_AI_Leaning_Library_1014142311_texture.glb` |  |
| `bookshelf_trio.glb` | `Meshy_AI_Bookshelf_trio_1014142255_texture.glb` |  |
| `bunk_bed.glb` | `Meshy_AI_Wooden_Bunk_Bed_1014130132_texture.glb` |  |
| `bunk_bed_2.glb` | `Meshy_AI_Wooden_Bunk_Bed_1014130152_texture.glb` |  |
| `cabinet_beige.glb` | `Meshy_AI_Beige_Storage_Cabinet_1014125103_texture.glb` |  |
| `cabinet_brown.glb` | `Meshy_AI_Brown_Wooden_Cabinet_1014125049_texture.glb` |  |
| `cabinet_glass_door.glb` | `Meshy_AI_Glass_Door_Cabinet_1014132812_texture.glb` |  |
| `cabinet_modern.glb` | `Meshy_AI_Modern_Storage_Cabine_1014124921_texture.glb` |  |
| `cabinet_sliding_door.glb` | `Meshy_AI_Wooden_Sliding_Door_C_1014125042_texture.glb` |  |
| `cabinet_storage.glb` | `Meshy_AI_Storage_Cabinet_1014124857_texture.glb` |  |
| `cabinet_white.glb` | `Meshy_AI_White_Storage_Cabinet_1014124828_texture.glb` |  |
| `cabinet_wooden.glb` | `Meshy_AI_Wooden_Cabinet_1014125035_texture.glb` |  |
| `chair_folding.glb` | `Meshy_AI_Wooden_Folding_Chair_1014125434_texture.glb` |  |
| `chair_folding_2.glb` | `Meshy_AI_Wooden_Folding_Chair_1014130535_texture.glb` |  |
| `crib.glb` | `Meshy_AI_Pastel_Crib_1014125503_texture.glb` |  |
| `dresser.glb` | `Meshy_AI_Rustic_Wooden_Dresser_1014130837_texture.glb` |  |
| `fireplace.glb` | `Meshy_AI_Stone_fireplace_1014125630_texture.glb` |  |
| `high_chair.glb` | `Meshy_AI_Toddler_High_Chair_1014125844_texture.glb` |  |
| `loveseat.glb` | `Meshy_AI_Green_Loveseat_1014130918_texture.glb` |  |
| `media_console.glb` | `Meshy_AI_Rustic_Wooden_Media_C_1014132839_texture.glb` |  |
| `nightstand.glb` | `Meshy_AI_Four_Drawer_Nightstan_1014130830_texture.glb` |  |
| `piano.glb` | `Meshy_AI_Vintage_Upright_Piano_1014124426_texture.glb` |  |
| `room_divider.glb` | `Meshy_AI_Wooden_Folding_Room_D_1014125540_texture.glb` |  |
| `sofa.glb` | `Meshy_AI_Golden_Comfort_Sofa_1014130931_texture.glb` |  |
| `staircase.glb` | `Meshy_AI_Wooden_Staircase_1014125657_texture.glb` |  |
| `stool.glb` | `Meshy_AI_Wooden_Stool_1014130528_texture.glb` |  |
| `table.glb` | `Meshy_AI_Wooden_Table_1014124612_texture.glb` |  |
| `table_2.glb` | `Meshy_AI_Wooden_Table_1014125324_texture.glb` |  |
| `table_glass.glb` | `Meshy_AI_Frosted_Glass_Table_1014125255_texture.glb` |  |
| `table_glass_yellow.glb` | `Meshy_AI_Yellow_Glass_Top_Free_1014125519_texture.glb` |  |
| `table_rustic.glb` | `Meshy_AI_Rustic_Wooden_Table_1014130027_texture.glb` |  |
| `table_rustic_2.glb` | `Meshy_AI_Rustic_Wooden_Table_1014130857_texture.glb` |  |

## `kitchen/`

| File | Meshy export | Note |
| --- | --- | --- |
| `bowl_cream.glb` | `Meshy_AI_Octagonal_Cream_Bowl_1014141904_texture.glb` |  |
| `bowl_wooden.glb` | `Meshy_AI_Faceted_Wooden_Bowl_1014141844_texture.glb` |  |
| `cabinets_cream.glb` | `Meshy_AI__1014125546_texture.glb` | no name in the export; named from its texture; a run of cream cabinets with dark panels |
| `coffee_maker.glb` | `Meshy_AI_Coffee_Maker_1014142347_texture.glb` |  |
| `fruit_bowl.glb` | `Meshy_AI_Gemstone_Fruit_Bowl_1014141857_texture.glb` |  |
| `island.glb` | `Meshy_AI_Kitchen_Island_1014135430_texture.glb` |  |
| `microwave.glb` | `Meshy_AI_Microwave_Oven_1014142452_texture.glb` |  |
| `platter.glb` | `Meshy_AI_Empty_Serving_Platter_1014141823_texture.glb` |  |
| `range_hood.glb` | `Meshy_AI_Ivory_Range_Hood_1014130425_texture.glb` |  |
| `refrigerator.glb` | `Meshy_AI_refrigerator_1014124731_texture.glb` |  |
| `sandwich_plate.glb` | `Meshy_AI_Club_Sandwiches_on_a__1014141918_texture.glb` |  |
| `saucepan.glb` | `Meshy_AI_Lidded_Saucepan_1014141939_texture.glb` |  |
| `sink_rusty.glb` | `Meshy_AI_Rusty_Sink_1014130955_texture.glb` |  |
| `skillet.glb` | `Meshy_AI_Forged_Skillet_1014142018_texture.glb` |  |
| `stove.glb` | `Meshy_AI_Vintage_Electric_Stov_1014125028_texture.glb` |  |
| `stove_2.glb` | `Meshy_AI_Vintage_Electric_Stov_1014130138_texture.glb` |  |
| `table_setting.glb` | `Meshy_AI_Table_Setting_1014141912_texture.glb` |  |

## `bathroom/`

| File | Meshy export | Note |
| --- | --- | --- |
| `bathtub.glb` | `Meshy_AI_Serene_Soak_1014130725_texture.glb` |  |
| `bathtub_clawfoot.glb` | `Meshy_AI_Vintage_Clawfoot_Bath_1014130719_texture.glb` |  |
| `plunger.glb` | `Meshy_AI_Toilet_Plunger_1014141727_texture.glb` |  |
| `shower_enclosure.glb` | `Meshy_AI_Glass_Shower_Enclosur_1014132923_texture.glb` |  |
| `shower_stall.glb` | `Meshy_AI_Glass_Shower_Stall_1014124807_texture.glb` |  |
| `sink_pedestal.glb` | `Meshy_AI_Pedestal_Sink_1014130618_texture.glb` |  |
| `toilet.glb` | `Meshy_AI_Open_Toilet_1014130612_texture.glb` |  |
| `toilet_paper.glb` | `Meshy_AI_Toilet_paper_roll_1014141741_texture.glb` |  |
| `toilet_rusty.glb` | `Meshy_AI_Rustworn_Porcelain_Th_1014130942_texture.glb` |  |
| `toilet_rusty_2.glb` | `Meshy_AI_Rustworn_Porcelain_Th_1014130949_texture.glb` |  |
| `towels.glb` | `Meshy_AI_Stacked_Towels_1014142305_texture.glb` |  |
| `vanity_sink.glb` | `Meshy_AI_Cream_Vanity_Sink_1014130639_texture.glb` |  |

## `utility/`

| File | Meshy export | Note |
| --- | --- | --- |
| `ac_wall.glb` | `Meshy_AI_Wall_Mounted_Air_Cond_1014142604_texture.glb` |  |
| `ac_window.glb` | `Meshy_AI_Vintage_Window_Air_Co_1014125218_texture.glb` |  |
| `antenna.glb` | `Meshy_AI_Yagi_Antenna_1014124656_texture.glb` |  |
| `barrel_stone.glb` | `Meshy_AI_Octagonal_Stone_Barre_1014142520_texture.glb` |  |
| `craftsman_bench.glb` | `Meshy_AI_Weathered_Craftsman_s_1014130851_texture.glb` | Meshy cut the name off at 'Weathered Craftsman's'; a long low bench |
| `dryer.glb` | `Meshy_AI_Vintage_Dryer_1014125802_texture.glb` |  |
| `laundry_basket.glb` | `Meshy_AI_Colorful_Laundry_Bask_1014142355_texture.glb` |  |
| `laundry_pile.glb` | `Meshy_AI_Colorful_Laundry_Pile_1014125534_texture.glb` |  |
| `led_light_bar.glb` | `Meshy_AI_LED_Light_Bar_1014142138_texture.glb` |  |
| `light_switch.glb` | `Meshy_AI_Light_Switch_1014141734_texture.glb` |  |
| `light_switch_double.glb` | `Meshy_AI_Double_Light_Switch_1014141815_texture.glb` |  |
| `pegboard.glb` | `Meshy_AI_Tool_Pegboard_1014130604_texture.glb` |  |
| `propane_tank.glb` | `Meshy_AI_Propane_Cylinder_1014142538_texture.glb` |  |
| `radiator.glb` | `Meshy_AI_Cream_Panel_Radiator_1014125247_texture.glb` |  |
| `radiator_vintage.glb` | `Meshy_AI_Vintage_Radiator_1014142611_texture.glb` |  |
| `satellite_dish.glb` | `Meshy_AI_Satellite_Dish_1014124941_texture.glb` |  |
| `shelf_metal.glb` | `Meshy_AI_Metal_Storage_Shelf_1014124913_texture.glb` |  |
| `sink_utility.glb` | `Meshy_AI_Utility_Sink_Vanity_1014124843_texture.glb` |  |
| `sink_utility_rusty.glb` | `Meshy_AI_Rusty_Utility_Sink_1014125723_texture.glb` |  |
| `solar_panel.glb` | `Meshy_AI_Solar_Panel_Stand_1014125714_texture.glb` |  |
| `space_heater.glb` | `Meshy_AI_Retro_Space_Heater_1014125230_texture.glb` |  |
| `storage_chest_striped.glb` | `Meshy_AI_Rust_Striped_Storage__1014131030_texture.glb` | Meshy cut the name off at 'Rust Striped Storage'; a long low box |
| `vent_shield.glb` | `Meshy_AI_Iron_Vent_Shield_1014142551_texture.glb` |  |
| `ventilator.glb` | `Meshy_AI_Rustbound_Ventilator_1014131003_texture.glb` |  |
| `wall_outlet.glb` | `Meshy_AI_Ivory_Wall_Outlet_1014141800_texture.glb` |  |
| `washing_machine.glb` | `Meshy_AI_Washing_Machine_1014130510_texture.glb` |  |
| `washing_machine_rusty.glb` | `Meshy_AI_Rusty_Washing_Machine_1014125755_texture.glb` |  |
| `washing_machine_top_load.glb` | `Meshy_AI_Top_Loading_Washing_M_1014130502_texture.glb` |  |
| `water_cooler.glb` | `Meshy_AI_Dual_Tap_Cooler_1014142646_texture.glb` |  |

## `store/`

| File | Meshy export | Note |
| --- | --- | --- |
| `display_fridge.glb` | `Meshy_AI_Grocery_Store_Refrige_1014130047_texture.glb` |  |
| `display_fridge_stocked.glb` | `Meshy_AI_Stocked_Display_Refri_1014130041_texture.glb` |  |
| `grocery_shelf.glb` | `Meshy_AI_Grocery_Shelf_1014124715_texture.glb` |  |
| `grocery_shelf_stocked.glb` | `Meshy_AI_Colorful_Grocery_Shel_1014130433_texture.glb` |  |
| `grocery_shelf_stocked_2.glb` | `Meshy_AI_Colorful_Grocery_Shel_1014130440_texture.glb` |  |
| `market_shelf.glb` | `Meshy_AI_Mini_Market_Shelf_1014124703_texture.glb` |  |
| `pantry_shelf.glb` | `Meshy_AI_Pantry_Shelf_Display_1014130806_texture.glb` |  |
| `pantry_shelf_rusty.glb` | `Meshy_AI_Rusty_Pantry_Shelf_1014130843_texture.glb` |  |
| `postcard_rack.glb` | `Meshy_AI_Scenic_Postcard_Rack_1014125317_texture.glb` |  |
| `sign_hanging.glb` | `Meshy_AI_Hanging_Wooden_Sign_1014130705_texture.glb` |  |
| `snack_display.glb` | `Meshy_AI_Rolling_Snack_Display_1014130521_texture.glb` |  |

## `office/`

| File | Meshy export | Note |
| --- | --- | --- |
| `chalkboard.glb` | `Meshy_AI_Wooden_Chalkboard_1014135412_texture.glb` |  |
| `desk_classic.glb` | `Meshy_AI_Classic_Wooden_Desk_1014130740_texture.glb` |  |
| `desk_executive.glb` | `Meshy_AI_Wooden_Executive_Desk_1014135419_texture.glb` |  |
| `filing_cabinet.glb` | `Meshy_AI_Golden_Filing_Cabinet_1014130543_texture.glb` |  |
| `lockers.glb` | `Meshy_AI_Blue_School_Lockers_1014135405_texture.glb` |  |
| `monitor.glb` | `Meshy_AI_Computer_monitor_1014142447_texture.glb` |  |
| `office_chair.glb` | `Meshy_AI_Blue_Office_Chair_1014142641_texture.glb` |  |
| `school_desk.glb` | `Meshy_AI_School_Desk_1014135358_texture.glb` |  |

## `electronics/`

| File | Meshy export | Note |
| --- | --- | --- |
| `floor_speaker.glb` | `Meshy_AI__1014142544_texture.glb` | no name in the export; named from its texture |
| `game_controller.glb` | `Meshy_AI_Game_Controller_1014142322_texture.glb` |  |
| `microphone.glb` | `Meshy_AI_Vintage_Microphone_1014142340_texture.glb` |  |
| `radio.glb` | `Meshy_AI_Vintage_Radio_1014142230_texture.glb` |  |
| `remote.glb` | `Meshy_AI_Remote_Control_1014141721_texture.glb` |  |
| `tv_flat.glb` | `Meshy_AI_Modern_Flat_Screen_TV_1014135318_texture.glb` |  |
| `tv_retro.glb` | `Meshy_AI_Retro_Television_1014125307_texture.glb` |  |

## `decor/`

| File | Meshy export | Note |
| --- | --- | --- |
| `book_stack.glb` | `Meshy_AI_Vintage_Book_Stack_1014142250_texture.glb` |  |
| `ceiling_fan.glb` | `Meshy_AI_Three_Light_Ceiling_F_1014141748_texture.glb` |  |
| `chandelier.glb` | `Meshy_AI_Rustic_Four_Light_Cha_1014141923_texture.glb` |  |
| `globe.glb` | `Meshy_AI_Vintage_Globe_1014142439_texture.glb` |  |
| `houseplant.glb` | `Meshy_AI_Emerald_Houseplant_1014142401_texture.glb` |  |
| `lamp_pendant.glb` | `Meshy_AI_Vintage_Pendant_Lamp_1014141830_texture.glb` |  |
| `lamp_table.glb` | `Meshy_AI_Beige_Lampshade_1014142334_texture.glb` |  |
| `mirror_arched.glb` | `Meshy_AI_Bronze_Arched_Mirror_1014125730_texture.glb` |  |
| `mirror_brass.glb` | `Meshy_AI_Weathered_Brass_Mirro_1014125809_texture.glb` |  |
| `mirror_wide.glb` | `Meshy_AI_Bronze_Reflection_1014125735_texture.glb` |  |
| `painting_abstract_red.glb` | `Meshy_AI__1014142030_texture.glb` | no name in the export; named from its texture; red, black and cream abstract |
| `painting_coastal.glb` | `Meshy_AI_Coastal_Lines_1014142155_texture.glb` |  |
| `painting_portrait_faceless.glb` | `Meshy_AI_Faceless_Portrait_in__1014142113_texture.glb` |  |
| `painting_primary_shapes.glb` | `Meshy_AI_Primary_Shapes_1014141808_texture.glb` |  |
| `painting_skyline.glb` | `Meshy_AI_Colorful_Skyline_Bloc_1014142100_texture.glb` |  |
| `painting_triangles.glb` | `Meshy_AI_Prismatic_Triangles_1014142144_texture.glb` |  |
| `plant_potted.glb` | `Meshy_AI_Potted_Greenery_1014142413_texture.glb` |  |
| `plant_snake.glb` | `Meshy_AI_Potted_Snake_Plant_1014142407_texture.glb` |  |
| `plant_terracotta.glb` | `Meshy_AI__1014142635_texture.glb` | no name in the export; named from its texture; a green plant in a terracotta pot |
| `plant_yellow_flowers.glb` | `Meshy_AI__1014142558_texture.glb` | no name in the export; named from its texture; yellow flowers in a pale pot |
| `portrait_business.glb` | `Meshy_AI_Framed_Business_Portr_1014142106_texture.glb` |  |
| `portrait_gentleman.glb` | `Meshy_AI_Framed_Gentleman_1014142204_texture.glb` |  |
| `portrait_red_scarf.glb` | `Meshy_AI__1014142054_texture.glb` | no name in the export; named from its texture; a framed figure in a red scarf |
| `rug.glb` | `Meshy_AI_Layered_Rectangular_Rug_1014130406_texture.glb` |  |
| `vase_tulips.glb` | `Meshy_AI_Yellow_Tulips_in_a_Va_1014142243_texture.glb` |  |
| `vase_white_blossoms.glb` | `Meshy_AI_White_Blossoms_in_a_V_1014142237_texture.glb` |  |
| `wall_clock.glb` | `Meshy_AI_Pendulum_Wall_Clock_1014142040_texture.glb` |  |

## `small/`

| File | Meshy export | Note |
| --- | --- | --- |
| `backpack.glb` | `Meshy_AI_Olive_Trailpack_1014125238_texture.glb` |  |
| `cardboard_box.glb` | `Meshy_AI_Sealed_Cardboard_Box_1014142047_texture.glb` |  |
| `cooler.glb` | `Meshy_AI_Blue_Cooler_Box_1014142628_texture.glb` |  |
| `crate_wooden.glb` | `Meshy_AI_Wooden_Box_1014142005_texture.glb` |  |
| `pet_bowl.glb` | `Meshy_AI_Dual_Hex_Pet_Bowl_1014141929_texture.glb` |  |
| `shopping_bag.glb` | `Meshy_AI__1014142327_texture.glb` | no name in the export; named from its texture; orange, tall, with loop handles |
| `storage_box.glb` | `Meshy_AI_Storage_Box_1014141754_texture.glb` |  |
| `tissue_box.glb` | `Meshy_AI_Tissue_Box_1014141850_texture.glb` |  |
| `toy_train.glb` | `Meshy_AI_Wooden_Toy_Train_1014141838_texture.glb` |  |
