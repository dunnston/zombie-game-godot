# Lessons (raw log)

Distilled into `PROJECT.md` §8. Append here first.

## 2026-09-08

- The global class_name cache is only rebuilt by the editor or `--import`.
  Headless runs after adding a `class_name` script fail with "Could not find
  type" until then. `tools/test` now always imports first (about 2s).
- Rewriting `project.godot` while the editor had the project open: the editor
  wrote back its in-memory copy and the owner saw "no main scene". Close the
  project before editing that file by hand.
- A bash heredoc holding a large markdown file tripped the shell parser once.
  Use the Write tool for documents; keep heredocs for short scripts.
- Checksum a ported system against the original when both are deterministic.
  One number proved the whole map; a mismatch would have localised the bug.
- `for x in [literal array]` leaves x a Variant; `var y := x.a + 1` then
  fails to parse and takes every dependent script down. Type loop variables.
- A smoke run must fail when it cannot find `smoke_run` on the scene; a
  script that failed to compile looks exactly like a scene with nothing to
  check.
- Comments in the prototype are claims. The sprint-winded comment described
  code that did not exist. Port the code, flag the gap.

## 2026-09-08 (Phase 2)

- `class_name Noise` collides with Godot's own Noise resource; the script
  compiles and every static call on it fails at parse time in the callers.
- `var x := a and dict.get(k, false)` is a Variant: "cannot infer the type"
  and the dependent script chain fails. Type it.
- `PackedInt32Array` stored in an `Array`: `arr[i].append(x)` appends to a
  copy. Use Array elements, or one flat packed array with indices.
- Parking the player 3000px away to keep it out of sense range put the
  test enemy past the 2400px cull. 1500px is the right distance.
- The prototype's spawner counted within 950px of a ring at 880–1300; a
  still player in tier 1 collected 26 enemies in 20s. Measured, not
  eyeballed: the test printed it. Count radius is now 1400.
- The prototype's "stuck" threshold (1.1px per step) was below a brute's
  walking pace. Relative thresholds for anything compared against speed.
- Trace before tuning: the 10.7s shack chase was a 22-tile path, not an
  oscillation. A per-second print of field distance settled it in one run.
- A 27ms Dijkstra with per-neighbour Variant arrays became a 1.6ms BFS with
  a padded byte grid and index arithmetic. In GDScript the inner loop's
  shape is the whole cost.
