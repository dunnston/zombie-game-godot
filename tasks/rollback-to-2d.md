# Going back to 2D

The 3D conversion (2026-10-13, `tasks/3d-conversion.md`) was built so that
giving it up costs nothing. Three ways back, shortest first. Do the first
one; do the others only when the owner has decided for good.

## 1. Flip the flag (one line, no git)

```
Config.STAGE := "2d"      # src/config.gd
```

Both stages ship in the game. `Stage.pick()` reads `--stage=2d` /
`--stage=3d` from the command line, else this const. The 2D view code in
`src/world/` was never removed, so the game is exactly what it was: same
sim, same UI, same co-op, same saves. (Arrives with Phase 1 of the
conversion; until that PR merges there is only the 2D stage and nothing to
flip.)

## 2. Delete the 3D stage (one commit)

```
git rm -r src/stage/stage_3d.gd src/stage/*_3d.gd src/stage/actor_model.gd \
          src/stage/models.gd src/stage/units.gd src/stage/overlay_2d.gd \
          assets/models tests/units_test.gd
```

then drop `Config.STAGE`, `Config.CAMERA3D`, `Config.STAGE_UNITS` and the
`--stage=2d` argument in `tools/smoke.cmd`, and make `Stage.pick()` return
`"2d"`. The `Stage` seam itself (`stage.gd`, `stage_2d.gd`) is worth
keeping: `main.gd` is smaller for it and nothing in it is 3D.

Check the exact file list against the PRs on the Notion card *3D
conversion* — each PR's description says what it added.

## 3. The pristine game

```
git checkout -b <name> 2d-final
```

`2d-final` is an annotated tag on `main` as it was on 2026-10-13 (merge of
PR #70, `b7e61a6`), before any of this. The branch `2d` points at the same
commit so it shows in GitHub's branch list. Nothing is ever pushed to
either.

## What each conversion PR touched (keep current)

| PR | Added | Changed |
| --- | --- | --- |
| A — rollback point and the models | this file, `tasks/3d-conversion.md`, `assets/models/**` (LFS), `.gitattributes` LFS rule, `.gdignore` in the inbox folders, `zombie-game-style-bible.md`, `Zombie Game Art/` | `.gitignore`, `CLAUDE.md`, `PROJECT.md` |
