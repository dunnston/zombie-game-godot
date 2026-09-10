# DEADLINE on Godot — Project Document

**This is the living map of the project.** Read it at the start of a session,
update it at the end of one. It says what we are building, where we are, why
past decisions were made, what is next, and what we have learned. If the code
contradicts it, the code is right — fix this file and say so.

- **Last updated:** 2026-09-10, content out of `config.gd` into `data/*.json` with a local editor (`tools\edit`: views by bench and weapon class, item art, loot odds both ways), and the roadmap moved from Notion to Linear. Before that, the owner's first playtest: Mutation three times slower, near-black nights and a torch you can see, E opens a workbench (the upgrade is a button in it), C is the six basics, a Hatchet lasts about a hundred trees, click food to eat, and nothing is built on litter. Before that, on 2026-09-09, the Notion catalogue restructured to eleven categories with a tab each, and weapons split into six melee and eight ranged classes. Before that, bugfix round one: the car key, sight through walls, litter on tarmac, zombies in the base, and a dev menu behind F1. The HOST page also names your public address when UPnP will not
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
| `tasks/switch-to-webrtc.md` | The runbook for turning on room codes over WebRTC. Built, tested, switched off. |
| **Notion → DEADLINE → Items & Crafting** | **The content catalogue.** Every item, recipe, bench and loot source, owner-editable. §10 says how it is synced into `config.gd`. |

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

You are also already infected. The bite happened before the first frame,
there is no cure, and what holds the change back is something in a zombie's
brain — so the one status you manage runs *through* the horde rather than
around it. Further along you hit harder and the dead barely notice you; you
are also worse with a gun and closer to gone.

**The loop:** Explore → Scavenge → Fight → Build → Defend → push somewhere worse.

---

## 2. Design pillars

These settle arguments. When a decision is close, the pillar wins.

1. **Survival without survival-game chores.** No thirst bars, no hunger
   micromanagement, no sleep, no long crafting timers. Upkeep lives at the
   base (survivor Rations), not on a bar above the player. **There is exactly
   one meter you manage, and it is Mutation** — you were bitten before the
   game started, brain matter holds it back, and it is measured in days rather
   than minutes. Food and drink are buffs and nothing else. The pillar is not
   "no meters"; it is "no chores": a meter earns its place by being a decision
   with two good answers, which is why letting Mutation climb is sometimes the
   right play. Hunger has one answer, so hunger stays out.
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

**Status: Phase 5 is built and every phase is now in Godot.** Everything the
browser prototype had, and several things it did not. What is left is the
owner playing it — alone, and then with a friend.

**Other people at the table.** A game can be hosted from the pause menu or
the title screen, and joined from the title with an address, a name and an
optional password. Up to four. The host runs the simulation exactly as solo
does; a guest keeps a mirror of it, built through the same load path a save
uses, sends what it wants every step and predicts only its own footsteps.
Twenty snapshots a second describe everything within 1600px of that guest;
walls, chests, emptied containers, felled trees and the roster travel
reliably as diffs; every command a guest's pack screen makes runs on the host
through the same function solo uses, range check included. The transport is
ENet, which the engine ships with, and no broker to run. When you host, the
game asks your router to open the port itself over UPnP and shows the
address to hand out; a router that says no leaves the LAN address on the
same page. And **downed-not-dead**: with a teammate standing, running
out of health puts you on the ground for thirty seconds rather than in it,
and holding E beside you gets you up. Alone, you die as you always did.

**The ears.** Every sound in the game is synthesised at boot — thirty-five
recipes in `Config`, no audio file anywhere in the project — and rate-limited
per kind, so a shotgun hitting twelve zombies is one impact rather than
twelve. The gunshot rides the muzzle flash, not the bullet. And sounds fade
with distance, which the prototype never did.

**The map.** There is a
minimap in the corner and a town map behind `M`: the ground tinted red by
danger, the districts you have stood in named and the ones you have not marked
`? ? ?`, and enemies revealed within a radius that Sixth Sense doubles — the
prototype drew every enemy in the world and left that perk doing nothing.

**The front door.** The game boots to a title screen
with CONTINUE, NEW GAME, LOAD GAME, CONTROLS and QUIT. Six save slots, each
with a summary — name, day, level, kills, play time, how long ago — read from
a small index rather than by parsing six worlds. A game with a slot autosaves
every two minutes. Escape closes what is open, innermost first, and then opens
a pause menu that freezes the world; SAVE AND QUIT TO TITLE writes the game
down before it leaves. Every key is rebindable, saved per machine rather than
per save, and every on-screen prompt is built from the binding.

**Phase 4c — you have people and you have wheels.** About
thirty cars sit across the town, most locked and most nearly dry. There are
three ways into a locked one: the key hidden in a container near it, a
lockpick that may snap and be heard, or the Hotwire perk — which is no longer
refused for want of the system it names. Driving is arcade and loud: an engine
is heard six hundred pixels away and climbs Threat while it runs, so crossing
town is a decision. A car runs people over, carries four hundred units in the
boot, and can be stripped when it is finished.

**Phase 4c survivors — you are not alone.** Seven people are scattered across
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
of its own: six things by hand, and the rest at the workbench you open with
`E` (the Stone Hammer used to lift simple bench work into the field; since
the first playtest it does not). A chest opens on `E`
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
| Phase | **5 of 5 built.** 4a progression, 4b day and fire, 4c survivors and vehicles, 4d the front door, the map and the audio, 5 co-op. None of it has been played by the owner yet |
| Playable | The whole loop, it levels you, it gets dark, you can hold it with other people, and a friend can join you in it. **E** searches, uses and gets a teammate up, **Tab** the pack, **C** crafting, **K** the character sheet, **B** build mode, **T** a torch, **F5** / **F9** save and load, MULTIPLAYER on the title and HOST THIS GAME on the pause menu. |
| Unit tests | 561 tests, 7177 assertions (`tools\test.cmd`). `--all` adds the compound raid harness, the save round trips, the fire spread trials, the survivor combat tests, the UPnP door and the real broker under Node: 597 tests, 7325 assertions. The broker leg needs `node` and `npm` on PATH; `server/node_modules/` is gitignored, so in a fresh worktree the test runs `npm install` itself (through `cmd.exe` on Windows, where npm is a batch file) and needs the network that once. Wall-clock varies with the machine — see §9 |
| Smoke | 71 checkpoints: a loopback guest joined, walked and parked, and before that walk, sprint, seven districts, a container searched, the pack, a stack dropped and recovered, a wall built, walked into, repaired and salvaged, a hatchet crafted from the six-recipe C tab, broken and mended at the bench that made it, a workbench opened with E and upgraded with its button, the character sheet opened and a point spent, a chest filled, **four raised beds at four stages, the bed panel, compost dug in and a ripe bed harvested on the key**, a save reloaded, a walker shot, a raid, dusk and night, a torch lit in the dark, a treeline set alight, a swing interrupted mid-wind-up and something left bleeding, somebody taken in, the roster opened, a job reassigned, a car found, driven and parked, the town map with its districts, Sixth Sense widening the reveal, a Chemistry Station and the dose it unlocks, the Lurch, a Raider holding its standoff, the pause menu, CONTROLS, a key rebound, a save written, the title screen, and a slot loaded from it, and every cue reaching a voice |
| World build | ~320ms generation, ~80ms terrain, at boot; a flow field ~2ms |
| Save format | **v11** — what is in every raised bed: the seed, the feed, the water and the growing banked so far. **Not the stage**, which is derived from the last of those on load exactly as it is in play, so a save can no more carry a stale stage than it can a stale stat. On top of v10's weapon condition (on the slot, so it travels with the weapon), v9's and v8's the Mutation meter and the effect clocks (the band derived on load), and v7's every player by identity, with whether they are here, so a guest's character comes back to them next week (a guest's seat loads parked; the host's never does), on top of v6's the districts you have found (ids only: the rects are `Config`, so a save cannot carry a stale map), on top of v5's what a run changed about the cars (broken, open, fuelled, loaded, and where the driven one stopped), on top of v4's crew (level, job, tower by tile, whatever they are hauling) and who is still out there, on top of v3's clock, v2's build, and v1's tile-derived container identity, world fingerprint and slots under `user://saves/`. No derived stat is ever stored: not the player's, not a survivor's. |

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
| Combat: melee, bow, guns, bullets | 2 | improved | Fed by the hotbar; and what a weapon does on a hit is the weapon's — blunt things stagger, edged things bleed, crit is per weapon plus gloves and buffs |
| Damage routing | 2, 5 | ported | Alone you die; with a teammate standing you go down for thirty seconds, and E beside you gets you up |
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
| Vehicles | 4c | ported | Key, pick or Hotwire; a parked car blocks its tiles and a driven one does not |
| Fire | 4b | ported | Spreads through scenery and enemies; cannot reach a player structure, by design |
| Title screen, save slots, keybinds | 4d | ported | Six slots with summaries off an index; binds are per machine, not per save |
| Minimap and town map | 4d | improved | The prototype showed every enemy in the world; here the reveal radius is what Sixth Sense buys |
| Audio | 4d | improved | Synthesised at boot, not per shot; rate-limited per kind; the prototype had no distance falloff |
| Online co-op | 5 | **built** | Host-authoritative over ENet (built in, no broker); the prototype's WebRTC is the same `MultiplayerPeer` face once the extension is dropped in — see §6 |
| Farming: raised beds, seeds, crops, fertilizer | — | **new** | Not in the prototype and was on §7's refused list until 2026-09-10. A dry bed stalls and never dies, which is the whole reason it is allowed to exist. The Farmer job is the next card |

---

## 4. What is built

### A seed, some water, and a few days

- **The Raised Bed** is a tier-1 piece with four fields on it: what is
  planted, what it has been fed, how wet it is, and how much growing it has
  banked. **The stage is never stored** — it is derived from `grow` every time
  it is asked for, so nothing can save, send or draw a stale one. It is not
  solid (you walk through your own garden) and it is deliberately not
  `protect`: a vegetable patch is not a fortification and must not widen the
  base radius or pull a raid at the lettuce.
- **Farming was on §7's "deliberately not building" list.** It comes off it
  because that list is against *chores*, and a garden earns its place on three
  rules that `farming_test.gd` asserts one by one. **A dry bed stalls and
  never dies** — nothing anywhere takes a planting away, so forgetting costs
  you time and never the crop. **Nothing is ever required** — crops are buffs
  and cooking inputs exactly like the rest of the food table, and there is
  still no hunger field. **It is delegable** — `plant`, `water` and `harvest`
  each take the player doing it, so the Farmer job is four calls.
- **Water is Clean Water out of your own pack**, and that is the point: it is
  the same bottle that buys the Hydrated buff, so *drink it or grow with it*
  is the decision the bed exists to pose. One bottle is half a tank and a full
  bed dries out over a day and a half — thirteen minutes of play — which makes
  watering a thing you do walking past rather than a thing the game asks you
  for. There is no rain, no well and no water source of its own.
- **Three crops, and each is a reason.** Potatoes are the bulk crop and the
  cooking staple. **Corn becomes Rations at a bench**, and Rations are what the
  crew eats out of the shared stash — so a corn patch is what stops a base
  needing a supply run to stay fed, and it is why farming exists at all.
  **Herbs become Medical**, two an in-game day against a pharmacy's eight to
  sixteen in one search: enough that a siege stops running you out of
  bandages, nowhere near enough that a pharmacy stops being worth the walk.
  Cooking with what you grew beats cooking with what you found — two Hot Meals
  from the garden against one from three rations.
- **Every harvest hands a seed back**, and sometimes two. A farm that
  dead-ends the first time the loot tables stop offering seed is a worse
  outcome than an economy that grows slowly. Seeds are in five loot tables as
  well, so the first one is found rather than made.
- **Two fertilizers, both yield rather than speed**, because the grow clock is
  what you plan the day around and one that quietly moved it would make the
  whole thing unreadable. **Compost** is fiber and sticks by hand, +60%.
  **Mutagen Sludge** breaks that rule on purpose because it is the expensive
  one: made at the **Chemistry Station** out of the brain matter that holds
  the Mutation meter down, +150% and 40% faster. It is the bargain the whole
  game runs on, restated in a vegetable patch, and it is that bench's second
  job. One dose per bed, and it can go in after planting — feeding yesterday's
  crop still counts, which costs nothing to allow.
- **`E` at a bed is contextual, the way the generator key is.** A ripe bed
  harvests where you stand with no screen at all; anything else opens a fifth
  mode of the pack screen with a typed seed slot, a typed feed slot, the water
  meter and the growth bar. `Farming.prompt` is the one string the offer and
  the action are both built from. The band the panel shows is what the bed
  will actually pay, fertilizer included, so feeding it visibly moves the
  number — 4–7 Corn becomes 6–11.
- **A row of beds reads as a progress bar without carrying one**: dots, short
  shoots, tall shoots, and a ring round the ready one. The smoke run
  photographs four at four stages, because "can you tell from across the base
  which one is ready" is a drawing question and one bed cannot answer it.
- **Destruction loses the planting and salvage returns it** — the same line
  `destroy` and `demolish` already draw. A brute through the beds is a story;
  losing a two-day corn crop to a misclick is not.
- **A garden is not a base, and it is the last thing a horde goes for.** A bed
  is skipped by `base_centre`, so an allotment can neither drag the point a
  raid converges on nor make the game announce "they are heading for your
  base" at somebody who has planted a potato. It stays a `raid_target`,
  because that is the only route by which anything ever damages a structure —
  a bed excluded there could never be destroyed — but at the back of the
  queue, so a horde eats the walls and the workbench first and the vegetables
  last.
- **What is deliberately not here yet: the Farmer.** A fifth survivor job that
  waters, harvests and replants out of the shared stash is the next card, and
  every seam above is left open for it.

### Blunt things stagger, edged things bleed

Three weapon systems, and one sentence of content design holding them
together: **what a weapon does to what it hits is now the weapon's, not the
game's.** Before this, every melee weapon in the game staggered nothing, bled
nothing, and critted identically.

- **Stagger interrupts a committed swing.** `stagger` on a weapon is seconds,
  and what lands is `stagger x (1 - knock_resist)` — the resistance that
  already scales knockback, so "a Brute is hard to rock" is the same fact
  that makes it hard to shove rather than a second table saying it twice.
  A stagger clears the enemy's `windup` and everything it had picked out, and
  **`atk_cd` is not refunded**: the swing it had started is gone, and that is
  what you bought. A staggered enemy does nothing at all — no targeting, no
  step, no attack — which is also true of a Raider holding its distance and a
  Looter running for the treeline.
- **A floor makes bosses immune without naming them.** Anything under
  `STAGGER.min` (0.12s) does nothing, so a Behemoth at 0.95 resistance takes
  0.045s off a Sledgehammer and shrugs. No line anywhere says "Behemoth".
- **`STAGGER.immune` is the rule the whole thing rests on.** After it
  recovers, an enemy cannot be staggered again for 2.2s. Without it a Stone
  Knife at 0.28s would hold a walker still for ever and melee would stop
  being a fight. It is also why all eight shotgun pellets carry a stagger and
  the crowd gets one shove rather than eight.
- **Bleed is what a blade leaves behind.** `bleed` is damage per second and
  `BLEED.time` (5s) is how long a wound runs. A fresh cut refreshes the clock
  and keeps the *higher* rate — the deepest cut is the one that is bleeding —
  so a fast knife rewards staying on a target without multiplying itself into
  a boss-killer. It carries who opened it, so a body that drops seconds later
  still pays its XP and its drops to a person. It is flat from the weapon and
  deliberately not scaled by `melee_mul`. **This is the mechanic cut on
  2026-09-08 for being declared and never read**, back on the terms the
  decision log set: the same three weapons, spec'd.
- **No weapon has both**, and that is the design rather than an accident:
  blunt weapons and shotguns interrupt, the Machete, Stone Knife and Scythe
  cut, Fists do neither. A test asserts the split holds.
- **Crit is per weapon, and per what you are wearing and what you have
  taken.** `Combat.crit_chance` and `Combat.crit_mul` are the only two places
  either question is answered. Chance is the player's (Luck, Lucky Strike,
  gloves, the Mutation band, the effect clock — all arriving already summed
  and capped through `recompute_stats`) plus the weapon's `crit`. Severity is
  the weapon's `crit_mul` plus the player's `crit_dmg`. The two pull opposite
  ways on purpose: a Hunting Rifle or a Stone Knife finds the gap often for
  less, a Sledgehammer almost never for 2.8x.
- **The hands are the crit slot**, and the only one — gloves carry `crit`,
  no other gear does. `MAX_CRIT` (0.75) is clamped once at the end of the
  recompute, because the band and the effect clock both land after gear and a
  cap applied earlier would not be a cap. It is headroom: the best legitimate
  build in the game is nowhere near it.
- **Both new conditions cost one bit each on the wire** (`EF_STAGGER`,
  `EF_BLEED`, protocol 4). A guest never ticks either clock; it only needs to
  know that the thing in front of it is reeling and losing blood. Bleeding is
  spent inside the enemy loop that was already running, so unlike fire it
  needs no scan of its own and a run where nothing is bleeding pays nothing.
- The numbers are the code's first guess, exactly as `dur` was: Notion's
  `Crit Chance` column was blank on every weapon and `Stagger` was set on two
  Planned shotguns only. Both columns have been filled in from what was
  built, so the design table and the game now agree.

### Weapons wear out, and the bench that made one mends it

- **`dur` is a count of uses**, per weapon in `WEAPONS`: one connecting melee
  swing, or one shot. A swing at air costs nothing — the same rule that
  already makes flailing at scenery free. A chop costs what a blow does
  (`WEAR.chop_mul`, 1): it was 2, with stone tools at 140 uses, and a
  Hatchet felled seventeen trees — "much too fast" on the owner's first
  playtest. The five stone tools are 600 now, about a hundred trees, and
  `wear_test` measures that off the swing. Fists carry no `dur` and never wear.
- **Nothing degrades on the way down.** A weapon swings exactly as well at 5%
  as at 100% and then it stops. A weapon that got quietly worse would be a
  chore you could not see, which is the thing pillar 1 is against; instead
  the hotbar carries a condition sliver, and one warning fires on each
  crossing of `worn_at` (30%) and `spent_at` (10%).
- **Broken is refused, not degraded and not destroyed.** A broken weapon
  keeps its slot and does nothing — it is the thing you carry back to the
  bench, and a weapon that crumbled at zero would make "you repair it" a
  promise the game could not keep. The hotbar says BROKEN and the tooltip
  says where to take it.
- **Mended at the bench that made it**, for a share of what it cost to make
  scaled by how worn it is (`WEAR.repair_cost_share`, 0.5), with the main
  material always at least one so no repair is free. The gate is not a second
  rule: it is `Crafting.bench_reason` asked about the weapon's own recipe
  row, so a Hatchet is mended by hand in a field and a Machete needs the
  Workbench, automatically and forever. The rows sit at the top of the CRAFT
  tab, above the recipes, with the verb **MEND** — REPAIR is the build bar's
  word for a wall, and one verb for two jobs teaches the wrong thing.
- **A weapon nothing makes is mended nowhere.** That falls out of the recipe
  lookup rather than needing a flag, and it is what a unique, found-only
  weapon would lean on: no recipe, so no bench, and a bigger `dur` to pay for
  it. **No such weapon exists yet** — every weapon in the game but Fists is
  craftable — so the mechanic is ready and the content is not.
- **Condition belongs to the weapon, not the carrier.** It lives in the slot,
  as the optional `w` on a `Slots` stack, so it travels wherever the weapon
  does: into a chest, into a car boot, onto the ground, into somebody else's
  pack, through a save (v10) and through the pack diff a guest gets. An unset
  slot is a whole weapon, which is also what makes a crafted or scavenged one
  arrive new without anyone arranging it. `Wear.use` is the only writer.
  This is deliberately **not** how `mag` works, and the difference is the
  point: a magazine refills for free the moment you have ammunition, so where
  the count is kept barely matters. Condition only comes back by paying
  materials at a bench, which makes who owns it the whole mechanic.
- **The one place it flattens is the backpack you drop when you die**, because
  `held` is a flat id -> count and always has been. Two Machetes come back as
  one condition, and it keeps **the worse of the two**, so the flattening can
  never quietly mend anything. Leaving it out entirely would make walking back
  to your own body a free repair on everything in it.
- **A broken tool is not a tool.** A zero-condition Stone Knife does not cut
  cordage — "broken weapons do nothing until mended" has to reach the bench
  too. Nothing deadlocks: every tool a recipe names is itself a bench-0
  recipe, so a broken one is always mendable by hand.

### The chemistry, the living, and losing control (Phase 6b)

Everything built on top of the meter. The bar was Phase 6a; this is what
makes it a bet.

- **The Chemistry Station.** A tier-2 structure, and the only bench in the
  game that is *not* a step up the workbench ladder. `station: "chem"` on the
  structure, `station: "chem"` on the recipe, and `Crafting.stations_at`
  sitting beside `bench_tier_at`. Recipe `bench` stays 0 for these on
  purpose: the two gates are independent, and no amount of Workbench II ever
  produces a suppressant.
- **The full chain.** Raw Brain Matter −10 (Nausea) → Mutated −20 → Stabilized
  Neural Serum −30 → **Refined Suppressant −50** → **Experimental −75**, and
  the last one is a gamble: ninety seconds of **Surge** (+35% melee, +10%
  speed) every time, and a **one-in-four Fever** that weakens you *and turns
  you faster*. The risk sits on the same axis as the reward, which is what
  stops it being a free win.
- **Food and drink — buffs, and nothing else.** Nine items, every one an
  entry in `Config.EFFECTS`: Fed, Sated, Steady, Hydrated, Wired, Drunk.
  **There is no hunger meter under any of it and there never will be**
  (pillar 1) — `mutation_depth_test` asserts no such field exists. Hydration
  slows the change (`mut_rate_mul`, the stat Phase 6a left with no writer);
  Drunk is +15% melee, −30% stagger and an aim you would not trust.
  `F` eats the *commonest* thing that would actually help — lowest `rank`
  first, never a second helping of a buff already running — so a tap never
  spends the Field Ration you were saving. Right-click in the pack uses the
  thing you clicked, through `Actions` like every other screen command.
- **The Lurch.** At FERAL, every 60–140s, for 1.2–1.8 seconds your legs stop
  being yours and carry you at the nearest zombie. `Mutation.hijack_intent`
  rewrites the intent rather than guarding twenty branches, so "the intent is
  taken off you" is literally true. Host-rolled; a guest stops predicting its
  own footsteps for the duration exactly as it does while driving.
- **The living.** Three human enemy types — **Looter**, **Raider**,
  **Enforcer** — and a raid track of their own (`HUMAN_RAIDS`), rolled against
  the base owner's Mutation band when Threat schedules a raid: never at HUMAN,
  25% at TURNING, 55% at FERAL. They run on the same AI, the same raid code
  and the same loot roller as everything else; what is new is three things.
  They **shoot** (hostile bullets look for people, not for enemies, and their
  gunfire brings the horde down on the fight). They **hold a range** —
  `standoff` is what a Raider backs off to and what an Enforcer walks in to.
  And a Looter **empties your stash and runs**: put it down and you get it
  back, let it reach the edge and it is gone. They carry no brain matter, so
  killing people is never a way to hold the meter down.
- **And nobody will go anywhere with you.** At FERAL a rescue refuses
  outright — the first answer, before beds or Charisma.
- **What the living deliberately are not: zombie food.** Nothing in the game
  has enemy-versus-enemy targeting and adding it for one faction would be a
  system with one caller. The honest half — their rifles pulling the horde
  onto them — costs nothing and is in.

### What you are becoming (Phase 6a — Mutation)

**The theme moved.** You were bitten before the first frame and there is no
cure. What there is, is control: something in a zombie's brain suppresses the
change, so the supply line that keeps you human runs through the horde. That
is the one meter the player manages, and it is not food.

- **The meter.** `PlayerSim.mutation`, 0–100, climbing on its own. A full
  cycle untouched is 7.5 in-game days — about sixty-seven minutes of play — so
  brains are something you stock, not something you think about every five
  minutes. Worse ground turns you faster (×1.6 in tier 4), so does the dark
  (×1.2 at full night), and so do teeth: one zombie melee hit in ten is a
  **bite** (+6), any hit of 25 or more is +5, and going down is +10. (It was
  2.5 days and one in seven at +12 until the owner's first playtest found it
  "way too fast".)
- **Three bands, and one door.** HUMAN (0–35), TURNING (35–70), FERAL
  (70–100). A band is a table of modifiers in `Config.MUTATION.bands`, and it
  reaches the player through `recompute_stats` and nothing else (invariant 4).
  A **band change** is the only thing that triggers a recompute, so the meter
  drifting a tenth of a point costs nothing. TURNING is +20% melee, +6% speed,
  +15 stamina, 25% worse spread and 10% harder to sense. FERAL is +45% melee,
  +12% speed, +15 health, 60% worse spread, **sensed at 0.6× the radius**, and
  half the stagger — the flash, the shove and the shake all come off
  `stagger_mul`.
- **The bargain.** Further along you hit harder and the dead barely notice
  you; you are also worse with a gun and closer to gone. Letting it climb is
  sometimes the play, which is the whole reason it is a meter and not a timer.
- **Turning.** At 100 you die with your own banner — `YOU TURNED` — and come
  back at **55**, never at 0: letting the bar fill must not be the cheapest way
  to empty it. `Damage.kill_player` grew a `cause` so there is still one death
  path and one place that says what happened.
- **Brains, by what the body was.** A kill drops brain matter at most once,
  whatever loot perks are stacked on it — a corpse has one head in it. Walker
  45% → Raw; Runner 55% → Raw ×1–2; Brute 85% → **Mutated** plus Raw;
  Behemoth always → **Neural Tissue** plus Mutated ×2. This is why one fight
  is now worth more than another.
- **The chain.** Raw Brain Matter is the field answer: −10, and Nausea for a
  minute. A Workbench turns three of them into a **Stabilized Neural Serum**:
  −30 and no side effect. (Refined and Experimental doses, and the Chemistry
  Station they are made at, are Phase 6b.) `G` takes the strongest dose that
  does not overshoot by more than 8 points, so a Serum is never spent to clear
  four — the rule is written against the table, not against three item ids.
- **Buffs and debuffs are one table.** `Config.EFFECTS`, `PlayerSim.effects`
  as id → seconds, applied inside the same recompute. Nausea is the only
  entry today; the food and drink table lands on it in Phase 6b, buff-only,
  with no hunger bar underneath.
- **It travels.** Saves carry the meter and the clocks (payload v8, the band
  is *derived* on load, before the recompute). The snapshot carries mutation
  in the player stride and the effect clocks as a fourth string, and a guest
  rebuilds its own band from them — so a guest at FERAL predicts its own
  footsteps at the speed the host is actually giving it.
- **You can see it.** A third bar under health and stamina, with the band
  name and its colour, and ticks where the bands start. The body tint follows
  the *meter* toward the *band's* colour, so the change creeps rather than
  switching on. The smoke run photographs TURNING, FERAL and a dose landing.

### Other people at the table (Phase 5 — co-op)

- **The host runs the game; guests run a mirror of it.** `NetHost` sits
  beside the scene's ordinary loop: read the guests' intent, `sim.tick`,
  send. `NetGuest` builds its mirror with `SaveGame.apply` from the host's
  payload — the same load path a save uses, so a guest joins with every wall,
  chest and district exactly as the host has them — and then never ticks it.
  Snapshots land in the mirror's entity lists, events land in its `events`,
  and every view draws it exactly as it draws the host's. The one thing a
  guest simulates is its own next step: `PlayerSim.move()` with the host's
  code, pulled toward the host's answer (a lerp inside 48px, a snap past it).
- **Intent up, snapshots down, facts reliably.** `Intent` is packed to a few
  bytes and sent every step on the unreliable channel; edges are merged so a
  press survives a packet without it, and a late packet gives up only its
  edges. A silent guest is holding nothing after 400ms, and a paused one says
  so every step. Snapshots at 20Hz describe every player, every survivor,
  and the enemies, piles, cars and fires within 1600px, as flat float arrays
  — sixty enemies and twenty piles in under three kilobytes. Anything over
  900 bytes is zstd-compressed to stay inside one datagram. Walls, stores,
  emptied containers, felled trees, found districts, waiting rescues and the
  roster go over the reliable channel as diffs every half second, keyed by
  tile and id and never by index (invariant 7); a guest's own pack goes the
  moment it changes.
- **A guest's command is the host's function.** `Actions` is the one seam
  between the screens and shared state: on the host and in solo it calls
  `Crafting.craft`, `Equipment.move_stack` and the rest; on a guest it sends
  the same arguments to the host, who runs the same function with the same
  range, cost and room checks. Building, searching, driving and getting
  somebody up are not commands — they are `Intent` edges, and were already
  the sim's door.
- **Seats and identity.** A guest's machine has an identity in
  `user://net.json`; the host's save keeps every player by it (v7), so
  leaving parks the character where it stood and coming back next week is
  the same character, level, pack and all. Four seats; "full" is who is
  here, not who has ever been. A wrong password, a full game, a stale build
  or a second copy of somebody already connected is refused with the reason.
- **Downed, not dead.** With a teammate standing, zero health is thirty
  seconds on the ground: the horde loses interest in you, being hit again
  does nothing, and a teammate holding E beside you for two and a half
  seconds brings you back at 40%. Bleed out, or leave, and it is the death
  it always was. Alone there is nobody to come, so alone you just die.
- **The door.** START HOSTING listens on the port and, on a thread, asks
  the router over UPnP to map it, then asks for the public address. The
  HOST page says what happened in a sentence: open, with the address to
  click-to-copy; refused, with the router's reason; or no router answered.
  When UPnP says no or is switched off, `Stun` asks a public STUN server
  what the internet sees and the address is shown anyway, hedged — "works
  only if you forwarded UDP 27333" — because STUN reports an address, never
  whether anything is listening behind it. A host who forwarded the port by
  hand has a line to copy instead of a website to go find; nobody remembers
  their own public address and it changes. `Config.NET.upnp` false takes the
  same path without asking the router anything — that setting is what a host
  who forwarded the port by hand would reach for, and it used to build no
  door at all. The one refusal that shows no address is a conflicting
  mapping: the external port already belongs to another device here, so the
  public address would reach them and not this host.
  The LAN addresses are on the page
  either way. Closing never waits on a router — a discovery still running is
  orphaned and takes its own mapping down. Carrier-grade NAT is the one
  thing neither road gets past; that is the VPN or WebRTC (§6).
- **The room-code road, built and switched off.** `WebRtcHub` is the same
  `PeerHub` face over `WebRTCMultiplayerPeer`: the host registers with the
  broker (`server/signal.js`, the prototype's, unchanged) and gets a
  six-letter code, a guest joins with the code, and the broker relays the
  offer, the answer and the ICE candidates until the two machines talk
  directly. The signalling is a `NetSignaller` over the engine's own
  `WebSocketPeer`; the connection comes from a factory. It is off until
  `Config.NET.broker` names a broker **and** the native `webrtc-native`
  extension is in `addons/webrtc/` (`tools/fetch-webrtc`, gitignored) —
  the engine ships the WebRTC API and not the implementation. With both,
  START HOSTING opens a room beside the port and shows the code, and JOIN
  takes a code where it takes an address. The switch is those three steps;
  `server/README.md` has the free-tier deployment.
- **The transport is a face.** `NetLink` is bytes in on a channel, bytes out
  with the channel they came on. `Loopback` is a pair of queues — optionally
  lossy and out of order — and is what the tests and the smoke run join a
  guest through; `EnetHub` stands the engine's own `ENetMultiplayerPeer`
  behind the same face, one hub dealing packets to one link per peer. A
  WebRTC peer would plug in there without the sessions changing.

### The ears (Phase 4d — audio)

- **Every sound is synthesised, and none of it is loaded.** There is not one
  audio file in the project. `Config.SFX` is thirty-five recipes — a `tone` is
  an oscillator with a pitch glide, a `noise` is white noise through a filter,
  and both have a 5ms attack and an exponential decay — and `Sfx` renders each
  one to a PCM buffer at boot.
- **Rendered once, not per shot.** The prototype built a WebAudio graph on
  every single sound. Godot has no cheap equivalent and does not need one:
  these cues never change, so playing one costs a `play()` on a pooled voice.
  The whole bank is 91ms at boot, after the per-sample `exp` and `pow` were
  replaced by stepped multipliers that give the identical curve.
- **A shotgun blast hitting twelve zombies is one impact.** Identical cues
  inside a per-kind window are dropped — bullet hit 28ms, growl 260ms, player
  hurt 140ms — and the gunshot rides the `shot` event, which already carries
  the weapon id on the first pellet only, so a shotgun blast is one bang and
  not eight. It is also the only event a bow produces: a bow emits no muzzle
  flash, because a flash is a light source at night.
- **The simulation stays deaf.** `SfxView` maps events to cues, exactly as
  `FxView` maps them to particles and `LightView` to lights. Nothing in
  `src/sim` knows a sound exists, which is what lets the whole game run
  headless with no audio device.
- **Distance is new.** Web audio gave every sound the same volume wherever it
  happened, so a turret across town was as loud as the gun in your hand. Here
  a cue fades from 340px and stops at 1500px — which is also what stops a raid
  on the far side of the map being a wall of noise.
- **A Chamberlin state-variable filter** gives the lowpass, highpass and
  bandpass the prototype's biquad gave, from one loop, and it can sweep its
  cutoff per sample — which is what makes a shotgun a falling roar rather than
  a burst of static.
- **SOUND: ON is a row on the pause menu and the title**, not a hotkey, and
  the setting is per machine like the key bindings. Whether your speakers are
  on is not a property of the world you are playing.

### The map (Phase 4d — minimap and town map)

- **One Control draws both.** The corner minimap and the town map behind `M`
  are the same picture at two sizes with two levels of detail, off one
  `_draw` — a marker that appears on one and not the other is a bug, and
  having two functions is how you get one.
- **The ground is a 320×320 image, one pixel per tile**, tinted red by danger
  tier so the map itself says where not to go, and darkened where the ground
  is solid so the river and the walls read as shape. Built once per world and
  cached on the generator's fingerprint: 41ms, inside the boot or the load it
  already belongs to.
- **The town map names what you have stood in.** An undiscovered district
  still shows its outline — you can see there is *somewhere* there — but not
  its name or its danger, which is the reason to go and look. Walking into one
  pays 25 XP per danger tier, so finding the place is worth something on its
  own. What you have found is saved.
- **Sixth Sense finally does something.** The prototype drew every enemy in
  the world on the minimap and left `radarMul` set by the perk and read by
  nobody — six ranks of Perception for nothing. Here the map reveals what is
  near (380px), further for anything that has already noticed you (900px,
  because a horde on its way is not a secret), and the whole radius scales
  with `radar_mul`. **This is a deliberate change from the prototype**, and it
  is the last `needs` gate coming off a perk.
- **The map is a panel over a running world**, like the pack — reading it is
  not a time-out, which is why its markers are live. Escape closes it before
  it opens anything else.

### The front door (Phase 4d — title, slots, keys)

- **The game boots to a title screen** rather than into a world. CONTINUE
  names the game it would open and what state it is in; NEW GAME, LOAD GAME,
  CONTROLS and QUIT sit under it. The one exception is the smoke run, which
  boots straight into a world — a screenshot harness that had to click
  through a menu first would be testing the menu on every checkpoint.
- **`Saves` is an index, not a directory listing.** Name, day, level, kills,
  play time and when it was last touched live in one small
  `user://saves/index.json`, rewritten on every save. Listing six saves must
  not mean parsing six worlds, which is exactly what reading the payloads
  would cost.
- **The file is the truth about existence; the index is the truth about the
  summary.** An entry whose payload was deleted from outside is dropped
  rather than offered, and a payload with no entry is still on disk — both
  halves can outlive the other and neither is silent.
- **CONTINUE opens the one you last chose, not the one last written.**
  Loading marks a slot current before anything else writes, so coming
  straight back after a LOAD returns to the game you picked rather than to
  whichever autosave happened to fire last.
- **Autosave every two minutes, for a game that has a slot.** A run with no
  slot — a smoke run, a NEW GAME the player has not named — writes nothing;
  the alternative is a headless test quietly creating a save file.
- **Escape closes what is open, innermost first**, and only opens the pause
  menu once there is nothing left to close. The menu owns input while it is
  visible and the world does not step behind it: the smoke asserts the sim
  clock has not moved after a second of paused frames.
- **SAVE AND QUIT TO TITLE writes the game down before it leaves.** Quitting
  is the moment a player is least able to notice they lost an hour.
- **Every key is rebindable, and the binds belong to the machine.** They are
  written to `user://binds.json`, not into the save — the keyboard in front
  of you does not change when you load a different game. `KeyBinds` is now
  static state on a `class_name` rather than autoload-only fields, because an
  autoload does not exist under `godot -s` and the binds had no test.
- **A conflict is reported, not refused.** Two things on one key is a choice
  the player is allowed to make, so CONTROLS marks both rows rather than
  rejecting the second. Escape is the one key nothing may take: it is how you
  leave a screen you opened by accident with a key you just reassigned.
- **Every prompt is built from the binding.** `KeyBinds.primary_label` is what
  the HUD and the interact prompt read, so rebinding E changes what the game
  tells you to press.
- **One `_rows()` builds the page, and both the hit test and the drawing read
  it** — a menu whose click map and paint can disagree is a button that does
  the wrong thing. The footer rows (RESET TO DEFAULTS, BACK) are pinned
  rather than scrolled, because on a long CONTROLS list BACK went off the
  bottom of the panel.

### Wheels (Phase 4c — vehicles)

- **`Vehicles`** turns the generator's parked-car markers into about thirty
  real cars, each rolled from its *own* seed stored on the marker — so how
  many you break into cannot shift the world's or the spawner's numbers.
  62% start locked and most are nearly dry: a full tank is a find.
- **Three ways into a locked one, cheapest first.** The key hidden in a
  container near it, a lockpick (0.34 + 0.07 per Perception, clamped so it is
  never certain and never hopeless — a failure snaps the tool and is heard
  260px away), or Hotwire, which is loud and takes 3.2 seconds of standing
  still. **Hotwire's `needs` gate comes off with this**, leaving only Sixth
  Sense waiting on 4d's minimap.
- **A car key is learned, not carried.** No weight, no slot, undroppable — a
  key you could leave in a chest would make "whose car is this?"
  unanswerable again, which is the whole reason the keys are planted.
- **Driving is all you can do at the wheel.** The player tick returns early
  rather than guarding each part, so there is one place to look for what is
  possible while driving and the answer is "drive". The car owns where its
  driver is, and sets it *after* moving — the players tick before the cars, so
  copying it the other way drew the driver a frame behind their own car.
- **Arcade handling.** Steering authority scales with speed, so a stationary
  car cannot spin on the spot. An engine is heard 640px away and adds Threat
  while it runs: a car is the answer to distance and the cost is being noticed
  (pillar 6). Roadkill is the driver's — their XP and their Luck on the drop.
- **A parked car blocks the tiles it sits on** and a driven one does not, with
  the claimed tiles tracked precisely rather than recomputed. Claiming asks
  *both* collision maps (invariant 2): checking only the terrain bitmap let a
  car park inside your own wall, because a wall lives in `Structures`.
- Anything in the boot spills onto the road when a car is wrecked, and a wreck
  can be stripped for scrap — a dead car is still worth something. A stripped
  one stays stripped across a save: the fleet is regenerated from the seed, so
  a car the save does not mention is removed rather than quietly returning.
- **Tap E to drive, hold E for the boot** — the same tap/hold split a
  container already uses. The boot is a `Slots` like every other container, so
  the two-panel store screen opens it and refuelling is a button on it, rather
  than a second kind of storage UI existing.
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
    on nothing is worse than a row that explains itself. **As of 4d none are
    left**: Hotwire got its cars and Sixth Sense got its map. A test asserts
    that, so a `needs` cannot outlive the system it names.
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

- **`Crafting`** — instant, because the materials are the whole cost. `C`
  is by hand and only by hand: Bandage, Hatchet, Stone Knife, Stone Pickaxe,
  Stone Hammer, Torch, and a test holds the table to that list. Everything
  else is on the bench screen `E` opens at a workbench or a Chemistry
  Station, at that bench's tier, with UPGRADE as a priced button in it.
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
  the bow as a one-round gun, and `crit_chance` / `crit_mul` — the only two
  places the game asks how often a hit is a critical and what it costs.
- **`Damage`** — enemy damage with knockback and resistance, kills (xp to
  the killer, threat, quiet, corpse), player damage with invulnerability,
  death, healing, respawn on tier-1 ground clear of enemies. It owns the two
  conditions a blow can leave as well: `stagger_enemy` (resisted, floored,
  with the immunity window, and it takes the wind-up with it) and
  `bleed_enemy` / `tick_bleed`. One writer each, beside the resistance they
  both read.
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
   Base → attributes → perks → gear → Mutation band → effects, rebuilt from
   scratch. Never mutate a stat on purchase, and never on a band change
   either: change `mut_band` and let the one door open.
5. **Every tunable and content table is reached through `Config`.** Tunables
   are consts in `config.gd`; content tables are files in `data/`, loaded
   into `static var`s of the same names (`Config.WEAPONS` is
   `data/weapons.json`). A number the game uses is in one of the two, never
   in a sim file. Edit the tables with `tools\edit` (§10), never by hand.
6. **Anything that walks toward a target needs give-up logic**, even with
   navigation. The prototype's stuck-AI bugs all came from the absence of it.
7. **Container identity in saves derives from tile position**, never from
   ordinal index. The prototype's ordinal scheme invalidated every save twice.
8. **Simulation code takes the acting player as a parameter.** A system that
   means "whoever did this" — damage, XP, threat, cost, loot — takes `p`.
9. **Every write to the Mutation meter goes through `Mutation.add`.** It is
   what derives the band, what decides you have turned, and what emits the
   notice. A `p.mutation = x` anywhere else is a character whose stats are a
   band behind — which is exactly the bug `mutation_test` was written around.
10. **The class_name cache goes stale** whenever a script is added outside the
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
| 2026-09-08 | The minimap reveals enemies within a radius, rather than showing every enemy in the world as the prototype did | The prototype set `radarMul` from Sixth Sense and read it nowhere, so a rank-6 Perception perk did literally nothing. A radius makes the perk the thing that buys the radar, and stops the minimap being a free solution to the whole game. **This is a balance change, not a port** — 380px, 900px for anything that has already noticed you, ×2.4 with the perk — and it is a feel question for the owner. | Yes, three numbers in `Config.MAP` |
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
| 2026-09-10 | **Farming comes off §7's "deliberately not building" list**, and a Raised Bed is buildable | The owner asked for it, and the list was written against *chores* — meters the game nags you about — not against growing things. A garden stays on the right side of pillar 1 on three rules, and all three are asserted in `farming_test.gd`: a dry bed **stalls and never dies**, so forgetting costs time and never the crop; nothing is ever required, so crops are buffs and cooking inputs exactly like the rest of the food table and no hunger field exists; and it is delegable, which the Farmer job will collect. The third amendment to that list, after Mutation and factions. | Yes, but it is a system |
| 2026-09-10 | Growth stops when the water runs out; it never kills the planting | The obvious version — a crop that withers — is the chore the whole list refuses. It also punishes exactly the thing this game is about: being away from home because something out there needed doing. A throttle costs the player time, which is a real price, and never a walk back to nothing. The water gauge is drawn amber when it is low and grey when it is out, never red, because colouring it like damage would be the screen telling a lie about the rules. | Yes, one `if` |
| 2026-09-10 | A bed is watered with Clean Water out of your own pack, and there is no rain, no well and no water source of its own | It is deliberately the *same* bottle that buys the Hydrated buff, so drink it or grow with it is the decision the bed exists to pose. `hotMeal` already cost `water: 1`, so the precedent was set. A rain barrel or a river tile would be a second economy for one system and would make the bottle worthless. | Yes — additive |
| 2026-09-10 | Fertilizer is **yield**, not speed — except the one made of brain matter, which is both | The grow clock is what a player plans the day around, and a fertilizer that quietly moved it would make the whole thing unreadable. Compost is +60% and nothing else. Mutagen Sludge breaks the rule on purpose because it is the expensive one: made at the Chemistry Station out of the brain matter that holds the Mutation meter down, it is this game's own bargain restated in a vegetable patch, and it gives that bench a second job. | Yes, two numbers |
| 2026-09-10 | Every harvest returns a seed of its own kind, plus a 35% chance of a second | A farm that dead-ends the first time the loot tables stop offering seed is a worse outcome than an economy that grows slowly. Seeds are also in five loot tables, so the first one is found rather than crafted. | Yes, two numbers |
| 2026-09-10 | A raised bed is **excluded from `base_centre` but kept in `raid_target`** — Codex's first finding on PR #24, resolved the other way round | Codex was right that `protect` was doing less than the row below claims: it only *weights*, so a bed still anchored a base and still drew raiders. It proposed excluding plots from both, and half of that is right. `base_centre` is where a raid converges, and a garden is not where you live: counted there, twelve beds in a field outrank a whole compound and drag the convergence into the allotment, and one bed in open country was enough to make `has_base` true and announce "they are heading for your base" at somebody who had planted a potato. But **`raid_target` is the only route by which anything ever damages a structure** — an enemy's `pending_struct` comes from its `objective` and from nowhere else — so a bed excluded there is a bed that can never be destroyed, `Farming.on_removed(refund: false)` becomes dead code, and "a brute through the beds takes the crop with it" becomes a promise the game cannot keep, which is what the `bleed` row below is about. Beds stay eligible and go to the *back* of the queue instead (`raid_pull_plot`), so a horde eats the walls and the workbench before the vegetables and can still eat the vegetables. | Yes, one skip and one weight |
| 2026-09-10 | **Nothing on a harvest scales with `loot_mul`** — Codex's third finding on PR #24 | It was in `Farming.harvest` and not in the band the panel prints, so the screen promised 3-5 Potatoes and paid 4-6 to anyone holding a rank of Scrounger. Two ways to close that, and printing it is the worse one: the perk's own description is "+35% resources **from containers**", a crop you grew is nearer to a craft than to a find, and crafting has never scaled with a loot perk. Taking it out also keeps the feed slot the one dial the whole system is built around, rather than a number a Perception build quietly stacks on top of it. | Yes, one factor |
| 2026-09-10 | **The shared stash is reachable from anywhere, and farming does not change that** — Codex's second finding on PR #24, declined with a card | The finding is factually right and the target is wrong. `PlayerSim.total_res` has added `sim.stash` with no distance test since Phase 3, so a Steel Wall, a repair, a Machete and a Medkit have always been payable from a stash on the far side of town; farming inherits the rule rather than introducing it. Making watering the **one** operation in the game that range-checks the stash would be a surprise rather than a fix — you would be able to build a wall out here but not pour a bottle on a bed. What the PR actually got wrong was a comment claiming a field bed was "a thing you carry water to", which the code has never done; that comment is gone. Whether the stash should have a reach at all is a real question about the whole economy and every system that spends, and it is on the roadmap as its own card. | The card is open |
| 2026-09-10 | A bed's water and growth go on the wire **coarse, and floored** | They are the first fields in the game that move every single frame, and the world diff re-sends any structure whose packed record has changed — so at full precision a twelve-bed garden would re-send itself every half second for the rest of the run, for a difference no guest could see. Four seconds of growth and five units of water are both under a step the eye can find. Floored rather than rounded to nearest so a guest is always a little *behind*: one that reached "ready" first would offer a harvest the host then refuses. Two tests hold it — one counts the distinct records two in-game minutes produce, one asserts the wire is never ahead. | Yes, two numbers in `Config.FARM` |
| 2026-09-10 | A Raised Bed is not `protect`, and it is not solid | `protect` is for pieces somebody planted to make a place theirs — a bunk, a stash, a bench, a tower. Marking a vegetable patch would widen `BASE.radius` around the allotment and make `raid_target` pull a horde at the lettuce. Not solid because you walk through your own garden, like a spike trap or a floodlight. | Yes, two flags |
| 2026-09-10 | Destroying a bed loses the planting; salvaging one returns it | The same line `destroy` and `demolish` already draw everywhere else. A brute through the beds mid-raid is a real loss and a good story; deciding to move a bed is not, and losing a two-day corn crop to a misclick would be. | Yes, one bool |
| 2026-09-10 | Herbs become Medical at a bench, at a deliberate trickle | Two Medical per in-game day against a pharmacy's eight to sixteen in one search. Enough that a long siege stops running you out of bandages and serum, nowhere near enough that a pharmacy stops being worth walking to — which is the whole balance question, and the number most likely to want moving. | Yes, one recipe |
| 2026-09-10 | The bed is a fifth mode of the pack screen, and a ripe bed answers `E` with no screen at all | The same argument CRAFT, CHAR and STORE already won: what you plant is a decision about what you are carrying. The contextual key is the shape `use_generator` has — switching to the useful job takes priority — and `Farming.prompt` is the single string the offer and the action are both built from, so they cannot disagree. | Yes |
| 2026-09-10 | Condition lives on the **slot**, not on the player — reversing the row below after Codex found what it cost | A slot gains an optional `w`, so condition travels with the weapon into chests, car boots, the ground and other players' packs. The player-keyed version leaked four ways, and Codex caught it on PR #22: a broken weapon left in a chest came back whole to the next person to open it; a freshly crafted weapon was **born broken** because the last one of its kind had been; the free repair the death drop is careful to prevent was one deposit away; and two of a kind could never be told apart. Cheap in practice because weapons are stack-limit 1 (no merge ever has to decide what two joined conditions are) and `Slots.move` already moves a whole stack dictionary. | Yes, but it is the slot model |
| 2026-09-10 | Condition on the slot, magazines still on the player | Not symmetry for its own sake. A magazine refills for free the moment you have ammunition, so where the count lives barely matters — a found gun coming up loaded is fine. Condition only comes back by paying materials at a bench, so *who owns it* is the entire mechanic. `mag` has the same transfer looseness and it is not a bug there. | Yes |
| ~~2026-09-09~~ | ~~Wear is kept per weapon **id**, not per instance~~ | **Superseded on 2026-09-10, see above.** The reasoning was that `mag` had already made this trade and a slot is `{id, n}` and nothing else. What it underweighted is that a magazine is refillable and condition is not, so the state has to follow the object. Left here because the wrong version is the interesting half of the record. | n/a |
| 2026-09-09 | A broken weapon refuses; it does not degrade, and it does not vanish | Three options, and only one is both readable and honest. Degrading on the way down is a chore you cannot see (pillar 1) and makes every combat number a function of wear. Vanishing at zero makes "you repair it" impossible. Refusing is one rule, warned about twice before it fires, and leaves the thing in your hands to carry to the bench. | Yes |
| 2026-09-09 | The repair gate is the recipe's own bench, not a table of its own | "Repaired at the same bench they are made" is literally `Crafting.bench_reason` asked about the same recipe row — which is why that gate was split out of `Crafting.status` rather than copied. A new weapon needs no repair entry, and the two can never drift apart. | Yes |
| 2026-09-09 | The weapon repair bill ignores `build_cost_mul`; the structure one still takes it | That multiplier is Engineer and the Intelligence ladder making what you *construct* cheaper, and `Crafting.craft` already ignores it — a Machete costs 24 scrap at any Intelligence. Charging a share of a price the perk does not touch, and then discounting the share, would make mending cheaper than making for a reason nothing in the game states. | Yes, one argument |
| 2026-09-09 | Durability numbers are the code's first guess, not Notion's | Notion's `Durability` column is where the owner's per-weapon intent belongs, and **it is blank for every weapon in the game** — one Planned row (AK-Style Rifle, 5) is the only value in it. §10 says not to read that column as a spec, so the table in `Config.WEAPONS` is a first pass to be played and argued with, and the write-back is the owner's to make. | Yes, sixteen numbers |
| 2026-09-10 | Stagger is deterministic seconds, resisted by `knock_resist`, with an immunity window | A chance roll per hit was the other option and is more dramatic. Deterministic wins on three counts: the same blow does the same thing every time, which is what a player learns a weapon by; host and guest agree without either touching the seeded RNG; and the rule that stops a stun-lock has to exist either way, so the roll buys nothing but variance. Reusing `knock_resist` rather than adding a `stagger_resist` keeps one fact about how heavy a body is in one place. | Yes |
| 2026-09-10 | An enemy is stagger-immune for `STAGGER.immune` after it recovers | Without it a Stone Knife at 0.28s cooldown holds a walker still for ever, and every fight against anything that is not a boss becomes a lock. With it, an interrupt is a thing you spend and time. It is also what makes a shotgun's eight pellets one shove rather than eight, at no extra cost. | Yes |
| 2026-09-10 | A bleed does not stack; the deepest cut wins and refreshes | Stacking makes a fast weapon multiply itself — a Stone Knife at 0.28s would out-damage everything in the game against a Behemoth by standing still and cutting. Taking the higher rate and refreshing the clock still rewards staying on the target, and it keeps the number on screen readable: it is the weapon's, not the weapon's times how long you have been at it. | Yes |
| 2026-09-10 | Bleed is flat from the weapon and ignores `melee_mul` | A cut bleeds the same however strong you are. The realism argument goes the other way, but the readable one wins: `bleed` on the row is what the wound does, full stop, and a Strength ladder that silently doubled it would make the field a lie. Damage is where Strength belongs and it already is there. | Yes, one multiplier |
| 2026-09-10 | A stagger does not refund the enemy's `atk_cd` | It was spent starting the swing that has just been taken away, and losing it is the reward for the interrupt. Refunding would make an interrupted enemy swing again sooner than one you left alone, which is exactly backwards. | Yes |
| 2026-09-10 | Crit chance and severity are per weapon; the cap is clamped once, at the end | `crit_chance + 0.06` at 1.9x for every melee weapon and `crit_chance` at 1.8x for every gun meant a Stone Knife and a Sledgehammer critted identically, and no piece of content could ever say otherwise. Two functions in `Combat` are now the only answer to either question. The `MAX_CRIT` clamp sits at the end of `recompute_stats` rather than beside the gear sum because the Mutation band and the effect clock both apply after gear — a cap applied any earlier is not a cap. | Yes |
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
| 2026-09-09 | STUN fills in the public address when UPnP will not | The owner's router has UPnP switched off and is staying that way — there is a Foundry server on the same network and widening the blast radius for a game was not the trade. UDP 27333 is forwarded by hand instead, which works, but the HOST page could only learn the public address from `query_external_address()` on the UPnP success path, so it showed nothing to copy and the owner had to go find their own address on a website. One UDP binding request to a public STUN server answers it: forty lines, no dependency, no broker, and `Config.NET.stun` already had the server in it. The line is hedged, because STUN reports the address the internet sees whether or not anything is listening behind it. | Yes — additive |
| 2026-09-09 | The WebRTC road is built to the last step and left switched off | The owner wants to flip to it quickly if UPnP fails, so everything that can be written and tested without the native binaries is: the hub, the broker wire over the real WebSocket, the menu rows, the fetch script and the deployment notes. The binaries stay out of git (`addons/webrtc/` is ignored) because they are per-platform, several megabytes, and a download away; and the broker URL stays empty in `Config` because there is no broker yet. A GDScript `WebRTCPeerConnectionExtension` stands in for the native one in tests — it carries the handshake and the connection through the real `WebRTCMultiplayerPeer`, but not bytes: the engine hands that layer raw pointers. | Yes — one config value and one script |
| 2026-09-09 | UPnP before WebRTC for internet play | The owner asked for the cheap way. UPnP is twenty lines against a class the engine ships, no binaries to vendor and no broker to keep alive; it fails only on routers with it switched off and on carrier-grade NAT. WebRTC stays the road for those cases: an extension, a broker on a free tier, and TURN money if STUN is not enough. Try the free thing with real friends before paying for the sure thing. | Yes — additive |
| 2026-09-09 | Co-op transport is ENet, built into the engine, not WebRTC | The plan said WebRTC because the browser had no choice. Godot's WebRTC is a GDExtension that is not in the engine — tens of megabytes of binaries to vendor per platform — and it still needs the signalling broker to introduce two peers. ENet is in the box, needs no broker, and is the same `MultiplayerPeer` face; every session object above the hub is transport-blind, so WebRTC is an additive change when the owner wants internet play without port forwarding. What ENet does not do is punch through two home routers on its own. | Yes — `EnetHub` gets a sibling |
| 2026-09-09 | A guest holds a real `GameSim` as its mirror, never ticked | Every view already reads a `GameSim`; teaching them a second shape would have meant a second view layer. The mirror is built by `SaveGame.apply` (so joining is the load path, invariant 7 keeps container identity honest) and snapshots write into its lists. Its clock, stats and threat are whatever the host last said. | Expensive later |
| 2026-09-09 | World facts travel as diffs of state, not as a vocabulary of events | The prototype relayed `struct`, `sdel`, `looted`, `prop` and so on, and every new system needed a new event or a guest quietly drifted. Here the host compares what it last sent against `structs.list`, the looted flags, `chopped`, `discovered` and the roster every half second, and sends the difference. A missed event is impossible because there are no events to miss; the cost is a hash of the structure list twice a second. | Yes |
| 2026-09-09 | Snapshot entities are flat `PackedFloat32Array`s, players included | A Dictionary per enemy is a type header per field; two player dictionaries alone put a snapshot over the 1392-byte MTU and the engine warned about it in the socket test. Fixed strides, an index for the type and the item, and zstd over 900 bytes. | Yes |
| 2026-09-09 | Downed-not-dead only when a teammate is standing | The mechanic is "somebody can come"; with nobody to come it is thirty seconds of watching a timer. `has_teammate_for` decides at the moment of the fall, so a guest leaving mid-bleed-out is death, not a rescue. | Yes, one condition |
| 2026-09-09 | The host keeps the world running while its pause menu is up, if anyone is connected | A pause that froze three other people's game would be the host's screen deciding everyone's time. Alone, a pause is a pause. The host's own intent is cleared while the menu is up. | Yes |
| 2026-09-09 | Felled props carry a `gone` flag the renderer skips | The prop renderers bucket the prop dictionaries once and hold references, so a chopped tree went on being drawn until a reload — on the host too, not only the mirror. One flag, no rebuild per swing. | Yes |
| 2026-09-08 | Anti-stall relocation gated at 400px, and the no-base centre follows you | The gate was a bare 240 and the centre froze at the warning, so a raider legitimately chasing a player who had moved read as stalled and got warped out of the fight. 400 sits below the 520px spawn ring (a raider wedged where it spawned is still rescued) and past half a screen (nothing you are watching is teleported). | Yes, one number |
| 2026-09-09 | Content tables are designed in Notion (DEADLINE → Items & Crafting) and mirrored into `config.gd` by a sync, rather than edited in the code first | The owner wants to see and reorganise every item, recipe, bench and loot source in one place, on a phone, without a text editor — and to add benches and weapon classes before they exist in code. Notion owns *what exists and what it costs*; the code owns *how it behaves*; the sync procedure in §10 keeps the seam honest. Invariant 5 still holds: `config.gd` is the only place the game reads from. | Yes — the tables are a mirror, and `config.gd` stays the truth for the running game |
| 2026-09-10 | Content tables moved out of `config.gd` into `data/*.json`, edited with a local page (`tools\edit`); Notion's roadmap moved to Linear | Notion blocks guests from its connector, so the collaborator could not work with it, and a sync is a second copy that drifts. The tables are `static var`s of the same names loaded through `DataTable` (typed `fields`, because Godot reads every JSON number as a float; one canonical encoder, so an edit is a one-line diff), and the editor refuses any save that breaks a reference anywhere. It is a headless Godot on loopback — nothing to install, nothing hosted. Supersedes the row above once Notion is archived | Yes — the loader is one function per table |
| 2026-09-10 | E opens a bench; the upgrade is a button inside it | E at a workbench spent the upgrade's materials directly, so the key you press to *look* at a bench was the key that spent on it, and the prompt never said how to reach the menu. Now E emits `open_bench` (the sim still knows nothing about screens) and UPGRADE is a priced button that goes through `Actions.upgrade_bench`, reach-checked on the host by tile like a chest. A Chemistry Station answers E the same way, because its recipes are on the bench screen and nowhere else. | Yes |
| 2026-09-10 | By hand is exactly six recipes, and the Stone Hammer is no longer a portable bench | The owner's call: C is what you need before you have a base — Bandage, Hatchet, Stone Knife, Stone Pickaxe, Stone Hammer, Torch. Bow, Arrows, Scythe, Cloth, Compost and the first clothes moved to bench 1. The hammer's privilege (lifting a few bench-1 recipes into the field) would have put them back in C, so it went with them; the `hammer` recipe flag was deleted rather than left inert. Notion's *Crafted at* was moved for the seven rows. | Yes — `bench` numbers in `RECIPES` |
| 2026-09-10 | Nothing is built on litter | A loose stone, a bush or a thicket does not block its tile, so a wall went up on top of one and it lived on inside the wall, gatherable and drawn. `can_place` refuses with *Pick up the stone first* (named from the prop), and `Structures.make` removes any non-solid prop under a new piece through `remove_prop` — for saves made before the refusal, so the tile lands in `chopped` for good. There was never a litter respawn: the stone had simply never been removed. | Yes |
| 2026-09-10 | Night was deepened by scaling the curve, with `DARKNESS_FULL` scaled to match | The owner found night bright and a lit torch invisible; the photographs agreed — the lit torch was barely distinguishable from the ambient. Every key of `DARKNESS_KEYS`, `DARKNESS_FULL` and `DARK_ENOUGH` was multiplied by the same 1.17 (peak 0.82 → 0.959), so `k` — what spawns, sense, speed, Threat and Mutation read — is unchanged at every moment and only the picture moved. The torch went from 200px at 0.8 to 300px at 1.15. | Yes, one factor |

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
| 5 | Online co-op | Built 2026-09-09 — **owner plays with a friend** |
| 6a | Mutation: the meter, the bands, brains, the first two doses | Built 2026-09-09 — **owner feels the bar** |
| 6b | Chemistry Station, the deeper doses, the Lurch, food and drink, human raiders | Built 2026-09-09 — **owner meets the living** |

### Next up

0. **Hand the garden to the crew.** The Farmer job: a fifth `JOBS` row and a
   `_farmer_step` beside `_scavenger_step` — walk to the driest planted bed in
   the base, water it **out of the shared stash** like every other thing a
   survivor consumes, harvest what is ripe, haul it back, and replant from the
   stash's seeds. The framework is already there (a walk with a give-up timer,
   a timed job, a haul to the stash) and every seam in `Farming` is left open
   for it, so this is a job row and about a hundred lines, not a system. It is
   also the third of the three rules farming was allowed on, so it is not
   optional in the long run. The questions it brings: is one Farmer enough for
   four beds; does a Farmer drinking the stash's Clean Water read as sensible
   or as theft; and should they replant automatically or leave the bed empty
   for you to decide.
0. **Should the shared stash have a reach?** Raised by Codex against farming
   on PR #24, and it is not a farming question: `PlayerSim.total_res` has
   added `sim.stash` with no distance test since Phase 3, so a Steel Wall, a
   repair, a Machete and a Medkit are all payable from a stash on the far
   side of town. It is either a deliberate convenience that should be written
   down as one, or a hole that wants closing in `can_afford` / `spend` for
   every system at once — but not in one system, because "I can build a wall
   out here but not water a bed" is a worse rule than either. The knock-on if
   it closes: an outlying bed genuinely becomes a thing you carry water to,
   which is a nicer shape and a real cost in walking. Owner's call.
0. **Does a garden feel like a supply line or like a window box?** The farming
   gate, and the numbers most likely to want moving. A potato is one in-game
   day and corn is two; a full bed dries out over a day and a half, which is
   thirteen minutes of play. The questions: is watering something you do
   walking past, or something you resent; is a dry bed *stalling* obviously
   better than a dry bed dying, or does nothing-happens read as broken; is
   four Corn for eight Rations worth two days of a bed; is two Medical an
   in-game day enough to matter without making a pharmacy pointless; and is
   Mutagen Sludge a bet anyone takes — is more food ever worth the brain
   matter that keeps you human? The dev menu has `Ripen and fill every raised
   bed`, so none of this needs eighteen minutes of watching corn.
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
1. **Is an interrupt worth carrying a heavy weapon for?** The stagger gate.
   A Sledgehammer takes 0.86s to swing and stops a walker dead for 0.9s; a
   Machete swings at 0.34s, stops nothing, and leaves it bleeding. That trade
   is the whole question, and the numbers most likely to move are the
   immunity window (2.2s — long enough that you cannot lock a walker, short
   enough that a crowd control weapon is still a crowd control weapon?) and
   the floor (0.12s, which is what makes a Behemoth immune: should a boss
   flinch at all?). The rest: does a stagger read at a glance in a crowd —
   arms down and body lurched back, against arms up for the wind-up — or do
   the two poses blur; is the Pump Shotgun's shove the "get off me" the
   design says it is; does 6 dps of bleeding on a Machete feel like anything
   next to 40 damage a swing, or is it a number you never notice. The dev
   menu has `Stagger and open up everything near you`.
1. **Does breaking a weapon read as tension or as a chore?** The wear gate,
   and the one most likely to want its numbers moved. A Hatchet is 140
   connecting swings and a tree costs two of them, so it is roughly seventy
   trees; a pistol is 600 rounds. The questions: does the first break arrive
   as a story or as an interruption; is a warning at 30% and again at 10%
   enough that it never surprises you; is *refusing* the right answer at zero
   or should a broken weapon still swing like fists; is half the recipe the
   right bill, or does mending want to be cheap enough that you never think
   about it. Two of a kind wear and mend separately — condition is on the
   weapon, not on you — so a spare Hatchet is a real answer to a broken one,
   and whether carrying that spare beats carrying the materials is the other
   question worth watching. The
   dev menu has `Wear what you are holding to a sliver` and `Mend everything
   you are carrying`, so none of this needs an afternoon of chopping.
1. **Meet the living.** Phase 6b's gate. Is a four-person Scavenger Crew a
   harder fight than twenty walkers or just a fiddlier one; does a Raider
   holding its distance read as cover-fighting or as running away; is losing
   your stash to a Looter a good story or an annoyance — and is the Lurch,
   at one every couple of minutes, frightening or irritating? The odds on a
   human raid (25% at TURNING, 55% at FERAL) are the number most likely to
   want moving. And the Experimental dose: is one Fever in four enough to
   make you think twice?
1. **Feel the bar.** Phase 6a's gate, and the one 6b is built on top of.
   Is 2.5 days the right length — does a
   full cycle feel like a supply line or like a countdown? Is one bite in
   seven at +12 frightening or annoying? Are the bands far enough apart to
   *feel* different, and is FERAL a bargain you would actually take: is
   +45% melee and being half-invisible worth 60% worse spread? Does the body
   tint read at a glance in a crowd, and is the bar in the right place — it
   is the main status but it is sitting third, under health and stamina.
   The dev menu has `+20 Mutation` and `Clear the Mutation meter` so none of
   this needs twenty-two minutes of waiting.
1. **Play it.** Phase 4 is done and none of it has been played by the owner.
   The outstanding feel questions are in `tasks/todo.md`; the biggest are
   whether night is dark enough to matter and light enough to play in, whether
   a level arrives often enough to feel earned, and whether the new minimap
   reveal radius makes Sixth Sense worth six Perception or just makes the map
   useless without it.
1. **Play it with somebody.** The co-op gate. On a LAN or a VPN today: the
   host clicks HOST THIS GAME, the guest types the host's address. Two
   copies on one machine also work (`127.0.0.1`). The questions: does a
   guest's walk feel like their own or like being dragged; does 48px of
   snap ever show; is twenty-eight seconds on the ground long enough to be
   rescued and short enough to hurt; does a shared stash make stocking it a
   decision between two people; is a raid with two guns fun or just short.
1. **Internet play across two home routers.** The cheap road is in:
   UPnP, through the engine's own `UPNP` class, no server. The owner's
   router has not answered it yet; the HOST page will say whether it did.
   If it says no, or a friend is behind carrier-grade NAT, the roads left
   are a VPN (no code) or the WebRTC GDExtension plus the prototype's
   `server/signal.js` broker on a free host — **already built**; the
   runbook is `tasks/switch-to-webrtc.md` (three steps and a test run).
   The one thing untested until the extension is fetched is bytes over a
   real WebRTC channel; `webrtc_slow_test` runs that leg on localhost the
   moment `WebRtcHub.available()` is true — see §6.
1. **The test budget.** The fast tier is ~20s against a ten-second rule.
   `save_test.gd` regenerates worlds and belongs in the slow tier, and
   `net_test.gd` opens a real UDP socket once; both are owner decisions
   because they change what runs on every commit.

### Deliberately not building

Thirst, hunger, temperature, illness, sleep, long crafting timers,
many ammo calibres, dialogue, quests, huge procedural
worlds, realistic electrics or plumbing. PvP, dedicated servers and
persistent shared worlds. Carried over from the prototype and still right —
with three amendments. Two from 2026-09-09: **Mutation is a meter and it
stays** (it is the one the whole theme hangs on, and food and drink are
buffs on top of it rather than bars of their own), and **factions are back
on the list** — hostile humans who come for a base whose owner has gone too
far are Phase 6b, because "the living turn on you" is half of what makes the
meter a bet.

And one from 2026-09-10: **farming comes off the list.** The list is against
*chores* — meters the game nags you about — and not against growing things.
A Raised Bed is allowed to exist because of three rules, and if any of them
ever stops being true the amendment should be reversed rather than argued
with: **a dry bed stalls and never dies**, so forgetting costs you time and
never the crop; **nothing is ever required**, so crops are buffs and cooking
inputs like the rest of the food table and no hunger field exists;
and **it is delegable**, which is what the Farmer job above collects.
`farming_test.gd` asserts all three, `test_nothing_here_is_a_hunger_meter`
most directly. The rest of the list stands, thirst and hunger included —
growing food is not the same promise as needing it.

---

## 8. Lessons

Distilled. The raw log is `tasks/lessons.md`; the prototype's full §8 is
summarised in `tasks/port-inventory.md`.

### A bug report describes an experience, not a cause

DL-46 said felled trees stay on screen and drop nothing; DL-55 said gathered
litter stays on the map. Neither reproduces. `remove_prop` clears the tile,
flags `gone` and unblocks; the smoke run now fells a tree and gathers a stick
with a photograph either side, and both are plainly gone with WOOD +11 and
FIBER +3 over them.

What does reproduce is the *experience*, and the smoke run hit both by
accident while being written:

- Two hundred axe swings took a tree from 470hp to 387, because the aim had
  been set once before the camera settled and nearly every swing hit air. The
  player faces the mouse. A swing that misses a tree is completely silent —
  there is no way to tell it from a swing that is not working. That is DL-46.
- The gather step failed with "E offers 'vehicle', not a gather". Gathering is
  offered last by design, so a car or a shelf nearby takes the key and the
  stick stays on the ground. That is DL-55.

Both are readability, not removal, and neither is visible from the code or
from a headless test that calls `chop_prop` directly. **Reproduce a report
through the same surface the reporter used** — the mouse, the key, the
screen — before deciding it is wrong.

### The smoke's flakiness was never "load". It was window focus.

For two phases the smoke run has failed a few times a session, in different
places each time — repair, then demolish, then a save round trip, then a
pistol that would not kill a walker — and it was written up as timing
fragility under load, because it always passed once the machine was quiet.

It is not load. **Half this script steers with `Input.warp_mouse`, which does
nothing at all on an unfocused window.** When the terminal or the editor
keeps the focus, the cursor never moves: the build ghost stays on whatever
tile it was over, the pistol fires at the last aim, the axe swings at air —
six failures, one cause, and none of the messages says "mouse".

The fix is two lines in `Smoke._run`: `window_move_to_foreground()` and
`grab_focus()`, with a failure if the focus never arrives. Every checkpoint
is reached now where runs used to stop at 55 of 61, and the build ghost's
failure message carries the cursor position and the focus flag so the next
one is diagnosed in a line rather than an hour.

The general lesson is the one above, from the other side: a harness that
drives real input inherits every constraint real input has. **When a
scripted-input test fails somewhere unrelated to what it was testing, suspect
the input, not the game.**

### A test that passes because of the bug

The smoke run stood the player at `(container.tx, container.ty + 1)` to search
a container. For the nightstand it picks, that tile is the *wall*: `unstick`
shoved the player outside the building and the search worked anyway, through
it. Fixing the wall-looting bug broke the test, and five more steps cascaded
off it. A test whose setup relies on a bug will defend that bug, and it reads
as a regression when the bug is fixed. The five cascading failures were one
root cause; the temptation to revert was strongest at exactly the wrong moment.

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

- **A snapshot that fits a Dictionary does not fit a datagram.** Two player
  records as Dictionaries were 500 bytes each; the engine's MTU warning in
  the socket test was the only thing that said so. Measure the packet, in a
  test, against the number the transport cares about. (2026-09-09)
- **Read what arrived before judging the line.** A refusal is followed by a
  hang-up, and a guest that checked `is_open()` first reported "the host
  closed the connection" instead of "wrong password". Same on the host: a
  `bye` and the drop arrive together, and "left" is the truer word.
  (2026-09-09)
- **A `RefCounted` pair that point at each other leak.** Loopback ends and
  hub↔link both did; `close()` breaks the cycle. The leak was a warning at
  exit, not a failure, which is exactly how it would have shipped.
  (2026-09-09)
- **Polling a hung-up ENet peer is an engine error.** `poll()` on a peer
  whose status is DISCONNECTED logs an error every frame; check the status
  first. (2026-09-09)
- **`--headless` cannot run the smoke.** `checkpoint` awaits
  `RenderingServer.frame_post_draw`, which never fires without a renderer,
  and the run hangs at the first one. Xvfb runs the real windowed smoke on a
  Linux box with no screen. (2026-09-09)

- **Anything a headless run writes under `user://` needs its own path.**
  `user://` is shared with the game the owner plays, and three times in Phase
  4 a test or the smoke wrote into it — real save slots, the player's key
  bindings, the player's mute setting. Every such path is a `static var` the
  test or the smoke redirects, never a `const`. (2026-09-08)
- **Assert on what the code decided, not on what fed it.** Three times in
  Phase 4 a test watched the thing feeding the code rather than the choice the
  code made — the bow had a sound cue and made no noise, while a test happily
  confirmed that firing a bow emits a `shot` event. Anything that maps an
  input to a choice should **return the choice** so a test can assert on it,
  and the check is to break the mapping and see whether anything fails.
  (2026-09-08)
- **An autoload must never share its name with a `class_name`.** The autoload
  registers a global holding the *instance*, which shadows the class; under
  `godot --headless -s` there is no autoload, so the name resolves to a bare
  GDScript resource and every static call on it fails with "nonexistent
  function". `Bindings`/`KeyBinds` had already established the pattern and
  `Sfx` hit it again anyway — the autoload is `Audio` now. (2026-09-08)

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
tests: 368  asserts: 5041  failures: 0
tests: 401  asserts: 5174  failures: 0   (--all)
SMOKE done checkpoints=48 failures=0 exit=0
```

On Linux (the remote session that built Phase 5 ran on one): set `GODOT`
to a Linux 4.7.2 binary and run `tools/test.sh`; the smoke needs a display,
and `xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-driver opengl3 -- --smoke --smoke-out=$PWD/.smoke`
is what ran it there. `--headless` hangs the smoke: `frame_post_draw` never
fires without a renderer.

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

### Editing content — `data/` and `tools\edit`

Content lives in `data/*.json`, one file per table: WEAPONS, RES,
CONSUMABLES, GEAR, RECIPES, STRUCTURES, LOOT, CONTAINERS, ENEMIES, CROPS,
plus `catalog.json` (every item, real or planned, with its category, class
and status — the game never reads it) and `categories.json` (the eleven
categories and fourteen weapon classes, each with what it is for).

- **The editor:** double-click `Content Editor.cmd` in the project folder
  (the same as `.\tools\edit.cmd`; `tools/edit.sh` off Windows). It starts a
  headless Godot on `http://127.0.0.1:8765/` and opens it. Loopback only;
  `--lan` shares it on the local network on purpose; it is never deployed.
  Views (Workbenches, Weapons by class, Materials, Tools, Ammo, Catalog) sit
  over the raw tables, and every item shows where it is crafted, found and
  used, with the odds per search.
- **A save is refused** unless the file decodes against its `fields`, the
  field list is unchanged, and nothing anywhere points at something missing
  (a recipe making a deleted weapon, a loot roll for a renamed item).
- **The format is `DataTable`'s** (`src/core/data_table.gd`): a `fields`
  schema, because Godot parses every JSON number as a float; sorted keys,
  one field per line, fixed floats, so a one-number edit is a one-line diff.
  Design comments are `notes` on the table or the row. A new or retyped
  field is a code change in a commit, not an editor change.
- **Art:** `art/items/<id>.png` (and `<id>_ground.png`), uploaded from an
  item's Look card. No file, the placeholder draws.

### Syncing content from Notion

Retiring: content now lives in `data/` and is edited with the tool above;
this procedure goes when Notion is archived (Phase 3 of the Linear move).

The owner designs content in Notion, on the **Items & Crafting** page under
DEADLINE (page `3d610d456b16816fbf35d781eeaccb11`). Three tables:

| Table | Data source | Mirrors in `data/` |
| --- | --- | --- |
| Items | `collection://23c90712-6033-4bf5-b835-114704efbdc6` | `WEAPONS`, `GEAR`, `CONSUMABLES`, `RES`, `RECIPES`, `STRUCTURES` |
| Workbenches | `collection://98144f5b-c2b1-475d-960e-0efbe4895f44` | the `bench` field on `RECIPES`. The rows are Player Menu, Basic, Advanced, Tech, Recycle; the code today has only 0 = by hand and 1/2 = the one Workbench and its upgrade |
| Loot Sources | `collection://915ca948-b8e7-45a8-bca4-a3d621cf5e30` | `CONTAINERS`, `LOOT`, `HARVEST`, and `FURNISHING` via the `Where` column |

**The Items table is owner-facing, and its shape is not the code's shape.**
Eleven categories, each with its own tab: Building, Materials, Tools, Weapons,
Clothing/Armor, Consumables food, Consumables misc, Ammo, Medical Items,
Special Items, Misc Items. Weapons carries six melee classes (Improvised,
Blunt, Bladed, Axes, Polearms, Heavy) and eight ranged (Handguns, Shotguns,
Rifles, SMGs, Assault Rifles, Precision Rifles, Bows/Crossbows,
Heavy/Special). None of this is a `Config` key. `Building` is the pieces in
`STRUCTURES`; `Tools`, `Consumables misc`, `Medical Items` and
`Consumables food` all land in `CONSUMABLES` or `GEAR`. Map by `Code ID`,
never by category name.

Weapons also carry ten 1-5 design-intent ratings. They fall into three
groups, and the difference decides how much work a change to one is:

| Rating | Where it stands |
| --- | --- |
| Damage, Attack Speed, Reach, Knockback, Noise | **Already per-weapon** in `WEAPONS` as `dmg`, `cd`, `range`, `knock` and (guns) `noise`. A change here is a number. |
| Crit Chance, Stagger | **Built 2026-09-10**, and now per-weapon in `WEAPONS` as `crit` / `crit_mul` and `stagger`. The columns were blank (Crit Chance on every row; Stagger on all but two Planned shotguns), so the code's numbers were written first and all seventeen in-game weapon rows filled in from them — the ratings and the game agree as of that date, and a change to either column is now a real change to make. **On Stagger, 1 means the weapon does not interrupt at all**: only nine weapons stagger, and the scale had to say so rather than leaving a blank that reads as missing data. |
| Durability | **Built 2026-09-09**, and now per-weapon in `WEAPONS` as `dur` — a count of uses, with repair at the recipe's own bench. The Notion column is **blank on every row but one**, so the numbers in the code are the code's first guess; filling that column in and syncing it back is a real change to make, and it is the owner's call, not a sync's. |
| Stamina Cost, Cleave | **The mechanic exists; the per-weapon field does not.** A swing costs a flat `PLAYER.stam_swing` (2.0) whatever you hold; cleave is real but derived from the weapon's `arc` (`melee_targets` allows 6 targets over 1.4 radians, otherwise 3). A change here means making an existing system read a per-weapon value. |

Do not read a number in the bottom group as a spec to implement: it is a
small change to a system that already works, not a new feature, and confusing
the two in either direction wastes a phase. The two built groups are the
opposite — a number moved there is a number the game will use.

When the owner says **"look at Notion and update the game"**:

1. Query all three data sources (`notion-query-data-sources`, SQL mode) and
   fetch any row whose Notes look long. Read `Recipe` for quantities and
   `Ingredients` for the links; the two should agree, and a mismatch is a
   question for the owner, not a coin toss.
2. Diff against `data/*.json` by `Code ID`. Rows with a blank `Code ID` and
   `Status = Planned` are new content. Rows whose `Recipe`, `Crafted at`,
   `Found in` or `Breaks down into` differ from the code are changes. Rows
   marked `Cut` come out. On Loot Sources, `Rolls` is the `rolls` field on
   `CONTAINERS`, and **`Where` is `FURNISHING`** — the buildings a container
   is placed in. It is prose, and `FURNISHING` is weighted, so a building
   added or removed there is a real change to make while the weights stay as
   they are; a weight is a feel number and is not edited from Notion.
3. **Report before changing anything**: what will be built, what will change,
   and what does not add up (an ingredient with no row, a bench that is not in
   the game yet, a weapon class the code has no stats for).
4. Build it on a branch from `main`, as ever. A new *system* (a Recycling
   bench, a stamina cost on axes) is its own roadmap card and its own PR; a
   sync never smuggles one in.
5. Write back: fill in `Code ID`, flip `Status` to `In game`, and refresh
   `Stats` from the code. Stats are a mirror of the code, not a control — feel
   numbers are tuned by playing.

Notion owns *what exists, what it costs, where it is made and where it is
found*. The code owns *how it behaves*. The tables were seeded from
`config.gd` on 2026-09-09, so the first sync should find nothing to do
except the Planned rows.

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
| 2026-09-10 | **The owner's first playtest — nine notes, nine fixes.** **Mutation** fills untouched in 7.5 in-game days rather than 2.5 (about sixty-seven minutes), and a bite is one hit in ten at +6 rather than one in seven at +12. **Night** is near-black: the darkness curve, `DARKNESS_FULL` and `DARK_ENOUGH` were all scaled by 1.17 so every night multiplier fires exactly when it did, and the torch is 300px at 1.15 — the before photograph showed a lit torch you could barely see. The HUD's dark hint is readable and says the next step (*wear a Torch in your off-hand, then T*). **E at a workbench opens it** instead of spending on the upgrade: a BENCH mode of the pack screen at that bench's tier, titled WORKBENCH / WORKBENCH II, with a priced UPGRADE button through the new `Actions.upgrade_bench`; a Chemistry Station opens the same way. **C is by hand only** — Bandage, Hatchet, Stone Knife, Stone Pickaxe, Stone Hammer, Torch — and seven recipes moved to bench 1, in `config.gd` and in Notion; the Stone Hammer's portable-bench privilege is gone. **Wear**: a chop costs one use rather than two, and the five stone tools have 600 rather than 140-160, so a Hatchet fells about a hundred trees (measured off the swing: six chops a tree). **Click food to eat**: a click that does not drag opens a small menu beside the cell — EAT, DRINK or USE by an optional `verb` on the consumable, and DROP; right-click still uses directly. **Nothing is built on litter**: placement refuses with *Pick up the stone first*, and a piece loaded over litter from an older save clears it for good. `playtest_test.gd` (11 tests); two new smoke checkpoints (the workbench menu, and the bench after UPGRADE); the chem leg now opens its station with E |
| 2026-09-10 | **A seed, some water, and a few days — the Raised Bed.** Farming comes off §7's "deliberately not building" list, the third amendment to it, because that list is against *chores* and not against growing things. Three rules make a garden allowed, and `farming_test.gd` (27 tests) asserts each: **a dry bed stalls and never dies** — nothing anywhere takes a planting away, so forgetting costs time and never the crop; **nothing is ever required**, so crops are buffs and cooking inputs like everything else in the food table and `test_nothing_here_is_a_hunger_meter` says so; and **it is delegable**, which the Farmer job collects next. `Config.FARM`, `CROPS` and `FERTILIZER`; `raisedBed` in `STRUCTURES`, not solid and deliberately not `protect`; `src/sim/farming.gd` as the whole mechanic, with four fields on the structure and **the stage never stored** — derived from `grow`, so a save, a wire packet and a screen cannot disagree about what is in the ground. Water is Clean Water out of your own pack, the same bottle that buys Hydrated, so *drink it or grow with it* is the decision the bed poses; one bottle is half a tank and a full bed dries out over a day and a half. Three crops and each is a reason: potatoes are the staple, **corn becomes Rations** and Rations are what the crew eats out of the shared stash, **herbs become Medical** at two an in-game day against a pharmacy's eight to sixteen. Every harvest hands a seed back, and seeds are in five loot tables, so a farm can neither dead-end nor be bootstrapped from nothing. Two fertilizers, both yield: Compost by hand at +60%, and **Mutagen Sludge at the Chemistry Station** — brain matter for +150% and 40% faster, that bench's second job and this game's own bargain in a vegetable patch. `E` at a bed is contextual the way the generator key is: a ripe one harvests where you stand, anything else opens a fifth mode of the pack screen with two typed slots and the meters. Destruction loses the planting and salvage returns it. Save v11, four fields on the structure diff, four `Actions` commands, a dev verb and four smoke checkpoints. Fixed in passing: the chem checkpoint had been asserting a recipe was on the *visible* craft page rather than offered at its bench, so it failed the day a recipe was added above it |
| 2026-09-10 | **Blunt things stagger, edged things bleed, and crit comes off the weapon.** Three systems and one sentence of content design. **Stagger** is `stagger` seconds per weapon, resisted by the `knock_resist` that already scales knockback — no second table — and it clears the enemy's `windup` and everything it had picked out, without refunding `atk_cd`: the swing you took away is what you bought. A staggered enemy does nothing at all, Raiders and Looters included. Two rules make it work: a **floor** (`STAGGER.min`, 0.12s) that leaves a Behemoth at 0.95 resistance shrugging off a Sledgehammer with no line anywhere naming a Behemoth, and **`STAGGER.immune`** (2.2s after recovery), without which a 0.28s Stone Knife holds a walker still for ever — it is also what makes a shotgun's eight pellets one shove rather than eight. **Bleed returns** on exactly the three weapons it was cut from on 2026-09-08, on the terms the decision log set: `bleed` dps for `BLEED.time`, no stacking (the deepest cut wins and refreshes), flat from the weapon rather than scaled by `melee_mul`, and carrying who opened it so a body that drops seconds later still pays the right person. It is spent inside the enemy loop that was already running, so unlike fire it needs no scan of its own. **Crit stops being hard-coded**: `crit_chance + 0.06` at 1.9x for melee and `crit_chance` at 1.8x for guns meant a Stone Knife and a Sledgehammer critted identically. Now `Combat.crit_chance` and `Combat.crit_mul` are the only answer, summing the player's half (Luck — which also gains `crit_dmg` — perks, gloves, the Mutation band, the effect clock) with the weapon's `crit` and `crit_mul`, which pull opposite ways: rifle 0.15 at 2.5x, sledge 0.02 at 2.8x. Gloves are the only gear that carries crit and `MAX_CRIT` is clamped once at the end of the recompute, because the band and the effects land after gear. Protocol 4 for one bit each on the wire; `stagger_test.gd` and `bleed_test.gd` (36 tests, 515 fast / 551 with `--all`), crit assertions in `combat_test.gd`, a dev verb and two smoke checkpoints. **The numbers were the code's first guess and Notion's Crit Chance and Stagger columns have been filled in from them** — blank before on every in-game weapon. Fixed from Codex's review of PR #23: a closed wound left its rate and its owner behind, and since a fresh cut keeps the *higher* of the two rates, the next one was measured against a wound that had already finished — a Stone Knife opening something a Machete had bled dry inherited the Machete's 6 dps and credited it the kill. `tick_bleed` clears both as the clock passes zero, and the fields now mean nothing unless `bleed_t` is above it |
| 2026-09-10 | **Condition moved from the player to the weapon**, from Codex's review of PR #22. The first cut kept `PlayerSim.wear` as weapon id -> uses left, beside `mag`, and that leaked four ways: a broken weapon left in a chest came back whole to the next person to open it, a **freshly crafted weapon was born broken** because the last one of its kind had been, the free repair the death drop is careful to prevent was one deposit away, and two of a kind could never be told apart. A `Slots` stack now carries an optional `w`, so condition travels with the weapon through chests, car boots, the ground, other players' packs, the save and the wire — and an unset slot is a whole weapon, which is what makes a crafted or scavenged one arrive new with nobody arranging it. Cheap in practice: weapons are stack-limit 1, so no merge ever has to decide what two joined conditions are, and `Slots.move` already moved a whole stack dictionary. The death drop is the one place it still flattens, because `held` is a flat id -> count — it keeps **the worse of two**, so flattening can never mend. Repair is addressed by slot rather than by id, which is also what stops a guest naming a weapon it is not carrying. Second finding, also Codex's: **a broken tool is not a tool** — a zero-condition Stone Knife no longer cuts cordage and a zero-condition Stone Hammer is no longer a portable workbench, and nothing deadlocks because every tool recipe and every tool's own recipe is bench 0. `wear_test.gd` is 32 tests, nine of them the transfer paths that were wrong |
| 2026-09-09 | **Weapons wear out and benches mend them.** `dur` on every weapon in `WEAPONS` as a count of *uses* — one connecting swing, one shot — and `Wear` as the only thing that writes it, kept per weapon id beside `mag` for the same reason `mag` is (a slot is `{id, n}`; two Hatchets share one condition, and that is the accepted cost of the slot model). A swing at air is free; **felling a tree costs a tool twice what a walker does**. Nothing degrades on the way down: one warning at 30%, one at 10%, a condition sliver on the hotbar, and then it is **broken — refused, not destroyed and not quietly worse**, because it is the thing you carry back to the bench. Mending is a share of the recipe scaled by the wear (0.5, main material always ≥ 1) at **the recipe's own bench** — `Crafting.bench_reason` split out of `status` so the gate cannot drift, which makes a Hatchet mendable by hand and a Machete not, for free and forever. MEND rows sit above the recipes on the CRAFT tab (a different verb to the build bar's REPAIR on purpose). A weapon nothing makes is mended nowhere, which is what a unique found-only weapon will lean on — **no such weapon exists yet**. Wear travels with the save (v10), the guest's pack diff, and the backpack you drop when you die, without which walking back to your own corpse would be the cheapest bench in the game. Repair goes through `Actions` like every other screen command. Two dev verbs, `wear_test.gd` (23 tests) and two smoke checkpoints. **The sixteen `dur` numbers are the code's first guess: Notion's Durability column is blank on every in-game weapon** |
| 2026-09-09 | **The chemistry, the living, and losing control** (Phase 6b). A **Chemistry Station**: the first bench that is not a rung on the workbench ladder, gated by `station` rather than by `bench`, so no amount of upgrading ever produces a suppressant. The chain finishes — Refined −50, and **Experimental −75**, which always pays ninety seconds of Surge and charges a Fever one time in four; the Fever turns you *faster*, so the risk is on the same axis as the reward. **Food and drink arrive as a full table and as buffs only** — nine items, six effects, no hunger meter under any of it and a test that asserts no such field exists. Hydration is what finally writes `mut_rate_mul`. `F` eats the commonest thing that would help; right-click in the pack uses what you clicked, through `Actions`. **The Lurch**: at FERAL your legs stop being yours for a second and a half every couple of minutes, the intent is rewritten rather than guarded, and a guest hands the body to the host for the duration. And **the living**: Looter, Raider and Enforcer, a raid track of their own rolled against your Mutation band (never at HUMAN, 55% at FERAL), hostile bullets that look for people instead of enemies, a `standoff` a rifleman keeps and a shotgun closes, and a Looter that empties your stash and runs for the edge — kill it and you get it back. They carry no brain matter: killing people is never a way to hold the meter down. Two new test files (47 tests) and five more smoke checkpoints. Save v9, protocol 3 |
| 2026-09-09 | **The theme moved: Mutation is the main status** (Phase 6a). The player was bitten before the first frame, there is no cure, and brain matter is what holds the change back — so the meter you manage runs through the horde. 0–100, a full cycle in 2.5 in-game days, faster in worse districts and in the dark, and moved by teeth: one zombie hit in seven is a bite. Three bands (HUMAN / TURNING / FERAL) whose modifiers live in `Config.MUTATION.bands` and reach the player through `recompute_stats` and nowhere else; a **band change** is the only thing that triggers a recompute. FERAL is the bargain stated plainly: +45% melee, +12% speed, half the stagger, sensed at 0.6× the radius — and 60% worse spread and a worse gun multiplier. At 100 you turn: your own banner, and you come back at 55 rather than 0. Kills drop brain matter by what the body was (Walker 45% Raw → Behemoth always Neural Tissue), once per corpse whatever the loot perks say. Raw is −10 and Nausea; a Workbench makes the Stabilized Neural Serum, −30 and clean. `G` picks the dose that fits the hole. `Config.EFFECTS` is one table for every buff and debuff, ticked on the player and applied inside the same recompute. Save payload v8, snapshot stride 20 plus a fourth string for the effect clocks, protocol 2. Pillar 1 rewritten (the pillar was never "no meters", it was "no chores"), invariant 4 extended, invariant 9 added, `mutation_test.gd` (29 tests) and three smoke checkpoints |
| 2026-09-09 | Notion catalogue restructured to the owner's taxonomy. Eleven categories replace the first seven, each with its own tab on the Items table: Building (needs no bench, and is where a bench is crafted), Materials, Tools, Weapons, Clothing/Armor, Consumables food, Consumables misc, Ammo, Medical Items, Special Items, Misc Items. Weapons split into six melee classes and eight ranged, with the ranged identities written down (handgun as backup, shotgun as "get off me", bow as the quiet answer rather than a worse gun) and **noise as a first-class weapon stat**. Ten 1-5 design-intent columns added. Five are already per-weapon in `WEAPONS`; Stamina Cost, Crit Chance and Cleave name mechanics that exist but are not per-weapon (a flat `stam_swing`, a player-stat crit, cleave derived from `arc`); only Stagger and Durability are absent entirely. Codex caught the first draft calling all five missing, which would have sent a future pass rebuilding combat systems that already work. The benches became Player Menu, Basic, Advanced, Tech and Recycle, and each is now also a buildable row under Building. 19 rows added: the ranged weapons the owner enumerated, plus the four benches. 117 item rows, 42 of them Planned. Renaming a Notion select option drops the value on every row that held it, so all 98 existing rows were re-mapped from a dump taken first; §10 gains the taxonomy note |
| 2026-09-09 | Bugfix round one, from the Notion 🐞 Open bugs view. **DL-45**: a tap of E beside a car opened the boot instead of driving — `interact_held` is already true on the frame `interact` fires, so the vehicle branch read every press as a hold and tap-to-drive had been unreachable since it shipped; the choice now waits out `Config.PLAYER.boot_hold` on a `car_hold` channel. **DL-45 (body)**: containers could be searched through a wall; reach now needs sight as well, using the rule bullets use, counting only tiles strictly between and exempting touching tiles. **DL-42**: 135 litter props on road and pavement tiles — `_plant_litter` had no surface policy, so the camp starter-cache planted on kitchen floors; `Config.LITTER_SURFACES` is now the one table and is enforced inside the planter. **DL-43**: zombies spawned inside the base because nothing knew what a base was — `Config.BASE.radius` and `Structures.in_base()`, anchored on every piece marked `protect`, excluded from ambient spawning (raids are untouched). **DL-56**: a dev menu behind F1, built only in a debug build or under `--dev`. **DL-46 / DL-55 do not reproduce** — see §8. 19 new tests (386 fast), 4 new smoke checkpoints |
| 2026-09-09 | **Content catalogue in Notion.** Three linked databases under DEADLINE → Items & Crafting, seeded from `config.gd`: Items (every weapon, armour piece, ammo, consumable, material, utility item and structure — 98 rows, 27 of them the planned melee weapons — with recipe, bench, loot sources, recycling output, stats and status), Benches (Hand plus the planned Wood Work Bench, Scrap Work Bench, Tech Bench and Recycling, each in-game recipe placed on the bench it will move to), and Loot Sources (all 30 container kinds, 6 harvest scenery kinds, car trunks and stripped cars, with which buildings they furnish). Ten views on Items: Weapons by class, Armor by slot, Ammo & Consumables, Materials with what they are used for, Structures, By bench board, Craft by hand, Findable, Planned, Everything. The 27 melee weapons from the owner's class list (Improvised, Blunt, Bladed, Axes, Polearms, Heavy) are in as Planned. No code change; §10 gains the sync procedure |
| 2026-09-09 | Phase 5 Codex pass on PR #15: intent **edges travel on the reliable channel** as their own message (`msg_edges`), once, and the state packet carries held state only — a dropped datagram no longer swallows a press and a duplicate cannot toggle a gate twice; **seats belong to who is present**: a parked character gives its seat up to a newcomer and gets one back on return, so three absent friends cannot make a game "full"; `open_boot` names its seat and is gated like `open_store`; an emptied boot sends one empty record so a guest's copy clears; automated kills and raid payouts pay `present_players()` only. Also: the test runner now fails a file that loads but cannot instantiate (a parse error had been counting as zero tests, zero failures — `net_test.gd` vanished from a run that reported green). 7 new tests |
| 2026-09-09 | Phase 5, the room-code road (off): `PeerHub` — the `MultiplayerPeer`-behind-`NetLink` half of `EnetHub` pulled out as a base, with the "no answer" text reserved for a dial nobody answered; `EnetHub` extends it; `WebRtcHub` — rooms and joins over `WebRTCMultiplayerPeer`, signalling over `WebSocketPeer` to `server/signal.js`, room codes, gid→peer id, a connection factory, `available()`; `server/` — the prototype's broker with a `package.json` and a README for free-tier hosting; `tools/fetch-webrtc` for the native extension into gitignored `addons/webrtc/`; `Config.NET.broker`, `stun`, `rtc_timeout`; the HOST page's ROOM CODE row and JOIN taking a code; `tests/support/fake_rtc.gd` and `fake_broker.gd`; `webrtc_test` (4, fast: the handshake through the real multiplayer peer) and `webrtc_slow_test` (1: the real broker under Node, and real WebRTC on localhost when the extension is present) |
| 2026-09-09 | Phase 5, the door: `NetDoor` — UPnP port mapping on a thread when hosting starts, the public address queried and shown on the HOST page as a click-to-copy row, the LAN addresses beside it, refusal reasons in words, and a close that never blocks on a router (an unfinished discovery is orphaned, reaped from `_process`, and takes its own mapping down); `Config.NET.upnp`, `upnp_timeout_ms`, `upnp_lease_s`; `door_slow_test.gd` (2 tests, slow tier: discovery on a box with no router takes eight seconds to say so) |
| 2026-09-09 | Phase 5 (co-op) — **every phase built**: `Config.NET`; `src/net/` — `NetProtocol` (framing with zstd over 900 bytes, packed intents with edge merging, flat-array snapshots, structure and inventory records, the join refusal), `NetLink` with `Loopback` (lossy, reordering, seeded), `EnetHub` over `ENetMultiplayerPeer`, `NetHost` (admission by identity, intent expiry, snapshots at 20Hz, inventory and store diffs, world diffs, event relay by interest), `NetGuest` (the mirror via `SaveGame.apply`, prediction with `PlayerSim.move`, easing, cosmetic tracers, the roster), `Actions` (the command seam the pack screen now calls) and `NetPrefs`; `PlayerSim` gains identity, away, downed, down_t and reviving; `GameSim` gains join, park, unpark, present players and `has_teammate_for`; `Damage` gains down, bleed-out and revive; `Interact` offers a downed teammate first and runs the revive channel; `SaveGame` v7; `Equipment.move_stack` and `drop_stack` resolve a car boot by id (dragging in and out of a boot works now); `PlayerView` draws every player with names and the downed pose; the HUD shows teammates, the downed state and the revive bar; the map shows teammates; MULTIPLAYER, HOST and JOIN pages with typed fields; the host and guest loops in `main.gd`; 24 new tests (362 fast, 392 with `--all`) including a real UDP handshake on localhost and a 30%-loss loopback; three smoke checkpoints with a loopback guest joined, walked and parked. Fixed in passing: a felled tree kept being drawn until a reload |
| 2026-09-08 | Phase 4d (audio) — **Phase 4 complete**: `Config.SFX` (35 cues as recipes), `SFX_THROTTLE`, `SFX_RATE`/`SFX_GAIN`/`SFX_NEAR`/`SFX_RANGE`; `Sfx` — tone and filtered-noise synthesis rendered to PCM at boot rather than a graph per shot, a Chamberlin state-variable filter for the lowpass/highpass/bandpass with a per-sample cutoff sweep, a 24-voice pool, the per-kind rate limit, and mute persisted to `user://audio.json`; `SfxView` maps sim events to cues so `src/sim` never learns that sound exists; the gunshot rides the muzzle flash rather than the bullet, so a shotgun is one bang and not eight; distance falloff, which the prototype had none of; the hit event gained a `kind` so a pipe thumps and a bullet pings; SOUND on the pause menu and the title; 19 new tests (338 fast, 368 with `--all`); a smoke checkpoint that plays every cue and checks a voice actually started. The bank was 205ms at boot until the per-sample `exp` and `pow` became stepped multipliers giving the identical curve: 91ms. The autoload is `Audio`, not `Sfx` — an autoload whose name matches a `class_name` shadows the class, and under `-s` the name then resolves to a bare GDScript with no static methods, which is the second time this project has hit that |
| 2026-09-08 | Phase 4d (the map): `Config.MAP`; `MapScreen` — the corner minimap and the town map behind `M` off one `_draw`, a 320x320 one-pixel-per-tile ground image tinted by danger and cached on the generator's fingerprint (41ms, once per world), structures, packs, crew, enemies, the pulsing raid marker and the player's facing; district discovery in `GameSim` paying 25 XP per danger tier — the tenth XP site — with undiscovered districts drawn as `? ? ?`; `SaveGame` v6 carries what you have found, by id; **Sixth Sense loses its `needs` gate and `radar_mul` becomes a reveal radius**, which is a deliberate balance change from the prototype, where the minimap showed every enemy in the world and the perk did nothing; the debug readout moved off the corner the minimap now owns; 10 new tests (319 fast, 349 with `--all`); smoke opens the town map, buys the perk and watches the reveal widen. Two existing tests changed with it, both correctly: no perk carries a `needs` any more, and the raid test searched the notices for INCOMING instead of assuming it was first, because a discovery notice can now arrive on the same tick |
| 2026-09-08 | Phase 4d (the front door): `Saves` — six slots behind a small `user://saves/index.json` so listing six games does not parse six worlds, with the file as the truth about existence and the index as the truth about the summary, `latest()` preferring the slot last chosen over the one last written, and the play time and "3 hours ago" labels; autosave every two minutes for a game that has a slot, and never for one that does not; `KeyBinds` rewritten as static state on a `class_name` — full rebinding to `user://binds.json`, conflicts reported rather than refused, Escape reserved, unknown actions from an old file dropped, and every prompt built from `primary_label`; `MenuScreen` with TITLE, PAUSE, LOAD, CONTROLS and NEW GAME off one `_rows()` that is both the hit test and the paint, footer rows pinned so BACK cannot scroll away; `scenes/main.gd` boots to the title (except under smoke), Escape closes innermost-first and then pauses with the world frozen, and SAVE AND QUIT TO TITLE writes before it leaves; 21 new tests (309 fast, 339 with `--all`); 6 new smoke checkpoints — pause, CONTROLS, a key rebound, a save written, the title, and that slot loaded from it. The menu never repainted after a page change: the assertions passed because they read `menu.page`, and only the screenshot showed CONTROLS still on screen |
| 2026-09-08 | Phase 4c (vehicles): `CAR` in `Config`; `Vehicles` — about thirty cars rolled from their own per-spawn seeds, three ways into a locked one (a key planted in a nearby container, a lockpick that can snap and be heard, or Hotwire), arcade handling with speed-scaled steering, fuel, engine noise and Threat, roadkill credited to the driver, the 400-unit boot, refuelling, wrecking and stripping; a parked car blocks its tiles and a driven one does not, asking both collision maps; driving short-circuits the player tick entirely; a car key is learned rather than carried; `VehicleView`; `SaveGame` v5 stores only what a run changed about a car; Hotwire's `needs` gate comes off, leaving only Sixth Sense; 33 new tests; smoke finds a car, drives it and parks it. `plant_keys` buckets containers rather than scanning all six hundred per locked car — it ran on every `GameSim.start` and was five milliseconds of every test |
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
