# DEADLINE on Godot — Project Document

**This is the living map of the project.** Read it at the start of a session,
update it at the end of one. It says what we are building, where we are, why
past decisions were made, what is next, and what we have learned. If the code
contradicts it, the code is right — fix this file and say so.

- **Last updated:** 2026-09-08, Phase 4c survivors: the roster, four jobs, upkeep and permanent death
- **Repo:** https://github.com/dunnston/zombie-game-godot
- **Owner:** dunnston
- **Engine:** Godot 4.7.2, GDScript, 2D

| Where things live | |
| --- | --- |
| `PROJECT.md` | This file. Vision, status, decisions, roadmap, lessons. |
| `CLAUDE.md` | Auto-loaded each session. Points here; holds the invariants. |
| `tasks/todo.md` | The phase plan with checkboxes, and per-phase review notes. |
| `tasks/port-inventory.md` | **The spec.** Every system in the prototype, what it does, its numbers. |
| `tasks/lessons.md` | Raw running log of lessons. §8 here is the distilled version. |

---

## 0. Where this came from

DEADLINE was prototyped in the browser (vanilla JS, Canvas2D, Vite) over
eleven merged rounds in September 2026 — about 18,800 lines, 44 modules, a
Node test suite and a Playwright smoke suite, save format v12, and online
co-op over WebRTC. The prototype lives at
`C:\Users\ryans\OneDrive\Desktop\AI Games\zombie-game`
(https://github.com/dunnston/zombie-game) and is **read-only from here on**.

On 2026-09-08 the owner decided the game had outgrown the browser and moved it
to Godot. The agreed framing: **this is a rebuild, not a translation.** The
prototype is the design spec — its `PROJECT.md` for intent and reasoning, its
`config.js` for every number — and `tasks/port-inventory.md` condenses both
into the checklist this build is measured against.

**Goal of the port:** the game as it stands today, playable in Godot, with
multiplayer as the final phase.

---

## 1. What we are making

A top-down survival, scavenging and base-defence game.

> You wake up on the roadside outside a dead town with a steel pipe and nothing
> else. Loot houses, chop trees, build a workbench, craft a gun, wall in a patch
> of ground you like, and hold it when the horde comes — because it comes for
> you *because* of what you built.

Influences: Project Zomboid, 7 Days to Die, ARK, They Are Billions. Not a
clone of any of them, and explicitly **not a realism simulator**.

**The loop:** Explore → Scavenge → Fight → Build → Defend → push somewhere worse.

---

## 2. Design pillars

These settle arguments. When a decision is close, the pillar wins.

1. **Survival without survival-game chores.** No thirst bars, no hunger
   micromanagement, no sleep, no long crafting timers. Upkeep lives at the
   base (survivor Rations), not on a bar above the player.
2. **Danger is the only gate.** Nothing is level-locked. The map shades
   districts by danger so you can *see* where you want to go before you can
   survive it.
3. **Fun over realism.** Bullets pass over your own walls because a base you
   cannot shoot out of punishes you for building it.
4. **Readability over fidelity.** If a thing cannot be identified at a glance
   in a crowd, fix that before adding detail.
5. **Every system has to be finished.** Cut breadth, not quality.
6. **The player's power should raise the stakes.** Threat is driven by what you
   do — building, shooting, running a generator, driving fast.
7. **Build anywhere.** No designated home plot. Your base is wherever your
   structures are; raids, survivors and respawns follow it.

---

## 3. Where we are right now

**Status: Phase 4c — you are not alone.** Seven people are scattered across
the town waiting to be found. Taking one in needs a Bunk *and* the Charisma to
lead them, and the refusal says which of the two is actually in the way. They
guard, snipe from a Watchtower, scavenge containers and haul the loot home, or
repair your walls mid-raid. They eat Rations and shoot ammunition **out of the
shared stash and never your pack**, which is what makes stocking the base a
decision. They level, they can be knocked down and helped back up, and they
stay dead.

**Phase 4b — it gets dark.** A day is nine minutes: dawn, day,
dusk, night, and a curve of darkness that creeps rather than snaps. Night is
the pressure valve — more of them out there, noticing you sooner, moving a
little faster, and Threat climbing at nearly twice the rate. The dark is a
real `CanvasModulate` and the torch, flashlight, floodlight, muzzle flash and
fire are real `PointLight2D`s, so two lights overlap properly instead of
cutting holes in an overlay. Fire spreads through scenery and enemies, burns
whoever stands in it, and **never touches anything the player built**. And
the view interpolates between physics steps, so movement is smooth above 60Hz.

**Phase 4a — the loop pays out.** Kills, containers, harvests,
crafts, builds and raid payouts all pay XP into levels; a level hands you
skill points; `K` opens the character sheet, a fourth tab of the pack, where
a point buys a rank in one of six attributes or one of twenty-eight perks.
**`recompute_stats` is now what it was always meant to be** — every derived
number on the player is produced from base, attributes, perks and gear on one
pure pass, and nothing else writes one.

**Phase 3 — the loop closes.** You can make things, keep
them and come back to them. Crafting is a tab of the pack (`C`), not a menu
of its own: thirty-eight recipes across three bench tiers, with the Stone
Hammer lifting the simple bench work and never a gun. A chest opens on `E`
into a two-panel screen with DEPOSIT ALL and TAKE SUPPLIES. And the game
saves: payload v1, **containers keyed by tile position and never by ordinal
index**, chopped props replayed against a world rebuilt from the seed, and a
world fingerprint that refuses a save the generator has outgrown, with the
reason. `F5` and `F9` reach slot 0; the title screen and autosave are
Phase 4's.

**Phase 3b — you can put up a wall and the horde breaks on
it.** Everything the player builds lives in a destructible tile map beside
the terrain bitmap: walls, gates, spikes, three tiers of storage, a
workbench that upgrades, a bedroll that is where you wake up, a generator
that powers turrets and floodlights, and a watchtower waiting for Phase 4's
survivor. `B` opens build mode with the ghost, the range ring and the
repair and salvage tools. Enemies punch what blocks them, brutes are what
breaches a wall, raiders walk at the *nearest* structure so a horde breaks
on the perimeter, and a base quietens the ground around it.

**Phase 3a — the game has things in it.** On top of Phase
2's fight: a survivor wakes with a steel pipe and two bandages and nothing
else. Everything else is out there. Thirty container archetypes answer a
held E and pay out of their own loot table; ground litter, bushes and rocks
answer a tap. What comes out goes into a thirty-slot pack, a six-slot hotbar
and six body slots, all of it draggable, droppable and weighed — capacity is
200 units across the pack and hotbar together. Fifteen armour pieces reduce
damage through `recompute_stats()` and nothing else; a torch lights the
off-hand and burns itself away. Dying leaves a pack where you fell. Nothing
that will not fit is ever destroyed: it lands on the ground.

| | |
| --- | --- |
| Phase | 4 of 5 — 4a progression, 4b day and fire, 4c survivors done; vehicles and 4d menus and audio to come |
| Playable | The whole loop, it levels you, it gets dark, and you can hold it with other people. **E** searches and uses, **Tab** the pack, **C** crafting, **K** the character sheet, **B** build mode, **T** a torch, **F5** / **F9** save and load. |
| Unit tests | 249 tests, 3934 assertions (`tools\test.cmd`). `--all` adds the compound raid harness, the save round trips, the fire spread trials and the survivor combat tests: 279 tests, 4047 assertions. Wall-clock varies with the machine — see §9 |
| Smoke | 33 checkpoints: walk, sprint, seven districts, a container searched, the pack, a stack dropped and recovered, a wall built, walked into, repaired and salvaged, a hatchet crafted, the character sheet opened and a point spent, a chest filled, a save reloaded, a walker shot, a raid, dusk and night, a torch lit in the dark, a treeline set alight, somebody taken in, the roster opened, a job reassigned |
| World build | ~320ms generation, ~80ms terrain, at boot; a flow field ~2ms |
| Save format | **v4** — the crew (level, job, tower by tile, whatever they are hauling) and who is still out there, on top of v3's clock, v2's build, and v1's tile-derived container identity, world fingerprint and slots under `user://saves/`. No derived stat is ever stored: not the player's, not a survivor's. |

### Port status by system

Status legend: **—** not started · **wip** in progress · **ported** behaves
like the prototype · **verified** the owner has played it and it feels right.
The spec for each row is in `tasks/port-inventory.md`.

| System | Phase | Status | Notes |
| --- | --- | --- | --- |
| World generation, districts, danger field | 1 | ported | Bit-identical to the prototype: same RNG, same order |
| Tile collision (two maps) | 1, 3b | ported | `World.blocked` for terrain, `Structures` for what you built; passed in, never global |
| Player movement, stamina, camera | 1 | ported | Winded latch present; sprint alone never trips it (as in the prototype) |
| Intent (input → sim boundary) | 1 | ported | `LocalInput.gather` is the only reader of `Input` for the sim |
| Enemies, spawning, chase | 2 | ported | Count radius widened past the spawn ring (§6); stuck test is relative to pace (§6) |
| Noise | 2 | ported | One `Sound.make_noise`; alert + destination, never aggro |
| Quiet field / pressure | 2, 3b | ported | A base standing nearby quietens the ground, and losing it makes it dangerous again |
| Combat: melee, bow, guns, bullets | 2 | ported | Now fed by the hotbar; `TEST_KIT` is what the tests hold |
| Damage routing | 2 | ported | Solo death only; downed-not-dead is co-op (Phase 5) |
| Navigation | 2 | **new** | Flow field per living player; enemies chasing you follow it |
| Raids and threat | 2, 3b | ported | Raiders walk at the nearest structure; the compound harness reproduces §9 |
| Items registry | 3a | ported | `Items` over RES + WEAPONS + GEAR + CONSUMABLES; `Slots` is the container |
| Inventory, equipment, hotbar | 3a | ported | Tab; drag, right-click, ctrl+click to drop, shift+click to split |
| Loot and containers | 3a | ported | 30 tables; overflow always lands on the ground |
| Ground pickups and death packs | 3a | ported | Magnet, dropper hold-off, recoverable backpack |
| Lights (torch, flashlight) | 3a | ported | Charge lives on the player; the dark itself is Phase 4 |
| Crafting | 3c | ported | A tab of the pack, not a menu — the playtest finding |
| Storage screens | 3c | ported | Two panels, DEPOSIT ALL and TAKE SUPPLIES, reach-checked by tile |
| Building, structures, turrets | 3b | ported | Build anywhere; a Watchtower needs Phase 4 to post a survivor on it |
| Storage tiers | 3b | ported | Stash 48 / locker 32 / chest 16; the two-panel screen is 3c |
| Save / load | 3c | ported | v1: container identity by tile, world fingerprint, refusals with a reason |
| Progression, SPECIAL, perks | 4a | ported | `recompute_stats` is the whole build: base -> attributes -> perks -> gear, on one pure pass |
| Day/night and light | 4b | ported | Real 2D lights, as promised: `CanvasModulate` plus `PointLight2D`, not an overlay |
| Survivors, jobs, bunks | 4c | ported | Roster capped by Charisma and bunks both; everything out of the shared stash |
| Vehicles | 4 | — | |
| Fire | 4b | ported | Spreads through scenery and enemies; cannot reach a player structure, by design |
| Title screen, save slots, keybinds | 4 | — | |
| Audio | 4 | — | |
| Online co-op | 5 | — | Last |

---

## 4. What is built

### Other people (Phase 4c — survivors)

- **`Survivors`** owns the roster, the rescues, the upkeep and the day's work;
  **`SurvivorSim`** is one person. Their combat numbers are *derived*, not
  stored: `refresh()` rebuilds them from level and the base owner's Charisma
  perks, the same way `recompute_stats` rebuilds the player's. So Inspiring
  Presence reaches the crew already standing in your base rather than only the
  next hire, and a save stores the level rather than the health it implies.
- **Two limits, and the refusal names the one that binds.** Charisma is how
  many will follow you; Bunks are how many you can house; the cap is the lower.
  "No room" without saying which kind of room is useless, so
  `recruit_refusal()` returns the sentence the prompt and the roster both show.
- **Four jobs.** Guard holds the base. Sniper is posted on a Watchtower and
  gets its armament — but only while actually standing on it, because holding
  a reference to a structure across the base is not being up it. Scavenger
  works containers and hauls the loot home. Builder patches the most damaged
  thing in range, during a raid and after it.
- **Everything comes out of the shared stash.** Rations, ammunition, and a
  builder's materials. Food in your own pack is no use to anyone until you
  drop it off, which is the whole reason a Supply Stash is worth building.
  Unpaid upkeep accrues as debt, is charged *with* the next bill so restocking
  actually clears it, and is capped so a long trip away is recoverable rather
  than a death spiral.
- **Nothing a survivor carries is ever quietly destroyed.** A haul came out of
  a real container, so it is handed in or put on the ground when they are
  reassigned, when the stash cannot be reached, and when they die.
- **No pathfinding, so every walk has a give-up timer.** Invariant 6 is
  written about enemies and it is the same rule here: a container behind a
  locked gate would otherwise hold a scavenger against it for the rest of the
  run. A target that stops getting closer is written off and another picked.
- **Enemies ignore survivors unless one is in the way.** They come for you and
  for what you built; somebody standing between a zombie and its target gets
  bitten, which is what makes a line of guards a wall you have to keep alive.
- Down is a countdown, not a death: eight seconds, and a medkit or two
  bandages puts them back up. Nobody reaches them and they are gone for good.

### The dark, and what is in it (Phase 4b)

- **`DayNight`** — two numbers are the whole clock: `t`, the fraction of the
  day elapsed, and `day`. Everything else is derived, so a save stores those
  two and nothing can come back out of step. A day is 540s; dawn, day, dusk
  and night tile it without a gap; and the darkness is a ramp along
  `Config.DARKNESS_KEYS` rather than a step per phase, because dusk has to
  creep in. Each crossing announces itself exactly once.
- **The four multipliers already had callers.** The spawner's density, the
  sense radius, walk speed and `Threat.add` have all been reading
  `sim.night_factors()` since Phase 2, against a stub that always said noon.
  Turning the sky dark was the only thing that had to change.
- **Real 2D lights.** The prototype painted a translucent rectangle over the
  finished frame. This uses a `CanvasModulate` that multiplies the canvas down
  and `PointLight2D`s that add light back — so two torches overlap correctly
  instead of each cutting its own hole in an overlay. The torch, the
  flashlight (a puddle *and* a cone, which is what the batteries buy), powered
  floodlights, muzzle flashes and every fire are lights. Pooled and reassigned
  each frame, because 140 fires flickering in and out would otherwise be 140
  node allocations a second.
- **`Fire`** — a crowd weapon with a real cost. Burning enemies take 9 dps for
  6.5s and try to take their neighbours and the scenery with them; burning
  scenery lives ~7s, hurts anything standing in it (you included) and spreads
  at 16% a tick to what is within 1.6 tiles. A ceiling of 140 refuses rather
  than slows. A burnt prop leaves by the same door chopping uses, so a burnt
  treeline is still burnt after a save and load.
  - **Nothing in `fire.gd` can reach `sim.structs`.** That is a decision
    carried from the prototype, not an oversight, and there are two tests on
    it: a cheap one that no structure definition can even read as flammable,
    and a compound ringed with fire that takes zero damage.
  - Fire skips its enemy scan entirely when nothing is alight. Without that,
    every tick of every run paid for a full pass over the enemy list to
    discover that nothing was on fire — which put the test suite over its
    ten-second budget on its own.
- **Render interpolation.** The sim steps at 60Hz and the view draws at the
  monitor's rate, so two or three frames in a row used to show the identical
  position and then jump. Every entity captures where it was at the top of its
  tick and `Util.render_pos` blends. A gap larger than anything can walk in
  one step is treated as a teleport and snaps, so a respawn or a load does not
  slide in from across the map. The camera follows the *drawn* position, or
  the world juddered under a smooth player instead.

### What you become (Phase 4a)

- **`Progression`** — one door for XP. All nine award sites (kills, container
  searches, harvesting by hand and by tool, crafting, building, repairing, the
  workbench upgrade, raid payouts) call `add_xp`, which is the only place
  `xp_mul` is applied and the only place a level can happen. Levelling is a
  loop, not an `if`: a first raid payout is worth several levels at once.
  XP to the next level is `floor(55 + 45 * (level - 1) ^ 2.35)` — 55, 100,
  284, 649, 1224 — and every fifth level pays two points instead of one.
- **`Perks`** — six attributes (rank 1–10, everyone starts at 2) and
  twenty-eight perks gated on the rank of their parent attribute. The tables
  are data in `config.gd`; what a perk *does* is a match on its id, and a test
  asserts every id in the table moves at least one stat.
- **`recompute_stats` finally does its job.** Every derived number is written
  from `Config.STAT_BASE` and then layered: attributes, then perks, then gear.
  Buying a rank writes a count into `p.attrs` or `p.perks` and re-derives
  everything; nothing is mutated on purchase. That is what makes save/load and
  any future respec correct by construction, and it is why a save stores the
  build and never a stat.
  - The one deliberate exception is in `Progression`, not the recompute: a
    rank that raises the ceiling **hands the gain over** rather than leaving
    it as headroom, so Thick Skin bought mid-raid heals you by 30.
- **The character sheet is a fourth tab of the pack** (`K`), on the same
  argument that put crafting there. Clicking an attribute opens its tree;
  clicking it again spends a point — so browsing can never cost you one.
  Nothing is merely greyed out: a row you cannot buy says *why*, because
  "Needs STR 5" is a plan and "No skill points" is a wait.
- **Everything a perk promises, it does.** Build cost, structure health,
  turret power, trap damage, crafted ammunition yield, loot rarity, double
  drops, Adrenaline, Second Wind and the rest are wired to their consumers.
  Base-wide numbers (wall strength, turret reach) come from `sim.host()`, not
  from whoever is standing next to the thing.
  - **A perk whose system does not exist yet carries a `needs` field and
    cannot be bought.** It stays visible so the tree matches the spec and can
    be planned around, and its row says what it is waiting on — a point spent
    on nothing is worse than a row that explains itself. Two carry it today:
    **Sixth Sense** (the minimap, 4d) and **Hotwire** (cars, 4c). The field
    comes off as each system lands.
  - The five survivor stats (`survivor_cap`, `upkeep_mul` and friends) are
    produced here and not read until 4c, but the perks that write them —
    Recruiter, Inspiring Presence, Quartermaster, Natural Leader — are not
    gated, because 4c reads what they set the moment it exists.
- **Two perk descriptions were rewritten to match what they do.** Fire Control
  gives range half the bonus damage gets, and Fortune Favours is a 35% chance
  rather than a certainty. Both are the prototype's own numbers, and in the
  prototype both descriptions overstate them; the behaviour is ported
  faithfully and the wording corrected.
- **Salvage refunds a share of what you paid, not of the list price.** Without
  that, Engineer 3 builds a wall for 0.47 and salvages it for 0.55, and a wall
  put up and taken down again is free material. There is a test that turns 400
  wood into 424 against the unfixed code.

Starting stats are now *produced* rather than written down, and four of them
were previously sitting at their pre-attribute values: carry capacity 200 →
**225**, pickup range 46 → **49**, search time ×1.0 → **×0.95**, chop ×1.0 →
**×1.06**. All four now match the prototype at Strength/Perception 2.

### What you make and what you keep (Phase 3c)

- **`Crafting`** — instant, because the materials are the whole cost. The
  bench comes from the workbench you are standing beside; a Stone Hammer in
  the pack lifts the `hammer` recipes to bench 1 and no further, and a test
  walks every recipe to prove none of those is above bench 1 or makes a gun.
  The room check names the same container the craft will use, or the cost is
  spent and the output lands on the floor.
- **`SaveGame`** — payload v1. **Containers by tile position, never by
  ordinal index** (invariant 7), chopped props as tile keys replayed against
  a world rebuilt from the seed, and every structure, store, worn piece and
  magazine. `World.fingerprint()` is taken once when generation finishes and
  refuses a save the generator has outgrown, by name.
- **The screens** — crafting is a tab of the pack rather than a menu of its
  own, which is the playtest finding: a separate screen made you forget what
  you were carrying. A chest opens the same panel in STORE mode, contents on
  the left, with DEPOSIT ALL and TAKE SUPPLIES. `Interact` emits
  `open_store` with a tile and the scene decides that means a panel — the
  sim never learns what a screen is, and the reach check stays in the sim
  where a guest's command will meet it.

### What you build (Phase 3b)

- **`Structures`** — the destructible tile map and everything done to it:
  placement with the full refusal list, damage, destruction, repair,
  `plan_repair_all` (the label is the plan the button runs), demolition
  that spills what was inside, power, generators, turrets, spike traps,
  gates and the workbench upgrade. It hangs off `GameSim`, and every query
  that needs it is **handed** it rather than reaching for a global.
- **Collision** — `World.is_blocked_tile(tx, ty, structs)`. Movement,
  `unstick`, sight and the flow field all take the same optional argument;
  omit it and you get terrain, which is what bullets and the world
  generator want. Building bumps `world_version`, so the flow fields
  rebuild and the horde walks round the wall rather than through it.
- **Enemies** — the wall in front of one becomes the thing it hits, flesh
  always outranks scenery, and a stuck raider punches whatever it is stuck
  against rather than shuffling sideways for ever. `struct_mul` is what
  makes a brute the answer to a wall and a walker not.
- **Raids** — the centre is the base's centre, each raider walks at the
  *nearest* piece so the horde breaks on the perimeter, objectives are
  refreshed as walls fall, and the payout goes into the stash.
- **View** — `StructureView` draws every piece with its damage, a gate that
  is visibly open, a turret that points at what it is shooting and says
  when it has no power or no rounds. `BuildBar` is build mode: the wrapping
  card bar, the ghost, the range ring, REPAIR, REPAIR ALL and DEMOLISH.
- **The click is an intent.** `BuildBar` writes `build_action` /
  `build_type` / `build_tile` into the player's `Intent` and `PlayerSim`
  acts on it, so building goes through the same door as walking and firing.

### What you carry (Phase 3a)

- **`Items`** — one registry over `RES`, `WEAPONS`, `GEAR` and `CONSUMABLES`.
  `kind` ("res" / "weapon" / "gear" / "consumable") is what the screen
  switches on. Fists are excluded: they are not an object you carry.
- **`Slots`** — the slot container behind the pack, the hotbar and (from 3b)
  every chest. Add tops up part-used stacks before opening new ones; `add`
  and `add_capped` report what actually fitted so the caller can spill the
  rest. The plain id→count maps keep their own three functions on `Items`.
- **`PlayerSim`** — a 30-slot `bag`, a 6-slot `hotbar` and six `equip`
  slots. `count_res` / `add_res` / `take_res` still answer for the pack, so
  reloading and healing did not have to learn about any of this;
  `count_carried` is the wider question, and only what you hold in your hand
  asks it. Capacity is weight across pack and hotbar together.
- **`Loot`** — the weighted roll, the prefixed entry grammar
  (`weapon:` / `gear:` / `item:` / bare resource) with the pickup decoder
  beside it, ground piles with the magnet and the dropper hold-off, the
  death backpack, and small drops from bodies.
- **`Interact`** — one function decides what `E` is offering, so the prompt
  and the key can never disagree. Searching is a held channel that stops if
  you let go or drift away; gathering is offered last, because litter is
  everywhere and would otherwise outrank the cabinet you crossed the room for.
- **`Equipment`** — equip, unequip, quick-equip, moves, drops and the light,
  every one ending in `recompute_stats()` (invariant 4). Phase 3 gives that
  function one output, `armor_dr`; Phase 4 grows it into the whole build.
- **View** — `PickupView` draws the piles and packs; `InventoryScreen` is the
  pack, drawn immediate-mode against a computed cell list so the hit test and
  the drawing describe the same rectangles; the HUD gained the real hotbar, a
  weight bar, the interact prompt and the search ring.

### Something to fear (Phase 2)

All simulation, all `RefCounted`, all under `src/sim/`:

- **`EnemySim`** — one enemy: the spec row's numbers copied out, position,
  aggro, alert timer, noise destination, wind-up, stuck timer, raid flag.
- **`Enemies`** — the list, the spatial hash (96px cells, rebuilt each
  step), the ambient spawner (population per danger tier around each living
  player, ring off screen, cull at 2400px, cap 160, the quiet field's
  suppression) and the AI step: sense (halved crouching), sight check to
  set aggro, aggro expiry unless real sensing renews it, noise destination
  dropped on arrival, idle wander, wind-up then bite, probe steering,
  separation, stuck rescue.
- **`NavField`** — a flow field: BFS distances over the collision bitmap
  in an 83-tile window around a player, padded so the loop has no bounds
  checks (1.6ms). `step_dir` picks the closest of eight neighbours and
  refuses a diagonal between two blocked corners. `GameSim.nav_for(p)`
  rebuilds when the player has moved two tiles or the world changed.
  A hunting enemy goes straight only with a body-width clear run.
- **`Sound`** — `make_noise(sim, x, y, radius, actor)`: alert + destination
  for everything in range, scaled by the actor's `noise_mul`. Never aggro.
- **`QuietField`** — 256px cells, bilinear read, the 1.7-cell kill kernel,
  ceiling 6, decay 6/270 per second, suppression at 2.9, floor 0.3.
- **`Combat`** — bullets (12px substeps, terrain-only collision, pierce at
  75%), the melee arc (enemies first; only an empty arc falls through to
  scenery; a target needs the same clear line a bullet does, so no
  swinging through a wall), harvest stamina and the winded latch, tool
  gates and hints,
  guns with magazines, spread, pellets, recoil, shell-at-a-time reloads,
  the bow as a one-round gun.
- **`Damage`** — enemy damage with knockback and resistance, kills (xp to
  the killer, threat, quiet, corpse), player damage with invulnerability,
  death, healing, respawn on tier-1 ground clear of enemies.
- **`Threat`** and **`Raid`** — the meter (gain scaled by night, decay,
  pinned at 100, tier warnings); the raid (12s warning, waves, 0.22s spawn
  cadence on a 520–800px ring, hp x(1 + 0.06 x index), anti-stall
  relocation, 25s no-progress break-off, 300s ceiling, payout by share).
- **`GameSim`** gained: `events` (the sim tells the view what happened:
  shot, hit, kill, notify, shake — the list co-op will send), `stats`,
  `night_factors()` (day until Phase 4), `base_centre()` and
  `structure_hp_total()` (Phase 3 hooks), `view_radius`, `world_version`.
- **`PlayerSim`** gained: the loadout, `res` (id -> count, the resource API
  Phase 3's inventory keeps), magazines, attack cooldown, reload, healing
  channel, swing, recoil, invulnerability, death and the starting stat
  multipliers (rank 2 in every attribute: 112 HP, +9% melee, +6% chop, 8%
  crit).

Presentation: **`EnemyView`** (tiered bodies, arms raised in the wind-up,
hurt flash and bar, raid tick, fading corpses), **`FxView`** (tracers,
blood, sparks, muzzle flash, debris, damage numbers, harvest labels, the
swing arc, rings), the **`Hud`** (hotbar with magazines, reload, Q meds,
Threat meter with tier, raid banner, notices, hurt vignette, death), and
`main.gd` draining events into them with camera shake.

### The game (Phase 1)

- **`Config`** — tile size, terrain palette, solid/shoot-over tables, the
  player's numbers, camera, the 18 districts, container kinds, furnishing
  tables. Content only; no logic.
- **`Rng`** — Mulberry32, bit-for-bit the prototype's, so seed 20240917
  is the same town in both builds. Tested against values from Node.
- **`World`** — the generator, ported function-for-function: terrain noise,
  the Marrow river with two bridges, four lakes, the road grid, every
  building with doors, partitions and furniture, cars, wrecks, woodland,
  boulders, thickets, litter, the starter cache, reeds, the danger field
  and the spawn tiles. Plus the accessors and the circle-vs-tile movement
  (`move_circle`, `unstick`, `circle_hits_solid`). 644 containers, 10,916
  props, 72 cars, 3,267 spawn tiles — the prototype's counts exactly.
- **`PlayerSim`** — position, velocity, aim, stamina with the regen delay
  and the winded latch, sprint and sneak multipliers. Reads only `Intent`.
- **`GameSim`** — owns the world and the players; `tick(dt)`; spawn choice.
- **`TileArt`** + **`TerrainRenderer`** — a 32px atlas generated from
  rectangles at boot (five variants per terrain, 16 water-lip masks, 16
  fence masks, bridge parapets, road dashes, three wall faces, a shadow),
  laid into three `TileMapLayer`s: ground, wall shadow offset (3,5), walls.
- **`PropRenderer`** — trees, pines, bushes, rocks, boulders, thickets,
  litter, reeds, hay, silos, wrecks, containers and parked cars drawn with
  canvas primitives from 256px buckets, y-sorted, split into a behind-player
  and an in-front-of-player instance.
- **`PlayerView`**, **`Hud`** — the survivor with a seat-coloured ground
  ring and a weapon pointing at the cursor; district name, danger pips, HP
  and stamina bars, an fps/tile corner.
- **`Bindings`** autoload — default keys registered in code (WASD/arrows,
  Shift sprint, Ctrl sneak, E, R, Tab, C, B, M, Esc, mouse fire/aim).
- **`LocalInput`** — the one reader of the keyboard for the simulation.
- **`scenes/main.gd`** — builds all of the above, gathers intent in
  `_physics_process`, ticks the sim, lerps the camera in `_process`, and
  exposes `smoke_run` / `smoke_state` / `smoke_teleport`.

### Infrastructure (Phase 0)

- **Headless test runner** (`tests/run.gd`). Discovers `tests/**/*_test.gd`,
  runs every `test_*` method on a `TestCase` subclass, records every failed
  assertion with file and line, prints a summary, exits non-zero on failure.
  Optional substring filter: `tools\test.cmd world`. It also installs an
  `OS.add_logger` spy around every test method, so any error the engine logs
  during a test is a failure of that test.
- **`TestCase`** (`tests/test_case.gd`): `ok`, `eq`, `ne`, `near`, `gt`, `has`,
  `before_each`, `after_each`. Failures accumulate rather than abort. Test
  files use `extends "res://tests/test_case.gd"` by path so they never depend
  on the class cache.
- **Smoke autoload** (`src/debug/smoke.gd`). Inert normally. With `-- --smoke`
  it runs a scripted session through the real input path (`hold`, `tap`),
  and at each `checkpoint(name)` writes a viewport PNG plus a JSON dump of
  the current scene's `smoke_state()` to `.smoke/`. Claude reads the PNGs.
- **Placeholder main scene** so the smoke path has something to photograph.

---

## 5. Architecture

```
project.godot        main scene, autoloads, 1280x720, nearest-neighbour textures
scenes/main.tscn     the root scene (placeholder until Phase 1)
src/
  config.gd          ALL tunables and content tables. One file to balance.
  sim/               RefCounted simulation classes. No nodes, no Input.
                     Everything here runs headless and is unit-tested.
  world/             nodes that draw the sim: tile layers, entities, camera
  ui/                HUD, inventory, menus (Control nodes)
  debug/smoke.gd     the smoke-test autoload
tests/
  run.gd             the runner (SceneTree script, headless)
  test_case.gd       assertion base class
  *_test.gd          one file per sim module
tools/
  test.cmd / .sh     unit tests
  smoke.cmd / .sh    the windowed smoke run
```

### The one architectural rule

**Simulation and presentation are separate layers.** The sim is plain
`RefCounted` classes holding plain data (world tiles, entity arrays, inventory
slots) and stepping them with `tick(dt, intents)`. Nodes read the sim to draw
it and write to it only through `Intent` or the action layer. This is what
lets every rule run under `--headless` in milliseconds, and it is the same
split that made co-op possible in the prototype (the host's sim is
authoritative; guests send intent and render snapshots). Phase 5 depends on
Phases 1–4 respecting it.

### Invariants — break these and something subtle goes wrong

1. **Sim classes never touch nodes or `Input`.** `Intent` is the only way
   input reaches them. A second player's intent arriving over a wire must
   drive identical code.
2. **All static collision is one tile bitmap** (`PackedByteArray`). Player
   structures live in a *separate* destructible map. Collision, bullets,
   build validation and AI steering read the same two sources.
3. **Bullets collide with terrain only** and pass over player structures
   (pillar 3). Water and fences go the other way: solid to feet, transparent
   to shots.
4. **`recompute_stats()` is the only source of player stat modifiers.**
   Base → attributes → perks, rebuilt from scratch. Never mutate a stat on
   purchase.
5. **Every tunable and content table lives in `config.gd`.**
6. **Anything that walks toward a target needs give-up logic**, even with
   navigation. The prototype's stuck-AI bugs all came from the absence of it.
7. **Container identity in saves derives from tile position**, never from
   ordinal index. The prototype's ordinal scheme invalidated every save twice.
8. **Simulation code takes the acting player as a parameter.** A system that
   means "whoever did this" — damage, XP, threat, cost, loot — takes `p`.
9. **The class_name cache goes stale** whenever a script is added outside the
   editor. `tools\test` runs `--import` first for exactly this reason. If a
   headless run says "Could not find type", that is why.

---

## 6. Decision log

| Date | Decision | Why | Reversible? |
| --- | --- | --- | --- |
| 2026-09-08 | Rebuild in Godot rather than keep extending the browser prototype | Navigation, 2D lighting, distribution and entity scale all cost more to fake in Canvas2D than to get from an engine. The code only gets bigger, so now is the cheapest moment. | Not cheaply |
| 2026-09-08 | GDScript, not C# | Fastest iteration, no build step, what the tooling and community assume. | Yes, per module |
| 2026-09-08 | Rebuild, not translate | 18,800 lines of JS with browser-specific harnesses. Translating carries the prototype's compromises; rebuilding against the spec lets each system be finished properly (pillar 5). | n/a |
| 2026-09-08 | Harness before any game code | Every serious bug in the prototype was invisible in review and found only by running the game. | n/a |
| 2026-09-08 | Sim as RefCounted classes, nodes as a view layer | Headless tests in milliseconds; the same split co-op needs. | Expensive later |
| 2026-09-08 | Keep Forward Plus + D3D12 as created | Works on this machine; Compatibility would reach weaker PCs. Revisit at export time. | Yes, one setting |
| 2026-09-08 | 32px tiles, 1280x720 base, nearest-neighbour filtering | Matches the prototype's scale so the spec's numbers carry over. | Yes, but touches every number |
| 2026-09-08 | Code-generated art, as in the prototype | "The project as it is now." A real tileset is a separate decision for after it plays. | Yes |
| 2026-09-08 | Multiplayer is Phase 5, last | It is the largest rebuild and depends on the sim/view split holding through Phases 1–4. | n/a |
| 2026-09-08 | Playtest gate after Phases 1, 2 and 3 | The prototype's roadmap was blocked on the owner playing it. Do not let that happen again. | n/a |
| 2026-09-08 | Smoke output to `.smoke/` in the project, gitignored | `user://` is buried in AppData; a project-relative path is one Read away. | Yes |
| 2026-09-08 | The world generator is the one thing translated line-for-line, RNG included | The map is authored content, not architecture. Keeping it bit-identical means every number in the spec still points at the same tile, and a checksum against the browser build proves the port instead of a screenshot opinion. | Yes, per district |
| 2026-09-08 | Terrain baked into a TileMapLayer atlas; props drawn with canvas primitives per frame | Tiles never change shape, so bake them once and let the engine cull. Props are ~11k dictionaries that get harvested, burned and rebuilt; drawing the visible few hundred from buckets each frame is simpler than 11k nodes and is what the prototype did. Revisit if a frame ever costs more than 2ms here. | Yes |
| 2026-09-08 | Sim ticks in `_physics_process` at 60Hz; view redraws in `_process` | Matches the prototype's fixed timestep, and `is_action_just_pressed` is per-physics-frame there, which is invariant 5 (edges consumed exactly once) for free. No render interpolation yet. | Yes |
| 2026-09-08 | Sprinting alone never winds you | Ported as found: sprint stops at "stamina above 1", so the bar hovers just above empty and only refused work trips the latch. The prototype's comment claimed otherwise; the code did this. Flagged for the owner's walk. | Yes, one condition |
| 2026-09-08 | A flow field per living player, not NavigationServer2D | The sim must run headless with no nodes or servers; a BFS over the collision bitmap is 1.6ms, deterministic and testable (a walker finds the shack door in 10.7s where straight steering never does). Enemies not hunting a player still steer straight, and the prototype's probe steering and give-up rules stay underneath. | Yes |
| 2026-09-08 | Spawner count radius 1400, not the prototype's 950 | The prototype counted inside a ring that ran 880–1300, so most of what it spawned never counted: measured here, a still player in tier 1 collected 26 enemies in 20 seconds against a target of 4. Counting past the ring's edge gives exactly 4. The "no lull to build in" the quiet field was added to cure was partly this. Flagged for the owner's fight. | Yes, one number |
| 2026-09-08 | Stuck test relative to the enemy's own pace | The prototype called an enemy stuck below 1.1px per step, which a walking brute (52px/s) never exceeded, so brutes lurched sideways every 0.7s. "Under a quarter of its pace while trying to get somewhere" is what the check meant. | Yes |
| 2026-09-08 | A fixed six-weapon kit and a plain `res` map until Phase 3 | The gate is "the owner fights", which needs every weapon in hand. The hotbar, drag and drop and weight arrive with the inventory; the resource API (`count_res`, `add_res`, `take_res`) is the one the stash keeps. | n/a |
| 2026-09-08 | The sim reports through an event list, not callbacks into nodes | `GameSim.events` is drained by `main.gd` each frame into effects and the HUD. It keeps the sim node-free, and it is the reliable-channel event stream co-op needs. | Expensive later |
| 2026-09-08 | Raiders come for the player until structures exist | The spec targets the nearest structure so hordes break on the perimeter; with no structures the only target is you. The compound reference figures (§9) are a Phase 3 check. | n/a |
| 2026-09-08 | A melee target needs the line a bullet needs | The arc checked distance and angle only, so a pipe (73px of threshold) hit through a one-tile wall that holds two bodies 66px apart. Terrain line of sight, not foot collision, so water and fences are still swung over — the same asymmetry shots have. | Yes, one check |
| 2026-09-08 | `bleed` dropped from the machete, knife and scythe | The prototype declared it on three weapons and never read it anywhere. Advertising a mechanic nothing implements is worse than not having it (pillar 5); those three are already separated by damage, cadence, reach and arc. Comes back as a spec'd mechanic or not at all. | Yes |
| 2026-09-08 | An unfinished raid pays XP on the same share as salvage | The floor was `0.5 + share/2`, so a horde you never touched still paid half its XP — the exact "hiding beats defending" the salvage share exists to prevent. | Yes, one expression |
| 2026-09-08 | The save fingerprint is taken when generation finishes, not when the save is written | It has to describe the *generator*, not the run. Taken live it included the current collision bitmap and prop count, so felling a single tree changed it and the save refused itself on load. A test fells a tree and asserts the fingerprint does not move. | Yes |
| 2026-09-08 | Crafting is a tab of the pack, and storage is the same panel again | The playtest finding from the prototype: a crafting screen of its own made you forget what you were carrying. One panel, three modes, one `_cells()` — and the storage half is opened by an event carrying a tile, so the sim never learns what a screen is. | Yes |
| 2026-09-08 | The structure map is passed to collision, never read from a global | The prototype reached for `G.structures` from inside `solidTile`. Here every test shares one generated `World` — a wall built in one simulation would exist in the next — so `is_blocked_tile(tx, ty, structs)` takes it as an argument and the world stays a pure generated artefact. It also makes invariant 3 impossible to get wrong: bullets simply do not pass it. | Yes, but it is a signature change |
| 2026-09-08 | A click in build mode becomes an `Intent` field, not a call into the sim | `build_action` / `build_type` / `build_tile` go through the same door as movement and firing, so a guest's build command will run identical code and the UI stays a view. | No reason to |
| 2026-09-08 | The pump-action interrupt only fires with a round in the tube | Found by the compound harness on its first run: a defender holding the trigger on an empty shotgun cancelled its shell-at-a-time reload every frame and never fired again — 900 shells, two minutes, no kills, and the siege ran to the 300s backstop. Firing interrupts a reload because there is something to fire; an empty gun has nothing to interrupt it with. | Yes, one condition |
| 2026-09-08 | The runner fails a test on any engine error logged while it ran | `TestCase` records failures instead of throwing, but a GDScript *runtime* error aborts the method and hands control straight back to the runner, which then counted the test as passed on however few assertions it had reached. Four `building_test.gd` methods sat like that. An `OS.add_logger` spy around each method closes it in twelve lines; the alternative, an end-of-method marker in all 165 tests, is bigger and leaks the moment someone forgets one. | Yes |
| 2026-09-08 | The compound raid harness is a `_slow_test.gd`, run by `tools\test --all` | It is 3.5s of simulated siege on its own and took the suite past the ten-second agreement. Splitting the tier keeps the working agreement honest instead of quietly widening it; `--all` runs once per branch beside the smoke run. | Yes |
| 2026-09-08 | One `Slots` container, and the pack keeps the Phase 2 resource API | `count_res` / `add_res` / `take_res` now answer for the bag rather than a flat map, so reloading, chopping and healing did not change at all when the inventory landed underneath them. The stash and car boots stay plain id→count maps with three functions of their own: the prototype proved one API can serve both shapes. | Yes |
| 2026-09-08 | Weight capacity is netted across the pack and the hotbar | The bar shows both, so every capacity check has to subtract the hotbar or loot keeps fitting after the bar reads full. `pack_allowance()` is the one expression that does it. | Yes |
| 2026-09-08 | The entry grammar and the pickup decoder live in the same file | `weapon:` / `gear:` / `item:` / bare resource, encoded and decoded within twenty lines of each other. In the prototype the two drifted and the symptom was rare gear silently deleted on contact — a bug you only find by dropping a rifle. | No reason to |
| 2026-09-08 | Nothing equips itself | Loot goes to the pack and waits. The prototype auto-wore the best piece and became impossible to reason about; quick-equip is a button you press, and it never picks between a torch and a flashlight for you because that is a decision about how loud you want to be. | Yes |
| 2026-09-08 | Gathering is the last thing `E` offers | Ranked by distance like everything else, a twig at your feet beats the container you walked across the room for. Litter is everywhere by design, so it only gets the key when nothing else wants it. | Yes |
| 2026-09-08 | A dropped pile ignores its dropper until they step clear | It lands at your feet, inside collection range, so without the hold-off the magnet hands it straight back and dropping does nothing. A state, not a timer: it waits as long as you stand there. Teammates may take it immediately — that is how you hand something over. | Yes |
| 2026-09-08 | The pack screen is drawn immediate-mode, not built from Control nodes | One `_cells()` function produces the rectangles that both the drawing and the hit test use, so they cannot describe different grids. It is also how the HUD already works, and how the prototype's canvas inventory worked. | Yes, but it is a rewrite |
| 2026-09-08 | Panels are polled, not handled as input events | `Input.action_press` sets action state without synthesising an `InputEvent`, so a scripted Tab never reached `_unhandled_input` and the smoke run could not open the pack. Polling `is_action_just_pressed` matches every other key here and keeps the smoke path honest. | Yes |
| 2026-09-08 | Anti-stall relocation gated at 400px, and the no-base centre follows you | The gate was a bare 240 and the centre froze at the warning, so a raider legitimately chasing a player who had moved read as stalled and got warped out of the fight. 400 sits below the 520px spawn ring (a raider wedged where it spawned is still rescued) and past half a screen (nothing you are watching is teleported). | Yes, one number |

---

## 7. Roadmap

Detail and checkboxes are in `tasks/todo.md`. This is the shape.

| Phase | Delivers | Gate |
| --- | --- | --- |
| 0 | Harness, smoke path, this document | ✅ 2026-09-08 |
| 1 | World, tiles, collision, player, camera | Built 2026-09-08 — **owner walks the map** |
| 2 | Enemies, combat, noise, quiet field, navigation, raids | Built 2026-09-08 — **owner fights** |
| 3 | Items, inventory, loot, crafting, building, raids, saves | Owner builds and holds a base |
| 4 | Progression, day/night, survivors, vehicles, fire, menus, audio | Owner plays a full session |
| 5 | Online co-op | Owner plays with a friend |

### Next up

0. **The owner walks, fights, and builds** (the Phase 1, 2 and 3 gates,
   together — three phases are now waiting on one session at the keyboard).
   Phase 3's questions: does searching a container at 1.05s feel like
   searching or like waiting; is a thirty-slot pack at 200 units generous or
   fussy; does dropping and dragging read; is the build bar quick enough to
   use mid-raid; does a wood wall feel worth 16 wood; is crafting-in-the-pack
   the right call. And the older ones:
   Walking: is 176px/s the right pace at this zoom; does the camera lead
   feel like aiming or like drift; should sprinting to empty wind you; is
   the world readable at a glance; is the zoom right. Fighting: does a
   walker read as a walker and a brute as a brute in a crowd; is the pistol
   too easy and the bow too weak; does the wind-up telegraph a bite in
   time; do enemies coming round a building feel like hunting or like
   cheating; does the tier-1 crowd (four around you, 1400px) feel thin or
   dead; does a raid with nothing to defend feel like anything.
   Phase 4a adds two more: does a level arrive often enough to feel earned
   and rarely enough to feel like something, and is the character sheet worth
   a tab or does it want to be a menu you stop for? And 4b adds the big one:
   **is night dark enough to matter and light enough to play in?** The curve
   peaks at 0.82 alpha, which is the prototype's number, and the tint is now
   applied the way the prototype applied it — so this is the real curve
   rather than the too-dark one the first cut of `LightView` produced.
1. **Vehicles.** About thirty cars, 62% locked, opened by a key, a lockpick
   or Hotwire; arcade handling, fuel, roadkill, a 400-unit boot. Split out of
   4c because survivors alone was already a large change, and because Hotwire
   is the one perk still refused for want of the system it names. Cut from
   `main` once the survivors PR is in.
2. **Phase 4d — the front door.** Title screen, save slots with an index,
   autosave, full key rebinding over `src/core/bindings.gd`, a pause menu that
   saves before it quits, the minimap (which is what Sixth Sense is waiting
   for), and synthesised audio with per-kind rate limits.

### Deliberately not building

Thirst, detailed hunger, temperature, illness, sleep, long crafting timers,
many ammo calibres, farming, factions, dialogue, quests, huge procedural
worlds, realistic electrics or plumbing. PvP, dedicated servers and
persistent shared worlds. Carried over from the prototype and still right.

---

## 8. Lessons

Distilled. The raw log is `tasks/lessons.md`; the prototype's full §8 is
summarised in `tasks/port-inventory.md`.

### From the prototype, still true here

- **Test by running the game.** Review finds nothing that matters in this
  kind of code. The smoke path exists so that "does it work" is a screenshot,
  not an opinion.
- **Assert on outcomes**, not on calls. `killed > 0`, `raid completes`.
- **The owner's feel feedback outranks the roadmap.** Numbers are measured
  until someone plays them.
- **Match the check to the change.** Unit tests every commit; smoke once per
  branch. Running the slow suite after every edit was what slowed the
  prototype down, and it caught nothing the targeted checks missed.
- **Saves are the first thing content changes break.** Design identity into
  the save format from the start.

### New in Godot

- **Checksum the port against the original.** Summing every tile and every
  collision byte in both builds and comparing the two numbers proved the
  world generator in one line, and the first mismatch would have said
  exactly where to look. Do this for every system that has a prototype
  counterpart with deterministic output: loot tables, raid schedules, the
  XP curve. (2026-09-08)
- **Type your loop variables.** `for off in [Vector2i(...)]` leaves `off`
  a Variant, and the first `var x := a + off.x` is a parse error that takes
  the whole dependent script chain down with it. `for off: Vector2i in`
  costs nothing. (2026-09-08)
- **A smoke run that cannot find its scene must fail, not pass.** A script
  that fails to compile has no methods, so "no smoke_run here" looked like
  "nothing to check" and exited 0. It now fails. (2026-09-08)
- **The prototype's comments are claims; its code is the spec.** The
  sprint-winds-you comment described behaviour the code never had. Port
  what runs, then flag the gap for the owner. (2026-09-08)
- **The class_name cache is not the file system.** A script added by hand is
  invisible to `--headless` until an import pass runs. (2026-09-08)
- **Rewriting `project.godot` while the editor is open loses.** The editor
  holds settings in memory and writes them back. Close the project first,
  or edit through the editor. (2026-09-08 — the owner hit "no main scene")
- **Measure with a control, and keep the player in range of the cull.** The
  first noise test parked the player 3000px away so nothing would be
  sensed, and the walker was culled after 0.6s; "walked 13px toward the
  bang" looked like a broken mechanic. 1500px is out of sense and inside
  the cull. (2026-09-08)
- **A packed array inside an Array is a copy.** `buckets[i].append(x)` on a
  `PackedInt32Array` element modifies a temporary; use a plain `Array`
  element or index into one flat packed array. (2026-09-08)
- **Godot owns some good class names.** `class_name Noise` compiles and
  then every `Noise.make_noise` call fails with "not found in base
  GDScriptNativeClass". The sim's is `Sound`. (2026-09-08)
- **Type the variable when the value comes from `Dictionary.get`.**
  `var x := d.has("k") and w.get("k", false)` is a Variant and a parse
  error that takes the dependent scripts down. (2026-09-08)
- **Trace before tuning.** A walker that took 10.7s round the shack looked
  like oscillation; a per-second trace of its field distance (22 → 3,
  monotonic) showed it was a 22-tile path at a walker's pace. (2026-09-08)
- **A member initializer runs while the class is still loading.** `var bag
  := Slots.new(...)` at the top of `PlayerSim` failed with "nonexistent
  function 'new' in base GDScript" — the other class was not ready yet.
  Build cross-class objects in `_init`. (2026-09-08)
- **A green suite can be lying about how much it ran.** Four `building_test.gd`
  methods aborted on a runtime error partway through: a renamed `NavField`
  method, and three that read a field off the empty `Dictionary` that
  `Structures.at_tile()` returns when a build had silently failed for want of
  materials. All four reported as passing, on a fraction of their assertions.
  Assert that a `place()` came back non-empty before using what it returned.
  (2026-09-08)
- **The unit tests never load the UI.** Two parse errors in the pack screen
  passed a green `tools\test` and only surfaced when the smoke run tried to
  boot the scene. A UI change is not verified until the smoke run has drawn
  it. (2026-09-08)
- **`Input.action_press` does not synthesise an `InputEvent`.** It sets the
  action's state, so polled code sees it and `_input`/`_unhandled_input`
  never fire. Anything the smoke run needs to press must be polled.
  (2026-09-08)
- **A harness that only measures the end state hides the middle.** The
  compound siege "ended" every time — at the 300s backstop, which is a
  pass for `raid == null` and a failure for the game. Printing what was
  alive, how far out and what the defender was holding, every sixty
  seconds, found the empty-shotgun reload bug in one run. (2026-09-08)
- **A fingerprint that guards a save must describe the generator, not the
  run.** Taken live it included the current collision bitmap and prop
  count, so felling one tree changed it and the save refused itself.
  (2026-09-08)
- **A Control keeps whatever it last drew.** The build bar had its own
  `open` flag and the scene stopped redrawing it when closed, so the cards
  stayed painted over the world. Set `visible` and let Godot hide it.
  (2026-09-08)
- **Scripted mouse input needs the cursor, not just the event.** A panel
  reading `_gui_input` gets the position off the event; code polling
  `get_global_mouse_position` does not. Warp first, hold the button for
  several frames so a physics step sees it, and re-aim in a loop when the
  camera leads toward the cursor and moves the target. (2026-09-08)

---

## 9. How to verify

| When | What to run |
| --- | --- |
| While working | `tools\test.cmd` (optionally with a filter), plus a targeted smoke checkpoint of the one thing you changed |
| Before you commit | `tools\test.cmd` |
| Before you push for review | `tools\test.cmd --all` and `tools\smoke.cmd` once, and read the PNGs |

All must report **zero failures**. Current expected output:

```
tests: 249  asserts: 3934  failures: 0
tests: 279  asserts: 4047  failures: 0   (--all)
SMOKE done checkpoints=33 failures=0 exit=0
```

**On timings.** The ten-second agreement is about the edit loop staying quick,
and the number is machine- and load-dependent: the identical commit measured
9.9s and 12.1s on the same PC within one session. Compare a change against a
baseline measured in the same sitting rather than against a figure written
down here — the fast tier was 9.57s on `main` when Phase 4b started, and 4b
added about 0.3s to it.


Since PR #7 the runner fails a test on any engine error logged while it ran,
so a method that aborts partway can no longer report as passing. Four
`building_test.gd` methods had been doing exactly that.

`tools\test` skips `*_slow_test.gd` so the default loop stays under the
ten-second agreement. There is one such file — the compound raid harness,
three and a half seconds of simulated siege — and `--all` is what runs it.

The tests also print measurements worth reading when a number moves:

```
spawner: 4 within 1400 px, 4 alive after 20s in tier 1
nav: 83x83 field built in 1.6 ms
nav: with the field the walker closed from 128 to 47 px in 10.7s; straight steering got to 128 px
noise: closed 105 px toward the bang in 4s; control drifted 43
raid harness [0 SCATTERED HORDE]: 18s, 19 kills, repelled=true, scrap +30
raid harness [2 HEAVY HORDE]: 93s, 52 kills, repelled=false
```

The raid harness plays a god-mode defender against a raid and reports.
`tests/raid_test.gd` runs index 0 in the open; `tests/compound_slow_test.gd`
builds the prototype's standard compound — an 11x11 perimeter, four gates,
spikes on the north approach, workbench, stash, bedroll, generator and two
turrets — and throws raids at it. **The number is `raids_done`, a zero-based
index, not the raid's ordinal:** index 1 is the second raid, RUNNING HORDE.

| Index | Ours (2026-09-08) | The prototype's range |
| --- | --- | --- |
| 1 RUNNING HORDE | 60s, 0 lost, walls 100% | 70–93s, 0 lost, walls 18–90% |
| 3 SIEGE | 124s, 11 lost, walls 86% | 72–260s, whole base, walls 0% |

**These are single runs of a stochastic harness — read them as ranges.** The
browser build produced 67s and 172s for the same raid on the same code. What
matters is that nothing reaches the 300s backstop and that what the compound
loses is stable; when a run looks wrong, run it twice more before reading
anything into it. Index 3 leaves more perimeter standing than the browser
build did because our defender never dies and the prototype's died twice.

The smoke PNGs in `.smoke/` are the proof for anything visual: read them.
`00_spawn` and `01_walked_east` should show the survivor on the highway
west of the camp; `03`–`09` are the suburbs, Market Row, downtown, the
farms, the lake lodge, the forest and the junkyard; `10`–`13` are a
container just searched, the pack screen with the pipe and the bandages on
the hotbar, a dropped stack on the ground and the same stack recovered;
`14`–`15` are a wall built beside the camp and the same wall repaired,
with the build bar and its ghost; `16`–`19` are the craft tab, a chest
opened, the same chest after DEPOSIT ALL, and the game reloaded from disk;
`20`–`23` are a walker approaching with its arms out, its corpse after
three pistol rounds, the raid banner with a raider on the ring, and the
salvage notice.

A UI change is not verified by `tools\test.cmd`: the headless run never
loads a Control, so a parse error in a screen passes the tests and fails
the game. Run the smoke and look at the picture.

`tools\smoke.cmd` opens a window for a few seconds; that is expected. The
Godot MCP's `run_project` / `get_debug_output` are the alternative when a
window is not wanted, once the desktop app has restarted with the 4.7.2 path.

---

## 10. Session protocol

1. Read this file, then `tasks/todo.md`.
2. **Branch from an up-to-date `main`:**
   `git fetch origin && git checkout -b <name> origin/main`.
3. Work. `tools\test.cmd` before every commit.
4. Before finishing: update §3 (status table and numbers), §7, §11; add a §6
   row for any choice a future session might reverse without knowing why;
   add lessons to §8 and `tasks/lessons.md`.
5. `tools\test.cmd --all` and `tools\smoke.cmd` once, and read the PNGs.
6. **`gh pr create --base main`.** Then check nothing has drifted:
   `gh pr list --json number,baseRefName` — every open PR must say `main`.

### `main` is the only merge target

A branch cut from another open branch produces a PR that merges into that
branch, and the work never reaches `main`. It has happened here once:
`phase-2-combat` was cut from `phase-1-world` while PR #1 was open, PR #2
merged Phase 2 into `phase-1-world`, PR #1 had already merged, and `main`
sat on Phase 1 while Phases 3a, 3b and 3c stacked on the wrong branch.
Untangling it cost a fourth PR (#6) and a retarget of three others.

Stack a branch only when the work genuinely cannot compile without a parent
that is still open — say so in the PR body, and retarget to `main` the
moment the parent merges.

---

## 11. Changelog

| Date | What |
| --- | --- |
| 2026-09-08 | Phase 4c (survivors): `SURVIVOR`, `JOBS`, `SCAVENGE`, `BUILDER`, the names and the rescue counts in `Config`; `SurvivorSim` (one person, combat numbers derived from level and the owner's Charisma perks) and `Survivors` (the roster and its two limits, rescues seeded on their own RNG stream, recruiting with a refusal that names the binding limit, Rations upkeep from the shared stash with clearing debt and a cap, damage, down, revive and permanent death, XP and levels, and the guard/sniper/scavenger/builder step); enemies bite a survivor who is in the way; a survivor's kill pays the survivor and the player; `E` takes somebody in and helps somebody up, ahead of every container and gate; a CREW tab on the pack screen with the roster, both limits and the ration clock; `SurvivorView`; `SaveGame` v4 carries the crew and the rescues, a sniper's tower keyed by tile (invariant 7); 26 new tests, three in the slow tier; smoke takes somebody in, opens the roster and reassigns them |
| 2026-09-08 | Phase 4b: `DAY_LENGTH`, `PHASES`, `DARKNESS_KEYS`, `NIGHT`, `FIRE` and `FLAMMABLE` in `Config`; `DayNight` (the clock, the darkness ramp, the four multipliers four callers had been reading against a stub since Phase 2, the 24h HUD string) and `Fire` (burning enemies and scenery, spread, the 140 ceiling, the wildfire warning, and no path to `sim.structs`); `LightView` — a `CanvasModulate` for the dark and pooled `PointLight2D`s for the torch, the flashlight's puddle and cone, floodlights, muzzle flashes and every fire; render interpolation via `prev_pos` and `Util.render_pos`, with a snap threshold so a respawn does not smear; the HUD gains a day, a clock, a phase and a light hint; `SaveGame` v3 carries the clock; 23 new tests (219 fast, 242 with `--all`); smoke reaches dusk, night, a lit torch and a burning treeline. Fire skips its enemy scan when nothing is alight — without it the suite went over ten seconds on the cost of discovering nothing was on fire |
| 2026-09-08 | Phase 4a: `ATTRS`, `PERKS`, `STAT_BASE` and the XP curve in `Config`; `Perks` (the pure base → attributes → perks → gear rebuild, and the two `{ok, reason}` gate checks) and `Progression` (one `add_xp` for all nine award sites, `raise_attribute`, `buy_perk`); every derived stat on `PlayerSim` now comes from the recompute instead of a literal; a CHAR tab on the pack screen and a level/XP bar on the HUD; build cost, structure health, turret power, trap damage, ammunition yield, loot rarity, double drops, Adrenaline and Second Wind wired to their consumers; base-wide numbers read `sim.host()`; salvage refunds a share of what you paid so Engineer is not a wood mine; `SaveGame` v2 stores the build and no derived stat; 32 new tests (197 fast, 207 with `--all`); smoke opens the sheet and spends a point. Fixed in passing: the smoke's REPAIR step aimed once and waited a fixed six frames instead of settling the cursor, which made it fail the moment the player stood a few pixels elsewhere |
| 2026-09-08 | Phase 3c: `RECIPES` in `Config`; `Crafting` (bench tier from the workbench beside you, the Stone Hammer lift, tool gates, room checked against the container the craft will use, overflow to stash then ground); the pack screen grows a CRAFT tab and a STORE mode with DEPOSIT ALL and TAKE SUPPLIES; `SaveGame` v1 — containers by tile, chopped props by tile, structures, stores, worn gear and magazines, behind a world fingerprint taken at generation; `F5` / `F9`; 22 new tests (159 fast, 167 with `--all`); smoke crafts a hatchet, fills a chest, saves and reloads |
| 2026-09-08 | Phase 3b review pass (PR #4): the shared stash is cleared with its last door; salvaging a workbench recomputes the bench tier; REPAIR sweeps while held |
| 2026-09-08 | Phase 3b: `STRUCTURES`, `BUILD_ORDER` and `ARMAMENTS` in `Config`; `Structures` — the destructible tile map, placement, damage, repair, `plan_repair_all`, demolition, power, generators, turrets, traps, gates, the bench upgrade and storage; collision, sight and the flow field take it as a parameter; enemies punch what blocks them and raiders walk at the nearest piece; `StructureView` and `BuildBar` with the ghost, the range ring and the repair and salvage tools; building goes through `Intent`; 27 new tests plus the compound raid harness in a slow tier; smoke builds a wall, walks into it, repairs it and takes it down. Fixed in passing: a Phase 2 bug where holding the trigger on an empty shotgun cancelled its reload for ever |
| 2026-09-08 | Phase 3a review pass (PR #3): raid payouts through the capped path; weight is the cap for guns and gear too; a duplicate gun's spare ammo spills rather than vanishing, and a pickup refuses an overflow that is not its own; non-stacking rolls are never aggregated; magazines clear on death; light charge is per light id; `drop_stack` empties the slot that was clicked; 8 new tests, 113 total |
| 2026-09-08 | Phase 3a: `GEAR`, the 30 `LOOT` tables and the real starting kit in `Config`; `Items` and `Slots`; the pack, hotbar and body slots on `PlayerSim` with weight capacity; `Loot` (rolls, the entry grammar, ground pickups, the death backpack, body drops), `Interact` (the E target and the search channel), `Equipment` (wearing things, moves, drops, the light, and `recompute_stats`); `PickupView` and `InventoryScreen`; the HUD's real hotbar, weight bar and interact prompt; 30 new headless tests, 105 total; smoke searches a container, opens the pack, drops a stack and picks it back up |
| 2026-09-08 | Phase 2 review pass (PR #2): melee needs terrain line of sight; raid XP paid on the killed share and the raid kill bonus limited to raiders; the no-base raid centre follows the player and the anti-stall gate moved into `Config.RAID.stall_radius`; `bleed` removed from three weapon rows; 3 new tests, 75 total |
| 2026-09-08 | Phase 2: the spec's enemy, weapon, resource, spawn, noise, quiet, threat and raid tables in `Config`; `EnemySim`, `Enemies` (spawner + AI), `SpatialHash`, `NavField` (the flow field), `Sound`, `QuietField`, `Combat`, `Damage`, `Threat`, `Raid`; player combat, the Phase 2 kit, sim events; enemy, effects and player views, the HUD's hotbar, threat meter, raid banner and notices; 53 new headless tests including a raid harness; smoke run shoots a walker and forces a raid |
| 2026-09-08 | Phase 1: `Config`, `Rng`, `World` (the generator, bit-identical to the prototype), `PlayerSim`, `GameSim`, `Intent`; terrain atlas + TileMapLayers, prop renderer, player view, HUD; bindings autoload and `LocalInput`; 19 headless tests; smoke run walks, sprints and photographs seven districts |
| 2026-09-08 | Phase 0: project created on Godot 4.7.2; headless test runner and `TestCase`; smoke autoload with screenshot + state checkpoints; placeholder scene; this document; `tasks/port-inventory.md` as the spec |
