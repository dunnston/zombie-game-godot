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
