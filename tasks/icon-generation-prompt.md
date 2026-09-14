# Icon generation prompt — paste into an image-capable chat

## How to use this

1. Open a new chat with whatever AI you want to design the art (one that can
   generate images — e.g. ChatGPT with image generation, Gemini, Midjourney).
2. Paste the **Style Bible** below first, by itself, so it's established
   before any items show up.
3. Then paste each **Batch** in order, one per message, *in that same
   conversation* — that's what keeps 143 icons looking like one set instead
   of 143 unrelated pictures.
4. Ask it to save/export every image, one PNG per item, and tell you which
   file is which id (the prompt already asks for this).
5. Send me (Claude Code) everything it produces. I'll drop each PNG into
   `art/items/<id>.png` — that's the exact filename the game already looks
   for (`src/sim/items.gd`, enforced by `tests/icons_test.gd`) — so nothing
   else needs to change in code for items, weapons, gear, and consumables.

**One thing to know going in:** walls and other buildables (Batches 12–13)
render from flat hex colors in the build menu and the world today — there's
no icon-file hookup for them yet. I'll wire that up myself once you have art
for them; you don't need to do anything differently in the prompt below.

---

## Style Bible (paste this first)

I'm making icon art for a top-down 2D post-apocalyptic zombie survival game
called DEADLINE, built in Godot. I need a complete, consistent icon set for
every item, weapon, piece of gear, and buildable in the game. Right now
everything is a flat colored square placeholder — I need real icons that let
a player tell items apart at a glance in a small inventory grid.

**Design priorities (in order): readability over fidelity, fun over
realism.** These are not photoreal renders — they're clear, high-contrast
icons that read correctly at a tiny size, the way item icons in games like
Don't Starve, Project Zomboid, or Terraria do: simplified shapes, strong
silhouette, minimal fine detail, no clutter.

**Technical spec — every icon must follow this exactly:**
- Square canvas, 128×128 px (or a resolution you can export cleanly to that).
- Transparent background (no background color, frame, or drop shadow — the
  game draws its own slot frame around it).
- Subject centered, filling most of the frame with a small margin — icons
  get scaled down to ~34×25 px in inventory slots and ~16×16 px on the
  ground, so anything thin, small, or low-contrast disappears at that size.
- No text, letters, numbers, or UI chrome baked into the image — just the
  object.
- One item per image.

**Consistency rules across the whole set (critical):**
- Same rendering style for every single icon — pick one and hold it for all
  143: flat/vector-shaded illustration with clean outlines is a good
  default, but a light painterly style works too as long as EVERY icon uses
  it identically.
- Same light source and shading direction on every icon (e.g., soft light
  from the upper-left) so nothing looks like it's from a different set.
- Same outline weight and level of detail on every icon.
- Each item already has a canonical color in the game (I'll give you a hex
  code per item below) — use that hex as the item's dominant/base color so
  the new art matches the color the player already associates with that
  item elsewhere in the UI. Treat it as the primary material color, not a
  tint over the whole image — a "steel" item can still have grey highlights
  and dark shadow, just anchored on that hex.
- Where an item has obvious siblings (three tiers of the same armor slot,
  five different knives, four different walls), make sure they're
  distinguishable from each other by shape/silhouette, not just color —
  that's the whole point of this exercise. I've added a short visual note
  per item below specifically to help you tell lookalikes apart.

**Output format:** For each item, generate one image and tell me the exact
filename to save it as (I'll give you the filename — it's always
`<id>.png`, using the id in parentheses below). Work through a batch
completely before I send you the next one. If at any point you can't
generate an image directly, give me a precise enough visual description
that I can hand it to an image generator myself — but images are strongly
preferred.

Confirm you've got the style locked in, then I'll send Batch 1.

---

## Batch 1 — Raw materials & salvage (16 icons)

Everyday scavenged materials. These need to look like real salvage, not
fantasy resource icons — think "pile of X you'd actually pick up in a
ruined town."

- `wood` — Wood — `#a3763f` — a few stacked wooden planks/logs
- `sticks` — Sticks — `#8a6a3c` — a small bundle of thin branches/twigs
- `stone` — Stone — `#8f8a80` — a couple of fist-sized grey rocks
- `fiber` — Fiber — `#9aae5a` — a twist/hank of plant fiber or dry grass cordage
- `scrap` — Scrap — `#9aa2ab` — a jagged bent piece of sheet metal, unmistakably metal junk (this is one of the ones you specifically wanted distinct from Stone and from Weapon Parts below)
- `cloth` — Cloth — `#c2a98a` — a folded/torn piece of fabric
- `elec` — Electronics — `#59b8c4` — a small circuit board or tangle of wires/components
- `battery` — Batteries — `#8fd08a` — one or two cylindrical batteries
- `med` — Medical (raw material, not a usable item) — `#d9575f` — a loose roll of gauze/medical supplies, distinct from the Bandage/Medkit items in Batch 8
- `parts` — Weapon Parts — `#c9a227` — small precision metal components (springs, a gear, a bolt) — should read as "gun parts," not generic scrap
- `mil` — Military (supplies) — `#7fa14a` — an olive-drab ammo box or military crate fragment
- `fuel` — Fuel — `#d2762c` — a red/orange metal jerry can
- `rations` — Rations — `#c4a86a` — a sealed field-ration pouch/box, generic (not a specific food, which are separate items in Batch 8)
- `compost` — Compost — `#5a4a32` — a dark clump of rich soil/compost
- `sludge` — Mutagen Sludge — `#b06ad0` — a small jar/vial of glowing purple viscous liquid
- `precision` — Precision Parts — `#9fd0ff` — small, clean, high-tech machined metal parts with a faint blue tint — should read as rarer/cleaner than Weapon Parts above

## Batch 2 — Seeds & ammo (7 icons)

Three seed varieties (must look clearly different from each other) and four
ammo types.

- `seedPotato` — Potato Eyes — `#c9a86a` — a few knobby potato eyes/small potato chunks in a small pouch
- `seedCorn` — Corn Seed — `#e0c24a` — a handful of yellow corn kernels
- `seedHerb` — Herb Seed — `#9aae5a` — tiny green herb seeds/sprigs, visibly smaller/finer than the corn kernels
- `arrow` — Arrows — `#b9a072` — a small bundle of fletched wooden arrows
- `ammoP` — 9mm Rounds — `#d8c98a` — a stack/handful of small pistol cartridges
- `ammoS` — Shells — `#c9584e` — a couple of red shotgun shells with brass base
- `ammoR` — Rifle Rounds — `#b8a05a` — a stack of longer rifle cartridges, visibly bigger than the 9mm rounds

## Batch 3 — Melee weapons I (20 icons)

Blunt and edged melee weapons/tools. Each name below is followed by a note
to keep visually distinct from its closest sibling — there are a lot of
similar-sounding items in this set.

- `pipe` — Steel Pipe — `#9aa2ab` — a plain bent length of grey steel pipe
- `machete` — Machete — `#cfd6dd` — long, wide, single-edge chopping blade, simple handle
- `axe` — Hatchet — `#b08a5a` — small one-handed axe, wood handle, single blade head
- `pick` — Stone Pickaxe — `#9a9088` — crude stone pick-head lashed with cord to a wooden handle (make it look primitive/DIY)
- `knife` — Stone Knife — `#c2b8a6` — a knapped flint blade with a cord-wrapped wooden grip (primitive, distinct from the steel kitchen/hunting knives in Batch 4)
- `scythe` — Scythe — `#b9b3a2` — a long curved blade mounted at an angle on a long pole
- `hammer` — Stone Hammer — `#8a8078` — a heavy stone head lashed to a wood handle
- `fireaxe` — Fire Axe — `#c4463a` — red-painted firefighter's axe with a flat spike on the back of the head
- `steelpick` — Steel Pickaxe — `#aeb6bd` — full steel pick head (both points), wood handle — should read as a clear upgrade from the Stone Pickaxe
- `sledge` — Sledgehammer — `#8d7a5e` — heavy flat-faced steel head on a long handle
- `varsityBat` — Varsity Bat — `#c9a227` — a wooden baseball bat with school colors/tape wrapped on the grip
- `bladedPike` — Bladed Pike — `#8d97a1` — a long polearm with a narrow spear/blade tip
- `doubleBitAxe` — Double-Bit Axe — `#a2742f` — an axe head with a blade on both sides
- `leafSpringBlade` — Leaf-Spring Blade — `#3f4449` — a curved sharpened car leaf-spring turned into a blade, dark tempered steel
- `makeshiftConcreteClub` — Makeshift Concrete Club — `#9a9a94` — a length of rebar with a lump of concrete/chunks embedded at the striking end
- `metalSpear` — Metal Spear — `#9aa2ab` — a steel pipe with a welded sharpened point
- `pistonHammer` — Piston Hammer — `#6f7a82` — an engine piston welded to the end of a pipe handle
- `woodenSpear` — Wooden Spear — `#b08a5a` — a plain sharpened wooden stick/spear, no metal
- `baseballBat` — Baseball Bat — `#c9a56b` — a plain unmodified wooden bat (contrast with the Varsity Bat's tape/colors and the Spiked Bat's nails in Batch 4)
- `boarSpear` — Boar Spear — `#86705a` — a hunting spear with a crossbar just below the blade tip

## Batch 4 — Melee weapons II (20 icons)

- `campingAxe` — Camping Axe — `#9a6f45` — a small backpacking hatchet, smaller/lighter-looking than the Hatchet in Batch 3
- `chainsaw` — Chainsaw — `#d8642c` — an orange-and-black gas chainsaw with visible chain
- `cleaver` — Cleaver — `#c3ccd4` — a wide rectangular butcher's cleaver blade
- `crowbar` — Crowbar — `#8f9499` — a steel bar with a curved claw/flat end
- `fryingPan` — Frying Pan — `#4a4a4a` — a cast-iron frying pan with a handle
- `gardenSpear` — Garden Spear — `#7f8c7a` — a garden fork/pitchfork tine welded onto a long pole, improvised
- `halliganBar` — Halligan Bar — `#b5443a` — a black forked firefighter's prying tool
- `huntingKnife` — Hunting Knife — `#b9c2cb` — a fixed-blade steel knife with a brown wrapped handle (steel, unlike the flint Stone Knife)
- `katana` — Katana — `#dfe6ec` — a curved single-edge sword with a wrapped grip
- `kitchenKnife` — Kitchen Knife — `#d5dbe1` — a plain steel chef's knife
- `kukri` — Kukri — `#a8b2bb` — a thick, inward-curving blade knife
- `largeWrench` — Large Wrench — `#79828a` — an oversized steel spanner/wrench
- `mace` — Mace — `#8a8f96` — a flanged metal ball-head on a short shaft
- `makeshiftKnifeSpear` — Makeshift Knife Spear — `#a89070` — a kitchen-style knife lashed to a wooden pole
- `maul` — Maul — `#7c6a50` — a huge wedge-faced splitting hammer, bigger than the Sledgehammer
- `pitchfork` — Pitchfork — `#9aa08f` — a farm pitchfork with 3–4 tines
- `policeBaton` — Police Baton — `#2f3336` — a plain black straight baton
- `shovel` — Shovel — `#7d8a93` — a flat-bladed digging shovel
- `spikedBat` — Spiked Bat — `#b08a52` — a wooden bat with nails driven through the barrel
- `splittingAxe` — Splitting Axe — `#8b6239` — a wedge-shaped wood-splitting axe head, wider than the Hatchet

## Batch 5 — Ranged weapons I (12 icons)

- `bow` — Hunting Bow — `#9a7a48` — a simple wooden recurve bow with a string
- `pistol` — M9 Pistol — `#71787f` — a black semi-automatic pistol
- `smg` — Scrap SMG — `#6b7178` — an obviously improvised, welded-pipe-and-scrap submachine gun
- `shotgun` — Pump Shotgun — `#5e5148` — a pump-action shotgun with a wood stock
- `rifle` — Hunting Rifle — `#4c4136` — a bolt-action hunting rifle with a wood stock
- `carbine` — Military Carbine — `#4a5340` — a black tactical carbine with a rail and magazine
- `sixShooter` — Six-Shooter — `#c9a227` — an old-west style revolver with a wood grip
- `compoundBow` — Compound Bow — `#4b5a4a` — a modern compound bow with pulley cams
- `crossbow` — Crossbow — `#6a5a46` — a crossbow with a stock and a loaded bolt
- `machinePistol` — Machine Pistol — `#5b6166` — a compact automatic pistol with an extended magazine
- `pipeShotgun` — Pipe Shotgun — `#5f5850` — a crude single-barrel break-action improvised shotgun
- `akStyleRifle` — AK-Style Rifle — `#6b5535` — an AK-pattern rifle with a curved magazine and wood furniture

## Batch 6 — Ranged weapons II (11 icons)

- `arStyleRifle` — AR-Style Rifle — `#4f5550` — an AR-pattern rifle, black polymer, straight magazine (contrast with the AK's curved mag and wood furniture)
- `boltActionRifle` — Bolt-Action Rifle — `#4a4036` — a heavy bolt-action rifle, no scope
- `compactSmg` — Compact SMG — `#63696f` — a small black SMG with a folding stock
- `doubleBarrelShotgun` — Double-Barrel Shotgun — `#6b5a42` — a break-action double-barrel shotgun, wood stock
- `lmg` — LMG — `#3e4238` — a large belt-fed light machine gun with a bipod
- `leverActionRifle` — Lever-Action Rifle — `#7a5c38` — a western-style lever-action rifle with brass fittings
- `marksmanRifle` — Marksman Rifle — `#3f4a3e` — a semi-auto rifle mounted with a scope
- `revolver` — Revolver — `#8a8d92` — a modern black revolver (distinct from the old-west Six-Shooter)
- `scopedHuntingRifle` — Scoped Hunting Rifle — `#45392f` — the Hunting Rifle silhouette but with a scope mounted on top
- `semiAutoShotgun` — Semi-Auto Shotgun — `#55504a` — a black semi-automatic shotgun
- `slingshot` — Slingshot — `#8a7f6a` — a simple Y-frame wooden slingshot with rubber bands

## Batch 7 — Armor & gear I: head, body, hands (9 icons)

Each slot has 3 tiers. Make the tiers a visible progression: **tier 1 =
scavenged workwear, tier 2 = riot/police gear, tier 3 = military-issue** —
each tier across every slot should share a family look (tier-3 items all
read as "military," etc.) while still being a distinct piece of gear.

- `hardHat` — Hard Hat (tier 1) — `#c9a227` — a yellow construction hard hat
- `riotHelm` — Riot Helmet (tier 2) — `#4d5866` — a dark blue-grey police riot helmet with visor
- `milHelm` — Combat Helmet (tier 3) — `#5b6640` — an olive-drab military combat helmet
- `lightVest` — Padded Vest (tier 1) — `#6f7a52` — a worn civilian padded vest/jacket
- `heavyVest` — Riot Armor (tier 2) — `#4d5866` — dark blue-grey riot body armor with plates
- `milVest` — Plate Carrier (tier 3) — `#5b6640` — an olive-drab military plate carrier with pouches
- `workGloves` — Work Gloves (tier 1) — `#a3763f` — brown leather work gloves
- `tacGloves` — Tactical Gloves (tier 2) — `#4d5866` — dark grey fingerless tactical gloves
- `armGuards` — Arm Guards (tier 3) — `#5b6640` — olive-drab hard armor forearm guards

## Batch 8 — Armor & gear II: legs, feet, lights (8 icons)

- `denimPants` — Work Trousers (tier 1) — `#4a5a72` — plain blue denim work trousers
- `paddedLegs` — Padded Leggings (tier 2) — `#6f7a52` — padded/armored leggings
- `milGreaves` — Combat Trousers (tier 3) — `#5b6640` — olive-drab military combat trousers with knee pads
- `workBoots` — Work Boots (tier 1) — `#6b4a2f` — brown leather work boots
- `combatBoots` — Combat Boots (tier 2) — `#3f4a38` — dark green/black combat boots
- `milBoots` — Assault Boots (tier 3) — `#5b6640` — olive-drab military assault boots
- `torch` — Torch — `#e0913a` — a wooden stick with a burning cloth-wrapped end, warm orange flame
- `flashlight` — Flashlight — `#d8d2c0` — a handheld flashlight with a bright lens

## Batch 9 — Consumables I: medical & chemistry chain (11 icons)

The brain-matter/serum chain (`brainRaw` → `brainMut` / `brainSpec` →
`serum` → `suppressant` → `experimental`) is a progression — later items
should look more refined/processed than earlier ones (raw tissue → a clean
labeled vial), while staying recognizably part of the same "biological
sample" family.

- `bandage` — Bandage — `#d8cfc0` — a roll of clean bandage wrap
- `medkit` — Medkit — `#d9575f` — a red first-aid box/kit with a cross
- `brainRaw` — Raw Brain Matter — `#c07f9a` — a raw, glistening chunk of brain tissue on/in a small container
- `brainMut` — Mutated Brain Matter — `#b06ad0` — similar raw tissue but visibly discolored/purple and warped
- `brainSpec` — Neural Tissue — `#7fd0c4` — a cleaner, more clinical sample in a small jar or vial, less raw-looking than the above two
- `serum` — Stabilized Neural Serum — `#8fd08a` — a labeled glass vial of green-tinted liquid
- `suppressant` — Refined Suppressant — `#6ad0c4` — a small labeled syringe or vial of teal liquid, more "finished/pharma" looking than the serum
- `experimental` — Experimental Suppressant — `#d0a06a` — an unstable-looking amber vial/syringe, maybe with warning markings — should read as the riskiest/least-trustworthy item in the chain
- `lockpick` — Lockpick — `#9aa2ab` — a simple bent metal lockpick/tension wrench
- `cannedFood` — Tinned Food — `#c4a86a` — a sealed food tin with a label
- `jerky` — Dried Meat — `#b98a5a` — a few strips of dried jerky

## Batch 10 — Consumables II: food, drink, crops (10 icons)

- `hotMeal` — Hot Meal — `#d9a05a` — a bowl of hot stew/food with visible steam
- `mre` — Field Ration — `#7fa14a` — a sealed olive-drab military ration pouch
- `candyBar` — Candy Bar — `#d0709a` — a wrapped chocolate/candy bar
- `water` — Clean Water — `#6ad0c4` — a clear bottle of clean water
- `soda` — Warm Soda — `#c95a8a` — a soda can
- `coffee` — Instant Coffee — `#8a6a3c` — a small jar/tin of instant coffee
- `booze` — Bottle of Spirits — `#d98a4a` — a glass liquor bottle
- `potato` — Potatoes — `#c9a86a` — a couple of whole potatoes
- `corn` — Corn — `#e0c24a` — an ear of corn
- `herbs` — Herbs — `#8fd08a` — a small bundle of green leafy herbs

## Batch 11 — Structures I (10 icons)

These are buildables from the base-building menu — draw each as a small
three-quarter/isometric icon of the built object (not a top-down floor
tile), consistent with everything else in this set.

- `bedroll` — Bedroll — `#a3763f` — a rolled-out sleeping bag/bedroll on the ground
- `bunk` — Bunk — `#8a6a3c` — a simple wood-frame bunk bed
- `raisedBed` — Raised Bed — `#9aae5a` — a wooden raised garden bed with soil and a small plant
- `watchtower` — Watchtower — `#9aa2ab` — a tall wooden watchtower with a platform
- `stash` — Supply Stash — `#c9a227` — a large wooden storage crate/stash
- `chest` — Wooden Chest — `#a3763f` — a simple wooden storage chest
- `locker` — Steel Locker — `#9aa2ab` — a tall steel storage locker
- `workbench` — Workbench — `#8a6a3c` — a wooden workbench with tools laid on it
- `barricade` — Barricade — `#a3763f` — a rough, quickly-thrown-together wood barricade (should look flimsier/cheaper than the walls below)
- `woodWall` — Wood Wall — `#a3763f` — a solid section of wooden plank wall

## Batch 12 — Structures II: walls & defenses (9 icons)

The four walls should form a clear visual progression from crude to
heavy-duty — this is one of the sets you specifically want distinguishable.

- `stoneWall` — Stone Wall — `#8f8a80` — a dry-stacked stone wall section, no wood or metal visible
- `reinforcedWall` — Reinforced Wall — `#a3763f` — a wood wall section reinforced with visible sheet-metal patches/bolts
- `metalWall` — Steel Wall — `#9aa2ab` — a solid heavy steel wall panel — should read as the toughest of the four walls
- `gate` — Gate — `#a3763f` — a wooden gate section with visible hinges, distinct from a plain wall
- `spike` — Spike Trap — `#8f8a80` — a row of sharpened spikes set in the ground
- `turret` — Auto Turret — `#9aa2ab` — a mounted automated gun turret
- `floodlight` — Floodlight — `#d8d2c0` — a pole-mounted floodlight fixture
- `chemStation` — Chemistry Station — `#7fd0c4` — a small lab bench with beakers/tubes
- `generator` — Generator — `#d2762c` — a fuel-powered generator unit with a fuel cap and exhaust

---

## After you have the images

Send me every PNG you get back, named to match the ids above (or just tell
me which image is which id if the export names got mangled). I'll place
each one at `art/items/<id>.png`, run the project's icon test
(`tests/icons_test.gd`), and confirm everything shows up correctly in the
inventory, hotbar, and — once I've wired up the lookup for them — the build
menu for structures and walls.
