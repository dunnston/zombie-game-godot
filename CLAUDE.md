# DEADLINE (Godot) — start here

**Read `PROJECT.md` first**, then `tasks/todo.md`. This is the Godot rebuild of
the browser prototype at `C:\Users\ryans\OneDrive\Desktop\AI Games\zombie-game`;
that repo's `PROJECT.md` is the design spec and is not edited from here.

## Facts that are expensive to rediscover

- Engine: Godot **4.7.2**, executable `C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe`
- Remote: https://github.com/dunnston/zombie-game-godot
- Unit tests: `tools/test.cmd` (headless, under ten seconds). Smoke: `tools/smoke.cmd`.
- On Linux: `GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 tools/test.sh`; the
  smoke needs Xvfb (`xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-driver opengl3 -- --smoke --smoke-out=$PWD/.smoke`). `--headless` hangs it.
- Co-op: `src/net/`. Host-authoritative over ENet on UDP `Config.NET.port` (27333). Guests mirror a `GameSim` and never tick it. Screens change shared state only through `Actions`. `NetDoor` asks the router to open the port over UPnP.

## If the owner asks to switch co-op to WebRTC / room codes

**It is already built.** Do not design or rewrite anything. Read
`tasks/switch-to-webrtc.md` and follow it: fetch the extension, deploy
`server/`, set `Config.NET.broker`, run `tools\test --all`. Triggers: "switch
to WebRTC", "room codes", "UPnP didn't work", "my friend can't connect",
"no port forwarding".
- The Godot MCP (`run_project`, `get_debug_output`) reads `GODOT_PATH` from `~/.claude.json`.
- **Content is designed in Notion:** DEADLINE → *Items & Crafting* (page
  `3d610d456b16816fbf35d781eeaccb11`) holds the Items, Benches and Loot Sources
  tables, seeded from `config.gd`. "Look at Notion and update the game" means
  the procedure in `PROJECT.md` §10, *Syncing content from Notion*: diff, report,
  then build. Notion owns what exists and what it costs; the code owns how it behaves.

## Invariants (carried from the prototype, still true)

1. Simulation classes are `RefCounted` and never touch nodes or `Input`. `Intent` is the only way input reaches them.
2. Static collision is one tile bitmap; player structures are a separate destructible map.
3. Bullets collide with terrain only. Water and fences: solid to feet, transparent to shots.
4. `recompute_stats()` is the only source of player stat modifiers.
5. Every tunable and content table lives in `config.gd`.
6. There is no pathfinding without give-up logic.
7. Container identity in saves is derived from tile position, never ordinal index.
8. A screen that changes shared state calls `Actions`, never a sim function directly: on a guest that is the command to the host.

## Design pillars

1. Survival without survival chores. 2. Danger is the only gate. 3. Fun over realism.
4. Readability over fidelity. 5. Every system ships finished. 6. Getting stronger makes the world more dangerous.
7. Build anywhere.

## Working agreements

- Test by running the game. Assert on outcomes.
- `tools/test.cmd` before every commit (`--all` and smoke once per branch).
- Branch, PR, review, merge. Update `PROJECT.md` before finishing any piece of work.
- The owner's feel feedback outranks the roadmap.

## Branching — `main` is the only merge target

**Every branch is cut from an up-to-date `main`, and every PR targets
`main`.** Run `git fetch origin && git checkout -b <name> origin/main`, and
open with `gh pr create --base main`.

This is a rule because it was already broken once: `phase-2-combat` was cut
from `phase-1-world` while that PR was still open, so PR #2 merged Phase 2
into `phase-1-world` instead of `main`. PR #1 had already merged, so `main`
stayed on Phase 1 while three more phases stacked on the wrong branch, and
untangling it took a fourth PR.

If work genuinely cannot compile without a branch that is still open, say so
out loud, stack it deliberately, and **retarget it to `main` the moment the
parent merges**. Never leave a PR pointing at anything but `main` silently.
Before opening a PR, check: `gh pr list --json number,baseRefName` — every
open PR should say `main`.
