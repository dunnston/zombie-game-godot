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

## 2026-09-08 (Phase 3a)

- A member initializer runs while its class is still loading. `var bag :=
  Slots.new(...)` on PlayerSim died with "nonexistent function 'new' in
  base GDScript". Build cross-class objects in `_init`.
- The unit tests never load a Control, so two parse errors in the pack
  screen passed a green test run and only appeared when the smoke run
  booted the scene. Any UI change needs the smoke run.
- `Input.action_press` sets action state without synthesising an
  InputEvent: `_unhandled_input` never fires, so the scripted Tab could not
  open the pack. Poll anything the smoke run has to press.
- Two classes that name each other in type annotations are fine, but the
  weight-capped add read better on `Slots` than on `Items` anyway. When a
  cycle appears, ask which side the function belonged on.
- A test that puts the player beside one container and asserts on *that*
  container is wrong: furniture stands shoulder to shoulder and the key
  goes to the nearest. Assert on what the sim chose.
- Regenerating the world per test costs a third of a second each. One
  private world, with `looted` reset between tests, kept the suite at 6.8s.

## 2026-09-08 (Phase 3b)

- Pass the structure map into collision rather than reading a global. Every
  test shares one generated World; a wall built in one sim would otherwise
  exist in the next.
- A harness that only checks the end state hides the middle. The compound
  siege "ended" every time — at the 300s backstop, which is a pass for
  `raid == null` and a failure for the game. A sixty-second progress print
  found an empty-shotgun reload bug in one run.
- Scripted mouse input needs the cursor warped, not just an event parsed:
  `_gui_input` reads the event, polled code reads the real mouse. Hold the
  button several frames so a physics step sees it, and re-aim in a loop
  when the camera leads toward the cursor.
- When the suite passes its time budget, split a tier rather than deleting
  coverage or quietly widening the rule.
- Dead ported code is worse than none: the prototype's "Container there"
  placement check cannot fire here, because a container already blocks its
  own tile.

## 2026-09-08 (Phase 3c)

- A fingerprint that guards a save has to describe the *generator's* output,
  not the live world. Taken live, felling one tree changed the collision
  bitmap and the prop count, and the save refused itself.
- A Control keeps whatever it last drew. The build bar used its own `open`
  flag and the scene stopped redrawing it when closed, so the cards stayed
  painted over the world. Set `visible` too and let Godot hide it.
- Build the return dictionary and then check you actually put every list in
  it: `players` was assembled and never added, and the load path reported
  "no players in it" — a good error message for a bug three lines away.
- The sim must not know about screens. `Interact` emits `open_store` with a
  tile; the scene decides that means a panel. That keeps the storage rule
  (reach-checked, every frame, by tile) in the sim where a guest's command
  will meet it too.
