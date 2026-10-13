# Sprite pipeline — Blender skeleton, ComfyUI paint

> **Abandoned 2026-10-01 (owner).** The scripted puppet was rejected as
> "example blocks"; the repainted set as "comical ... abandon this idea."
> Kept as a record of what was tried and why it fell short. Nothing here
> was committed to `main`.

Owner's ask (2026-10-01): a repeatable workflow that turns an approved
character turnaround into sprite sheets, in the style of the Style Bible
(`zombie-game-style-bible.md`, art in `Zombie Game Art/Good`). Start with the
player, unarmed: idle, walk, run, dash. Then weapons.

## Facts that shape it

- Blender 4.3.1 is installed (`C:\Program Files\Blender Foundation\Blender 4.3\blender.exe`),
  runs headless with its own Python 3.11 + numpy.
- ComfyUI is installed at `C:\Users\ryans\ComfyUI` with SDXL (Juggernaut
  Ragnarok), IP-Adapter Plus SDXL, OpenPose ControlNet XL and an RTX 4080
  SUPER (16 GB). See the ComfyUI note below before running it by hand.
- Bible camera: 3/4 view looking down ~45°, light from top left, outline
  #2F292B, 2–3 hard tones per material, slate #2F3137 background. Five
  rendered directions (S, SE, E, NE, N); the engine mirrors the other three.
- Bible suggests a 128 px canvas for humans. On screen the player is about
  60–80 px tall (`Config.CAMERA.view_height` 580 at 1080p).
- The game has no jump. It has a dash (committed burst with i-frames). Dash
  replaces "jump" in the first set unless the owner wants a jump added.
- The player currently draws as circles in `src/world/player_view.gd` with an
  aim angle for the weapon. Hooking sheets into the engine is Step 5.

## The turn (2026-10-01, afternoon)

The scripted Blender puppet was shown and rejected: "example blocks ...
looks nothing like the reference, I would never use these in a game."
Right. Script-built geometry cannot reach the painted look. The owner said
"you can try it" to a repaint pass, and the test worked: the Blender render
is the skeleton (pose, camera, direction, silhouette) and the owner's
ComfyUI repaints each frame in the turnaround's style.

**Two stages, two commands:**

1. `tools\sprites <character> <animation>` — Blender, headless. Builds the
   jointed figure, keys the animation, renders five directions, packs strips
   to `art/render/<character>/` with a JSON sidecar (frames, fps, loop,
   feet anchor). Nobody looks at these as art.
2. `tools\paint <character> <animation>` — ComfyUI, headless. SDXL
   image-to-image at denoise 0.5 with IP-Adapter Plus holding the matching
   column of the approved turnaround as the style reference, one fixed seed
   per sheet. The render's alpha cuts the result out, grown two pixels with
   the background keyed out of the ring. Back views (NE, N) get a "seen from
   behind" prompt and a negative that forbids a face, or the model paints
   one on the back of the head. Writes game-ready sheets to
   `assets/sprites/<character>/` plus a 2x contact sheet on slate.

Measured: a frame paints in about 8 s on the 4080; an 8-frame cycle in
five directions in about 5.5 min. Denoise 0.7 loses the camera and flattens
the view to a front-on portrait.

## Layout

```
tools/sprites.cmd                 stage 1: .\tools\sprites.cmd player walk
tools/paint.cmd                   stage 2: .\tools\paint.cmd player walk
tools/sprites/
  common.py                       camera, light, toon materials, outline, render + pack, joint helpers
  characters/player.py            the jointed survivor; mannequin.py is the camera test
  animations/*.py                 turnaround, idle, walk, run, dash: sines on joint rotations
  paint.py                        the ComfyUI stage
art/blend/player.blend            written by --save-blend; open it to see the puppet
art/render/player/                stage 1 output (cel renders): the skeleton only
assets/sprites/player/
  player_walk_SE_8f.png + .json   bible naming: character_animation_direction_frames
  player_walk_contact.png         all 5 directions on slate at 2x, for review
```

**ComfyUI note.** Its `.venv` points at `C:\Python310`, which no longer
exists (the owner removed global Python), so `run.bat` fails. `paint.py`
starts `main.py` with miniconda's base Python 3.10 and the venv's intact
packages on `PYTHONPATH`; nothing in the ComfyUI folder is modified. The
owner can repair the venv for hand use by changing the `home =` line in
`ComfyUI\.venv\pyvenv.cfg` to `C:\Users\ryans\miniconda3`.

## Plan

- [x] **Step 1 — camera test.** Approved 2026-10-01: 45° down, 2 px outline,
      128 px canvas. `art/render/mannequin/camera_test_vs_reference.png`.
- [x] **Step 2 — player skeleton and repaint.** Puppet rejected as art, kept
      as the skeleton. Repainted turnaround in five directions:
      `assets/sprites/player/player_turnaround_contact.png`.
- [ ] **Step 3 — idle (6f loop).** Rendered and painted; owner to review.
- [ ] **Step 4 — walk (8f), run (8f), dash (4f).** Rendered and painted;
      contact sheets in `assets/sprites/player/`; owner to review.
- [ ] **Step 5 — engine hook.** `PlayerView` draws the sheet: 8-way facing from
      the move/aim angle, frame from sim time, mirror for W/SW/NW. Separate PR.
- [ ] **Step 6 — weapons.** Pistol held low (as in the turnaround), aim, shoot,
      reload, melee swing. Needs the pistol on the skeleton and "black pistol
      held low in his right hand" back in the prompt.
- [ ] Record decisions in PROJECT.md and the bible's *Open decisions*.

## Known rough edges

- Small costume details drift between frames (pocket count, shirt hem,
  boot cuffs). Invisible at 1x; visible on the 2x contact sheet.
- Hands sometimes paint as dark gloves in the S view.
- A faint halo can survive the key where the paint's background drifts far
  from slate. `HALO_KEY` in paint.py is the knob.
- The painted silhouette is clipped to the render's grown alpha, so hair
  tufts or a flared coat that the model adds are cut off. Intentional: the
  silhouette is the skeleton's, every frame.

## Notes from the build

- Blender's empty factory scene carries a `LineSet` with no line style;
  Freestyle's own script dies on it. `common.new_scene` removes it.
- View transform must be Standard, or palette hexes come out AgX-washed.
- Cast shadows are off: at 128 px they are blotches. Three ramp tones carry
  the form.
- Anything a few pixels wide (straps, eyes, beard) goes in the `detail`
  collection, which the outline pass skips; otherwise it is all outline.
- The camera reference is steeper than the painted turnaround, so the face
  would be hair. A fixed -18° tilt on a `skull` joint the animations never
  key cheats the face toward the viewer, as the turnaround artist did.
- One Blender render of a 1-frame turnaround takes about 40 s, mostly
  start-up and shader compile; an 8-frame cycle in five directions about
  two minutes. Several animations render side by side.
- IP-Adapter "style transfer" weight 0.8 with the per-direction turnaround
  column as reference holds identity across frames with a fixed seed.

## Review

Two approaches, one afternoon, both rejected by the owner on sight:

1. A jointed figure of script primitives in Blender, cel-shaded with a
   Freestyle outline. Reads as a toy, not a character.
2. The same figure as a skeleton under an SDXL image-to-image pass with
   IP-Adapter holding the approved turnaround. Individual frames were close
   to the reference's style; the set in motion read as a stiff puppet, and
   details drifted frame to frame.

What survived and could be reused: the headless Blender camera and packing
(`tools/sprites/common.py`), the headless ComfyUI driver (`paint.py`), and
the measured facts in *Notes from the build*.
