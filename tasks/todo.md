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
- [ ] Verify the Godot MCP (`run_project`, `get_debug_output`) works after the desktop app restart
- [x] Seed `PROJECT.md` (§1 vision, §2 pillars, §5 architecture, §6 decision log, §8 lessons
      carried from the prototype, plus new §0 "porting from")
- [x] First commit and push to `dunnston/zombie-game-godot`

## Phase 1 — a place to stand

- [ ] `config.gd` with world, player and camera tunables ported from `config.js`
- [ ] World generation: districts, tiles, the single collision bitmap invariant, danger field
- [ ] TileMapLayer rendering with code-generated tile textures (no art yet)
- [ ] Player: movement, stamina, camera follow, the `Intent` struct (sim never reads input)
- [ ] Headless tests: world gen determinism, every container reachable, collision
- [ ] **Playtest gate:** owner walks the map

## Phase 2 — something to fear

- [ ] Enemies: types, spawn, chase, the quiet field (pressure), noise
- [ ] Combat: melee, bow, guns, bullets vs terrain only (pillar 3), damage routing
- [ ] Navigation: NavigationServer2D or a flow field — the prototype's #1 wanted upgrade
- [ ] Raid harness reproducing the prototype's reference figures
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
