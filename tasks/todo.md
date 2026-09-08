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

- [ ] Day cycle at 540s; night scales density, sense, speed and Threat gain
- [ ] Real `CanvasModulate` + `PointLight2D` for the torch, flashlight,
      floodlight and muzzle flashes
- [ ] `Fire` — burning enemies and scenery, spread, the 140 ceiling, never
      player structures
- [ ] Render interpolation: a previous position per entity, lerped in the views

### 4c — survivors and vehicles

- [ ] Roster capped by Charisma and bunks; Guard, Sniper, Scavenger, Builder
- [ ] Rations upkeep from the shared stash, debt and warnings
- [ ] ~30 cars, 62% locked; key, lockpick or Hotwire; arcade handling, fuel,
      roadkill, a 400-unit boot
- [ ] Read the survivor stats 4a already produces

### 4d — the front door

- [ ] Title screen: CONTINUE, NEW GAME, LOAD GAME, CONTROLS
- [ ] Save slots with an index (day, level, kills, play time); autosave
- [ ] Full key rebinding written over `src/core/bindings.gd` from `user://`
- [ ] Pause menu that saves before it quits
- [ ] Minimap — which is what Sixth Sense has been waiting for
- [ ] Synthesised audio, rate-limited per kind

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
