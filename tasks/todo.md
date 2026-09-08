# DEADLINE on Godot — port plan

Reference implementation: `C:\Users\ryans\OneDrive\Desktop\AI Games\zombie-game`
(the browser prototype, read-only from here on). Its `PROJECT.md` is the design
spec; its `config.js` is the balance sheet. **This is a rebuild, not a translation.**

Godot 4.7.2 · GDScript · 2D · headless tests via
`Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/run.gd`

## Ground rules carried over

- Simulation is plain `RefCounted` classes with no node dependencies, so every
  rule runs headless. Nodes are a thin view layer.
- One `config.gd` holds every tunable and every content table.
- Test by running the game. Assert on outcomes, not calls.
- `npm test` equivalent must run in under ten seconds. Full browser-style smoke once per branch.
- Keep `PROJECT.md` alive: status, roadmap, decisions, lessons, changelog.

## Phase 0 — harness (nothing else until this is green)

- [x] `tests/run.gd`: discovers `tests/*_test.gd`, runs them, prints a summary, exits non-zero on failure
- [x] `tests/test_case.gd` (renamed from assert.gd): `eq`, `ok`, `near`, `throws`-style helpers with file:line on failure
- [x] `tools/test.cmd` and `tools/test.sh` wrapping the headless command
- [x] Smoke path: `tools/smoke.cmd` launches the real game with a `--smoke` arg; a `Debug` autoload
      drives scripted input, snapshots game state as JSON to `user://smoke/`, and saves a viewport
      PNG per checkpoint so Claude can read what the player would see
- [x] Verify the Godot MCP (`run_project`, `get_debug_output`) works after the desktop app restart
- [x] Seed `PROJECT.md` (§1 vision, §2 pillars, §5 architecture, §6 decision log, §8 lessons
      carried from the prototype, plus new §0 "porting from")
- [x] First commit and push to `dunnston/zombie-game-godot`

## Phase 1 — a place to stand

- [x] `config.gd` with world, player and camera tunables ported from `config.js`
- [x] World generation: districts, tiles, the single collision bitmap invariant, danger field
- [x] TileMapLayer rendering with code-generated tile textures (no art yet)
- [x] Player: movement, stamina, camera follow, the `Intent` struct (sim never reads input)
- [x] Headless tests: world gen determinism, every container reachable, collision
- [ ] **Playtest gate:** owner walks the map

## Phase 2 — something to fear

Branch `phase-2-combat`, off `phase-1-world` (its PR is still open).

- [x] `config.gd`: ENEMIES, WEAPONS, RES (ammo and consumables), SPAWN, NOISE,
      QUIET, THREAT, RAIDS + `raid_spec()`, NAV, HARVEST — every number from
      the spec
- [x] Sim events: `GameSim.events` is how the sim tells the view what happened
      (shot, hit, kill, notify, shake); the same list co-op will send
- [x] Enemies: `EnemySim`, spatial hash, ambient spawner (density per tier,
      mix, ring, cull, cap), the AI step (sense, sight, aggro expiry, noise
      destination, wander, windup attack, separation, stuck rescue)
- [x] Navigation: a local flow field per living player (`NavField`), BFS
      over the collision bitmap, no corner cutting; enemies chasing a player
      follow it and keep the prototype's probe steering and give-up rules
- [x] Noise: one `make_noise`, alert + destination, never aggro
- [x] Quiet field: 256px cells, bilinear read, kill kernel, decay, suppression
- [x] Combat: melee arc (fight first, then scenery), chop stamina and the
      winded latch, tool gates, bullets with substeps vs terrain only, guns
      with magazines, reloads (shell-at-a-time shotgun), spread, pellets,
      pierce, the bow as a one-round gun
- [x] Damage routing: enemy (knockback, resist, kill → xp/threat/quiet),
      player (invuln, death, respawn on safe tier-1 ground), healing (Q)
- [x] Threat meter and raids: gain, decay, pinned at 100, warning, waves,
      spawn ring, hp scaling, anti-stall, break-off, 300s cap, share payout.
      Raiders target the nearest structure in Phase 3; here they come for you
- [x] Phase 2 loadout: a fixed six-slot kit (pipe, hatchet, bow, pistol,
      shotgun, rifle) with ammo, on keys 1–6, so the gate can fire everything.
      Phase 3's hotbar replaces it
- [x] View: enemies, corpses, bullets, muzzle flash, blood, damage numbers,
      swing arc, screen shake, hurt flash; HUD weapon/ammo/reload, threat
      meter, raid banner, notifications
- [x] Tests: enemies, nav, noise, quiet, combat, damage, threat/raid — every
      one asserting an outcome (`killed > 0`, `raid completes`)
- [x] Raid harness: headless, scripted defender, indexes 0 and 2, logs
      duration and kills; the compound figures wait for Phase 3's walls
- [x] Smoke: fight checkpoint (spawn a walker, kill it), raid checkpoint
- [x] `PROJECT.md` §3, §4, §6, §7, §8, §11
- [ ] **Playtest gate:** owner fights

## Phase 3 — something to keep

- [ ] Items registry, slot inventory, equipment, hotbar, drag/drop
- [ ] Loot: containers, searchable furniture, tiered storage
- [ ] Building: destructible structure map, walls, towers, turrets, repair
- [ ] Threat and raids, break-off logic
- [ ] Crafting inside the inventory screen (the playtest finding)
- [ ] Save/load with stable container IDs (fixes prototype invariant 7)
- [ ] **Playtest gate:** owner builds and holds a base

## Phase 4 — a world that pushes back

- [ ] Progression: XP, SPECIAL, perks, `recompute_stats()` as the only modifier source
- [ ] Day/night with real 2D lights and the torch
- [ ] Survivors, jobs, bunks
- [ ] Vehicles
- [ ] Fire
- [ ] Title screen, save slots, rebindable keys, controller support

## Phase 5 — co-op

- [ ] Godot high-level multiplayer over WebRTC, host-authoritative, up to four
- [ ] Signalling broker (reuse `server/signal.js` from the prototype)
- [ ] Guests: intent up, snapshots down, prediction for own player

## Open decisions (owner)

1. Renderer: project was created with Forward Plus + D3D12. Fine on this PC; **Compatibility**
   would run on more machines for a 2D game. Recommend Forward Plus for now, revisit at export.
2. Pixel size: prototype used 32px tiles at 1x. Keep, or go 16px with integer scaling?
3. Art: still code-generated, or is this the moment to commission a tileset?

## Review

(filled in as phases land)

## Review — Phase 1 (2026-09-08)

- The world generator was translated line-for-line including the RNG, and a
  checksum of every tile and collision byte matches the browser build
  exactly (tiles 33948680, blocked 1860160, 10916 props, 644 containers,
  72 cars, 3267 spawn tiles). That is the whole verification of the map.
- Everything else was rebuilt against the spec: sim classes are RefCounted
  and headless-tested; nodes only draw.
- Found while porting: the prototype's "sprinting winds you" comment was
  never true in code (sprint stops at stamina > 1). Ported as the code
  does it; flagged in PROJECT.md §6 for the owner's walk.
- Three containers sit in corners reachable only diagonally. The player's
  76px interact range covers that, so the test counts eight neighbours.
- Not done: render interpolation between physics frames (judder on
  high-refresh monitors). Listed in §7.

## Review — Phase 2 (2026-09-08)

- Everything under `src/sim/` is `RefCounted` and headless; 53 new tests
  step the real sim and assert outcomes (a walker dies, a tree falls, a
  raid completes). The tests print their measurements.
- Navigation is new: a flow field per living player, 1.6ms to build,
  rebuilt every two tiles of movement. A walker behind the camp shack
  reaches the player in 10.7s; straight steering never does.
- Two prototype numbers moved, both measured and both in PROJECT.md §6:
  the spawner's count radius (26 enemies in 20s against a target of 4) and
  the stuck threshold (a walking brute counted as stuck).
- Starting stats corrected: rank 2 in every attribute is one rank above
  the baseline, so 112 HP, +9% melee, +6% chop, 8% crit. This is what
  makes a tree six hatchet swings, as the spec says.
- Stand-ins, all flagged: the six-weapon kit and `res` map (Phase 3
  inventory), raids targeting the player (Phase 3 structures), day always
  (Phase 4), solo death only (Phase 5 downed). The raid harness runs in the
  open; the compound reference figures are a Phase 3 check.
- Not done: render interpolation, still in §7.
