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
| `assets/models/characters/player.glb` | Rugged Trailblazer | Mixamo, 66 joints, 15.8k tris | Walking, Running, Sneaky_Walk_inplace, Run_and_Shoot, Running_Reload, Roll_Dodge_1 (dash), Left_Short_Hook_from_Guard (melee), Collect_Object, Archery_Shot ×3, Block3, Slap_Reaction, Jumping_Down, Regular_Jump, Dead, sleep, Gangnam_Groove. **No Idle** — re-export with one; frame 0 of Walking holds until then |
| `assets/models/enemies/walker.glb` | Undead Clown Charge | Mixamo, 72 joints, 15.3k tris | Idle_02, Walking, Unsteady_Walk, Running, Left_Hook_from_Guard, Left_Slash, Heavy_Hammer_Swing, Step_Forward_and_Push, Hit_Reaction ×2, Gunshot_Reaction, Zombie_Scream, Dead |
| `assets/models/enemies/runner.glb` | Ravenous Undead Charger | Mixamo, 36 joints, 15.8k tris | Idle_02, Walking, Unsteady_Walk, Slow_Orc_Walk, Running, Left_Hook_from_Guard, Zombie_Scream, Dead, Fall_Dead_from_Abdominal_Injury |

All three: 1.70 m tall, feet at the origin, one mesh, one material, three
textures, glTF forward (-Z).

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

### Phase 1 — the Stage seam (PR B, 2D only, behaviour identical)

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

### Phase 2 — the first playable 3D stage (PR C)

`Config.STAGE := "3d"`.

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
