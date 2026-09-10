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

Three branches off `main`, each its own PR, because one review of this much
is no review at all. 3a is the spine: nothing in 3b or 3c can be built until
an item can be held, carried and dropped.

### 3a — what you carry (`phase-3-inventory`)

- [x] `config.gd`: `GEAR` (15 armour pieces, three tiers across five slots,
      plus the torch and flashlight in the off-hand), `GEAR_SLOTS`,
      `ARMOR_SLOTS`, `MAX_GEAR_DR` 0.72, `lockpick` in `CONSUMABLES`,
      the ~30 `LOOT` tables, search time, pickup range, carry cap 200
- [x] `src/sim/items.gd`: one registry over `RES` + `WEAPONS` + `GEAR` +
      `CONSUMABLES` (`kind` is what the UI switches on), and `Slots` — the
      slot container with add / take / count / weight / move / split /
      entries. The stash and car boots stay plain id→count maps; one
      resource API serves both
- [x] `PlayerSim`: `bag` (30 slots), `hotbar` (6), `equip` (6), weight
      capacity over pack **and** hotbar together. `count_res` / `add_res` /
      `take_res` keep their names and delegate to the bag, so combat,
      reloads and healing are untouched. `weapon()` reads the hotbar
- [x] `src/sim/loot.gd`: the weighted roll, the prefixed entry grammar
      (`weapon:` / `gear:` / `item:` / bare resource) with pickup decode
      beside it so the two cannot drift, ground pickups with the magnet and
      the dropper hold-off, `stash_or_drop`, `spill_store`, the death
      backpack, enemy drops. Nothing that will not fit is ever destroyed
- [x] `src/sim/interact.gd`: what `E` is offering — recover pack, search a
      container (a held channel, aborts on release or drift), gather litter
      by hand. `Intent` gains `interact_held`
- [x] `src/sim/equipment.gd`: equip / unequip / equip-best / move between
      containers / drop, each ending in `recompute_stats()` — which arrives
      now as the one place `armor_dr` is written (invariant 4)
- [x] View: the inventory screen on Tab (pack grid, hotbar, body slots,
      weight bar, drag and drop, ctrl+click to drop), pickups on the
      ground, the hotbar on the HUD, the interact prompt and search ring
- [x] Tests: slot moves and merges, weight cap netting off the hotbar, every
      loot table rolls only known ids, overflow lands on the ground, the
      magnet does not hand back your own drop, the death backpack round
      trips, worn DR sums and caps, searching a container empties it once
- [x] Smoke: search a container, drop and recover something, open the pack

### 3b — what you build (`phase-3-building`)

- [x] `config.gd`: `STRUCTURES` (walls, gate, spike, bench, three stores,
      bedroll, bunk, watchtower, generator, turret, floodlight),
      `BUILD_ORDER`, `ARMAMENTS`, `STASH_SLOTS` 48
- [x] `src/sim/structures.gd`: the destructible structure map — tile keyed,
      separate from the terrain bitmap (invariant 2). Place with the full
      refusal list, damage, destroy, repair, `plan_repair_all` (the label is
      the plan), demolish (spills its store), power, generators, gates
- [x] `World.is_blocked_tile` consults the structure map; `world_version`
      bumps on every change so flow fields rebuild. Bullets stay terrain
      only (invariant 3) — you can shoot over your own barricade
- [x] Enemies: the blocker in front, the adjacent-structure attack,
      `struct_mul` damage, so a horde breaks on the perimeter
- [x] Turrets (powered, stash-fed, sight-checked) and spike traps
- [x] Raids: `base_centre` and `structure_hp_total` become real,
      `raid_target` is the nearest structure, break-off measured against it
- [x] View: structures drawn with damage state, build mode on `B` with the
      wrapping build bar, the ghost, repair and demolish tools
- [x] Tests: placement refusals, a wall makes the flow field go round, a
      brute breaches one, turret kills, trap damage and wear, repair cost
      and plan, demolish spills a full chest, generator fuel and power, a
      raid aims at the base. Raid harness gets its compound figures
- [x] Smoke: build a wall, let something break it, repair it

### 3c — what you make and what you keep (`phase-3-craft-save`)

- [x] `config.gd`: `RECIPES` (bench 0/1/2), `BENCH_UPGRADE_COST`
- [x] `src/sim/crafting.gd`: bench tier from a nearby workbench, the Stone
      Hammer lift (never a gun), tool requirements, room checked against the
      container the craft will actually use, overflow to stash then ground
- [x] Crafting inside the inventory screen — the playtest finding, not a
      separate menu. Storage as the two-panel screen (contents, then pack
      and hotbar) with DEPOSIT ALL and TAKE AMMO
- [x] `src/sim/save_game.gd`: payload v1. **Containers are identified by tile
      position, never ordinal index** (invariant 7) and chopped props by
      tile key, replayed against a world rebuilt from the seed. A world
      fingerprint test fails the build when generation changes without a
      version bump. A save that will not load says which and why
- [x] Save slots under `user://saves/`, autosave once a slot exists
- [x] Tests: every recipe's ids resolve, bench and hammer gates, craft
      overflow, a save round trips (looted containers by tile, felled
      props, structures, stash, worn gear, magazines), a bumped world
      fingerprint refuses to load
- [x] Smoke: craft a hatchet, save, reload, still there

- [ ] **Playtest gate:** owner builds and holds a base

## Phase 4 — a world that pushes back

Four PRs, in dependency order: perks include Hotwire (cars) and Fire Control
(turrets), so 4a is first; a Watchtower's Fire Arrows need fire, so 4b
precedes 4c; a save slot has nothing worth listing until there is a day, a
level and a kill count, so 4d is last. Each bumps `SaveGame.VERSION`.

### 4a — progression

- [x] `ATTRS`, `PERKS`, `STAT_BASE` and the XP curve in `config.gd`
      (invariant 5): six attributes, twenty-eight perks
- [x] `Perks.recompute_stats` — base → attributes → perks → gear, pure, the
      only writer of a modifier (invariant 4). Every literal on `PlayerSim`
      deleted in favour of it
- [x] `Progression` — one `add_xp` for all nine award sites, the level loop,
      `raise_attribute` and `buy_perk`; a ceiling gain is handed over
- [x] `{ok, reason}` on both gate checks, so a locked row says why
- [x] CHAR tab on the pack screen (`K`); level and XP on the HUD
- [x] Wire every perk to a consumer: build cost, structure health, turret
      power, trap damage, ammunition yield, loot rarity, double drops,
      Adrenaline, Second Wind. Base-wide numbers read `sim.host()`
- [x] Salvage refunds a share of what you *paid*, closing the Engineer loop
- [x] `SaveGame` v2: the build, and never a derived stat
- [x] Tests: the curve, multi-level grants, purity, gating, the handover, the
      starting survivor, the exploit, the save round trip — 32 in all
- [x] Smoke: open the sheet, select an attribute, spend a point

### 4b — day, night, light, fire, interpolation

- [x] Day cycle at 540s; night scales density, sense, speed and Threat gain —
      all four already had callers reading a stub that said noon
- [x] Real `CanvasModulate` + `PointLight2D` for the torch, the flashlight's
      puddle and cone, floodlights, muzzle flashes and fires; pooled, not
      created per frame
- [x] `Fire` — burning enemies and scenery, spread, the 140 ceiling, the
      wildfire warning, never player structures
- [x] Render interpolation: `prev_pos` per entity, lerped in the views and
      followed by the camera, with a snap threshold so a teleport is a
      teleport
- [x] HUD: day, 24h clock, phase, a bar of the day, and a hint when it is
      dark and you are carrying nothing lit
- [x] `SaveGame` v3 carries the clock; fires are deliberately not saved
- [x] 23 new tests; the fire spread trials in the slow tier

### 4c — survivors

Split from vehicles: two systems in one PR is one review of neither.

- [x] Roster capped by Charisma **and** bunks, with the refusal naming which
- [x] Guard, Sniper, Scavenger, Builder, each with a give-up timer
- [x] Rations upkeep from the shared stash: clearing debt, a cap, warnings
- [x] Reads the survivor stats 4a already produces, and `refresh_all` pushes
      a newly bought Charisma perk to the people already standing there
- [x] Enemies bite a survivor in the way; a survivor kill pays them and you
- [x] `E` takes somebody in and helps somebody up, ahead of containers
- [x] CREW tab: the roster, both limits, the ration clock, job reassignment
- [x] `SaveGame` v4; a sniper's tower by tile, never by index
- [x] 26 tests, three of them in the slow tier

### 4c-vehicles — cars

- [x] ~30 cars, 62 percent locked; key, lockpick or Hotwire
- [x] Arcade handling, fuel, roadkill, a 400-unit boot
- [x] A parked car blocks its tiles, a driven one does not, and claiming asks
      both collision maps
- [x] A car key is learned rather than carried
- [x] `SaveGame` v5 stores only what a run changed about a car
- [x] The `needs` gate comes off Hotwire; only Sixth Sense is left
- [x] 33 tests; smoke finds a car, drives it and parks it

### 4d — the front door

- [x] Title screen: CONTINUE, NEW GAME, LOAD GAME, CONTROLS, QUIT
- [x] Save slots with an index (day, level, kills, play time); autosave
- [x] Full key rebinding written over `src/core/bindings.gd` from `user://`
- [x] Pause menu that saves before it quits
- [x] Synthesised audio, rate-limited per kind (4d part three)

### 4d part two — the map

- [x] `Config.MAP`: the corner size, the reveal radii, the discovery XP
- [x] `World.discovered` and `GameSim` marking a district on entry, paying XP
- [x] `MapScreen`: one Control, corner and full page off the same overlay code
- [x] The world image, built once per world and cached on the fingerprint
- [x] Sixth Sense loses its `needs` gate and `radar_mul` finally does something
- [x] `SaveGame` v6 carries what you have found
- [x] Tests, and smoke checkpoints for the corner map and the open map

## Phase 5 — co-op (`claude/phase-5-completion-hif1bt`)

- [x] Host-authoritative, up to four, over the engine's `MultiplayerPeer` —
      ENet rather than WebRTC (PROJECT.md §6: WebRTC is an extension plus a
      broker; ENet is in the box and the sessions are transport-blind)
- [x] Guests: intent up every step, snapshots down at 20Hz, prediction for
      their own player only, 48px snap, everything else eased
- [x] A guest joins through the save path; the host's save keeps every
      player by identity (v7) and hands the character back on return
- [x] Commands through one seam (`Actions`), validated on the host with the
      functions solo uses; building, searching, driving and reviving are
      intent edges as before
- [x] World facts as reliable diffs (structures, stores, looted, chopped,
      discovered, rescues, roster); events relayed by interest radius
- [x] Downed-not-dead with a teammate standing; E beside them gets them up
- [x] MULTIPLAYER on the title (host a save, host a new game, join); HOST
      THIS GAME on the pause menu; LEAVE GAME for a guest; typed fields
- [x] Loopback link for tests and smoke; a real UDP handshake in the suite
- [x] UPnP: the host asks its router to open the port and shows the public
      address (the cheap road onto the internet — no server, no extension)
- [x] Room codes over WebRTC: `WebRtcHub`, the broker in `server/`, the
      fetch script, the menu rows, tests with a stand-in connection —
      **switched off** (`Config.NET.broker` empty, no binaries in git)
- [ ] Switch it on if UPnP says no — **`tasks/switch-to-webrtc.md`** is the
      runbook: `tools/fetch-webrtc`, deploy `server/` to a free tier, set
      `Config.NET.broker`, run `tools/test --all` (the slow test then walks
      a guest over real WebRTC on localhost)
- [ ] Owner plays with a friend (the Phase 5 gate)

## Open decisions (owner)

1. Renderer: project was created with Forward Plus + D3D12. Fine on this PC; **Compatibility**
   would run on more machines for a 2D game. Recommend Forward Plus for now, revisit at export.
2. Pixel size: prototype used 32px tiles at 1x. Keep, or go 16px with integer scaling?
3. Art: still code-generated, or is this the moment to commission a tileset?

## Review

(filled in as phases land)

## Review — Phase 5 Codex pass on PR #15 (2026-09-09)

Five findings, all real, all fixed with a test each:

- **P1 — edges lost on the unreliable channel.** Presses now go on the
  reliable channel as `msg_edges`, once, and the state packet carries held
  state only. A single slot press and a single wall placement land exactly
  once at 30% loss and reorder, without the retry loop the old test had.
- **P1 — seats exhausted by parked characters.** `_free_seat` takes the seat
  from an absent character and moves them above the four drawn seats;
  `unpark_player` hands one back. Three friends who came and went no
  longer make a game full for a fourth.
- **P2 — `open_boot` reached everyone near the car.** It names its seat and
  is gated like `open_store`, on the host's screen and in the relay.
- **P2 — an emptied boot never cleared on guests.** One empty record is
  sent after a boot is emptied (`_trunks_sent`).
- **P2 — parked characters earned shared XP.** Automated kills and raid
  payouts pay `present_players()`.

Found while fixing: the test runner treated a file that fails to parse as
zero tests and zero failures. It now fails the run.

## Review — Phase 5, co-op (2026-09-09)

**What landed.** `src/net/` (protocol, link + loopback, ENet hub, host,
guest, actions, prefs); sim seats/identity/away/downed; save v7; the
scene's host and guest loops; the menu pages; two test files.

**What was measured.**
- A guest walking east for two seconds ends within 12px of where the host
  has it, with no loss; within 48px (the snap) at 30% loss and 30% reorder
  on the state channel. Edges (a slot press) get through the same channel.
- A silent guest stops inside a second of sim time; a paused one stops at
  once.
- A snapshot of sixty enemies and twenty piles is under 3000 bytes; the
  first cut, with players as Dictionaries, tripped the engine's 1392-byte
  MTU warning with one player and ten enemies.
- The real UDP handshake on localhost connects on the first poll and a guest
  walks over it.
- A save with a connected guest, reloaded: the guest is parked, level kept;
  rejoining with the same identity gets the same seat.

**What was not.** Nobody has played it. Latency above loopback (the 6/s
lerp and the 48px snap are the prototype's numbers, untried here). A guest
driving. A guest at a raid. Four at once outside the refusal test. Internet
play across two NATs — ENet does not do that alone.

**Known gaps, deliberate.**
- A guest's own gunshots are drawn when the host says so, one round trip
  late; the prototype predicted its own tracers. Melee swings are predicted.
- The spawner uses the host's view radius for every player's ring;
  `Config.NET.guest_view_radius` is set on the mirror and read by nothing.
- The mirror's `sim.time` free-runs between snapshots and snaps at 0.5s of
  drift, so an animation keyed to it can hitch on a bad link.
- The host's pause menu keeps the world running while anyone is connected;
  the host's own body stands still. The guests are not told.
- No broker deployed, so no room codes yet: an address and a port. UPnP
  asks the router to open it; whether the owner's router agrees is the
  first thing to look at on the HOST page. The room-code road is built
  behind `Config.NET.broker`.
- Bytes over a real WebRTC channel are untested until the native extension
  is fetched; the test that walks a guest over it is written and gated on
  `WebRtcHub.available()`.

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

## Review — Phase 2 Codex pass (2026-09-08)

Six P2 items on PR #2, all addressed:

- [x] Melee reached through walls. `melee_targets` checked distance and
      angle only; a pipe's 73px threshold clears a one-tile wall that holds
      two bodies 66px apart. Now needs `has_terrain_line_of_sight` — the
      bullet rule, so water and fences are still swung over.
- [x] Raid kill XP bonus paid on ambient kills. Now gated on `e.raid`, the
      same flag the progress and quiet rules beside it already used.
- [x] An unfinished raid paid `0.5 + share/2` of its XP — half for walking
      away with no kills. Paid on `share`, as the salvage is.
- [x] Anti-stall relocation used a bare `240.0`. Now `Config.RAID.stall_radius`
      at 400: below the 520px spawn ring so a raider wedged where it spawned
      is still rescued, past half a screen so nothing you can see is warped.
      `breakoff_radius` was dead config and is gone; `stall_closing` too.
- [x] The no-base raid centre froze at the warning while the AI chased the
      live player, so pursuit read as a stall. It now follows the player.
- [x] `bleed` on the machete, knife and scythe: dead in the prototype too.
      Dropped rather than invented (owner's call).

Verification: 75 tests, 377 asserts, 0 failures. The four new assertions
were run against the pre-fix `src/` first and all four failed — the ignored
horde was paying 60 XP for zero kills. Raid harness unchanged (raid 1
repelled in 18s for 19 kills; raid 3 scatters at 97s against 93s before).

## Review — Phase 3a (2026-09-08)

- The starting kit is now the real one: a pipe and two bandages. The
  six-weapon kit lives on as `Config.TEST_KIT`, asked for by name by the
  combat tests, the raid harness and the smoke run's fight. Nothing else
  in the game hands it out.
- `count_res` / `add_res` / `take_res` kept their names and now answer for
  the pack, so combat, reloading, chopping and healing needed no changes
  when the inventory landed underneath them. Only healing moved, to
  `count_carried` / `take_carried`, because a bandage on the hotbar is one
  you can see going down.
- 30 new tests. The ones worth keeping honest: every entry in all 30 loot
  tables resolves to a real item and every container archetype has a table
  (1154 assertions total, most of them from that sweep); a full tier-3 set
  is 0.70 DR and 40 damage becomes 28.8 in a plate carrier; a pack full by
  weight takes nothing more; a dropped stack stays on the ground while you
  stand on it and comes back when you walk off and return.
- Three bugs the tests caught before the game did: the weight allowance
  ignored the hotbar (so loot kept fitting after the bar read full), the
  death drop left the off-hand light lit with no light in it, and a
  harvest into a full pack destroyed the wood instead of dropping it.
- Two things only the smoke run could catch: the pack screen had a parse
  error the headless tests never load, and `Input.action_press` does not
  fire `_unhandled_input`, so Tab could not open the panel under script.
  Both are in §8 of `PROJECT.md`.
- Stand-ins, all flagged: `stash_or_drop` has nowhere to put anything until
  3b builds a Supply Stash (it drops), the flashlight and torch keep their
  charge but the world is never dark until Phase 4, and `recompute_stats`
  produces exactly one number until Phase 4 gives it attributes and perks.
- Not done: render interpolation, still in §7.

## Review — Phase 3a Codex pass (2026-09-08)

Seven items on PR #3, all addressed. Each has a test that fails against the
pre-fix `src/` and passes after.

- [x] **P1** A raid payout went in through the uncapped `add_res`, so it
      could push you past the carry cap, or vanish into a full grid while
      the salvage notice reported the whole reward. Paid through
      `give_res_or_drop` now: what does not fit is at your feet.
- [x] Weight is the cap for equipment too. A six-unit rifle fitted into a
      free grid slot at 199.5/200 carried. `_give_item` checks the budget
      and the gun stays on the ground.
- [x] A duplicate gun's spare ammunition was destroyed when the pack could
      not hold it. It spills. Deliberately not returned as `overflow`: the
      pile it came from is a *gun*, and rewriting it into ammunition is the
      exact drift the one-file entry grammar exists to prevent — the
      pickup loop now also refuses an overflow whose entry is not the
      pile's own.
- [x] Two rolls of the same weapon in one container aggregated into
      `{id, n: 2}` and handed over one. `roll_container` never aggregates
      anything whose stack limit is 1.
- [x] The magazine map stayed on the corpse: a replacement gun inherited
      the dead one's rounds, and the pack's saved value could never be
      restored. Cleared for everything that went into the pack.
- [x] A light's charge is now kept per light id. A half-burned torch,
      swapped for a flashlight and back, was full again — free fuel.
- [x] `drop_stack` called `take(id, n)`, which drains matching stacks from
      the start of the grid: ctrl+dropping the second stack of scrap
      emptied the first and left the clicked cell full. It empties the
      slot that was clicked.

## Review — Phase 3b (2026-09-08)

- The structure map is the second collision source and it is passed as a
  parameter, not read from a global: `World.is_blocked_tile(tx, ty, structs)`
  and the movement, sight and flow-field queries above it all take it. The
  world stays a pure generated artefact — which matters because every test
  shares one, and a wall built in one sim must not exist in the next.
- Bullets still ignore it (invariant 3), proved by a test that fires across
  a wall it cannot see through.
- The compound raid harness is here at last, and it caught a **Phase 2
  combat bug on its first run**: holding the trigger on an empty shotgun
  cancelled its shell-at-a-time reload every frame, so it could never
  refill. A god-mode defender with 900 shells killed nothing for two
  minutes and the siege ran to the 300s backstop. The pump-action interrupt
  now only fires when there is a round in the tube. With that fixed the
  siege finishes in 131s and every raider dies.
- Compound figures, against the prototype's reference ranges:

  | Index | Ours | Prototype |
  | --- | --- | --- |
  | 1 RUNNING HORDE | 60s, 0 lost, walls 100% | 70–93s, 0 lost, walls 18–90% |
  | 3 SIEGE | 131s, 16 lost, walls 84% | 72–260s, whole base, walls 0% |

  Index 1 matches on what matters (nothing lost). Index 3 gets inside and
  eats the compound's insides but leaves more of the perimeter than the
  browser build did — our defender never dies, and the prototype's runs
  included two deaths. Neither goes near the 300s backstop.
- `tools/test` grew past ten seconds with the compound harness in it, so
  the harness moved to a `_slow_test.gd` tier: the default run is back to
  8.0s, `tools/test --all` is 12.9s and belongs with the smoke run, once
  per branch. The working agreement is kept rather than quietly broken.
- Found dead on arrival: the prototype's "Container there" placement check
  cannot fire here, because a container blocks its own tile in the terrain
  bitmap. Removed rather than left as a comforting no-op.
- Stand-ins, flagged: a Watchtower can be built and carries its armament
  choice, but posting a survivor on it is Phase 4; the floodlight lights
  nothing until there is a night; `ARMAMENTS` is content without a shooter.

## Review — Phase 3b Codex pass (2026-09-08)

Three items on PR #4, all addressed.

- [x] Losing the last Supply Stash spilled the pile but left `sim.stash`
      pointing at the empty container, so every later raid payout and
      crafting overflow deposited into something nobody could open. The
      shared pile is cleared with its last door.
- [x] Salvaging a workbench did not recompute `bench_tier` — only being
      destroyed by a raider did — so you could demolish your only
      Workbench II and go on building steel walls for ever. Both paths now
      end in `_after_removed`, which also handles the bedroll.
- [x] REPAIR is specified as click *or hold to sweep*, and only the click
      edge was routed. Held fire now sweeps for that tool alone; it stops
      itself, because a piece just repaired is no longer damaged.

The first two have tests that fail against the pre-fix `src/`; the sweep is
in the smoke run, which holds the button across a wall and then checks that
holding it over the repaired wall bills nothing more.

## Review — Phase 3c (2026-09-08)

- Crafting is a tab of the pack, not a screen of its own — the playtest
  finding. `C` opens it there and Tab opens the pack beside it. The recipe
  row prints the bill and either CRAFT or the reason it cannot: needs a
  workbench, needs a Stone Knife, missing materials, no room.
- The Stone Hammer lift is enforced twice: the rule is "a `hammer` recipe
  counts as bench 1 while one is carried", and a test walks every recipe to
  prove no `hammer` recipe sits above bench 1 or produces a gun. The
  prototype relied on the tables being right; here the tables are checked.
- Storage is the two-panel screen the spec asks for, opened by `E` at a
  chest. The sim does not know about screens: `Interact` emits `open_store`
  with a tile and the scene decides what that looks like. The tile is
  re-checked every frame, so walking away closes it.
- **Save format v1.** Containers are keyed by tile and chopped props by
  tile, replayed against a world rebuilt from the seed (invariant 7). The
  world fingerprint is the guard, and getting it right took two goes: taken
  live it included the *current* collision bitmap and prop count, so felling
  one tree made the save refuse itself. It is taken once, when generation
  finishes, and a test fells a tree to prove it does not move.
- Loading rebuilds the sim in place. The views hold the same `sim` and read
  it fresh, so only the three things that cached a player need telling.
- `tools/test` went over ten seconds again — a save round trip regenerates
  a 320-tile world, and there are eight of them. They joined the compound
  harness in the `_slow_test.gd` tier: 9.4s fast, 16.9s with `--all`.
- Not done: autosave and the save-slot UI. Both are the title screen's
  business (Phase 4); the format, the slots on disk and the refusal
  messages are here, and `F5` / `F9` reach slot 0 so it can be played.

## Review — Phase 3c Codex pass (2026-09-08)

Five items on PR #5, all addressed.

- [x] **P1** Loading into a live game left the run's transient state
      standing: a raid that had started went on spawning waves into the
      restored snapshot, and bullets already in the air arrived at the
      restored player. `GameSim.start` — the front half of a load — now
      clears the raid, the horde, the corpses, the bullets, the quiet
      field, Threat, the cached flow fields and the stats.
- [x] Both prop renderers bucket the *world's own dictionaries*, so after a
      load they were drawing the old world's containers. The scene rebuilds
      the terrain and both renderers.
- [x] Loading with build mode open set `open = false` and left the Control
      painted — the same stale-Control bug the bar's own `toggle` fixes. It
      goes through `toggle`.
- [x] Dragging out of a chest ignored carry weight, which was the one move
      that can add weight to a player. It is capped now, and takes a
      partial stack rather than refusing outright when some of it fits.
- [x] A crafted weapon or gear piece checked for a free slot but not for
      weight, so at the cap beside a full stash you could make a rifle you
      could not lift. Both are weighed.

The P1 and both weight holes have tests that fail against the pre-fix
`src/`. The smoke run found the last one for free: its player is carrying
four hundred units of building material by that point and could no longer
craft a hatchet, which is exactly right.

## Review — Phase 2 Codex pass on PR #6 (2026-09-08)

Codex reviewed the Phase-2-onto-`main` PR and found two real bugs in code
that had already been merged once. Both fixed on the tip
(`phase-3-craft-save`) rather than on `phase-1-world`, because that is where
the tests and the current shape of the code live — and because 3b rewrote
the same lines, so a fix on the old branch would collide on merge.

- [x] **P1** The aggro refresh needed sight; the expiry needed only
      distance. A player standing behind a wall inside the sense radius
      therefore kept the chase alive for ever, and the flow field walked the
      enemy to their exact position. Hiding did nothing. Both now ask the
      same question — within range, and either close enough to smell or
      with a line to look along.
- [x] Spawn points checked the tile under the entity's centre, not its
      body. A behemoth is 27 across on a 32px tile, so beside a wall it
      began embedded; an ambient one wedged off screen never freed itself
      (the stuck rescue only runs on something aggro'd or raiding) while
      still counting toward the standing population. Measured before the
      fix: **56 of 400 ambient spawns started inside geometry.**

Both have tests that fail against the pre-fix `src/`. The compound figures
moved a little (the raid picks its body before its spot, so the stream
shifted): index 1 is 57s, index 3 is 126s — both inside the ranges §9 has
always described.

## Review — Phase 4a (2026-09-08)

Progression, and the refactor it was really about.

The interesting part of 4a was not the XP curve; it was that
`recompute_stats` had been sitting in `equipment.gd` since 3a producing
exactly one field while the other thirty were hardcoded literals on
`PlayerSim` with a comment promising Phase 4 would fix it. It does now. The
whole stat block is written from `Config.STAT_BASE` and layered
base -> attributes -> perks -> gear on every call, so a build can never leave
a modifier behind and a save can store the build rather than its consequences.

Four starting stats turned out to be sitting at their *pre-attribute* values,
because nothing had ever applied the attribute pass: carry capacity was 200
rather than 225, pickup range 46 rather than 49, and search and chop were at
1.0 rather than the 0.95 and 1.06 that Perception 2 and Strength 2 are worth.
All four now match the prototype. Nine existing assertions moved with them,
each with a note saying which rank paid for the change.

Two things found on the way in, neither of them the feature:

- **Salvage was going to become a wood mine.** The refund is a share of the
  build price, and Engineer scales what you *pay* — so at rank 3 a wall cost
  0.47 and refunded 0.55, and putting one up and taking it down again turned
  a profit. The refund now scales too. The test builds and salvages the same
  tile twelve times and watches the total; against the unfixed code it turns
  400 wood into 424.
- **The smoke's REPAIR step was timing-fragile.** It aimed once and waited a
  fixed six frames, while the placement step right above it loops until the
  hovered tile has actually settled. It had been passing by luck; moving the
  player a few pixels broke it. Instrumenting showed the repair itself was
  fine — `check.ok` true, the right four-wood bill — so the step now settles
  the cursor the same way placement does.

Honest gaps, both deliberate:

- **Sixth Sense does nothing yet.** It wants a minimap, which is 4d. It has no
  implementation in the prototype either. It is in the tree because the tree
  should match the spec, and it is called out here rather than left to be
  discovered.
- **Five survivor stats are produced and not yet read** (`survivor_cap`,
  `survivor_dmg_mul`, `survivor_hp_mul`, `survivor_xp_mul`, `upkeep_mul`).
  4c reads them. Computing them now is the lesser evil: a perk you can spend
  a point on that quietly does nothing is worse than a field with no reader.

Also noted, and not mine: four methods in `tests/building_test.gd` abort
partway with a runtime script error and still report as passing, so the
suite's assertion count overstates its coverage. Confirmed pre-existing by
running the suite at `origin/main`. Left as a standing task, along with
making `tests/run.gd` fail the run when the engine logs a script error.

Numbers: 197 tests / 2393 assertions / 9.4s fast, 207 / 16.2s with `--all`,
26 smoke checkpoints. The compound harness moved a little because the player
it plays with is a slightly different player now: index 1 is 60s (was 57),
index 3 is 124s (was 126). Both still inside the prototype's ranges.

## Review — Phase 4a Codex pass on PR #8 (2026-09-08)

Four findings. Two were real, two were the port being faithful to a prototype
whose own wording overstates it.

- [x] **The build cards quoted the list price.** Placement and spending went
      through `cost_of()` with the build discount, but `BuildBar._draw()`
      checked affordability against `def.cost` and printed that — so a player
      with Engineer saw a red "WOOD 16" and then put the wall up for eleven.
      Exactly the quote-must-match-charge rule 4a already applied to the
      repair prompt, missed one screen over. The structure health on the card
      was unscaled too, which Codex did not flag and which the prototype does
      scale. Both fixed by pulling the card's numbers out of `_draw()` into
      `card_info()` — one source for what is drawn and what is asserted, the
      same reason `InventoryScreen._cells()` exists. The test fails against
      the old code with "expected 7, got 16".
- [x] **Hotwire could take a point and do nothing.** Fair, and my disclosure
      had missed it — I had listed Sixth Sense and the survivor stats and not
      this. Rather than disclose harder, a perk waiting on a system it does
      not have now carries `needs` in the table, is refused by `perk_status`
      with "Waiting on cars", and stays visible so the tree still matches the
      spec. Sixth Sense carries it too.
- [x] **Fire Control's range.** Codex read the description ("+35% damage and
      range") against the code (range gets half). The code is the prototype's
      — `def.range * (1 + (turretMul - 1) * 0.5)` — and there is a design
      reason for it: a turret that reached across the compound stops the walls
      mattering. Behaviour kept, description corrected.
- [x] **Fortune Favours.** Same shape: "enemies drop twice as much" against a
      35% roll. The prototype rolls 35% too. Description corrected.

The two description fixes are wording-only and deliberate divergences from
`port-inventory.md`'s text, not from its behaviour.

Numbers after the pass, on top of PR #7's merge: 199 tests / 2434 assertions /
9.8s fast, 209 / 17.6s with `--all`, 26 smoke checkpoints, zero failures.

Merging `main` also meant reconciling with #7: it restored four assertions
that had never run, and `test_repair_all_is_the_plan_it_printed` asserted a
four-wood repair bill that 4a's Intelligence-2 discount rounds to three. The
test now derives the unit cost instead of hardcoding it, so the next
build-cost modifier does not break it again.

## Review — Phase 4b (2026-09-08)

The dark, and what happens in it.

Most of the day/night work turned out to be *deleting a stub*. The spawner's
density, the sense radius, walk speed and `Threat.add` have all been calling
`sim.night_factors()` since Phase 2, against a function that returned
`{1.0, 1.0, 1.0, 1.0}` under a comment saying day/night arrives in Phase 4.
Building the clock was the whole change; nothing else had to move. That is
what a seam cut in advance is worth.

Lights were the opposite of a port. The prototype painted a translucent
rectangle over the finished frame and punched holes in it. Godot has real
2D lights, so this is a `CanvasModulate` multiplying the canvas down and
pooled `PointLight2D`s adding light back — which means two torches now
overlap correctly instead of each cutting its own hole. The overlay's
darkening curve is folded into the multiply so the look matches without a
second full-screen draw. The torch and flashlight have had `radius`,
`strength`, `warm` and cone fields sitting in `GEAR` since 3a with nothing
reading them; this is what they were for.

Three things worth recording:

- **Fire cost the whole test budget before it did anything.** `Fire.tick`
  scanned every enemy every tick to find out that nothing was burning, and
  that pass alone pushed `tools\test.cmd` from 9.6s to 10.9s across the
  existing suite. It now skips the scan unless something has been lit. That
  is a real optimisation, not a test trick — it was costing every frame of
  every run, not just the tests.
- **The ten-second budget was already nearly spent.** Measured on `main`
  before any of this: 9.57s. Phase 4b had about 0.4s of headroom to work
  with, which is why the fire spread trials went to the slow tier and the
  enemy scan had to go. Worth a decision before 4c: either something existing
  gets faster, or the fast tier's contract changes.
- **Interpolation needs a snap.** Lerping between the previous and current
  position is right for walking and wrong for a respawn, a load, or an entity
  drawn before its first tick — all of which would slide in from across the
  map or from the origin. Anything further than one step's worth of movement
  is a teleport and is drawn where it is.

The spread test was brittle first time round. It rolled a 16% chance on a
fixed seed, so it did not test "fire spreads", it tested "seed 1 spreads" —
and it flipped to failing the moment the RNG stream shifted under it. It now
runs the same treeline on six streams and asserts on the behaviour, which is
also why it is slow enough to live in the slow tier.

Numbers: 219 tests / 3683 assertions / 9.9s fast, 242 / 18.8s with `--all`,
30 smoke checkpoints, zero failures.

**For the play gate:** night peaks at 0.82 darkness, which is the prototype's
number and is *very* dark on a real monitor — the screenshots are close to
unreadable away from the torch. That is the most likely thing here to need a
feel pass, and it is one number in `Config.DARKNESS_KEYS`.

## Review — Phase 4b Codex pass on PR #9 (2026-09-08)

Four findings. Two P1s that were straightforwardly right, one P2 that was
right and material, and one P2 that was right about the symptom and wrong
about the cure.

- [x] **P1 A burn sprayed blood sixty times a second.** `Damage.damage_enemy`
      emits a `hit`, and the effects view answers each one with seven blood
      particles and a damage number. Fire calls it every frame, so one enemy
      surviving a 6.5s burn left about three thousand particles behind it and
      a burning horde would have dropped the frame rate through the floor.
      `damage_enemy` gained `no_fx` beside the existing `no_alert` — the two
      are separate problems and now have separate switches. A burning enemy
      is drawn from `burn_t` by `EnemyView` instead, which costs nothing.
- [x] **P1 Standing in a fire made you invulnerable.** Fire went through
      `damage_player`, which floors every accepted hit at 1 and grants
      `invuln_after_hit`. So 16 dps became about 3, and — much worse — the
      i-frames that stop a zombie hitting you twice made a bonfire the safest
      place in the game. Fire now goes through `Damage.burn_player`, which
      applies the exact amount, respects armour, and touches neither the
      invulnerability window nor the healing interrupt. Three tests.
- [x] **P2 The night tint was applied wrongly, and that is why night was so
      dark.** An overlay leaves `pixel * (1 - a) + tint * a`; a
      `CanvasModulate` can only multiply, and folding the tint into it gives
      `pixel * ((1 - a) + tint * a)` — a different curve that leaves black
      black and drags every dark colour well below where the overlay put it.
      The multiply is now just the multiply, and the additive term is a
      `DirectionalLight2D`, which in 2D adds a constant across the canvas and
      is exactly the missing `tint * a`. Night is legible now.

      **This corrects what the 4b review said.** It claimed the darkness was
      the prototype's number and probably wanted a feel pass. It was a bug in
      the light maths, not a tuning question.
- [x] **P2 Hay and reeds cannot catch fire — kept, and documented.** The
      observation is correct: both are in `Config.FLAMMABLE`, and the
      generator appends both to `props` without a `prop_grid` entry, so
      `prop_at_tile` can never return them. **The prototype does exactly the
      same** — its `addScenery` does not touch `propGrid` either — so the
      port is faithful and the table is aspirational in both.

      Indexing them was tried and reverted. It works, but it puts
      non-harvestable props in front of the melee chop check (which read
      `prop.harvest` directly and would have crashed on a hay bale) and the
      interact scan, and it moves the simulation enough to break four smoke
      checkpoints. That is a gameplay change wanting its own playtest, not a
      line in a review pass. `Config.FLAMMABLE` now says so, a test asserts
      the gap rather than a capability the game does not have, and the two
      `prop.harvest` reads in `combat.gd` are guarded anyway.

Also worth recording: **the ten-second timing figures in this repo are not
comparable across sittings.** The identical 4b commit measured 9.87s early in
the session and 12.13s an hour later on the same machine. Every conclusion
about the budget has to come from an A/B measured back to back, which is how
the fire enemy-scan regression was found and how these fixes were confirmed
to cost nothing.

Numbers: 219 tests / 3683 assertions fast, 246 / 3788 with `--all`, 30 smoke
checkpoints, zero failures.

## Review — Phase 4c, survivors (2026-09-08)

**Split from vehicles.** The plan had 4c as one PR covering both. Survivors
alone is ~900 lines of prototype behaviour and the last two PRs each came back
with real findings in a smaller diff; two systems in one review is one review
of neither. Vehicles is now its own branch off `main`.

What made this one different from 4a and 4b is how much of it is *refusal*
logic rather than mechanism. A survivor system is mostly a list of reasons you
cannot do the thing:

- You cannot take somebody in without a Bunk **and** the Charisma to lead
  them, and the interesting part is that being told "no room" is useless — so
  `recruit_refusal()` is one function returning the sentence, and the interact
  prompt, the roster header and the notification all print the same one.
- You cannot make a sniper without a free Watchtower, and the roster greys the
  row with the reason rather than after the click.
- You cannot walk to a container behind a locked gate, so every job has a
  give-up timer. This is invariant 6 again, written about enemies, applying
  unchanged to people.
- You cannot feed anyone out of your own pack. That one rule — the stash is
  the pantry and the armoury and the builder's yard — is what makes a Supply
  Stash worth building, and it is the reason a crew standing next to a player
  carrying 200 Rations can still starve.

Three decisions worth recording:

- **Survivor stats are derived, exactly like the player's.** `refresh()`
  rebuilds HP and damage from level and the owner's Charisma perks, so buying
  Inspiring Presence reaches the people already in your base rather than only
  the next hire, and the save stores the level rather than the health. That is
  invariant 4's shape applied to a second kind of body.
- **A sniper's tower is saved by tile, not by index.** Invariant 7 was written
  about containers; a reference into `structs.list` would have rotted the same
  way. A tower that did not come back turns its sniper into a guard rather
  than crashing.
- **Nothing a survivor carries is ever destroyed.** A haul came out of a real
  container, so reassigning mid-run, failing to reach the stash, and dying all
  put it on the ground. There is a test for the reassignment case because it
  is the one that looks like bookkeeping rather than loss.

**On the test budget.** Measured back to back this sitting: `main` at 11.07s,
this branch at 12.8s before I moved anything. Two things there:

1. My first cut spent ten *simulated* seconds per upkeep test just to reach a
   ten-second billing cadence. Driving `tick_upkeep` directly took ~2.5s off.
   The remaining survivor cost is about 1.8s, and three tests that need the
   whole world running went to the slow tier.
2. **The baseline is itself over ten seconds on this machine now.** It read
   9.53s twenty minutes earlier in the same session. This is the third phase
   running where the ten-second agreement could not actually be evaluated, and
   it now wants a decision rather than another round of shaving — see the note
   in PROJECT.md §9. The obvious candidate is `save_test.gd`, the single
   heaviest file.

Numbers: 242 tests / 3794 assertions fast, 272 / 3907 with `--all`, 33 smoke
checkpoints, zero failures.

## Review — Phase 4c Codex pass on PR #10 (2026-09-08)

Four findings, three of them P1, and all four real. Two are worth recording
because of *why the tests missed them*.

- [x] **P1 A survivor's bullet carried no owner.** `Combat.spawn_bullet`'s
      signature is `(..., owner, crit, weapon, color)` and the tag went into
      the `weapon` slot, so every survivor kill arrived at `damage_enemy` with
      a null source. Nobody was ever credited for one.

      The test that was supposed to cover this called `Damage.kill_enemy`
      directly with the tag — it asserted the credit *mechanism* and never
      touched the *wiring*. There are now two tests that go through a real
      bullet, and they fail against the old code.
- [x] **P1 Upkeep charged six Rations a minute instead of one.** One survivor
      owes about a sixth of a Ration per ten-second bill, and `ceili` rounded
      each bill up to a whole one; the following clamp then discarded the
      overpayment. The fraction is carried now and only whole earned Rations
      are taken.

      The epsilon this needs is not cosmetic: six sixths is 0.9999999999 in
      binary, and it has to be *inside* the floor rather than only on the way
      into the branch — the first attempt at the fix guarded the branch and
      still floored to zero, which the test caught.
- [x] **P1 Builders repaired for free out of an empty stash.** Healing ran
      unconditionally and the bill was charged on the way past a 100-point
      threshold, so with nothing in the stash a builder patched walls all raid
      for nothing. Repair is now *bought in blocks and then spent*: no credit,
      no healing, and a warning that says why. It also has its own field —
      sharing `job_t` with the scavenger's search timer was a clock and a
      currency in one variable, which is how a search timer starts paying for
      walls.
- [x] **P2 A sniper had no give-up path.** Every other walk in the file has
      one; the climb to a tower did not, so a Watchtower behind a shut gate
      held somebody against it for the rest of the run. They revert to
      guarding and the tower goes back on the free list.

The three old tests that broke on the upkeep fix were all encoding the buggy
behaviour — a single bill spending a whole Ration, and debt reaching exactly
zero. `debt` is a running fraction now, not a shortage, and the tests say so.

Numbers: 249 tests / 3934 assertions fast, 279 / 4047 with `--all`, 33 smoke
checkpoints, zero failures.

## Review — Phase 4c, vehicles (2026-09-08)

The second half of 4c, on its own branch as planned.

Two bugs found by writing the tests rather than by running the game, both of
the same shape — **a thing that exists in two places and was only asked about
in one**:

- **Claiming a parked tile only asked the terrain bitmap.** A wall lives in
  `Structures`, not in `world.blocked` (invariant 2), so a car could park
  inside your own gate. `is_blocked_tile(..., structs)` asks both.
- **The driver was drawn a frame behind their own car.** Players tick before
  cars, so copying the car's position in the player tick copied last frame's.
  The car sets it at the end of its own tick now: the car owns where its
  driver is.

One decision worth recording. **A car key is learned, not carried** — no
weight, no slot, undroppable, held as a plain id on the player. The
alternative is a resource you could leave in a chest, and the whole reason
keys are planted in the first place is that "whose car is this?" should always
have a findable answer.

And one performance note, because it is the third time this has come up.
`plant_keys` scanned all six hundred containers for each locked car, and it
runs on every `GameSim.start` — which is every test. Five milliseconds each,
about 1.4 seconds across the suite, and `sim.start` went from 0.38ms to
7.33ms. Bucketing the containers on a coarse grid took it to 0.54ms and
`start` back to 1.39ms. Worth remembering that anything hung off `start` is
paid for once per test, not once per run.

Measured back to back: `main` 10.13s, this branch 12.58s. Vehicles cost about
2.45s, of which roughly 1.6s is the test file itself (it needs a world of its
own — driving writes to `world.blocked`, so these tests would otherwise leave
the shared world full of holes for every file after them).

Numbers: 281 tests / 4227 assertions fast, 311 / 4340 with `--all`, 36 smoke
checkpoints, zero failures.

**Phase 4 is now one PR from done.** 4d is the title screen, save slots,
autosave, rebindable keys, the pause menu, the minimap — which is the last
thing Sixth Sense is waiting on — and audio.

## Review — Phase 4c vehicles Codex pass on PR #11 (2026-09-08)

Eight findings, four of them P1, and **all eight real**. The honest summary is
that I built the vehicle system and wired only its front door: the keys could
be planted but not picked up, the boot could be filled but not opened, and the
one thing a car is guaranteed to be parked next to — a person — lost the E key
to it.

- [x] **P1 The key path was entirely dead.** `roll_container` only rolls
      `Config.LOOT[c.table]` and never read `extra`, so every planted key sat
      on a container that could be searched empty. My test asserted the marker
      was *placed*; it never searched the container. That is the same mistake
      as the survivor bullet owner two PRs ago — asserting the setup rather
      than the path. The new test searches the container and unlocks the car.
- [x] **P1 A stripped car came back on load.** `_car_record` omits a salvaged
      car and the loader only overlays records onto a freshly generated fleet,
      so salvage → save → reload was an endless scrap mine. Anything the save
      does not mention is now removed.
- [x] **P1 The boot and refuelling had no caller but a test.** Four hundred
      units of storage and a refuel function that no key reached. Tap E drives,
      **hold E opens the boot** — the same tap/hold split a container uses —
      and the boot became a `Slots` so the existing two-panel store screen
      opens it, with REFUEL as a button on it. One storage UI, not two.
- [x] **P1 A car outranked a dying survivor.** The vehicle check returned
      before the person check, so somebody bleeding out beside a parked car
      could not be helped without walking away from it first. "People come
      before things" is a comment I wrote in the survivors PR and broke in the
      next one; the ordering now matches the comment.
- [x] **P2 Every car was drawn twice**, and driving one left a phantom at its
      spawn point, because `PropRenderer` still bucketed `vehicle_spawns`.
- [x] **P2 A key loot result had no `color`**, which `grant_loot` reads
      unconditionally — harmless while the key path was dead, and a crash the
      moment it was fixed.
- [x] **P2 `pick_time` was a number nothing read.** Picking resolved on the
      interaction frame. It is a held action now, like hotwiring and healing,
      and can be interrupted.
- [x] **P2 An idling engine burned no fuel**, because the burn was gated on
      moving. `burn_per_sec` is explicitly the idle rate.

The pattern across the P1s is worth naming: **four of them are a feature built
and not connected.** The tests all passed because they called the functions
directly. What would have caught them earlier is asking, for each new function,
*which key press reaches this* — and writing that test instead.

Numbers: 288 tests / 4249 assertions fast, 318 / 4362 with `--all`, 36 smoke
checkpoints, zero failures.

## Review — Phase 4d, the front door (2026-09-08)

Split deliberately: this is the shell — title, slots, autosave, pause,
keybinds. The minimap and the audio are the second half of 4d.

**Built.** `src/sim/saves.gd` (the slot index, `list`/`latest`/`first_free`/
`save_to`/`delete`, and the three labels); `src/core/bindings.gd` rewritten as
`class_name KeyBinds` with static state (rebind, conflicts, reset, persistence
to `user://binds.json`); `src/ui/menu_screen.gd` (five pages off one `_rows()`);
the wiring in `scenes/main.gd` — boots to the title unless `Smoke.enabled`,
Escape closes innermost-first then pauses, the world is frozen behind the pause
menu, autosave every 120s for a game that has a slot, SAVE and SAVE AND QUIT TO
TITLE. 19 tests in `tests/saves_slots_test.gd`, 6 new smoke checkpoints.

**Two bugs the smoke caught that the tests could not:**

- [x] **P1 The menu never repainted after a page change.** Clicking CONTROLS
      set `menu.page` and drew nothing new, so the screen still showed the
      pause menu while every assertion passed — they read `menu.page`. Only
      the screenshot shows it. A `_process` that calls `queue_redraw` while
      visible fixed it. This is the same lesson as the 4c P1s wearing a
      different hat: **assert on what the player sees, not on the variable
      that decides it.**
- [x] **P1 BACK scrolled off the bottom of CONTROLS.** The list is longer than
      the panel, so on a short window the only way out of the page was
      Escape — which is also the key you may have just been rebinding.
      RESET TO DEFAULTS and BACK are pinned footer rows now.

**Two things done deliberately, worth writing down:**

- **The test slots are 90/91/92, outside `Saves.MAX_SLOTS`.** `user://` is
  shared with the real game; the first cut used slots 3/4/5 and would have
  overwritten a player's third save on any headless run. Anything above
  `MAX_SLOTS` is unreachable from the menu and `first_free` never hands it out.
- **`KeyBinds` had to become static.** It was an autoload, and an autoload
  does not exist under `godot --headless -s`, so the entire binding system was
  untestable. Static state on a `class_name` is reachable from both.

**Still open: the ten-second test budget.** `main` measured 9.53–11.07s across
sittings before this branch and the fast tier is now 12.8s. The structural fix
is moving `save_test.gd`'s world-regenerating round trips into the slow tier,
which is the same rule Phase 3c wrote down and this file has not applied. This
needs an owner decision because it changes what runs on every commit.

Numbers: 309 tests / 4416 assertions fast, 339 / 4529 with `--all`, 42 smoke
checkpoints, zero failures.

## Review — Phase 4d Codex pass on PR #12 (2026-09-08)

Seven findings, three P1, all real. Three of them are the *same bug I named in
the 4c review one PR ago* — a feature built and not connected, with a test that
calls the function instead of pressing the key. Naming a pattern does not fix
it; the check has to be in the loop.

- [x] **P1 The rebind screen could never capture a key.** `_gui_input` only
      receives key events when the Control has keyboard focus, and `MenuScreen`
      is `FOCUS_NONE` — so clicking a binding row lit it up and then waited for
      ever. The smoke missed it because it called `menu._gui_input(...)`
      directly. Key capture is `_input` now, which does not need focus, and the
      smoke pushes the event through `get_viewport().push_input()` — the real
      delivery path, which is the whole point of a smoke test.
- [x] **P1 F5 and F9 ignored the slot you were playing.** They saved and loaded
      slot 0 unconditionally, so quick-saving in slot 3 overwrote whatever was
      in slot 0, and quick-loading pulled slot 0's world into slot 3's
      autosave. Both go through the active slot now, and F9 with no slot takes
      the same one CONTINUE would — a shortcut past the title screen has to
      agree with the title screen.
- [x] **P1 SAVE AND QUIT TO TITLE quit even when the save failed.** A full disk
      turned it into plain QUIT and CONTINUE then reopened an older payload.
      `_save_current()` returns whether the bytes reached disk and the title is
      only entered on true.
- [x] **P2 Escape did nothing on CONTROLS, LOAD or NEW GAME.** The poll only
      acted when the page was exactly PAUSE, so the documented "closes the
      innermost thing" stopped at the menu's own front door. `MenuScreen.back()`
      owns one step out — rebind, then subpage, then the pause menu — and
      Escape has exactly one owner, which is why the key branch in `_input`
      deliberately ignores it.
- [x] **P2 A stale index entry occupied a slot for ever.** `list()` hid a slot
      whose payload was deleted from outside, but `first_free` still counted
      it: six stale entries would show nothing to load *and* refuse NEW GAME.
      The file decides now, not the index.
- [x] **P2 Running the tests erased the player's controls.** `reset_all()`
      writes the store on every call and the suite calls it in `after_each`, so
      the first headless run on a machine wiped `user://binds.json`. This is
      the exact hazard the save tests avoid with slots 90–92 and I did not
      carry the reasoning across to the keyboard. `STORE` is a `static var`
      now, redirected for the duration of each case, and a test asserts the
      real file is byte-for-byte untouched.
- [x] **P2 `primary_label` had no callers.** The HUD still said `E`, `Q` and
      `K` in string literals, so rebinding changed what worked without
      changing what the game told you to press. **I claimed the opposite in the
      commit message and in PROJECT.md before it was true.** All three go
      through `KeyBinds` now, and the driving controls moved out of a
      `sim.notify` — the sim has no business naming keys it cannot see
      (invariant 1) — into a HUD hint built from the bindings.

Two things worth keeping from the fixing:

- **`_rows()` returns only what is on screen**, so the smoke's row-clicker now
  scrolls to find its target the way a player does. The map binding is twenty
  rows down; the first version of this step set `menu.rebinding` by hand and
  never touched the list at all.
- **The smoke had been writing to a real save slot.** It quick-saved into slot
  0. `SMOKE_SLOT` is 93, outside `MAX_SLOTS`, for the same reason the tests use
  90–92.

Numbers: 309 tests / 4416 assertions fast, 339 / 4529 with `--all`, 42 smoke
checkpoints, zero failures. The fast tier measured 15.9s this sitting against
12.8s for the same suite earlier — the machine drifts, so the still-open budget
question is about the shape of the suite, not about any one measurement.

## Review — Phase 4d part two, the map (2026-09-08)

**Built.** `Config.MAP`; `src/ui/map_screen.gd` (the corner minimap and the
town map behind `M`, one Control and one `_draw`); district discovery in
`GameSim._discover` paying 25 XP per danger tier; `SaveGame` v6 carrying the
ids of what you have found; Sixth Sense ungated and wired. 10 tests in
`tests/map_test.gd`, 2 new smoke checkpoints.

**The one thing that is not a port.** The prototype drew *every* enemy in the
world on the minimap, and set `radarMul` from Sixth Sense in a line that
nothing ever read — a rank-6 Perception perk that did literally nothing. Two
ways to fix that: delete the perk, or make the map obey it. Making the map
obey it is also better on its own terms, because a minimap that shows the
whole town is a free answer to the question the game is asking. So the reveal
is 380px, 900px for anything that has already noticed you (a horde on its way
is not a secret), ×2.4 with the perk. **This is a balance change and the owner
has not played it** — it is in the decision log and it is a feel question.

- [x] Two existing tests changed, both correct consequences:
      `progression_test` asserted at least one perk still carried a `needs`
      gate, and Sixth Sense was the last one — it now asserts the opposite,
      that none are left, and checks the refusal against a synthetic gate
      instead. `raid_test` read `notify[0]` and the discovery notice can now
      legitimately arrive on the same tick, so it searches for INCOMING.
- [x] The debug readout was in the bottom-right corner the minimap now owns.
      The screenshot is what showed the collision; nothing asserted on it.
      The developer line moved, not the map.
- [x] The ground image is 102,400 pixels of GDScript, measured at 41ms. It is
      built lazily on the first draw and cached against
      `world.gen_fingerprint`, so it lands inside the boot or the load it
      already belongs to and never runs again. A headless test never pays it
      at all, because no test builds a view.

**Still open for the owner**, unchanged: the fast tier is 13.5s against a
ten-second budget, and moving `save_test.gd`'s world-regenerating round trips
to the slow tier is the fix.

Numbers: 319 tests / 4434 assertions fast, 349 / 4547 with `--all`, 44 smoke
checkpoints, zero failures.

## Review — Phase 4d map Codex pass on PR #13 (2026-09-08)

One finding, P2, real.

- [x] **P2 Build mode opened behind the town map.** `B` was gated on
      `not inventory.visible` and nothing else, so with the map up it put the
      ghost and the click handler back on a screen you cannot see the world
      through — place, repair and salvage all reachable blind. The map already
      closed the build bar on the way in; the mirror was missing. Same rule as
      the pack now: an open screen closes build mode and build mode does not
      open behind one.

Checked rather than assumed: the guard was reverted and the smoke re-run, and
it failed eleven checkpoints. The smoke step presses `B` rather than calling
`build_bar.toggle()`, which is the whole reason it catches this.

Numbers: 319 tests / 4434 assertions fast, 44 smoke checkpoints, zero failures.

## Review — Phase 4d part three, audio (2026-09-08)

**Phase 4 is complete.** Everything the prototype had is in Godot.

**Built.** `Config.SFX` (34 cues as recipes, not files), `SFX_THROTTLE` and
the four gain/rate constants; `src/core/sfx.gd` (synthesis, the voice pool,
the rate limit, mute persisted per machine); `src/core/sfx_view.gd` (sim event
→ cue, and distance); a `kind` on the hit event; SOUND on the pause menu and
the title. 15 tests, one smoke checkpoint that plays all 34 cues and checks a
voice actually started.

**The architecture question, and why it went this way.** The prototype built a
WebAudio graph — oscillator, envelope, biquad — on *every single sound*. Godot
has no cheap equivalent. But these cues never change, so the graph does not
need to exist at play time at all: each recipe renders to a PCM buffer once at
boot and playing it is a `play()` on a pooled voice. That also makes the whole
thing testable without a speaker, which is why there are fifteen tests on
something that is fundamentally "does it sound good".

- [x] **205ms at boot, fixed to 91ms.** `exp(-9k)` and `pow(ratio, k)` per
      sample per op is three transcendentals a sample. Stepping the envelope
      and the pitch glide by a constant multiplier gives the *identical* curve
      for one multiply. Measured both ways rather than assumed.
- [x] **The autoload could not be called `Sfx`.** An autoload whose name
      matches a `class_name` shadows the class with its instance, and under
      `-s` there is no autoload, so the name resolves to a bare GDScript and
      every static call fails — 91 failures that read like a broken script.
      `Bindings`/`KeyBinds` had established the working pattern one PR
      earlier and I did not carry it across. It is `Audio` now, and the
      lesson is in `tasks/lessons.md`.
- [x] **`test_every_weapon_has_a_voice` caught a real gap on its first run:**
      the Military Carbine had no cue and would have fired with the pistol's
      bang. That is the kind of thing nothing else would ever have noticed.
- [x] **The gunshot is on the muzzle flash, not the bullet.** A shotgun spawns
      eight pellets and fires once; a cue on `shot` would be eight bangs a
      trigger pull, which is precisely what the rate limit exists to stop and
      would have hidden the mistake instead of fixing it.
- [x] **A/B'd the smoke.** Removing `attach(self)` from the autoload — the one
      line that makes the bank audible rather than merely built — fails three
      smoke checks. The step is real.

**Two deliberate additions the prototype did not have**, both flagged as feel
questions: **distance falloff** (340px full, silent at 1500px — web audio gave
a turret across town the same volume as the gun in your hand), and a **`kind`
on the hit event** so a pipe thumps and a bullet pings. Nothing in the
simulation reads `kind`; it exists for the ears alone.

**Now the owner's turn.** Phase 4 is finished and none of it has been played.
The feel questions are listed in §7 of `PROJECT.md`, and the test budget
decision (the fast tier is 17s against a ten-second rule) is still open.

Numbers: 334 tests / 4789 assertions fast, 364 / 4902 with `--all`, 45 smoke
checkpoints, zero failures.

## Review — Phase 4d audio Codex pass on PR #14 (2026-09-08)

Two findings, both P2, both real, and the first one is the same failure this
file has now named three times.

- [x] **P2 The bow was silent, and I wrote it a cue.** Every gun sound hung on
      the `muzzle` event, and `Combat.fire_gun` deliberately suppresses the
      muzzle flash for a bow — a flash is a light source at night, and a bow
      that lit up the treeline would give away the one thing it is for. So
      `Config.SFX.bow` was written, tested for existence, and never once
      reached in play. The `shot` event was the right home all along: it
      already carries the weapon id **on the first pellet only**, with a
      comment beside it in `combat.gd` reading "one sound per shot, not per
      pellet". The field was asking to be used and I did not read it.
- [x] **P2 The smoke wrote to the player's mute setting.** `set_muted(false)`
      at the end of the step wrote `{"muted": false}` into the real
      `user://audio.json`, and a player who had muted the game would have had
      the smoke both fail spuriously *and* unmute them. Third time for this
      exact hazard — save slots, key binds, now audio. `STORE` is a
      `static var` redirected to `user://audio_smoke.json` when `--smoke` is
      on the command line, checked from the cmdline rather than off the
      `Smoke` autoload because autoloads run in declaration order and `Smoke`
      has not loaded yet. Verified by hand: a real `{"muted":true}` survives a
      full smoke run byte for byte, and the run passes.

**The lesson underneath the first one, made structural.** My bow test asserted
that firing a bow emits a `shot` event — which was true the entire time the
bow was silent. That is the third time a test has checked the thing feeding
the code instead of what the code decided. So `SfxView.on_event` now **returns
the cue it chose**, and every mapping test asserts on that return value.
Reverting the one word `"shot"` back to `"muzzle"` now fails twelve
assertions across four tests; before, it failed none.

Also found while fixing: a survivor's gun had no cue either and would have
fallen back to the pistol — the same gap the carbine test caught, in the same
PR, one dispatch away.

Numbers: 338 tests / 4811 assertions fast, 368 / 4924 with `--all`, 45 smoke
checkpoints, zero failures.

## Bugfix round 1 — the Notion bug queue (branch `bugfix-round-1`)

Pulled from **DEADLINE → Ideas & Roadmap → 🐞 Open bugs**. Each card was
reproduced against the Godot build before any code was touched; two did not
reproduce in the sim and are being chased in the view layer instead.

Owner triage: skip DL-44 (bench split — it is the Notion content work and
belongs in its own PR per `PROJECT.md` §10) and DL-38 (survivor RTS — a system,
not a bug). Dev menu is wanted first because it makes the rest verifiable.

- [ ] **DL-56 — dev menu.** Spawn items and resources, spawn enemies, teleport,
      set time of day, refill stamina/HP. Gated behind a debug flag so it can
      never ship on. Built first: the owner needs it to confirm the rest.
- [ ] **DL-45a — a tap of E on a car opens the boot instead of driving.**
      Confirmed by test: `local_input.gd` sets `interact_held` from
      `is_action_pressed`, which is *already true* on the frame
      `is_action_just_pressed` fires, so `Interact.tick`'s vehicle branch always
      takes the held path. Tap-to-drive has been unreachable since it shipped.
      Fix: the boot is a hold with a threshold, like every other held channel.
- [ ] **DL-45b — containers can be searched through a wall.** Confirmed by test:
      standing 51px away with a solid tile between still offers "Search".
      `Interact.best_target` ranks by distance with no line-of-sight test.
- [ ] **DL-42 — nature litter on roads and indoors.** Confirmed by test: 135
      litter props sit on ROAD/SIDEWALK tiles on the default seed. Two causes —
      the map-wide scatter deliberately seeds roads, and `_plant_litter` has no
      surface policy at all, so the camp starter-cache loop plants on anything
      that is not water or wall, building floors included.
      Fix: one surface table in `config.gd`, enforced inside `_plant_litter`.
- [ ] **DL-43 — zombies spawn inside the player's base.** The ambient ring spawn
      knows nothing about the base. Needs the new "player base" concept:
      owner chose a radius around a base anchor (bedroll, else workbench),
      tunable in `config.gd`. Exclude the radius from ambient spawning.
- [ ] **DL-46 / DL-55 — chopped trees and gathered litter stay on screen, and
      nothing drops.** Does **not** reproduce headless: `remove_prop` clears the
      tile, flags `gone`, unblocks solid tiles, and `PropRenderer` skips `gone`
      every frame. Owner sees otherwise in the running game, so the defect is in
      the view layer or in the interaction never registering. Chase with the
      smoke harness screenshots once the dev menu exists.
      Note: "nothing drops on the ground" is partly by design —
      `Loot.give_res_or_drop` only drops when the pack is full. DL-46 also asks
      for visible drops, which is a separate readability change.

### Review

All five fixable cards are done, and the two that were not bugs are answered.

- [x] **DL-56 — dev menu.** F1, one filterable list: every carryable item off
      `Items.registry()`, every enemy, every district, eight verbs. Debug
      builds and `--dev` only, and deliberately absent from the rebindable
      actions so it cannot appear on the player's controls screen.
- [x] **DL-45a — tap of E drives the car.** `car_hold` channel,
      `Config.PLAYER.boot_hold`. The vehicles test that asserted the old
      behaviour was asserting the bug; it now holds for real.
- [x] **DL-45b — no more looting through walls.** `Interact._in_sight`, using
      `bullet_blocks_px` so a fence stays leanable and a river is not a wall.
      Only tiles strictly between count, and touching tiles are exempt.
      Surveyed across all 644 containers: strands none.
- [x] **DL-42 — litter stays on nature ground.** `Config.LITTER_SURFACES`,
      enforced inside `_plant_litter` so no caller can route around it.
- [x] **DL-43 — nothing ambient spawns in the base.** `Config.BASE.radius` and
      `Structures.in_base()`, anchored on every `protect` piece. Raids are
      untouched: a base is still attacked the way it is meant to be.
- [x] **DL-46 / DL-55 — not reproducible as written; the experience is real.**
      The smoke run now chops and gathers with a photograph either side and
      both props are plainly gone. What reproduces is a silent missed swing
      (the player faces the mouse, and a swing at air says nothing) and E
      going to a car or a shelf instead of the stick at your feet. Written up
      in `PROJECT.md` §8. **Both want a feel change, so they are the owner's
      call rather than something to slip into a bugfix branch.**

Not taken, by the owner's decision: DL-44 (bench split — the Notion content
work, its own PR per §10) and DL-38 (survivor RTS — a system, not a bug).

Fixed in passing, both pre-existing:

- `saves_slots_test` asserted `first_free() > free`, which is false when the
  slot it just filled was the last one. It failed on this machine because the
  owner has five saved games.
- The smoke run's repair step depended on the pack having room for its
  materials top-up, so a run that looted well read as a broken repair sweep.
  It stocks its own bill now.

`tools/test.cmd`: 386 tests, 5137 asserts, 0 failures.
`tools/smoke.cmd`: 52 checkpoints, 0 failures.
## The HOST page shows a public address without UPnP (2026-09-09)

The owner's router has UPnP switched off and will stay that way — there is a
Foundry server on the same network and widening the blast radius for a game
was not worth it. UDP 27333 is forwarded by hand instead. That works, but
`NetDoor` only ever learned the public address from `query_external_address()`
on the UPnP success path, so the HOST page had nothing to copy and the owner
had to go find the address on a website.

- [x] `src/net/stun.gd`: one UDP binding request, XOR-MAPPED-ADDRESS parsed out
- [x] `Config.NET.stun_timeout_ms`, and skip `turn:` entries in `Config.NET.stun`
- [x] `door.gd`: fall back to STUN on the `none`, `refused` and
      opened-but-would-not-say paths; word each line so it does not promise a
      door that is not open
- [x] `tests/stun_test.gd` for the parse, `door_slow_test.gd` for the real one
- [ ] `tools\test.cmd`, then `--all`

### Review

Done. `Stun` sends one binding request and reads XOR-MAPPED-ADDRESS back;
`NetDoor` asks it on all three paths where the router does not name an
address, and `menu_screen.gd` needed no change at all — the INTERNET row was
already a click-to-copy row the moment `net.public` was non-empty. On the
owner's machine the HOST page now reads
`INTERNET: <public>:27333 · works only if you forwarded UDP 27333 — UPnP is
off at your router`, verified against the address found independently from
the network side.

Two things found on the way that were not the job:

- **A pre-existing engine error on any router with UPnP off.** `discover()`
  answers SUCCESS having found nothing, and `get_gateway()` then raises
  rather than returning null. `run.gd`'s ErrorSpy counts an engine error as a
  failure, so `door_slow_test` failed on such a machine and passed only where
  a router answered. Counting devices before asking for the gateway fixes it;
  it is in this branch because the branch could not be tested without it.
- **`saves_slots_test::test_a_stale_index_entry_does_not_occupy_a_slot` fails
  on `origin/main`.** Reproduced on a clean worktree of `main` before
  touching anything. Not this branch's, not fixed here.

Also worth knowing: the smoke is timing-fragile under load. Three runs failed
in three different places (repair, demolish, a save round trip) while a second
Godot instance was importing and running beside it, and passed 3/3 once the
machine was quiet. It cost an hour of bisection that found nothing, because
there was nothing to find. A smoke that fails differently each time under load
is worth hardening or marking.

### Addressing the Codex review on PR #18

Both P2 comments were right and both are fixed.

- **STUN never ran when `Config.NET.upnp` was false.** `_start_hosting` built
  no `NetDoor` at all in that case, so the one configuration a hand-forwarding
  host would actually choose was the one where the address never appeared.
  The door is now built either way and decides for itself: `use_upnp` false
  asks the router nothing and goes straight to STUN, reporting state `off`.
  The flag doubles as the test seam, since a `const` Dictionary cannot be
  written to.
- **A conflicting mapping was being advertised.** `CONFLICT_WITH_OTHER_MAPPING`
  means the external port already belongs to another device on this network,
  so `<public>:27333` reaches them and not this host — a friend dialling it
  lands on somebody else's machine. `may_advertise()` singles that code out;
  every other refusal still shows the hedged address, because the host may
  well have forwarded the port by hand.

`tests/door_test.gd` is new and fast: both decisions are pure functions now,
and both are asserted there rather than only inside a thread that needs a
router. `door_slow_test` covers the `off` path end to end.

---

## Phase 6 — Mutation (the meter that replaces hunger)

**Not started. This is a plan awaiting the owner's sign-off.**

The theme moves. The player was bitten before the game starts and there is no
cure; what there is, is control. Zombie brain matter suppresses the change,
and the one meter you manage is **Mutation**, not food or water. Food and
drink stay in the game as *buffs only* — there is still no hunger bar, which
keeps pillar 1 intact by replacing the chore rather than adding one.

The contradiction is the point: mutation makes you stronger and makes the
world worse at the same time, so letting it climb is sometimes the play.

### The meter

`PlayerSim.mutation`, 0–100, ticking up on its own. One full cycle is about
**2.5 in-game days** (`DAY_LENGTH` is 540s, so ~1350s of play) — slow enough
that brains are a supply line, not a five-minute chore.

What makes it climb faster:

| Source | Effect |
| --- | --- |
| Time | `100 / (2.5 · DAY_LENGTH)` per second, the base |
| Danger tier | ×1.0 / ×1.15 / ×1.35 / ×1.6 by the tier you are standing in |
| Night | ×1.2 at full darkness, scaled by the darkness curve |
| A bite | 14% of any zombie melee hit is a bite: **+12** |
| Heavy damage | a single hit of 25 or more: **+5** |
| Going down | **+10** on top of whatever put you there |

### The three bands

Thresholds in `Config.MUTATION.bands`. A band change is the only thing that
triggers `Equipment.recompute_stats()` — mutation reaches the stats through
the one door, so invariant 4 holds.

- **HUMAN (0–35).** Nothing. You look like a person and read like one.
- **TURNING (35–70).** `melee_mul` +0.20, `speed_mul` +0.06, `max_stam` +15;
  `spread_mul` ×1.25 and `gun_mul` ×0.95 (you shoot worse); zombies sense you
  at ×0.9; the player sprite takes a first tint. Survivors you have already
  recruited stay; new rescues hesitate (a line, not a refusal).
- **FERAL (70–100).** `melee_mul` +0.45, `speed_mul` +0.12, `armor_dr` +0.10
  and stagger/flash cut by half (reduced pain); `spread_mul` ×1.6,
  `gun_mul` ×0.88; zombies sense you at ×0.6; the sprite changes properly;
  the HUD distorts and a low pulse plays; **rescues refuse you outright**;
  and the Lurch: every 60–140s, 1.2–1.8s where the intent is taken off you
  and your legs carry you at the nearest zombie. Host-rolled, mirrored to
  guests.
- **100 — you turn.** Death, the `YOU TURNED` banner rather than `YOU DIED`,
  and you come back at 55 rather than 0. Something more interesting than
  respawn is a later question; the hook is in `Damage.turn_player`.

### Brains, and why zombie types stop being interchangeable

Kills drop brain matter by type, so a Brute is worth walking toward:

| Enemy | Drop | Chance |
| --- | --- | --- |
| Walker | Raw Brain Matter ×1 | 45% |
| Runner | Raw Brain Matter ×1–2 | 55% |
| Brute | Mutated Brain Matter ×1 + Raw ×1–2 | 85% |
| Behemoth | Neural Tissue ×1–2 + Mutated ×2 | always |

### Suppressants — the processing chain

Raw is the field answer and it costs you something; the base turns it into
something clean.

| Item | Mutation | Made at | Side effect |
| --- | --- | --- | --- |
| Raw Brain Matter | −10 | eaten as found | Nausea, 60s |
| Stabilized Neural Serum | −30 | Workbench | none |
| Refined Suppressant | −50 | **Chemistry Station** | none, expensive |
| Experimental Suppressant | −75 | Chemistry Station | Surge (+35% melee, +10% speed, 90s), 25% chance of Fever |

**Chemistry Station** is a new tier-2 structure (`station: "chem"`), and
recipes gain an optional `station` field. `Crafting.bench_tier_at` grows a
sibling, `stations_at`, so the bench ladder is untouched.

### Food and drink — buffs, nothing else

One buff/debuff table (`Config.EFFECTS`) serves food, drink, suppressant side
effects and the Surge. `PlayerSim.effects` is id → seconds left; it is
applied inside `recompute_stats` and nowhere else, ticked in `PlayerSim.tick`,
and expiry triggers one recompute. Starter set: **Fed** (eat Rations: +20%
stamina regen, +10 max stamina, 300s), **Hydrated** (Clean Water, new loot
res: mutation rate ×0.85, 300s), **Nausea**, **Surge**, **Fever**.

### Decisions the owner made before any of this was written

- **Turning at 100** kills you with its own banner and you come back at 55,
  not 0. Letting the bar fill must never be the cheap way to empty it.
- **Food and drink get a full table now**, not a placeholder. Cooked meals,
  tinned goods, drink — every one a buff with a duration, no hunger meter
  underneath. Notion owns what exists and what it costs, so the table is
  designed here and pushed there once the owner says so.
- **Human raiders are in scope**, as their own branch. High Mutation is what
  brings them, which is what makes the meter a two-sided bet rather than a
  chore with a bonus.
- **Two branches**, so the meter can be felt and re-tuned before the deep end
  is built on top of it.

### Branch 1 — `mutation-meter`: the bar, the brains, the first two cures

Playable and reviewable on its own. Nothing here needs a new station, a new
faction or a food table.

- [x] `config.gd`: `MUTATION` (rate, tier and night multipliers, band
      thresholds, band stat tables, turn behaviour), `EFFECTS`, three brain
      resources, Raw Brain Matter and Stabilized Neural Serum, the serum
      recipe, the brain drop table, one SFX recipe
- [x] `PlayerSim`: `mutation`, `mut_band`, `effects`, `sense_mul`; the tick
      that raises it, the band-change recompute, effect expiry
- [x] `Perks.recompute_stats`: `_apply_mutation` and `_apply_effects` at the
      end of the one function that writes stats (invariant 4)
- [x] `Mutation` (new sim class): add/suppress, band lookup, the turn.
      Everything that changes the meter goes through it
- [x] `Damage`: bite roll on enemy melee, heavy-hit bump, down bump,
      `turn_player`, stagger and flash reduction at Feral
- [x] `Enemies.tick_ai`: the sense radius reads `p.sense_mul`
- [x] `Loot._roll_enemy_drop`: the brain table
- [x] Consuming rides the existing `using` channel and `Actions`, so a guest's
      use is a command to the host
- [x] `Hud`: the Mutation bar under HP and stamina, with the band name and
      the effect chips
- [x] `PlayerView`: tint by band
- [x] `SaveGame`: `mut` and `effects`, defaulted so old saves load as HUMAN
- [x] `Protocol`: mutation and effects in the player snapshot
- [x] `tests/mutation_test.gd`: the rate over a day, every accelerator, band
      thresholds moving stats through the recompute, both cures, the turn at
      100, brain drops by type, a save round trip, a guest mirroring the meter
- [x] `PROJECT.md`: §1, pillar 1 rewritten, a new §4 section, §7, §11

### Branch 2 — `mutation-depth`: the chemistry, the loss of control, the people

- [x] **Chemistry Station**: a tier-2 structure with `station: "chem"`;
      recipes gain an optional `station`, and `Crafting.stations_at` sits
      beside `bench_tier_at` so the bench ladder is untouched
- [x] **Refined Suppressant** (−50) and **Experimental Suppressant** (−75,
      Surge, and a Fever roll), both at the station
- [x] **The Lurch**: at FERAL, every 60–140s, 1.2–1.8s where the intent is
      taken off you and your legs carry you at the nearest zombie.
      Host-rolled, mirrored to guests, its own banner and sound
- [x] **Distortion**: the HUD warps and a low pulse plays as the bar fills
- [x] **The food and drink table**: a dozen consumables, every one a buff on
      the shared effects table — meals, tinned goods, drink, stimulants —
      with their loot sources and their recipes. Hydration slows the mutation
      rate; nothing here is ever a requirement
- [x] **Human raiders**: a hostile faction that comes for a base whose owner
      has gone too far. A new AI kind rather than a reskinned walker — they
      use cover, they carry guns, they take your stash rather than eat you.
      A raid table of their own, gated on Mutation; survivors refuse to be
      rescued by someone at FERAL, and hesitate at TURNING
- [x] Notion: the new items, the station and the loot sources go into the
      Items & Crafting tables once the owner says so (an external write)

### Review — Branch 1, 2026-09-09

Built, green, and photographed. `tools\test` is 424 tests / 5365 asserts in
20s; `--all` adds the slow tier with no new failures; the smoke is 56
checkpoints, 0 failures, and three of them are the new ones.

**What the meter turned out to be.** Two rules carry the whole feature, and
both were worth more than the code they cost:

1. Every write goes through `Mutation.add`, which is also the only place that
   derives the band, decides you have turned and emits the notice. There is
   no second path to be wrong on.
2. A band is a table of modifiers, and it reaches the player through
   `recompute_stats` and nothing else. A band *change* is the only thing that
   triggers a recompute, so a meter that moves every frame costs nothing —
   and `test_the_band_survives_a_recompute_from_anywhere_else` pins the bug
   that would otherwise have shipped: equipping a hat quietly handing a Feral
   character a human's stats back.

**Three things the plan did not survive contact with.**

- **`armor_dr` at FERAL was wrong.** It is summed from worn gear and capped
  at 0.72, so a band adding to it after the cap either breaks the cap or is
  silently inert on the exact player most likely to be Feral. Reduced pain is
  `stagger_mul` (the flash, the shove, the shake) plus flat health instead.
- **A recipe cost is not always a resource any more.** The Serum is paid for
  in Raw Brain Matter, a consumable — which `can_afford` and `spend` already
  handled, because both only ever ask a `Slots` for a count. The assertion in
  `crafting_test` that every cost is in `RES` was the only thing that had to
  move, and it moved to "anything that stacks".
- **Consumables needed their own stack and weight.** Brain matter stacks 20
  at 0.4 rather than the global 10 at 0.5; the two constants became the
  default rather than the law.

**Two carried into Branch 2.** Human raiders (the owner asked for them, and
they are a faction rather than a reskin) and the full food and drink table.
`mut_rate_mul` already exists on the player and nothing writes it — that is
where hydration lands.

**Open, and the owner's call.** The bar is the main status but it sits third,
under health and stamina. It may want to be first, or bigger. That is a feel
question and the gate above is where it gets answered.

### Addressing the Codex review on PR #20

One P1, and it was right: **a guest's `G` did nothing.** `NetGuest` sends an
edge on the RELIABLE channel as its own message, and `merge_late_intent`
listed the edges it preserved by hand — so `suppress` was packed, sent, and
dropped on arrival. `merge_intent` had the same hole. Brain matter worked in
solo and was inert in co-op.

The fix is not four more lines. `Intent.EDGES` now names every one-step
boolean edge once, and `clear_edges`, `has_edges` and both merges are driven
from it, so the next edge added to the game cannot be dropped by a function
that forgot to mention it. `pack_intent` still enumerates by hand on purpose —
its bit values are the wire format and must not move with the list order —
and `test_every_edge_survives_packing_and_both_merges` covers that leg too.

The test was checked against the bug before being kept: putting the omission
back into `merge_late_intent` fails it with the message a reader would need.

### Review — Branch 2, 2026-09-09

Built, green, photographed. `tools\test` is 458 tests / 6094 asserts in 22s;
the smoke is 61 checkpoints, 0 failures, five of them new — a meal, the
station, a Lurch, and a Raider still at arm's length after three seconds.

**The Chemistry Station is not a bench tier, and that is the whole design.**
Chemistry is different work, not harder metalwork. `station` is its own gate,
recipe `bench` stays 0 for the two doses that need it, and `Crafting.status`
asks the *world* whether the station is in reach rather than trusting the
number the screen passed — which is what makes it hold for a guest's command.

**Food landed as a table of buffs with no meter under it.** Nine items, six
effects, and a test that asserts no field called `hunger`, `thirst` or
`fatigue` has appeared on the player. Hydration is what finally writes
`mut_rate_mul`, the stat Branch 1 shipped with no writer. The quick key eats
the *commonest* thing that would help — lowest `rank`, never a buff already
running — so a tap of F never spends the Field Ration you were saving.

**The living reuse everything.** Three enemy types with `human: true`, a raid
track of their own, and three genuinely new behaviours: a hostile bullet that
looks for people instead of enemies, a `standoff` a rifleman keeps and a
shotgun closes, and a Looter that empties a store into its pockets and runs
for the map edge. Everything else — nav, spawning, waves, break-off, salvage,
corpses, turrets shooting them — was already there and needed nothing.

**Four things worth writing down.**

- **The first Raider fought like a walker with a rifle.** `_gun_tick` only
  held position on the frame it fired, so between shots the ordinary movement
  code walked it into melee. Holding the range is the behaviour, not the shot.
  `test_a_rifleman_keeps_its_distance` caught it before the smoke did.
- **Zombies do not eat raiders, deliberately.** Nothing in the game has
  enemy-versus-enemy targeting and building it for one faction would be a
  system with one caller. Their gunfire pulling the horde onto the fight is
  the honest half and costs nothing.
- **`Slots` has no `take_at` and no `is_empty`.** The Looter was written
  against an API that did not exist; `used()` and `take(id, n)` are the ones
  that do.
- **The smoke could not afford a Chemistry Station.** Thirty slots are long
  since full by that point in the run and `add` on a full grid quietly
  returns 0, which surfaced as "Not enough materials". The materials go into
  the stash now, which is where a base's materials live anyway.

**Open, and the owner's call.** The odds on a human raid (25% at TURNING, 55%
at FERAL) and the Lurch's one-every-couple-of-minutes are the two numbers
most likely to want moving after a session at the keyboard.

### Addressing the Codex review on PR #21

Three P2s, all three right.

- **A Looter punching you rolled a zombie bite.** The melee landing path is
  shared, and it passed `bite = true` for every enemy — so the living could
  add 12 Mutation and print BITTEN, which is the exact opposite of the line
  the faction rests on. The flag is now `not e.def.get("human", false)`.
- **Their guns were silent.** Every pellet went out with an empty weapon id,
  and `SfxView` reads an empty one as "pellet two through eight" and drops
  it — so raiders shot at you with no sound at all. The id rides the first
  pellet only, exactly as the player's guns do, and each gun names its own
  cue (`sfx`), so a shotgun is one bang rather than five.
- **Human raids were scaled by hordes.** `raid.index` is two things at once —
  which spec to field, and `hp_per_index` at the spawn — and it was read off
  `raids_done` for both. A crew arrived tougher for every horde you had
  beaten and never got tougher for beating *them*. It comes off whichever
  track the raid is on now.

All three have a test, and all three were checked against the bug before
being kept: putting each fault back fails its own test with the message a
reader would need.

### And the thing the review made visible

Chasing whether the branch had broken the smoke, `origin/main` turned out to
fail the same way, in the same legs, two runs in three. **The smoke's
flakiness was never load. It is window focus:** `Input.warp_mouse` does
nothing on an unfocused window, so every mouse-driven leg fails somewhere
downstream and none of the messages mentions the mouse. Two lines in
`Smoke._run` take the focus and fail loudly if it never arrives; the build
ghost's failure now carries the cursor position and the focus flag. Runs
reach all 61 checkpoints where they used to stop at 55, and the residue is
one leg in three runs rather than six. PROJECT.md §8 gains the lesson, which
replaces the one that blamed load.

---

## Weapons wear out (2026-09-09)

The Notion catalogue has had a `Durability` column since the taxonomy pass,
listed in `PROJECT.md` §10 as one of the two ratings with nothing behind it.
This is that card.

- [x] `dur` on all sixteen weapons in `WEAPONS`; a count of *uses*, not a
      pool of hit points. `WEAR` holds the four tunables
- [x] `Wear` (`src/sim/wear.gd`) — `use` as the only writer, the crossing
      warnings, `mend`, and the repair bill and its gate
- [x] **Condition on the slot, not the player** (Codex, PR #22). `Slots`
      stacks carry an optional `w`; it travels through chests, boots, the
      ground, other players' packs, the save and the wire. The first cut kept
      it on `PlayerSim` and a freshly crafted weapon was born broken
- [x] **A broken tool is not a tool** (Codex, PR #22) — no cordage from a
      dead knife, no portable bench from a dead hammer
- [x] Wear spent on a swing that connects and on a shot; a swing at air is
      free; a chop costs `WEAR.chop_mul`
- [x] Broken refuses, keeps its slot, and says so once every three seconds
- [x] `Crafting.bench_reason` split out of `Crafting.status`, so repair asks
      the recipe's own bench rather than carrying a second copy of the gate
- [x] MEND rows above the recipes on the CRAFT tab; condition sliver and
      BROKEN on the hotbar; condition in the pack tooltip
- [x] `Actions.repair_weapon` and its host branch (invariant 8)
- [x] Save v10, the guest's pack diff, and the death-drop backpack
- [x] Two dev verbs so a break can be watched rather than waited for
- [x] `wear_test.gd` (32 tests) and two smoke checkpoints

### Left for the owner

- [ ] **Play it and move the numbers.** Sixteen `dur` values, `chop_mul`,
      `repair_cost_share` and the two warning marks are all first guesses.
      The roadmap card in §7 lists the questions.
- [ ] **Fill in Notion's `Durability` column.** It is blank on every weapon
      that is in the game — the only value in it is the AK-Style Rifle's 5,
      on a Planned row. Notion owns the intent; the code owns the behaviour,
      so the 1-5 ratings want writing down and then mapping onto `dur`.
- [ ] **Decide whether unique weapons are a thing.** The mechanic is ready —
      a weapon with no recipe is mended nowhere, and `dur` is where "lasts
      longer" lives — but nothing uses it, because every weapon in the game
      but Fists is craftable. The Planned list has obvious candidates (the
      Katana is already written up as rare and display-case-only).
- [ ] **Armour and tools?** Only weapons wear today. Gear has no `dur` and
      neither does anything else. Left deliberately: one system, played
      first.

---

## Raised beds (2026-09-10)

The owner asked for a garden: build a bed, drop a seed in, optionally feed
it, keep it watered, harvest something to cook or eat.

**Farming was on §7's "deliberately not building" list.** It comes off it,
because that list is against *chores* and not against growing things — but
only on three rules, and if any of them stops being true the amendment
should be reversed rather than argued with:

1. A dry bed **stalls and never dies**.
2. Nothing is ever required — crops are buffs, and no hunger meter appears.
3. It is delegable — the Farmer job below.

- [x] `Config.FARM`, `CROPS` and `FERTILIZER`; the `raisedBed` structure,
      not solid and deliberately not `protect`
- [x] `src/sim/farming.gd` — the whole mechanic, static, state on the
      structure. **The stage is never stored**: derived from `grow`
- [x] Water is Clean Water from pack then stash — the same bottle that buys
      Hydrated, so drink-it-or-grow-with-it is the decision
- [x] Three crops: potatoes (staple), corn (→ Rations, which is what the
      crew eats), herbs (→ Medical, at a trickle)
- [x] A seed comes back from every harvest; seeds in five loot tables
- [x] Compost by hand (+60% yield) and Mutagen Sludge at the Chemistry
      Station (+150%, 40% faster, paid for in brain matter)
- [x] `E` is contextual: a ripe bed harvests where you stand, anything else
      opens a fifth mode of the pack screen with two typed slots
- [x] Destruction loses the planting; salvage returns it
- [x] Four `Actions` commands, host-side reach re-checked (invariant 8)
- [x] Save v11 and the four fields on the structure diff
- [x] A dev verb, `farming_test.gd` (27 tests), four smoke checkpoints

### Next card — the Farmer

- [ ] A fifth `JOBS` row and `_farmer_step` beside `_scavenger_step`: walk to
      the driest planted bed in the base, water it **out of the shared
      stash**, harvest what is ripe, haul it back, replant from the stash.
      The framework is there; this is a job row and about a hundred lines.
      Rule 3 above is the reason it is not optional in the long run.

### Left for the owner

- [ ] **Play it and move the numbers.** One in-game day for a potato, two
      for corn, a day and a half to dry out, 3-5 and 4-7 and 2-3 per bed —
      all first guesses. The §7 card lists the feel questions; the biggest
      are whether watering reads as a habit or a chore, and whether a dry bed
      *stalling* is obviously better than one dying or just reads as broken.
- [ ] **Herbs → Medical is the balance call most likely to want moving.**
      Two an in-game day against a pharmacy's eight to sixteen in one search.
- [ ] **Is Mutagen Sludge a bet anyone takes?** More food for the brain
      matter that keeps you human is the intended shape; whether the numbers
      make it tempting is a play question.
---
## Stagger, bleed, and a crit that comes off the weapon (2026-09-10)

Two of the three things this card was opened for turned out to be one: the
audit that named durability as missing predated PR #22, which built it. What
was actually left was Stagger (nothing in the game), Bleed (cut on 2026-09-08
for being declared and never read) and a crit that was hard-coded in two
places, and the owner's framing tied them together — *hook the weapons that
have these up to actually use them.*

The content design is one sentence: **blunt things stagger, edged things
bleed, and fists do neither.** No weapon has both, and a test asserts it.

- [x] `stagger` seconds per weapon; `STAGGER` holds the three tunables
- [x] `Damage.stagger_enemy` — one writer. Resisted by `knock_resist` (the
      same number that scales knockback, rather than a second table), floored
      at `STAGGER.min`, and it clears `windup`, `pending_struct`,
      `pending_survivor` and `blocker` without refunding `atk_cd`
- [x] The immunity window (`STAGGER.immune`), which is what stops a fast
      weapon being a lock and what makes eight shotgun pellets one shove
- [x] The staggered branch in `Enemies.tick_ai`, ahead of the human branches
      so a Raider stops shooting and a Looter stops running
- [x] `bleed` dps per weapon on the machete, knife and scythe — the exact
      three it was cut from — with `BLEED.time` on the wound
- [x] `Damage.bleed_enemy` / `tick_bleed`; the deepest cut wins and refreshes,
      `bleed_by` carries the kill, and it ticks inside the loop that was
      already running rather than needing fire's scan
- [x] `Combat.crit_chance` / `crit_mul` as the only answer to either
      question; `crit` and `crit_mul` on every weapon row
- [x] `crit_dmg` as a player stat with two real sources (Luck, Surge); `crit`
      on the three glove rows; crit on four `EFFECTS`; `MAX_CRIT` clamped
      once at the end of the recompute
- [x] `EF_STAGGER` / `EF_BLEED` and protocol 4; the guest mirrors both
      cosmetically the way it already does the burn
- [x] The reeling pose (arms back and down, body lurched — the opposite of
      the wind-up on purpose), blood beading off a bleeding one, the stagger
      ring and a thud cue
- [x] A dev verb, `stagger_test.gd` + `bleed_test.gd` (36 tests), crit
      assertions in `combat_test.gd`, two smoke checkpoints
- [x] Notion's `Crit Chance` and `Stagger` columns filled in from what was
      built, on all seventeen in-game weapons
- [x] **A closed wound leaves nothing behind** (Codex, PR #23). Zeroing the
      clock alone left `bleed_dps` and `bleed_by` standing, so the next cut
      was compared against a wound that had already finished: a knife
      opening something a machete had bled dry bled at the machete's rate
      and paid the machete's owner the kill

### Review

The three fields the owner asked about were in three different states, and
saying so up front was most of the value: durability was **already built**,
and a session that took the audit at its word would have rebuilt a working
system. Notion could not supply the numbers either — `Crit Chance` was blank
on every weapon and `Stagger` was set on two Planned shotguns — so the code
guessed first and the columns were filled in from the guess, which is the
reverse of the usual direction and is written down in §10 as such.

Two things fell out of the code rather than being designed in. A Behemoth is
stagger-immune because 0.95 resistance times a sledgehammer is under the
floor — nothing anywhere names a Behemoth. And a shotgun spread rocks a
walker once because the immunity window was already there for a different
reason.

The one thing worth flagging for the playtest: `STAGGER.immune` at 2.2s is
the number the whole mechanic balances on, and it has never been played.

Codex found the bug the "no stacking" rule hides: **a rule that keeps the
higher of two numbers has to be sure the number it is comparing against is
still live.** The wound's clock was cleared on expiry and its rate and owner
were not, so both outlived it — wrong damage, and in co-op the wrong player
paid. The lesson generalises past bleed: any pair of fields where one is a
clock and the others are only meaningful while it runs should be cleared
together, in the one place the clock runs out. The new test was checked by
reverting the fix and watching it fail first.

### Left for the owner

- [ ] **Play it.** The §7 card lists the questions; the immunity window and
      the floor are the two numbers most likely to want moving.
- [ ] **Bleeding on the player?** Only enemies bleed. A raider's blade
      leaving you bleeding is the obvious other half and was left out
      deliberately: one system, played first.
- [ ] **Stamina Cost and Cleave** are now the only two ratings in §10 whose
      mechanic exists without a per-weapon field.

## Off Notion: Linear for tracking, git for content

Branch `claude/notion-to-linear-git-bb7ffc`, off `main` at 6b1a030. Owner's
brief: Linear first, then a local content editor over the real data, and
Notion retired only after the owner has confirmed both. Docs (CLAUDE.md, §10)
change at the end of each phase, never ahead of what is built.

### Phase 1 — Linear

- [x] Linear reachable: workspace Deadline, team Deadline (`DEA`)
- [x] Labels: a `Type` group (Idea/Bug/Feel/Balance/Polish/Question/Chore,
      exclusive like Notion's select), 14 Area labels (flat, because Area is
      multi-select and Linear groups are single-choice), `playtest`
- [ ] **Owner:** workflow states. The connector cannot create or rename
      them. Rename Backlog→Someday, Todo→Next up, In Progress→In progress,
      In Review→In review, Done→Shipped, Canceled→Dropped; add Backlog-type
      Inbox. Issues were created under the old names and follow the rename
- [x] 50 Ideas & Roadmap rows → DEA-5…DEA-54 (DL-1…37 → DEA-5…41; DL-41,
      42, 43, 45, 46, 48, 50, 55, 56, 58, 59, 61, 63 → DEA-42…54). Body, live
      comment thread (author + date), Type, Area, Priority, prototype PR link,
      and a footer with the DL id and the Notion URL
- [ ] 9 Inbox rows (DL-38, 40, 44, 47, 52, 53, 54, 64, 65) — waiting on the
      Inbox state
- [x] First playtest → DEA-55 (`playtest`), related to DEA-8, 10, 28, 35,
      36. Notion's Findings relation was empty on both sides; the links come
      from the findings table in the page body
- [ ] **Owner:** invite Jim (therealslimjim05@gmail.com) — the connector has
      no invite tool, and it sends mail on your behalf
- [ ] Docs: CLAUDE.md and PROJECT.md point at Linear

### Phase 2a — content out of `config.gd`, one table at a time

- [x] `DataTable`: typed loader (`fields` schema, because Godot parses every
      JSON number as a float), validation (undeclared key, wrong type,
      duplicate id), deterministic `encode`, deep read-only rows
- [x] `tools/migrate_table.gd`: comments to `notes`, canonical write, strict
      parity (keys, values, Variant types, row order) and a word-for-word
      check on every comment
- [x] **WEAPONS** → `data/weapons.json`; `Config.WEAPONS` is a `static var`
      loaded at boot. Independent `var_to_str` snapshot before and after:
      identical, 300 values
- [x] `tests/data_test.gd`: canonical form, one-field edit is a one-line
      diff, types, order, read-only, notes stripped, bad files refused
- [x] Owner go-ahead for the rest ("there is still a lot in the config
      file", round 3)
- [x] RECIPES, STRUCTURES, LOOT, CONTAINERS, RES, CONSUMABLES, GEAR,
      ENEMIES, CROPS — see Stage B below
- [x] Delete `tools/migrate_table.gd` after the last table

### Phase 2b — the editor

- [x] `tools/edit.cmd` / `edit.sh` → `tools/edit_server.gd`, a headless
      Godot HTTP server (no Node, no install: Godot is the one thing both
      collaborators have). Loopback by default, `--lan` opt-in, per-run
      write token in the page, Host allow-list against DNS rebinding
- [x] `EditApi` (tools/editor/edit_api.gd): request handling apart from the
      socket, so `edit_api_test.gd` drives it headless against a copy under
      user://. The file is only ever written by `DataTable.encode` — one
      serializer, so the "JS encoder must match" problem does not exist
- [x] Validation on every save, server-side: decode (types, undeclared
      keys, duplicate ids), the field list is frozen (schema is code), every
      `ref`/`key_ref`, and whole-content integrity — recipe costs are
      payable (RES or CONSUMABLES, the game's real rule, not "RES"), recipe
      outputs and tools exist, loot ids resolve, containers name a loot
      table, AMMO_IDS are resources. Deleting or renaming a weapon a recipe
      makes is refused
- [x] `DataTable`: `map<T>` / `list<T>` types, `ref` / `key_ref`,
      `check_refs`; `weapons.json` `ammo` now declares `ref: AMMO_IDS`
- [x] Page (tools/editor/): every table (unmigrated ones read-only from the
      literal), filter grammar, sortable grid, sparse field editing with
      add/remove, map and list editors, duplicate / move / rename / delete,
      table and row notes, live validation, weapon card (recipe, bench,
      loot share and containers, ammo, durability and full repair cost),
      generic "referenced by"
- [x] Browser-verified end to end against the real server: filter
      (`kind=gun ammo=ammoR` → rifle, carbine; `has:bleed` → 3), a valid
      save writes +1/−1 lines, `abc` in a float and `ammoX` in `ammo` are
      refused with the field named, read-only RES shows its loot sources,
      phone layout stacks. Live socket: 403 without the token, 403 for a
      foreign Host, 404 for a path escape
- [x] Owner-facing views (owner ask, 2026-09-10): Workbenches (by hand,
      Stone Hammer, Workbench, Workbench II, Chemistry Station, then the
      planned Basic / Advanced / Tech / Recycler split), Materials (by
      Raw/Salvage, harvested / found / made / used), Tools (harvest flags
      and what each opens; lights), Ammo (guns, recipes, loot), Catalog
- [x] `data/catalog.json`: one-time import of Notion Items + Workbenches —
      126 items (80 in game, 46 planned), category/subcategory/status,
      planned bench, 1–5 ratings, breaks-down-into, and for planned items
      their proposed recipe. `one_of` on category/status/bench_plan. The
      game never reads it; integrity checks every "in game" row exists.
      16 game items are not in it (brain matter, food, the Chem Station)
- [x] Art seam, future-proofing only: `Items.icon_of` finds
      `art/items/<id>.png` (and optional `<id>_ground.png`); pack, hotbar,
      drag ghost and ground draw it when present and the placeholder
      otherwise. No art ships, so the game draws exactly as before.
      `icons_test.gd`; the editor shows each item's look and the file name
- [x] Stage A (owner ask, round 3): image upload/replace/remove on the Look
      card (server-validated PNG, named after a real or planned item);
      Weapons view by Notion class, melee then ranged, and a `class`
      column on the item tables; containers ⇄ items both ways with chance
      per search (and per kill for bodies, and BRAIN_DROPS); "At a glance"
      (crafted at / found in / used in) on every item. Verified over the
      live socket: upload → identical bytes → listed → delete; bad id 404,
      not a PNG 422, no token 403
- [x] Stage B: the other nine tables migrated. `DataTable` gained row
      shapes (`list` for RECIPES, `by_id_bare` for RES and CONTAINERS,
      `groups` for LOOT) and nested `object` / `list<object>` types with
      path errors (`cabinet.entries[0].w: expected int`). Per table:
      comments to notes, strict parity (keys, values, Variant types,
      order), and an independent var_to_str snapshot of all nine before
      and after — identical. `config.gd` 2,204 → ~1,580 lines
- [x] `STASH_SLOTS` is now read from the stash's own `store` in
      STRUCTURES, not a second 48 beside it; the structures design note
      moved into `structures.json`
- [x] Editor: object and list-of-object editors (a recipe's `give`, a
      loot table's entries as a reorderable grid, a light, a gun); nested
      errors land on their field; grid cells summarise instead of JSON.
      Every table is a data file, so the read-only-literal path is gone
      (tests still use it for tables not copied into their private dir)
- [x] Weapon classes (owner correction, round 3): `data/categories.json`
      holds the 11 categories and the 14 weapon classes, melee and ranged,
      each with the identity from Notion. Catalog `category`/`subcategory`
      are refs into it. The Weapons view groups by class with the
      identity on top; an item's card has category and class pickers
- [x] Browser-verified on a private server: all 14 classes with
      identities; Steel Pipe → Weapons › Improvised with 14 class options;
      a bad loot weight is refused on `entries` and blocks Save; Revert
      clears it. Tests 585/0, `--all` 621 with only the known npm-spawn
      failure (also on main)
- [ ] Finding to report: an ordinary zombie's drop chances are hard-coded
      in `Loot._roll_enemy_drop`, not in a table (invariant 5)
- [x] Docs: invariant 5 (CLAUDE.md and PROJECT.md) says tables are
      `data/*.json` behind `Config`; PROJECT.md §10 gains *Editing content*;
      the Notion sync is marked retiring and diffs against `data/`

### Phase 3 — retire Notion (after the owner confirms 1 and 2)

- [ ] Surface the Workbenches gap (Basic/Advanced/Tech/Recycle vs `bench`
      0/1/2) for the owner to decide
- [ ] Archive the Notion pages; remove the §10 sync procedure
---
## Playtest round 1 — the owner's first session (2026-09-10)

Branch `claude/gameplay-balance-ui-fixes-ca8063`, off `main` at 6b1a030.
Nine notes from the owner's first real play. Each is traced to its code below;
the owner's feel feedback outranks the roadmap.

- [x] **1. Mutation is far too fast.** `MUTATION.days_to_full` 2.5 (≈22 min
      untouched in tier 1, ≈14 in tier 4, ×1.2 at night) plus a bite on one
      zombie hit in seven for +12. Slow the climb and soften the bite — numbers
      are the owner's call (see questions).
- [x] **2. A wall went up on a loose stone, and the stone stayed in it.**
      `Structures.can_place` only asks the collision bitmap, and litter, bushes
      and rocks are not solid — so a wall is allowed on top of them and the
      prop lives on inside it. Fix: refuse with "Pick up the stone first"
      (named from the prop), and have `Structures.make` remove any hand prop
      under a new piece through `World.remove_prop`, so a save made before the
      fix loads clean and the tile is in `chopped` for good. No litter respawn
      system exists — the stone was never removed in the first place.
- [x] **3. Night is still bright.** Peak darkness is 0.82 on `DARKNESS_KEYS`.
      Raise the curve toward near-black, and scale `DARKNESS_FULL` and
      `DARK_ENOUGH` by the same factor so every night multiplier (spawns,
      sense, speed, Threat, Mutation) lands at exactly the time it does today:
      only what you see changes. Photograph before and after.
- [x] **4. The torch gave no light.** The `torch_lit` photograph: it *did*
      light, and was barely visible against a night that still showed the
      whole screen. Same root cause as 3. Torch 200px/0.8 → 300px/1.15, and
      the HUD hint is 12pt, amber, and names the next step.
- [x] **5. E at the workbench spends materials on an upgrade.** Today the key
      calls `upgrade_bench` directly. Fix: E opens the bench menu — the craft
      list at that bench's tier, titled WORKBENCH / WORKBENCH II, with an
      UPGRADE button (cost on it) that goes through a new `Actions.upgrade_bench`
      so a guest's press is a command to the host (invariant 8). The prompt
      reads "Use Workbench". A Chemistry Station answers E the same way, or its
      recipes would become unreachable once C stops showing them (item 8).
- [x] **6. The Hatchet breaks too fast.** Owner chose ~100 trees. A tree is
      *six* chops, not the four I estimated — the test measuring it off the
      swing caught that at 66 trees — so stone tools are 600, `chop_mul` 1.
- [x] **7. Clicking food should offer EAT.** A left click that does not drag
      (press and release on the same cell) on a consumable opens a small menu
      beside the cell: EAT / DRINK / USE by item, and DROP. Right-click already
      uses an item directly and stays; ctrl+click stays drop, which it already
      is — so no second meaning for ctrl.
- [x] **8. C is hand crafting only: Hatchet, Pickaxe, Torch, Bandage, Stone
      Knife, Stone Hammer.** Everything else bench 0 moves to bench 1 (Scythe,
      Cloth, Bow, Arrows, Compost, Work Gloves, Work Trousers). C always shows
      the hand list, even beside a bench; the bench list is item 5's menu.
      The Stone Hammer's "portable bench" privilege goes (see questions).
- [x] Tests for every rule above, asserting on what the code decided
      (`playtest_test.gd`, 11; crafting, wear, farming and survivors updated)
- [x] Smoke: the craft tab asserts six, the bench menu and UPGRADE button
      (two new checkpoints), the chem leg opens its station with E
- [x] `PROJECT.md` §3/§4/§6/§11; Notion *Crafted at* moved to Basic for
      Scythe, Cloth, Hunting Bow, Arrows, Compost, Work Gloves, Work Trousers

### Review

Two of the nine notes were one bug: the torch lit fine and could not be seen,
because night was not dark. The photograph said so in one look, where reading
`LightView` had suggested a rendering fault. Of the rest, the "respawning"
stone was never respawning — nothing removed it, because nothing refused the
wall — and E at the bench was a key that spent money with a prompt that did
not say so.

The change with reach was the litter rule: it met every test that builds on
the shared world, because the generator scatters sticks on the plots those
tests use. Four survivors tests and one building test failed on it, and the
right fix was in the test helper — clear the ground as a player now must —
not in the rule. `TestCase.clear_ground` is that helper, and the slow tier
needed it too: `build_compound` had a wall refused for a stick, and the
horde walked through the gap. Final: 560 fast, 596 with `--all` (the two
failures are the broker leg, which cannot start `npm` in a fresh worktree —
§3 already says so), smoke 71/71. The refusal order also moved: "You are standing there" is
what you meet before "Pick up the sticks first".

My estimate of the Hatchet was wrong by half (four chops a tree; it is six).
The test that measures it off the real swing caught that before it shipped.

### Addressing the Codex review on PR #25

- [x] **Scope a bench screen to the bench that was opened.** BENCH mode took
      its tier and stations from everything in reach, so a Chemistry Station
      beside a workbench listed the workbench's recipes under its own title
      (and the reverse), and two differently upgraded benches side by side
      could change the list without changing the title. `bench()` and
      `recipes()` now read `bench_struct()`: a workbench lists its own tier, a
      station lists only its own work, and mend rows stay off a station.
      `test_a_bench_screen_lists_the_bench_you_opened_and_no_other` puts both
      side by side. 561 fast, smoke 71/71 (one earlier run missed the
      build-mode click as the camera led the cursor — §8's timing flake,
      not this change; the re-run passed).

### Left for the owner

- [ ] **Play it.** Mutation at 67 minutes and the bite halved are both
      first guesses at "not way too fast".
- [ ] **Metal tools now barely outlast stone.** Fire Axe and Steel Pickaxe
      are 420 uses against the stone tools' 600, and the chop cost halved for
      them too. Worth raising if they should feel like an upgrade in wear.
- [ ] **Notion's Player Menu row** still describes the hammer lifting bench
      work, and its *What it is for* lists a bow and arrows. Not edited: the
      go-ahead was for the seven items' *Crafted at*.

## The broker leg starts npm on Windows

- [x] **`webrtc_slow_test` could not launch npm on Windows.** It called
      `OS.execute("npm", …)`, and npm there is `npm.cmd`, a batch file
      CreateProcess will not start by bare name — so every fresh worktree
      failed `--all` with "Could not create child process" before the broker
      ever ran. On Windows it now goes through `cmd.exe /c npm …`; elsewhere
      it is unchanged. Node is a real `node.exe` and stays a direct
      `create_process`, so `OS.kill` still reaches it and not a shell.
- [x] `PROJECT.md` §3 no longer says the test fails until you install by
      hand: it installs itself, and needs the network that once.

Numbers: 561 / 7177 fast, 597 / 7325 with `--all`, zero failures — the
broker leg passed both with a fresh `npm install` and with `node_modules`
already there. Smoke 71/71, but not every time: two runs of four failed
"holding REPAIR left the wall at 136 of 340", on this branch and never on a
clean `main` (one run there). The third run on this branch passed with
nothing changed, and the change touches only a test the game never loads,
so it is the same family of timing flake as the build-mode click above —
recorded, not fixed here.

## The harvest popup reads any item's colour

- [x] **Every smoke run logged a SCRIPT ERROR in `FxView.on_event`.** A
      raised bed emits `harvest` with the crop as `res`, and a crop is a
      consumable; the popup looked its colour up in `Config.RES`, so every
      garden harvest errored and drew no label. It now asks
      `Items.color_of`, which covers every kind of item.
- [x] `farming_test` harvests a real bed, feeds the events to an `FxView`
      and asserts on the popup it drew. Putting the old lookup back fails
      it with the smoke's own error.

Numbers: 562 / 7181 fast, 598 / 7329 with `--all`, zero failures. Smoke
71/71, and no SCRIPT ERROR in its log.
