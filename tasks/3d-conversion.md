# The 3D conversion

> Owner, 2026-10-13: "I am thinking about switching to 3D." The sprite
> route to character art had failed (`tasks/sprite-pipeline.md`); a rigged
> model animates once and faces any way, which is the problem that killed
> the sprites. The owner now makes assets with Astra, Meshy, Tripo and
> Blender and drops them in `Meshy Models/`.

**The decision:** both stages live in the game behind `Config.STAGE`, and
3D work merges to `main` as it goes. `tasks/rollback-to-2d.md` is the way
back; `2d-final` is the tag. The 2D view code is deleted only once the
owner has chosen 3D for good.

## What the code already gives us

- The sim (`src/sim/`) never touches a node. Positions are 2D pixels,
  32 px per tile, 320 tiles square. Every 3D view reads it as-is.
- The UI (`src/ui/`) reads only the sim and screen-space mouse. It sits on
  a `CanvasLayer` and works unchanged over a 3D viewport.
- Co-op (`src/net/`) never touches a view.
- The world view is small: `src/world/` plus ~120 lines of `scenes/main.gd`
  that build it, follow the camera and convert the mouse.
- `TileArt` builds the terrain atlas at boot; `TerrainRenderer._paint` picks
  an atlas cell per tile. The 3D ground UVs into **the same atlas**, so the
  map looks identical in both stages.

## Decisions

- **Units.** 32 px = 1 m (`Config.STAGE_UNITS`). Sim `x` → 3D `x`, sim `y`
  → 3D `z`, up is `y`. A 1.70 m model is a 54 px person, which matches
  `PLAYER.r` 13 px. `Units` (`src/stage/units.gd`) is the one place this is
  written.
- **Camera.** Perspective, pitched about 50° (the bible's 3/4 view), south
  of the player looking north, so north is up on screen as it is in 2D.
  Distance set so the visible ground height matches `CAMERA.view_height`
  (580 px ≈ 18 m). Lead, follow, shake and the arena zoom-out carry over.
  Numbers in `Config.CAMERA3D`.
- **The flag.** `Config.STAGE`; `--stage=2d` / `--stage=3d` on the command
  line overrides it. The smoke passes `--stage=2d` so its checkpoints keep
  running on the stage they were written for, and has a 3D leg of its own.
- **Models in git via LFS.** `assets/models/**/*.glb` (`.gitattributes`).
  Tens of megabytes each, re-exported often: too much for plain history.
  GitHub's free quota (1 GB stored, 1 GB/month bandwidth) is ample.
- **Inbox folders are not the project's.** `Meshy Models/` is the owner's
  drop zone: gitignored, `.gdignore` so Godot does not import it. Game-ready
  copies live in `assets/models/` under game names. `Zombie Game Art/` is
  the reference art the bible points at: committed, `.gdignore`.
- **Enemy → model** is a view-side table in `src/stage/models.gd`, never
  content. Kinds without a model draw as a capsule in their 2D colour at
  their 2D radius.
- **Placeholders are allowed; nothing is skipped.** From the first playable,
  cars, survivors, bosses, props, pickups and structures all exist in 3D as
  coloured boxes and capsules of the right size, so the whole loop plays.
  Real meshes replace them one PR at a time as the owner makes them.

## The models (2026-10-13)

| Game name | Meshy export | Rig | Clips |
| --- | --- | --- | --- |
**Replaced 2026-10-13 by the Mixamo-rigged characters and the owner's own
clips.** The Meshy exports' own rigs and animations are gone; each character is
now its Mixamo auto-rig from the owner's packs, baked by `tools/build_anims.gd`
from `Meshy Models/Animations/` into a mesh-only GLB and a clip library:

| Game name | Character | Rig | Library | Clips (state → file) |
| --- | --- | --- | --- | --- |
| `characters/player.glb` | Rugged Trailblazer v2 | 52 bones | `anims/player.res` | idle, walk, run, jump (Locomotion); attack (Punching); hurt (Hit To Body); die, downed, dash (Pro Longbow: death back / forward, dodge forward); shoot, aim, rifle_idle / rifle_walk / rifle_run (Shooter); crouch, pistol_idle / pistol_walk / pistol_run (Pistol pack: kneeling idle, idle, walk, run); bow_idle / bow_walk / bow_run / bow_shoot / bow_reload / bow_equip / bow_disarm (Pro Longbow: standing idle 01, walk forward, run forward, aim recoil, draw arrow, equip bow, disarm bow); collect (Pick Fruit); throw. **No crouched walk, no swing with a weapon, no gun reload** |
| `enemies/walker.glb` | Undead Clown | 46 bones | `anims/walker.res` | idle, walk, run, attack, bite, bite_low, eat (zombie biting), scream, die, die2 (zombie dying), crawl, crawl_fast; hurt and getup are the Coach's clips, retargeted by bone name |
| `enemies/runner.glb` | Ravenous Undead | 34 bones | `anims/runner.res` | the same as the walker |
| `enemies/coach.glb` | Undead Coach | 52 bones | `anims/coach.res` | idle, walk, run, attack, hurt, die, wake, slam, charge_wind, charge_go, stun, throw, whistle, roar, agony, scream, shove |

All four: 1.70 m tall in real metres (the FBX importer's scale is multiplied
through the skeleton, skin and clips), feet at the origin, one mesh, one
material, one (albedo) texture, glTF forward (+Z). Root motion is held at the
first frame's X and Z in every clip (Y kept: a death drops the hips to 10 cm);
the distance it travelled is the clip's `speed` meta, which is what playback
is paced against. The Coach is drawn 1.5× a person.

**To change a clip or add one:** edit the manifest at the top of
`tools/build_anims.gd`, then `<godot> --headless --path . -s tools/build_anims.gd`
and `--import` (a script run alone sees the stale imported GLB).

## Asset conventions (for the owner's pipeline)

**Characters.** Fully clothed in their default outfit, empty-handed, no
backpack, no holster: those are props. A-pose (arms ~45°), legs slightly
apart, feet flat, symmetrical, facing forward. Hands in a loose half-curl
with the thumb off the palm, so a grip prop sits inside without finger
animation. Nothing touching anything (hands clear of thighs, hair clear of
shoulders, jacket close to the torso). Neutral face, mouth closed. No
dangling straps or scarves. Chunky stylised proportions: big hands, big
feet, slightly large head. Feed Meshy a front/side/back A-pose sheet on
flat grey, not the 45° top-down turnaround. Flat hand-painted textures with
no baked lighting. Retopology on; 10–20k tris; 1024 textures are plenty at
this screen size. **One skeleton for every humanoid** (player, survivors,
human zombies) so clips and props are shared; the Butcher gets his own.
Export GLB with the skeleton, real-world metres, feet at the origin.

**Weapons.** One prop each. Origin at the grip, barrel or blade along -Z.
Attached to `mixamorig:RightHand`; two-handed guns place the left hand by
animation.

**Armour.** Rigid props on bones, because layered clothing on generated
meshes is the hardest problem in the pipeline and reads as nothing at 70 px
on screen: head → `mixamorig:Head`; body (vest, over the shirt) →
`mixamorig:Spine2`; legs (knee/shin guards) → the `*Leg` bones; feet →
`*Foot`; offhand lights → `mixamorig:LeftHand`. Hands: a material tint, no
mesh. Origin at the point that meets the bone.

## Phases

### Phase 0 — rollback point ✔ (PR A)

`2d-final` tag and `2d` branch on `main`; `tasks/rollback-to-2d.md`; LFS;
the three models under game names; `.gdignore` on the inbox folders; the
style bible and reference art committed; this file; the CLAUDE.md trigger.

### Phase 1 — the Stage seam ✔ (PR B, #72; 2D only, behaviour identical)

`main.gd` stops knowing how the world is drawn.

- `src/stage/stage.gd` — `class_name Stage extends Node`: `build(sim)`,
  `rebuild()`, `set_local(p)`, `on_event(ev)`, `tick(dt)`, `frame()`,
  `repaint(tx, ty)`, `snap(pos)`, `focus(at, lead, zoom_mul, shake)`,
  `cursor_world() -> Vector2`, `to_screen(world) -> Vector2`,
  `view_radius() -> float`, `static func pick() -> String`.
- `src/stage/stage_2d.gd` — the view construction from `main._ready`, the
  Camera2D, `_update_camera`'s maths, `_set_local`'s view half; the view
  nodes stay public so the smoke legs that poke `lights` and `noise_lens`
  still can.
- `scenes/main.gd` — `var stage: Stage`; `camera.position = p.pos` →
  `stage.snap(p.pos)`; `get_global_mouse_position()` →
  `stage.cursor_world()`; `get_canvas_transform() * pos` →
  `stage.to_screen(pos)`; the per-view fan-out → `stage.on_event`,
  `stage.tick`, `stage.frame`.
- `LocalInput.gather(intent, cursor_world: Vector2, …)` instead of a node.
- `Config.STAGE := "2d"` lands here.
- Proof: the smoke's JSON state dumps before and after match checkpoint for
  checkpoint.

### Phase 2 — the first playable 3D stage ✔ (PR C)

`Config.STAGE := "3d"`. Built as planned with two changes: the ground is
one quad and a cell texture rather than a hundred chunk meshes (cheaper to
build and to draw), and the owner's first nine static props went straight
into `Structures3D` through `StaticModel.fit` rather than waiting for phase 3.

- `Units`: `to3(v2, h := 0.0)`, `to2(v3)`, `yaw(angle)`.
- `Stage3D`: `WorldEnvironment` + `DirectionalLight3D` following
  `sim.clock`; `Camera3D` as decided (cursor = ray ∩ plane y=0, `to_screen`
  = `unproject_position`).
- `Terrain3D`: `TerrainRenderer.cell_art(world, tx, ty)` split out of
  `_paint` and shared by both renderers; 100 chunks of 32×32 tiles as
  `ArrayMesh` via `SurfaceTool`, each tile a quad UV'd into `TileArt`'s
  atlas; WALL/ROOF as 2 m boxes (top from the wall art, sides a darker flat
  tone); fences 1 m; `repaint` rebuilds a chunk. Instances are tiles too.
- `Actors3D` + `ActorModel`: one node per living player/enemy, keyed by
  identity; GLB instanced, `AnimationPlayer` found, clip table per model
  (`models.gd`: idle, walk, run, sneak, attack, hurt, die, dash, reload,
  shoot); position from `Util.render_pos`, yaw from `angle`, state read
  from the sim exactly as the 2D views read it; hurt flash and burn tint
  as a material overlay; i-frame blink as visibility; seat ring and name
  over teammates; capsule fallback for kinds without a model; the weapon a
  coloured bar on `mixamorig:RightHand` via `BoneAttachment3D`.
- `Structures3D`: a box per piece keyed by tile, diffed each frame; walls
  2 m; `StructureView.COLORS`; damage darkens; the build ghost translucent.
- `Props3D`: trees as `MultiMesh` (trunk + canopy in `PropRenderer.CANOPY`),
  scenery/litter/wrecks small boxes, containers in `CONTAINER_PAINT`.
- `Pickups3D`, `Vehicles3D`, `Survivors3D`, `Bosses3D`: sim-sized boxes and
  capsules; boss telegraphs as flat ground quads (§8.4).
- `Fx3D`: tracers as `ImmediateMesh`, muzzle flash an `OmniLight3D` with a
  life, blood/sparks a `MultiMesh` of ground quads; names, bars and damage
  numbers on `Overlay2D` at `to_screen`.
- `Lights3D`: `OmniLight3D` pool (torch, fire, floodlight), `SpotLight3D`
  for the flashlight, radii from `GEAR.light`.
- Smoke 3D leg: boot; player `AnimationPlayer` playing; four compass walks;
  a walker and a runner teleported in with models loaded; aim, shoot, kill;
  a wall built; night with a lit torch. Screenshots at each.
- Tests: `units_test.gd`, `terrain_art_test.gd`.
- Bar: terrain under 500 ms at boot, 60 fps on the owner's 4080.

### Phase 3 — parity backlog (in the order it will be felt)

- Wall fade when a wall stands between the camera and you.
- The toon + outline shader (bible: 2–3 hard tones, `#2F292B` line).
- Weapon props on the hand bone from the owner's pipeline.
- Armour as rigid props (head, body, legs, feet, offhand).
- Real meshes for containers, trees, cars, structures.
- Survivors and the remaining enemy kinds as the owner generates them.
- Butcher and Coach.
- Day-night colour grading.
- The noise lens in 3D (F2 is 2D-only until then).
- **The decision.** Then `Stage2D` and `src/world/` go, and the tag is the
  only way back.

## Not in the first playable

Wall-occlusion fade, the toon/outline look, weapon and armour props, the
noise lens, an Idle for the player.
