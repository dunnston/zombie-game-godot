# DEADLINE on Godot — Project Document

**This is the living map of the project.** Read it at the start of a session,
update it at the end of one. It says what we are building, where we are, why
past decisions were made, what is next, and what we have learned. If the code
contradicts it, the code is right — fix this file and say so.

- **Last updated:** 2026-09-08, Phase 0: harness, placeholder scene, this document
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

**Status: Phase 0 complete. No game yet.** The test harness, the smoke path
and this document exist. The main scene is a placeholder checkerboard.

| | |
| --- | --- |
| Phase | 0 of 5 — harness |
| Playable | No |
| Unit tests | 2 tests, 7 assertions (`tools\test.cmd`, ~3s including the import pass) |
| Smoke | 1 checkpoint (`tools\smoke.cmd`, ~5s, windowed) |
| Save format | none yet |

### Port status by system

Status legend: **—** not started · **wip** in progress · **ported** behaves
like the prototype · **verified** the owner has played it and it feels right.
The spec for each row is in `tasks/port-inventory.md`.

| System | Phase | Status | Notes |
| --- | --- | --- | --- |
| World generation, districts, danger field | 1 | — | |
| Tile collision (one bitmap) | 1 | — | |
| Player movement, stamina, camera | 1 | — | |
| Intent (input → sim boundary) | 1 | — | |
| Enemies, spawning, chase | 2 | — | |
| Noise | 2 | — | |
| Quiet field / pressure | 2 | — | |
| Combat: melee, bow, guns, bullets | 2 | — | |
| Damage routing | 2 | — | |
| Navigation | 2 | — | New: prototype had none |
| Raids and threat | 3 | — | |
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

Nothing player-facing. Infrastructure only:

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

---

## 7. Roadmap

Detail and checkboxes are in `tasks/todo.md`. This is the shape.

| Phase | Delivers | Gate |
| --- | --- | --- |
| 0 | Harness, smoke path, this document | ✅ 2026-09-08 |
| 1 | World, tiles, collision, player, camera | Owner walks the map |
| 2 | Enemies, combat, noise, quiet field, navigation | Owner fights |
| 3 | Items, inventory, loot, crafting, building, raids, saves | Owner builds and holds a base |
| 4 | Progression, day/night, survivors, vehicles, fire, menus, audio | Owner plays a full session |
| 5 | Online co-op | Owner plays with a friend |

### Next up

1. **Phase 1.** `config.gd` seeded from the prototype's world/player numbers;
   `sim/world.gd` generating districts into a tile bitmap with a headless
   determinism test; a `TileMapLayer` drawing it; a player that moves and a
   camera that follows; a smoke checkpoint that walks the player and
   photographs three districts.

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

- **The class_name cache is not the file system.** A script added by hand is
  invisible to `--headless` until an import pass runs. (2026-09-08)
- **Rewriting `project.godot` while the editor is open loses.** The editor
  holds settings in memory and writes them back. Close the project first,
  or edit through the editor. (2026-09-08 — the owner hit "no main scene")

---

## 9. How to verify

| When | What to run |
| --- | --- |
| While working | `tools\test.cmd` (optionally with a filter), plus a targeted smoke checkpoint of the one thing you changed |
| Before you commit | `tools\test.cmd` |
| Before you push for review | `tools\smoke.cmd` once, and read the PNGs |

Both must report **zero failures**. Current expected output:

```
tests: 2  asserts: 7  failures: 0
SMOKE done checkpoints=1 exit=0
```

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
| 2026-09-08 | Phase 0: project created on Godot 4.7.2; headless test runner and `TestCase`; smoke autoload with screenshot + state checkpoints; placeholder scene; this document; `tasks/port-inventory.md` as the spec |
