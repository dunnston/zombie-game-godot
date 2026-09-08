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
