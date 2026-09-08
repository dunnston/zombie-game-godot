# DEADLINE (Godot) — start here

**Read `PROJECT.md` first**, then `tasks/todo.md`. This is the Godot rebuild of
the browser prototype at `C:\Users\ryans\OneDrive\Desktop\AI Games\zombie-game`;
that repo's `PROJECT.md` is the design spec and is not edited from here.

## Facts that are expensive to rediscover

- Engine: Godot **4.7.2**, executable `C:\Users\ryans\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe`
- Remote: https://github.com/dunnston/zombie-game-godot
- Unit tests: `tools/test.cmd` (headless, under ten seconds). Smoke: `tools/smoke.cmd`.
- The Godot MCP (`run_project`, `get_debug_output`) reads `GODOT_PATH` from `~/.claude.json`.

## Invariants (carried from the prototype, still true)

1. Simulation classes are `RefCounted` and never touch nodes or `Input`. `Intent` is the only way input reaches them.
2. Static collision is one tile bitmap; player structures are a separate destructible map.
3. Bullets collide with terrain only. Water and fences: solid to feet, transparent to shots.
4. `recompute_stats()` is the only source of player stat modifiers.
5. Every tunable and content table lives in `config.gd`.
6. There is no pathfinding without give-up logic.
7. Container identity in saves is derived from tile position, never ordinal index.

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
