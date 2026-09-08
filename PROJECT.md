# DEADLINE on Godot — Project Document

**This is the living map of the project.** Read it at the start of a session,
update it at the end of one. It says what we are building, where we are, why
past decisions were made, what is next, and what we have learned. If the code
contradicts it, the code is right — fix this file and say so.

- **Last updated:** 2026-09-08, Phase 2: enemies, combat, noise, quiet, navigation, raids — fightable
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

**Status: Phase 2 built, awaiting the owner's fight.** On top of Phase 1's
map: walkers, runners, brutes and behemoths from the spec's table, spawned
off screen around the player and culled far away; they see, hear, hunt,
investigate and give up; they find doors with a flow field the prototype
never had. The player holds a six-slot Phase 2 kit (pipe, hatchet, bow,
pistol, shotgun, rifle), swings, chops trees, shoots, reloads and bandages;
bullets stop on walls and fly over water and fences. Gunfire raises Threat;
at 100 a raid comes for you in waves. Nothing to pick up or build yet, and
no structures for a raid to break on: that is Phase 3.

| | |
| --- | --- |
| Phase | 2 of 5 — something to fear (PR open, playtest gate pending; Phase 1's PR is also still open) |
| Playable | Fightable. Open the project in Godot and press Play. Keys 1–6 pick a weapon, R reloads, Q bandages. |
| Unit tests | 72 tests, 365 assertions, ~5.5s (`tools\test.cmd`, ~8s with the import pass) |
| Smoke | 14 checkpoints: walk, sprint, seven districts, a walker shot, a raid wave, a raid over (`tools\smoke.cmd`, ~10s) |
| World build | ~320ms generation, ~80ms terrain, at boot; a flow field ~1.6ms |
| Save format | none yet |

### Port status by system

Status legend: **—** not started · **wip** in progress · **ported** behaves
like the prototype · **verified** the owner has played it and it feels right.
The spec for each row is in `tasks/port-inventory.md`.

| System | Phase | Status | Notes |
| --- | --- | --- | --- |
| World generation, districts, danger field | 1 | ported | Bit-identical to the prototype: same RNG, same order |
| Tile collision (one bitmap) | 1 | ported | `World.blocked`; structures map comes in Phase 3 |
| Player movement, stamina, camera | 1 | ported | Winded latch present; sprint alone never trips it (as in the prototype) |
| Intent (input → sim boundary) | 1 | ported | `LocalInput.gather` is the only reader of `Input` for the sim |
| Enemies, spawning, chase | 2 | ported | Count radius widened past the spawn ring (§6); stuck test is relative to pace (§6) |
| Noise | 2 | ported | One `Sound.make_noise`; alert + destination, never aggro |
| Quiet field / pressure | 2 | ported | Structures' standing quiet arrives with structures (Phase 3) |
| Combat: melee, bow, guns, bullets | 2 | ported | Fixed six-slot kit stands in for the hotbar until Phase 3 |
| Damage routing | 2 | ported | Solo death only; downed-not-dead is co-op (Phase 5) |
| Navigation | 2 | **new** | Flow field per living player; enemies chasing you follow it |
| Raids and threat | 2 | ported | Raiders come for you; targeting the nearest structure needs Phase 3 |
| Items registry | 3 | — | |
| Inventory, equipment, hotbar | 3 | — | |
| Loot and containers | 3 | — | |
| Crafting | 3 | — | Inside the inventory screen this time |
| Building, structures, towers, turrets | 3 | — | |
| Storage tiers | 3 | — | |
| Save / load | 3 | — | Stable container IDs this time |
| Progression, SPECIAL, perks | 4 | — | |
| Day/night and light | 4 | — | Real 2D lights this time |
| Survivors, jobs, bunks | 4 | — | |
| Vehicles | 4 | — | |
| Fire | 4 | — | |
| Title screen, save slots, keybinds | 4 | — | |
| Audio | 4 | — | |
| Online co-op | 5 | — | Last |

---

## 4. What is built

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
  scenery), harvest stamina and the winded latch, tool gates and hints,
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
  Optional substring filter: `tools\test.cmd world`.
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

0. **The owner walks and fights** (the Phase 1 and 2 gates, together).
   Walking: is 176px/s the right pace at this zoom; does the camera lead
   feel like aiming or like drift; should sprinting to empty wind you; is
   the world readable at a glance; is the zoom right. Fighting: does a
   walker read as a walker and a brute as a brute in a crowd; is the pistol
   too easy and the bow too weak; does the wind-up telegraph a bite in
   time; do enemies coming round a building feel like hunting or like
   cheating; does the tier-1 crowd (four around you, 1400px) feel thin or
   dead; does a raid with nothing to defend feel like anything.
1. **Phase 3.** Items, the inventory and hotbar (replacing the kit), loot
   and containers, the destructible structure map, building, storage,
   crafting in the inventory screen, saves with tile-derived container
   identity; then raiders target the nearest structure, enemies punch what
   blocks them, the quiet field counts structures, and the raid harness is
   run against the compound to reproduce §9's reference figures.
2. **Render interpolation.** The sim runs at 60Hz and the view at the
   monitor's rate; on a 144Hz screen movement judders until positions are
   interpolated between physics frames. Every entity now needs a previous
   position captured at the top of its tick.

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

---

## 9. How to verify

| When | What to run |
| --- | --- |
| While working | `tools\test.cmd` (optionally with a filter), plus a targeted smoke checkpoint of the one thing you changed |
| Before you commit | `tools\test.cmd` |
| Before you push for review | `tools\smoke.cmd` once, and read the PNGs |

Both must report **zero failures**. Current expected output:

```
tests: 72  asserts: 365  failures: 0
SMOKE done checkpoints=14 failures=0 exit=0
```

The tests also print measurements worth reading when a number moves:

```
spawner: 4 within 1400 px, 4 alive after 20s in tier 1
nav: 83x83 field built in 1.6 ms
nav: with the field the walker closed from 128 to 47 px in 10.7s; straight steering got to 128 px
noise: closed 105 px toward the bang in 4s; control drifted 43
raid harness [0 SCATTERED HORDE]: 18s, 19 kills, repelled=true, scrap +30
raid harness [2 HEAVY HORDE]: 93s, 52 kills, repelled=false
```

The raid harness (`tests/raid_test.gd`) plays a god-mode rifle defender in
the open against raid index 0 and 2. The prototype's reference figures were
measured against a walled compound with turrets; those are reproduced in
Phase 3 once there is a compound to build. What matters now is that no raid
reaches the 300s backstop: index 2 breaks off at ~93s with 52 of 57 killed
because the last stragglers wedge and the 25s no-progress rule fires.

The smoke PNGs in `.smoke/` are the proof for anything visual: read them.
`00_spawn` and `01_walked_east` should show the survivor on the highway
west of the camp; `03`–`09` are the suburbs, Market Row, downtown, the
farms, the lake lodge, the forest and the junkyard; `10`–`13` are a walker
approaching with its arms out, its corpse after three pistol rounds, the
raid banner with a raider on the ring, and the salvage notice.

`tools\smoke.cmd` opens a window for a few seconds; that is expected. The
Godot MCP's `run_project` / `get_debug_output` are the alternative when a
window is not wanted, once the desktop app has restarted with the 4.7.2 path.

---

## 10. Session protocol

1. Read this file, then `tasks/todo.md`.
2. Branch. Work. `tools\test.cmd` before every commit.
3. Before finishing: update §3 (status table and numbers), §7, §11; add a §6
   row for any choice a future session might reverse without knowing why;
   add lessons to §8 and `tasks/lessons.md`.
4. PR, review, merge.

---

## 11. Changelog

| Date | What |
| --- | --- |
| 2026-09-08 | Phase 2: the spec's enemy, weapon, resource, spawn, noise, quiet, threat and raid tables in `Config`; `EnemySim`, `Enemies` (spawner + AI), `SpatialHash`, `NavField` (the flow field), `Sound`, `QuietField`, `Combat`, `Damage`, `Threat`, `Raid`; player combat, the Phase 2 kit, sim events; enemy, effects and player views, the HUD's hotbar, threat meter, raid banner and notices; 53 new headless tests including a raid harness; smoke run shoots a walker and forces a raid |
| 2026-09-08 | Phase 1: `Config`, `Rng`, `World` (the generator, bit-identical to the prototype), `PlayerSim`, `GameSim`, `Intent`; terrain atlas + TileMapLayers, prop renderer, player view, HUD; bindings autoload and `LocalInput`; 19 headless tests; smoke run walks, sprints and photographs seven districts |
| 2026-09-08 | Phase 0: project created on Godot 4.7.2; headless test runner and `TestCase`; smoke autoload with screenshot + state checkpoints; placeholder scene; this document; `tasks/port-inventory.md` as the spec |
