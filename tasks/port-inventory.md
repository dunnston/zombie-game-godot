# DEADLINE — port inventory

What the browser prototype does, distilled so the Godot build can be ported
from it. Source of truth: `PROJECT.md` §4/§6/§8 and `src/game/config.js` in
`C:\Users\ryans\OneDrive\Desktop\AI Games\zombie-game`. Numbers are the
prototype's current values; a number that moved in the port should move for a
reason. Units are world pixels unless stated; the tile is 32px and the player
moves 176px/s, so "400px" is about 2.3 seconds of walking.

---

## Part 1 — System inventory

### 1. World and districts

- One authored 320x320-tile map (32px tiles, 10240px square) from a fixed seed
  so the player can learn its geography. The original 160-tile town sits in the
  middle, shifted by (80, 80); farms, forest, city and salvage wrap around it.
- Eighteen districts across four danger tiers, running roughly **west to east**:
  - Town (centre): Roadside Camp, Pine Hollow Suburbs (tier 1); East Terraces,
    Market Row, Fuel Stop (2); Precinct 12, St. Martha Hospital, Dock Yard (3);
    Checkpoint Delta (4).
  - Country (west, across the river): Hollow Creek Farms, Saddleback Ranch (1)
    with fields, barns, silos, a feed store, fenced paddocks.
  - Forest (north): Blackpine Forest, Grayson Lumber, Loon Lake (2) with pines,
    hunting cabins, a sawmill with log piles, a lodge with a jetty.
  - City (east): Crown Heights (3), Downtown (4), Galleria Mall (3) with
    apartment blocks, office towers, a bank vault, a drugstore, a gun shop.
  - South: Rust Belt Salvage (2), a walled junkyard; an orchard south of the
    hospital.
- The Marrow river runs the full height of the map down the west side with two
  bridges (highway and north road). Water and fences are solid to feet and
  transparent to bullets; walls and trees stop both. Fields are walkable and
  buildable.
- Terrain kinds: grass, road, sidewalk, dirt, wood floor, wall, water, rubble,
  lot, tile floor, gravel, field, sand, fence. Solid set = wall, water, fence.
- Static collision is one tile array; player structures live in a separate
  destructible map. Every scenery prop occupies a tile so a swing always has
  one thing to hit. Boulders block movement and line of sight; thickets block
  neither, so a thicket is cover you can stand in.
- New game starts within 30 tiles of the Roadside Camp (not anywhere in
  tier-1 land). Respawn without a bedroll uses any open tier-1 ground.
- Buildings are furnished by type (house, store, hardware, pawn, police,
  hospital, industrial, military, barn, farmstore, cabin, lumber, junk,
  apartment, office, bank, mall, drugstore, gunshop) from weighted lists, so a
  building's exterior tells you what is worth searching inside. Containers are
  never placed in a doorway or beside one; every container is reachable from
  the camp (asserted by a test).
- Ground litter: about 4,200 pieces of loose sticks, stone and dry grass
  (roughly 11,800 units of material), thickest on grass and dirt, sparse on
  tarmac. A starter cache near the camp tops up whatever the odds did not
  provide, so twice a Hatchet's cost is always within fifteen tiles.

### 2. Player, movement and stamina

- HP 100, radius 13, speed 176px/s, sprint x1.62. Invulnerable 0.32s after a
  hit. Respawn 3s. Carry capacity 200 weight units.
- Stamina: 100 base (110 at starting CON 2). Sprint drains 26/s, regenerates
  20/s after a 0.65s delay.
- Work costs stamina, fighting barely does: a harvest swing costs 6 and stops
  recovery for 1.1s; a combat swing costs 2 and is never refused. At starting
  stats a tree is six hatchet swings, so a full bar is three trees, then a pause.
- Exhaustion latches: being *refused* a work swing sets "winded", which only
  clears once stamina is back to 50%. Without the latch a player holding the
  button fells trees forever at a sixth of the speed (measured).
- Being winded stops you working, never defending yourself.
- Interact range 76px, pickup range 46px (loot magnetises toward the nearest
  player), search time 1.05s per container.
- Camera leads toward the cursor; view height ~580 CSS px of world, zoom
  0.9 to 2.6.
- Multiple players: each has an `intent` (movement, aim, fire, interact,
  edges) and the simulation reads only that; the keyboard is read in one place.
  Edge inputs are consumed by exactly one simulation step.
- Downed rather than dead when a teammate is up: 30s countdown, revive by
  holding E for 2.5s, back at 40% HP. Alone, death drops a recoverable backpack.

### 3. Enemies

Four tiers. `structMul` scales damage against player structures only: walkers
and runners threaten *you*, brutes are what breaches a wall.

| Type | HP | Speed | Dmg | Atk cd | Range | Radius | XP | Sense | Knock resist | structMul | Threat |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Walker | 58 | 60 | 13 | 1.0 | 26 | 12 | 10 | 330 | 0 | 0.5 | 0.35 |
| Runner | 44 | 132 | 11 | 0.65 | 25 | 11 | 18 | 430 | 0.15 | 0.4 | 0.5 |
| Brute | 300 | 52 | 34 | 1.35 | 34 | 19 | 55 | 380 | 0.75 | 2.2 | 1.1 |
| Behemoth (boss) | 1100 | 46 | 58 | 1.6 | 44 | 27 | 200 | 900 | 0.95 | 4.0 | 2.5 |

- No pathfinding. Steering is "walk toward the target; if blocked, attack the
  blocker or slide". Anything that walks to a target needs give-up logic.
- Aggro expires; only a player the enemy can sense *right now* renews it. A
  noise gives a destination (8s alert timer plus a point to walk to), never
  aggro; if they can also see a player, sight sets aggro and the hunt wins.
- Enemies go for the nearest player and ignore downed ones. Enemies ignore
  survivors unless blocked by them.
- Ambient spawner: standing population target per danger tier near each
  living player, DENSITY = [tier1: 4, tier2: 10, tier3: 17, tier4: 24],
  scaled by night factor and by the quiet field. Refill check every 0.6s.
  Hard cap 160 enemies. Spawn ring is off screen (max(880, view radius + 180)
  to +420 further). Cull anything more than 2400px from *every* player.
- Ambient mix per tier: t1 94% walker / 6% runner; t2 70/28/2% brute;
  t3 52/36/12; t4 40/36/24.

### 4. Combat and weapons

- Melee is an arc in front of the player; the arc is searched for enemies
  first and only an empty arc falls through to scenery (that is how the game
  knows a swing was a fight or a job). Knockback per weapon, some bleed.
- Firearms have real magazines, reload times, spread, bullet speed and life,
  pellets, pierce, screen shake, threat and a noise radius. Shotgun reloads a
  shell at a time. "One click, one magazine" is deliberate for guns; the bow
  keeps drawing while held.
- Bullets use terrain-only collision: they pass over player walls, fences and
  water, and stop on terrain walls and trees. No friendly fire.
- Weapon table (dmg / cooldown s / range px / arc rad / knock):

| Melee | Dmg | Cd | Range | Arc | Knock | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Fists | 9 | 0.42 | 34 | 1.0 | 70 | |
| Steel Pipe | 24 | 0.40 | 48 | 1.15 | 150 | bench 1 (or hammer) |
| Machete | 40 | 0.34 | 54 | 1.0 | 110 | bleed |
| Sledgehammer | 78 | 0.86 | 60 | 1.7 | 340 | bench 2, structureMul 1.0 |
| Hatchet | 30 | 0.52 | 48 | 0.9 | 130 | tool, axe, chopMul 2.4 |
| Stone Pickaxe | 26 | 0.62 | 50 | 0.9 | 150 | tool, pick, chopMul 2.2, toolMul 2.4 |
| Stone Knife | 19 | 0.28 | 40 | 0.8 | 60 | tool, bleed, chopMul 1.5 |
| Scythe | 24 | 0.46 | 62 | 1.6 | 80 | tool, bleed, chopMul 2.0, toolMul 2.2 |
| Stone Hammer | 36 | 0.72 | 46 | 1.2 | 240 | tool, structureMul 0.8 |
| Fire Axe | 34 | 0.46 | 52 | 1.0 | 190 | bench 1, axe, chopMul 4.2 |
| Steel Pickaxe | 30 | 0.56 | 54 | 0.9 | 210 | bench 1, pick, chopMul 4.4 |

| Gun | Dmg | Cd | Mag | Reload | Spread | Ammo | Speed | Life | Pellets | Pierce | Threat | Noise |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Hunting Bow | 19 | 0.85 | 1 | 0.55 | 0.03 | arrow | 780 | 0.85 | 1 | 0 | 0.15 | 90 |
| M9 Pistol | 27 | 0.17 | 12 | 1.15 | 0.035 | 9mm | 1150 | 0.55 | 1 | 0 | 1.0 | 420 |
| Scrap SMG | 17 | 0.075 | 30 | 1.6 | 0.075 | 9mm | 1100 | 0.5 | 1 | 0 | 0.6 | 400 |
| Pump Shotgun | 16 | 0.75 | 6 | 0.5/shell | 0.20 | shells | 980 | 0.30 | 8 | 0 | 2.4 | 620 |
| Hunting Rifle | 78 | 0.52 | 8 | 1.9 | 0.012 | rifle | 1700 | 0.9 | 1 | 2 | 2.0 | 700 |
| Military Carbine | 36 | 0.105 | 40 | 2.3 | 0.045 | rifle | 1500 | 0.8 | 1 | 1 | 1.1 | 560 |

- The bow is a gun with a magazine of one: three arrows to a walker against a
  rifle's one, at a seventh of the noise, and no muzzle flash (a flash is a
  light source at night).
- Every hand tool is a deliberately poor weapon (less damage than a machete).
- Consumables: Bandage heals 28 over 0.9s; Medkit heals 80 over 1.6s; Lockpick
  is a car tool that rides in the same inventory.
- Kill XP goes to the killer; turret, trap and survivor kills pay every
  present player.

### 5. Noise

- Every sound pulls enemies within its radius toward the point it happened:
  sets an 8s alert and a destination, never aggro.
- One `makeNoise(x, y, radius, actor)`; the actor's `noiseMul` (stealth perks)
  scales everything including cars and turrets.
- Radii: gunfire 400-700 (per weapon above), turret 520, engine 420, crash 380,
  generator 300, failed lockpick snap 260, build 190, chop 140, bow 90.
- Tower armaments: arrows 90, fire arrows 120, sniper 700, cannon 950.

### 6. Quiet field and ambient pressure

- A coarse "quiet" field over the map, 256px cells, sampled bilinearly (reading
  the containing cell made six kills buy 40s of calm or none depending on where
  in the cell you stood).
- Each non-raid kill deposits 1.0 quiet spread over a 1.7-cell kernel around
  where it fell. Ceiling 6. Decays at 6/270 per second so a full ceiling bleeds
  off in ~4.5 minutes.
- Above 2.9 quiet no new ambient enemies arrive at all (calibrated: three kills
  read 1.74-2.84, five read 2.91-4.67, so about one approaching group buys the
  lull). Quiet at its strongest still leaves 30% of the normal population.
- Structures add 1.6 quiet within 400px, weaker than clearing by hand.
- Raids ignore the field entirely and raid kills do not earn it.

### 7. Loot and containers

- About 30 container archetypes (cabinet, kitchen unit, toolbox, shelving,
  medicine cabinet, parts bin, supply crate, floor safe, staff locker, car
  trunk, police locker, gun safe, military crate, hospital supply cabinet, fuel
  pump, fuel drum, log pile, bookshelf, dresser, wardrobe, desk, filing cabinet,
  fridge, nightstand, vanity, footlocker, vending machine, tool rack, display
  case). Each has a loot table and a roll count range (1-1 for a nightstand up
  to 3-4 for a military crate).
- Loot tables are weighted entries `{id, min, max, weight}`; an id is a
  resource, `weapon:`, `item:` (consumable) or `gear:`. Tables read true to the
  fitting: a fridge is mostly rations, a wardrobe clothes and tier-1 gear, a
  gun safe pistols/shotguns/rifles, a footlocker military gear and rifle rounds.
- Batteries are in seven loot tables (toolbox, electronics, car trunk, desk,
  filing, nightstand, display case) before they are craftable.
- Searching takes 1.05s (scaled by Perception and perks). Loot spawns as
  pickups that magnetise to the nearest player within pickup range.
- Anything that will not fit lands on the ground, never nowhere. A dropped
  pile is held off from its dropper until they step away (re-arm at 1.2x pickup
  range, collect at 0.45x), keyed to the dropper so a teammate can take it.
- Death drops a recoverable backpack. A broken or demolished container spills
  what was in it.
- Survivor rescues seeded across the world (7 by default) to recruit.

### 8. Items, inventory, equipment and hotbar

- Resources (weight per unit / stack size): wood 1/50, sticks 0.5/50, stone
  1.5/50, fiber 0.3/50, scrap 1/50, cloth 1/50, electronics 1/30, batteries
  0.5/20, medical 1/30, weapon parts 1/20, military 1/20, fuel 1/20, rations
  1/20, arrows 0.15/60, 9mm 0.2/120, shells 0.3/60, rifle rounds 0.25/90.
- 30-slot pack grid with stacking; six-slot hotbar that decides what you are
  holding; everything moves by dragging. Capacity is weight, not slot count,
  and the weight bar counts pack and hotbar together (200 base).
- Dropping is ctrl+click or drag out of the panel; a release inside the panel
  snaps back. Both gestures also drop worn gear.
- Six equipment slots: head, body, hands, legs, feet (armour, damage
  reduction) and **off-hand** (a light, no DR). Nothing equips itself; gear
  goes to the pack and waits.
- Fifteen armour pieces, three tiers per slot. DR by slot/tier: head
  .05/.10/.15, body .10/.20/.28, hands .02/.04/.07, legs .04/.08/.12, feet
  .02/.05/.08. Full tier-1 set 0.23, full tier-3 set 0.70, hard cap 0.72.
  Weights 1-14, body heaviest.
- Lights: Torch (200px pool, 210s, burns away, consumed) and Flashlight (140px
  pool plus a 460px cone of 0.34 rad, 300s per battery). `T` lights it. Charge
  lives on the player, not the slot; swapping to a different light resets it.
- A lit player is noticed 90px further out.

### 9. Gathering and crafting

- Ground litter is picked up with the interact key (sticks 2-4, stone 1-3,
  fiber 2-4). Bushes and rocks answer the interact key too.
- Harvest rules: bush -> fiber 2-4 + sticks 1-2 (scythe x1.6 boost); rock ->
  stone 2-4 (pick boost); tree (470hp) -> wood 6-11 + sticks 1-3, **needs**
  axe; boulder (380hp) -> stone 9-16, needs pick; thicket (90hp) -> fiber 9-15
  + sticks 2-4, needs scythe. Small scenery is never gated, big scenery always is.
- Swing damage to scenery = weapon dmg x chopMul (1 for a non-tool, 1.3 machete,
  1.6 sledge) x 1.6 if the matching tool x player chopMul. Six swings a tree
  or boulder at starting stats; three with the metal tools (same yields).
- Recipe benches: 0 = by hand, 1 = workbench, 2 = upgraded workbench (upgrade
  cost scrap 55, elec 20, parts 5). `hammer`-flagged recipes are lifted to
  bench 1 by a carried Stone Hammer (pipe, lockpicks, ration packs) and nothing
  else; the hammer can never produce a gun.
- Bench 0: Bandage x2 (cloth 4), Hatchet (sticks 3, stone 3, fiber 4), Stone
  Knife (2/3/2), Stone Pickaxe (4/4/3), Scythe (5/3/4), Stone Hammer (3/6/2),
  Cloth x4 from fiber 10 (needs a knife), Torch (sticks 3, fiber 3), Hunting
  Bow (sticks 8, fiber 12, cloth 2), Arrows x10 (sticks 6, stone 3, fiber 2),
  Work Gloves (cloth 8), Work Trousers (cloth 14).
- Bench 1: Steel Pipe, 9mm x24 (scrap 9, parts 1), Medkit (med 5, cloth 5),
  Machete (scrap 24, parts 1), Fire Axe (wood 8, scrap 20, parts 2), Steel
  Pickaxe (wood 6, scrap 26, parts 3), M9 Pistol (scrap 28, parts 4), Padded
  Vest, Work Boots, Hard Hat, Padded Leggings, Shells x14, Lockpicks x3,
  Ration Pack x8 (med 2, cloth 3), Fuel x25 (scrap 10, elec 4), Batteries x2
  (scrap 6, elec 5), Flashlight (scrap 10, elec 6, parts 1).
- Bench 2: Sledgehammer, Scrap SMG (scrap 48, parts 8, elec 10), Pump Shotgun,
  Rifle Rounds x18, Hunting Rifle (scrap 62, parts 12, mil 3), Riot Armor,
  Military Carbine (scrap 85, parts 18, mil 14, elec 12), Plate Carrier.
- Crafting grants XP (3 for bandages up to 150 for the carbine) and 0.4 Threat.
  Crafting overflow goes to the stash, then the ground.

### 10. Building, structures, towers and turrets

- Build anywhere. Build mode owns the mouse; a build bar of cards that shrinks
  and wraps to fit the screen. Repair and salvage tools. Building makes 190px of
  noise and adds Threat scaled per structure.
- Structures (cost / hp / notes):
  - Barricade wood 8 / 160. Wood Wall wood 16 / 340. Stone Wall stone 18,
    sticks 4 / 430. Reinforced Wall wood 12, scrap 22 / 920. Steel Wall
    scrap 45, parts 2 / 2100 (tier 2).
  - Gate wood 22, scrap 12 / 560; interact to open or close.
  - Spike Trap wood 12, scrap 10 / 200; 26 dmg every 0.55s to whatever walks
    over it; wears out.
  - Workbench wood 30, scrap 18 / 300; craft while standing near it; upgradable.
  - Supply Stash wood 25, scrap 8 / 220 / 48 slots. Wooden Chest wood 20,
    sticks 8 / 180 / 16 slots. Steel Locker scrap 34, parts 1 / 420 / 32 slots.
  - Bedroll wood 15, cloth 12 / 90; sets respawn; only the newest is active.
  - Bunk wood 22, cloth 14 / 140; houses one survivor.
  - Watchtower wood 45, scrap 20 / 420; post a survivor as a sniper (range 520,
    x1.9 damage).
  - Generator scrap 38, elec 16 / 380; powers within 260px; burns 0.35 fuel/s
    from a 100 tank; 300px noise and 0.55 Threat/s while running.
  - Auto Turret scrap 50, elec 28, parts 6 / 340; needs power; range 330, 22
    dmg, 0.28s cd, 40-round magazine, 2.2s reload; eats 9mm from the stash;
    520px noise and 0.06 Threat per shot.
  - Floodlight scrap 22, elec 12 / 200; needs power; 260px light.
- Player structures never catch fire. Fences are terrain, not structures.
- Repair: `E` beside a damaged piece, the REPAIR tool (click or hold to sweep),
  or REPAIR ALL (everything within 520px, worst first, skipping what it cannot
  pay for; the label is the plan). A repair costs 45% of the build price scaled
  by damage, from the pack then the stash; materials the damage would not have
  consumed drop off the bill, but the main material is at least one.
- Manned tower armaments, bought once per base and chosen per tower:
  Arrows (free, dmg x1.0, cd x1.25, range 480, 1 arrow, noise 90); Fire Arrows
  (wood 20, cloth 20, fuel 30, parts 2; dmg x0.75, cd x1.45, 1 arrow + 1 fuel,
  noise 120, sets targets alight); Sniper Rifle (scrap 70, parts 12, mil 6;
  dmg x1.9, cd x1.7, range 520, 1 rifle round, pierce 1, noise 700); Scrap
  Cannon (scrap 90, parts 8, elec 10; dmg x3.4, cd x3.2, range 420, 2 scrap,
  70px splash, noise 950). Multipliers apply to the survivor's own numbers.
- Every Supply Stash aliases one shared pile; survivors eat and towers/turrets
  shoot only from it. A stash spills only when it was the last one standing.
- Base-wide numbers (turret reach, wall strength, upkeep, roster cap) come
  from the host's stats.

### 11. Threat and raids

- Threat meter 0-100 driven by activity, not a calendar. Gains: 0.35 per
  walker-equivalent kill (scaled by enemy threat), 1.0 per gunshot (scaled by
  weapon), 1.0 per build (scaled by structure, 0.5-5), 0.4 per craft, 0.45 per
  container looted, 0.55/s per running generator, 0.06 per turret shot, cars
  0.5/s. Decays 0.12/s (~7/min). Night nearly doubles gain. Warnings at 40,
  70, 90; tiers LOW / RISING / HIGH / CRITICAL.
- At 100 a raid starts after a 12s warning. Raid centre is the base centre
  (structures); if everyone has wandered off, spawn around whoever is nearest.
- Five authored tiers, then endless scaling (waves / base size / growth per
  wave / mix / reward / XP):
  1. SCATTERED HORDE: 2 waves, 8 +3, walkers; scrap 30, wood 30, parts 2; 120.
  2. RUNNING HORDE: 3, 11 +4, 65% walker 35% runner; scrap 45, parts 3,
     elec 10; 220.
  3. HEAVY HORDE: 3, 14 +5, 55/30/15% brute; scrap 60, parts 5, elec 15,
     mil 3; 360.
  4. SIEGE: 4, 18 +6, 45/33/22; scrap 80, parts 7, elec 20, mil 6; 520.
  5. BEHEMOTH SIEGE: 4, 22 +7, 40/32/25/3% behemoth; scrap 110, parts 10,
     elec 28, mil 12; 800.
  6+. base +5 and growth +1 per extra raid, XP x(1 + 0.35n), reward x(1 + 0.3n).
- Raider HP scales x(1 + 0.06 x raid index). Raiders spawn aggro on a 520-800px
  ring and target the **nearest** structure so hordes break on the perimeter.
- Anti-stall: every 4s, a raider more than the break-off radius (900px) from
  the centre and not getting closer for 12s is relocated to a 360-560px ring.
- A raid ends when every raider is dead, or after 25s with no progress (kills,
  structure damage, player damage or downs all unchanged), or at a 300s ceiling.
  An unfinished raid pays reward and XP by the share of the horde killed.
- After a raid Threat resets to 14. The raid summary counts pieces left damaged.

### 12. Progression, attributes and perks

- XP to next level = floor(55 + 45 x (level - 1)^2.35): the first few come
  quickly, then it bites. Levels grant skill points (1, or 2 on every fifth
  level) and never interrupt play.
- Six attributes (STR, PER, CON, CHA, INT, LCK), rank 1-10, all start at 2.
  Per rank: STR +9% melee, +25 carry, +6% chop; PER -4% spread, -5% search
  time; CON +12 HP, +10 stamina, +1.2 stam/s; CHA +1 survivor slot per 2
  ranks, +6% ally damage; INT +7% XP, -3% build cost, +5% turret; LCK +2%
  crit, +5% rare loot.
- 27 perks, each gated on a rank in its attribute, with a max rank:
  - STR: Pack Mule (2, x3, +70 carry), Heavy Hitter (3, x3, +25% melee),
    Demolisher (5, x2, fell/salvage 2x faster), Adrenaline (7, x1, below a
    third HP +45% melee +15% speed).
  - PER: Scrounger (2, x3, +35% container loot), Quick Hands (3, x2, -30%
    search, +18 pickup range), Eagle Eye (4, x3, -22% spread, +12% range),
    Sixth Sense (6, x1, enemies on the minimap far out).
  - CON: Thick Skin (2, x4, +30 HP), Marathon (3, x3, +45 stamina, faster
    recovery), Woodcraft (4, x2, harvest swings -35% stamina), Iron Stomach
    (4, x2, meds +60% and 30% faster), Second Wind (6, x1, once per two
    minutes a killing blow leaves you on 1 HP).
  - CHA: Recruiter (2, x3, +1 survivor slot), Inspiring Presence (3, x2,
    survivors +30% dmg +25% HP), Quartermaster (4, x2, survivors eat 40%
    less), Natural Leader (6, x1, survivors gain XP 60% faster and rally).
  - INT: Fast Learner (2, x3, +22% XP), Engineer (3, x3, -22% structure
    cost), Fortifier (4, x3, +45% structure HP), Gunsmith (4, x2, crafted ammo
    +60%), Fire Control (5, x2, +35% turret dmg and range), Hotwire (5, x2,
    start any locked car; rank 2 twice as fast).
  - LCK: Scavenger's Luck (2, x3, +30% chance of the rare loot entry), Lucky
    Strike (3, x3, +7% crit), Ammo Cache (4, x2, 20% chance a shot is free),
    Low Profile (5, x2, -30% Threat and quieter), Fortune Favours (7, x1,
    enemies drop twice as much, containers can pay out twice).
- All stat modifiers come from one pure `recomputeStats()`; nothing is mutated
  on purchase. This makes save/load, respawn and respec correct by construction.

### 13. Day, night and light

- One day is 540s (~9 minutes). Phases as fractions of the day: dawn 0-0.12,
  day 0.12-0.58, dusk 0.58-0.72, night 0.72-1.0. Darkness alpha ramps smoothly
  to 0.80 at full night. A new run starts at 0.16 (mid-morning) on day 1.
- Night factor k = darkness / 0.8: enemy density x(1 + 0.85k), sense
  x(1 + 0.55k), speed x(1 + 0.10k), Threat gain x(1 + 0.9k). A notification
  announces night ("they can hear you a long way off").
- Light sources punch out of the darkness: torch, flashlight (pool plus cone),
  floodlight (260px, powered), muzzle flashes (except the bow), fire.

### 14. Survivors, jobs and bunks

- Recruited from rescues found in the world; roster cap = min(Charisma slots,
  bunks). Named from a fixed list; permanent death.
- Stats: HP 90 + 22/level, damage 11 + 2.6/level, fire cd 0.62s, range 300,
  speed 118, 55 XP per level, max level 10, roam 190px from their post. Downed
  survivors die after 8s if nobody helps.
- Jobs: Guard (holds the base), Sniper (posted on a Watchtower within 52px:
  range 520 and x1.9 damage, or an armament), Scavenger (supply runs, brings
  material back to the stash; prefers targets with line of sight), Builder
  (repairs damaged structures during and after raids, unprompted).
- Upkeep: 1.0 Rations per survivor per minute, charged every 10s from the
  stash; unpaid upkeep accrues as debt (capped at 5) and warns every 45s.
- Survivors eat and shoot only from the shared stash, never the player's pack.

### 15. Vehicles

- About 30 cars in town, 62% locked. Three ways in: a key hidden near the car,
  a lockpick (chance 0.34 + 0.07 x Perception, clamped 0.15-0.92; a failed pick
  snaps the tool and makes 260px of noise; 1.6s), or the Hotwire perk (3.2s).
- Arcade handling: accel 340, reverse 180, max 430 (reverse 150), brake 520,
  steering 2.5 rad/s fully effective from 170 speed. Car HP 420, radius 20.
- Fuel tank 60; 25% of cars spawn with 18-60 fuel, the rest 0-9. Burns 0.55/s
  idling plus 0.004 per unit of speed.
- Roadkill does 46 to what you hit at speed, 3 to the car; hitting terrain
  above 150 speed hurts. Engine noise 640px, 0.5 Threat/s. Headlights.
- 400-unit boot (plain resource map). Enter range 74. No shooting while
  driving. One seat per car; a leaver parks; a roadkill is the driver's.
  Cars cannot drive through the player's own walls.

### 16. Fire

- A burning enemy takes 9 dps for 6.5s and every 0.6s tries to ignite enemies
  within 42px (45%) and scenery within 46px (22%).
- Burning scenery lives ~7s (x0.8-1.2), does 16 dps within 26px to anyone
  standing in it (players included), and spreads to scenery within 1.6 tiles
  at 16% per tick. Flammable: tree, pine, bush, thicket, litter, hay, reed.
  Rock, boulder, silo and wreck do not burn. A burnt prop is gone for good.
- Ceiling of 140 simultaneous fires. Fire never spreads to player structures.
- A burn does not re-alert or retarget the enemy on each tick.

### 17. Storage

- Every container has a slot count (stash 48, chest 16, locker 32). `E` opens a
  two-panel screen: contents left, pack and hotbar right; drag or right-click
  across; DEPOSIT ALL and TAKE AMMO buttons.
- Everything that writes to storage (salvage, crafting overflow, raid payouts,
  stripped wrecks, scavenger hauls) falls through to the ground when full.
- The stash, car boots and survivor cargo are plain id->count maps; the pack
  and hotbar are slot grids. One resource API serves both.

### 18. Saves

- Save slots: an index plus one payload per slot, so two solo runs and a co-op
  world sit side by side. Autosave only for a game that has a slot; the first
  manual save creates one.
- Payload version is 12. Containers are identified by ordinal index and props by
  a replay of `chopped` keys against a world rebuilt from the seed, so any
  change to world generation or the shared RNG stream needs a version bump (a
  fingerprint test enforces it). A save that will not load says the version and
  the reason instead of silently starting a new world.
- The host's save keeps every player by identity, so a returning guest gets
  their character back.

### 19. Title, menus and keybinds

- Boot to a menu: CONTINUE (slot last chosen, then last written), NEW GAME
  (named, gets its own slot), LOAD GAME (day, level, kills, play time, last
  played; LOAD or DELETE with confirm), MULTIPLAYER, CONTROLS.
- Every key rebindable: click a row, press a key; conflicts shown, not refused;
  RESET TO DEFAULTS. Mouse buttons, wheel and Esc are fixed. Bindings are
  per machine, not per save. Every on-screen hint is built from the bindings.
- Pause menu: CONTROLS (over the pause, world stays stopped) and QUIT TO TITLE
  (saves first). Buttons behind a modal are disabled, not just covered.
- Tutorial prompts that name the keys, including "press E to repair" once a
  wall has been hit.
- HUD: health, stamina, weight bar, threat meter with tier colour, clock and
  phase, minimap, hotbar, notifications. Two-tone ground ring per player seat
  (four colours) so you can find yourself in a crowd.

### 20. Audio

- Everything synthesised at runtime (no asset files); master gain 0.35; a
  shared noise buffer. Every entry point is guarded so broken audio never
  stops the game.
- Identical sounds are rate-limited per kind (e.g. bullet hit 28ms, zombie
  death 30ms, growl 260ms, player hurt 140ms) so a shotgun blast hitting twelve
  zombies is one impact, not twelve.
- Named cues: swing, melee hit, bullet hit, hit wall, structure hit, zombie
  growl and die, player hurt, turret, rifle, shotgun, level up, and so on.

### 21. Multiplayer

- Up to four, host-authoritative: the host runs the simulation exactly as in
  solo; guests send intent every step and predict only their own movement (and
  their own swing arc and tracers), lerping toward the host's answer and
  snapping over 48px.
- Host sends snapshots at 20Hz (every player, plus enemies, pickups, cars,
  survivors and packs within 1600px of that guest) over an unordered channel,
  and events (wall placed, container looted, kill, tracer, prop removed, fire
  state) over a reliable one. Inventories and the stash are diffed twice a
  second. Bullets are events, not entities; the host decides every hit.
- Anything a guest does to shared state (build, craft, equip, spend a point,
  move a stack in a container) is a command the host validates with the same
  functions solo uses, including range checks.
- A remote intent's edges are consumed after one step; a held intent expires
  after 400ms of silence; a paused guest sends "holding nothing" every step.
- Enemies cull far from every player and spawn around each. Base-wide numbers
  are the host's. No friendly fire, no player collision.
- Room codes via a tiny broker that only swaps connection details; password
  hashed on the guest and checked by the host. A guest joins through the same
  load path a save uses.

---

## Part 2 — Decisions worth keeping

Reasoning that still holds in any engine. Rows about Vite, Canvas, WebRTC
plumbing and module cycles are left out.

- **Threat meter, not a day-N raid timer.** Danger tied to behaviour (pillar 6).
  A calendar makes power free.
- **Bullets ignore player structures.** Tested the alternative; a walled base
  could not defend itself.
- **Enemy `structMul` split from `dmg`.** Walkers threaten the player, brutes
  threaten walls. This is what makes raid 3 feel like a different game.
- **Raiders target the nearest structure.** So hordes break on the perimeter.
  Targeting the most valuable walked them past the walls you built.
- **Levelling grants points, no forced draft.** A 1-of-3 draft paused the
  world mid-fight.
- **Stats via pure recompute.** Save/load, respawn and respec correct by
  construction. Never mutate a stat on purchase.
- **Survivor upkeep is Rations, not thirst.** Pillar 1: the fantasy at base
  level, not a bar over the player.
- **The stash is the pantry and the armoury.** Survivors and towers draw from
  it and never from the player's pack. Keeps "run home and drop the haul" a beat.
  Every stash aliases one shared pile; it spills only when the last one falls.
- **Scavengers and builders prefer targets with line of sight.** No
  pathfinding; they work the accessible stuff, the player clears buildings.
- **Cars cost fuel, bodywork and noise.** All existing systems; no new resource.
- **No shooting while driving.** Avoids a second aiming model. Revisit if it
  feels bad.
- **A raid ends when nothing is happening, not only when every raider is
  dead.** Without pathfinding "kill them all" is unsatisfiable; watch progress.
- **An unfinished raid pays by share killed.** Otherwise hiding beat defending.
- **Killing buys local, temporary quiet.** The spawner refilled every 0.6s so
  there was never a lull; the first playtest could not get a base up. Raids
  ignore it so they stay exactly as dangerous.
- **The quiet field is sampled bilinearly.** Cell-snapped reads made the same
  six kills worth 40 seconds or nothing.
- **Anything that will not fit lands on the ground.** No loot path may destroy
  something for want of a slot.
- **Nothing equips itself.** Auto-equip meant the player could neither choose
  nor see what they wore.
- **Carry capacity is a budget for pack and hotbar together.** Otherwise loot
  keeps fitting after the bar reads 100%.
- **Dropping is a gesture, not a button; a dropped pile is held off from its
  dropper until they step away.** A button that acts on the hovered item can
  never fire; a timer still snatches the pile back; "you have to leave it" is
  what dropping means. Keyed to the dropper so it can be used to hand things over.
- **Kill XP to the killer; automated kills to everyone present.** Both collapse
  to the old rule in solo.
- **Downed, not dead, when a teammate is up.** Thirty seconds, hold E, 40% HP.
  Enemies ignore the downed.
- **No friendly fire, no player collision.** A player who can block a doorway
  is a griefing tool nobody asked for.
- **Cull enemies far from every player, spawn around each.** One player's ring
  must not starve or cull the other's.
- **One seat per car; a leaver parks; a roadkill is the driver's.**
- **Bindings live on the machine, not in the save.** Two saves should not
  have two keyboards. Esc, mouse and wheel are never rebindable so the controls
  screen cannot lock you out of itself.
- **The controls panel over the pause keeps the world stopped.** The first
  version unpaused, so enemies acted on someone whose input was captured.
- **CONTINUE follows the slot last chosen, then last written.**
- **Every on-screen key hint is built from the bindings at draw time.**
  Hard-coded "press E" lies after a rebind.
- **Buttons behind a modal are disabled, not just covered.**
- **A new game has no slot until it saves.** Tests start dozens of games.
- **The town kept its layout and moved to the middle.** The owner had already
  learned it; the new biomes wrap it.
- **One river, two bridges, shootable across.** A river that stops feet but
  not bullets is a tactic; two crossings so the farms are never a dead end,
  not three so the crossing still matters.
- **Danger runs west to east.** Quiet, food and fuel west; guns east; the
  forest is tier 2 all along the north so "the woods at night" means something.
- **The new game starts by the camp**, not on any tier-1 tile.
- **A wardrobe never goes in a doorway.** Furnishing only off wall lines and
  never beside an opening; assert every container reachable.
- **Every hand tool is bench-0, made only of gathered material, and a poor
  weapon.** Gating any behind the bench (which costs wood, which needs the
  hatchet) deadlocks the opening; a tool tier that wins fights makes the
  machete pointless.
- **Small scenery is never gated; big scenery always is.** Each material has a
  hand source and a tool-gated source worth three times as much.
- **The Stone Hammer is a bench for simple work only** and can never make a gun.
- **Raw material is picked up with the interact key, not swung at.** The
  first playtest could not start: nobody guesses a bush is hit rather than taken.
- **The camp's opening is protected directly, not by global density.** A
  starter cache tops up what the odds missed; map-wide density is then free to
  be sparse.
- **Trees need an axe, and the axe needs no bench.** A real first ten minutes.
- **Fences are terrain, not structures.** Otherwise they join the raid target
  list and the salvage economy for nothing.
- **Repair is offered on `E`, not only as a build-mode tool.** Nobody found
  the fifteenth card on a bar that drew fourteen.
- **REPAIR ALL skips what it cannot pay for, worst first, and its label is its
  plan.** Range is a compound (520px), not base-wide, because of build-anywhere.
- **A repair bill leaves off materials the damage would not have consumed.**
  A scratched steel wall should not cost a weapon part.
- **The gathering tier is priced in swings, measured before changed.** A tree
  at one swing was an accident, not a balance figure.
- **Litter is a budget with a ceiling, not just a floor.** Test both ends.
- **The metal tools buy time, not yield.** More wood per tree would inflate
  the economy; identical yields keep the upgrade explainable in one sentence.
- **Work and combat swings are told apart by what the arc hit.** Work costs
  6 and is refused when short; a fight costs 2 and is never refused.
- **Exhaustion latches on the refusal and clears at half.** Otherwise holding
  the button is a throttle, never a pause.
- **A light goes in an off-hand slot**, never costing the weapon or the helmet.
- **A lit player is seen further.** Visibility has to cost something.
- **A light's charge lives on the player, not the slot.** Slots are `{id, n}`.
- **Aggro expires, and only real sensing renews it.** Once-noticed must not
  mean hunted forever.
- **A noise gives a destination, never aggro.** Otherwise a bang sends zombies
  at the nearest player instead of at the sound (measured: the wrong way).
- **Both spill paths (destroyed and demolished) spill the contents.**
- **One noise function, and stealth applies to all of it**, cars included.
- **The bow is a gun with a magazine of one, no muzzle flash, and keeps
  drawing while held.**
- **Arrows cost only hand-gathered material.** The sink that keeps sticks,
  stone and fiber meaningful all game.
- **Tower armaments are bought once and chosen per tower; arrows are free so
  a manned tower is never useless.**
- **The cannon is worse than a sniper one-on-one.** It is artillery; measure it
  against a crowd.
- **Fire spreads to zombies and scenery and never to player structures.**
  Losing your compound to your own tower ends a run.
- **A burn does not re-alert the enemy each tick.**
- **A burnt prop is removed like a chopped one** so saves and guests agree.
- **Host-authoritative multiplayer, not lockstep.** A single desync silently
  forks the world; one authority has no desync class of bug.
- **Structures and inventories travel reliably as events; positions as
  best-effort snapshots.** Bullets are events, not entities.
- **The guest predicts only its own picture** (movement, swing, tracers) and
  nothing anyone else does.
- **A held remote intent expires; silence is not "carry on".**
- **A save that will not load says why.** Silent refusal read as "it lost my
  game".

---

## Part 3 — Lessons that transfer

- **Test the thing, not the model of the thing.** Every serious bug was
  invisible in review and obvious within seconds of running the game. Assert on
  outcomes (`killed > 0`, `raid completes`), not on calls.
- **A control that acts on what you are hovering cannot be a separate
  button.** The mouse is in one place at a time; latch the target.
- **Silent no-ops are the worst failure mode.** The scavenger's reachability
  check passed 0 of 281 containers and degraded quietly to "nearest". Measure a
  mitigation actually mitigating.
- **Distinguish test-setup failures from product failures**, but notice when a
  "test bug" points at a real gap (tree chopping exists because turrets fired
  into treelines with no way to clear a line).
- **A hanging suite is worse than a failing one.** Every wait has a deadline.
- **Put every tunable in one file.** Three balance passes were cheap and tests
  can assert relationships (a metal tool's yield equals its stone twin's)
  rather than values.
- **Readability beats fidelity.** "I can't find myself in a crowd" was fixed by
  a two-tone ground ring and a brighter palette, not better art.
- **Automated review earns its keep**, but reproduce each finding against the
  running game before fixing, and say so.
- **A test tool that stops measuring looks like a passing test.** The raid
  harness respawned across the map, found nothing, and logged a flat line that
  read as an engine stall. Check the instrument before believing a bad number.
- **Reproduce against `main` before blaming the branch.**
- **A new assertion that passes proves nothing until you know why.** Always
  log the measurement (`stopped 80px short`), not just the verdict.
- **Check the suite has a case where the player does the thing.** Every kill
  in the combat section was by a turret, a survivor or the debug API, so a
  player-kill crash passed 298 assertions.
- **Split a refactor into a PR with no visible change**, gated on "plays
  byte-identically", so the feature PR is reviewed for the feature.
- **A feature nobody can reach is not shipped.** Repair existed for months and
  the next request was "add repair". When a request asks for something that
  exists, the bug is discoverability: screenshot the path a player would take.
- **Anything that must land on a tile re-aims until it settles** when the
  camera leads the cursor.
- **Silence is not neutral, and the other side has no test unless you build
  one.** A protocol that keeps the last state must expire it; every client-side
  transition needs a hook a test can call.
- **A test arena needs the whole corridor open, not just the centre.** With
  no pathfinding, one tree stops the walker and the assertion fails for a reason
  unrelated to what it measures.
- **A stale build is silent; a missing constant is loud.** Restart before
  every measurement and guard the check with "is the thing I just added there".
- **Measure with a control, and pen the ambient spawner.** "Moved 250px toward
  the noise" means nothing until you know they move 91px on their own. Run it
  with and without the mechanic; delete anything you did not plant.
- **Write the test that fails for the right reason.** A test that matched a
  comment, and one that punished the cannon for being artillery, were both the
  test's fault; make the test measure what the thing is for.
- **Render the map before you trust it.** A PNG dump plus a flood fill from
  the camp found three sealed rooms in ten minutes. Reachability is an outcome;
  assert it.
- **Measure before changing a balance number, and price tiers in player
  actions** (swings, trees per bar, kills per lull), not in raw HP.
- **Protect the opening directly.** Three litter passes traded "carpet" against
  "nothing"; what broke each time was narrow (enough within a short walk of
  spawn), so assert exactly that and let the world be sparse.
- **The owner's feel feedback outranks the roadmap.** Almost every number is
  measured rather than felt; a play session settles more than a balance pass.
