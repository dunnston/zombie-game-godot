# Zombie Game Style Bible

As of 2026-10-01 · Ryan Dunn

Images are not embedded in this file. Where a reference image applies, its file name in the Good folder is listed so you can attach it directly.

---

## How to use this bible

Every asset in the game must look like it came from the same artist, at the same camera, under the same light. This document is the single source of truth for that look. When an image and this text disagree, fix the image.

**Golden rules**

1. One camera angle, one light direction, one outline weight, one palette. No exceptions.
2. Always generate from approved references in this bible, never from a fresh prompt alone.
3. Paste character descriptions word for word. Changing the wording changes the design.
4. Isolate everything: characters, props, effects and decals on flat backgrounds, never baked into scenes.
5. Test every asset at its real in-game size before approving it.
6. Rejected images never go into a prompt or a training set. AI tools copy what they see.

**Workflow for a new asset**

1. Find the asset type below and read its rules.
2. Open a ChatGPT conversation, paste the Setup Prompt from the Prompt Library, and attach the golden references.
3. Paste the matching template from the Prompt Library and fill in the brackets.
4. Check the result against the Approval Checklist at the end of this document.
5. Approved: save to the Good folder using the naming convention. Rejected: save to the Do Not folder with one line on what went wrong.

---

## Core style rules

The look is hand-painted, cel-shaded game art: bold dark outlines, hard-edged shading, muted colors, with fresh red blood and glowing yellow eyes as the only loud accents.

### Golden references

These four images define the style. Attach them (or the first three) to every generation conversation.

- `Overhead Zombie Walker.png` (basic walker)
- `Feral Zombie Runner Lunging Forward.png` (fast runner)
- `Raging Undead Butcher Overhead Assault.png` (butcher brute)
- `Zombie Coach Lunging Forward.png` (coach zombie)

These are style and mood references, drawn at a dramatic lunging angle. They set the rendering, not the in-game camera. The game camera is defined below.

### The rules

| Element | Rule |
| --- | --- |
| Rendering | Hand-painted, cel-shaded. 2 to 3 hard-edged tones per material (base, shadow, highlight). No soft airbrushing, no photoreal texture. |
| Outline | Bold, dark brown-black (#2F292B), never pure black. Same weight on characters, props and buildings. Ground tiles get thinner, softer lines. |
| Camera | 3/4 isometric view looking down at about 45 degrees. Ground reads as a diamond. Match the camera references on every in-game asset. |
| Light | One soft light from the top left. Shadows fall down and to the right. |
| Color | Desaturated and muted. Olive, gray-green, khaki and brown dominate. Saturation is reserved for blood, fire and eye glow. |
| Zombies | Olive or khaki skin, glowing yellow eyes, open mouth with sharp teeth, blood concentrated on hands, mouth, head wounds and clothing. |
| Humans | Warm natural skin, normal eyes, dirt and wear on clothes, only light blood. Never glowing eyes. |
| Gore level | Stylized splotches of flat red, not wet realistic gore. No exposed organs except the butcher's shoulder mass. |
| Background | Solid flat dark slate (#2F3137) for characters and props. Pure black (#000000) for glowing effects. Light gray for decals. |
| Text | Never any text, labels, logos or readable signs inside an asset. |

### Camera references

The in-game camera. Every character sprite, prop and building must sit at this angle and this scale.

- `9d6879ac-f49f-4256-9279-84b7573f800f.png` (male survivor and walker on asphalt)
- `d6458bb4-22c6-43f8-8d66-096bba86b40b.png` (alternate female survivor and walker)

### Color palette

Reference image: `Zombie Game Color Palette Swatches.png`

Hex values sampled from the approved swatch sheet.

| Group | Swatch 1 | Swatch 2 | Swatch 3 | Swatch 4 | Swatch 5 |
| --- | --- | --- | --- | --- | --- |
| Zombie skin | #C4B086 highlight | #A1996C base | #958E66 midtone | #54503F deep shadow | #694C47 bruise |
| Blood | #D34141 fresh highlight | #9D222A base | #841922 shadow | #5E131A dried | #853A33 rust |
| Clothing | #EBD3BB off-white | #5A6566 denim | #57563E olive jacket | #664332 leather | #2F292B outline |
| Environment and glow | #65615D concrete | #3B3B38 asphalt | #694C3B dirt | #442B23 mud and wood | #FEDE7C eye glow |

---

## Characters

Every character gets one approved turnaround before any animation work starts. The turnaround is the master; all sprites are built from it.

### Cast and scale

Reference image: `Zombie Character Lineup Concept Art.png`

Humans and standard zombies share one height. The butcher is about 1.5 times as tall and twice as wide. Keep this ratio in every asset.

### Character descriptions

Paste these into prompts word for word. Changing the wording changes the design.

| Character | Role | Description to paste |
| --- | --- | --- |
| Rugged Survivor | Player | adult man with messy brown hair and a short beard, olive green canvas overshirt with rolled sleeves over a cream undershirt, brown leather belt, faded gray-blue jeans torn at the knee, brown lace-up boots, large brown canvas backpack, black pistol held low in his right hand |
| Scrubs Survivor | Civilian NPC | frightened woman with brown hair in a messy bun, teal-green medical scrubs top stained with dirt and dried blood, dark gray jeans torn at the knee, worn beige sneakers |
| Walker | Basic zombie | hunched bald zombie with olive-khaki skin and red blood patches on the scalp, glowing yellow eyes, open mouth with sharp teeth, torn short-sleeved off-white button-up shirt with red stains, gray-blue jeans, brown work boots, bloody hands hanging forward |
| Runner | Fast zombie | lean young zombie with messy brown hair and a bloody forehead gash, glowing yellow eyes, open fanged mouth, torn olive green jacket over a stained cream t-shirt, ripped dark gray jeans with a bloody wound on the right knee, brown boots, blood-red hands |
| Butcher | Brute zombie | hulking bald zombie about 1.5 times taller and twice as wide as a normal zombie, stitched wound on the scalp, swollen red flesh mass over the left shoulder, torn blood-soaked white butcher apron with brown leather straps and buckles, chains with steel meat hooks at the belt, brown trousers, brown boots, bloody meat cleaver in the right hand |
| Coach | Special zombie (concept only) | stocky middle-aged zombie with thinning brown hair and a mustache, glowing yellow eyes, torn white athletic polo with red stripes and a red collar, gold whistle on a black cord, red athletic shorts with white side stripes, red-striped wristbands, white tube socks with red stripes, white sneakers |

### Directions

Generate 5 directions: S, SE, E, NE, N. Mirror SE, E and NE in the engine to get SW, W and NW. Because of mirroring, keep important details symmetrical where you can, or accept that a held weapon swaps hands on the mirrored side.

### Turnaround rules

1. Same neutral standing pose in all five views, arms hanging slightly forward. Only the body rotates.
2. Same scale, and all feet on one ground line.
3. Same camera tilt in every view.
4. NE and N show the back of the head. The face is hidden or only a sliver of cheek in NE.
5. Asymmetric details (wounds, weapons, the butcher's shoulder mass) stay on the same body side in every view.
6. Even spacing between views, no labels.

### Approved turnarounds

| Character | File |
| --- | --- |
| Player (Rugged Survivor) | `Rugged Survivor Character Turnaround.png` |
| NPC (Scrubs Survivor) | `Anxious Survivor Medical Scrub Turnaround.png` |
| Walker | `Zombie  WakerTurnaround Sheet.png` |
| Runner | `Zombie Runner Turnaround.png` |
| Butcher | `Grotesque Butcher Turnaround Sheet.png` |

### Known issues in approved art

- **Walker golden reference:** the background was removed badly and left a red and yellow halo around the body. Re-export it on the flat slate background before attaching it to prompts, or the halo will spread into new art.
- **Runner turnaround, N view:** his left hand has a pink-magenta tint that does not match the palette. Fix before using it as a sprite master.
- **Coach:** key art only. Needs a turnaround before he can be animated.
- **Alternate survivor** (woman in an olive tank top, second camera reference): not in the cast yet. Decide if she is a second player character or an NPC.

---

## Animation

Every animation is made in all 5 generated directions, always starting from the approved turnaround view for that direction. Never animate from a new prompt.

| Character | Animation | Frames | Type |
| --- | --- | --- | --- |
| Player | Idle | 4 to 6 | Loop |
| Player | Walk | 8 | Loop |
| Player | Run | 8 | Loop |
| Player | Aim and shoot (pistol, rifle, melee) | 4 to 8 each | One-shot |
| Player | Reload | 6 to 10 | One-shot |
| Player | Interact or pick up | 4 to 6 | One-shot |
| Player | Hurt flinch | 2 to 3 | One-shot |
| Player | Death | 8 to 10 | One-shot, hold last frame |
| Walker | Idle sway | 4 to 6 | Loop |
| Walker | Shamble walk | 8 | Loop |
| Walker | Lunge and grab | 6 to 8 | One-shot |
| Walker | Feeding, crouched (optional) | 4 to 6 | Loop |
| Walker | Hurt flinch | 2 to 3 | One-shot |
| Walker | Death collapse | 6 to 10 | One-shot, hold last frame |
| Runner | Idle twitch | 4 to 6 | Loop |
| Runner | Sprint | 6 to 8 | Loop |
| Runner | Leap attack | 6 to 8 | One-shot |
| Runner | Hurt flinch | 2 to 3 | One-shot |
| Runner | Death | 6 to 10 | One-shot, hold last frame |
| Butcher | Heavy walk | 8 | Loop |
| Butcher | Cleaver swing | 8 to 10 | One-shot |
| Butcher | Charge | 6 to 8 | Loop |
| Butcher | Stagger (player's attack window) | 4 to 6 | One-shot |
| Butcher | Death | 10 to 12 | One-shot, hold last frame |
| NPC | Idle | 4 to 6 | Loop |
| NPC | Walk | 8 | Loop |
| NPC | Talk or gesture | 4 to 6 | Loop |
| NPC | Panic run | 8 | Loop |
| NPC | Death | 6 to 8 | One-shot, hold last frame |

**Animation rules**

- The character animates in place, centered, at the same size in every frame. The engine moves the sprite, not the art.
- Locked camera: no zoom, pan or rotation.
- Feet stay on the same ground line from frame to frame, except during jumps and leaps.
- Every frame matches the master design: same clothes, wounds, colors and outline.
- Death animations end with the body lying fully inside the frame.

---

## Environment

The world is drawn at the same isometric camera as the characters, with quieter, lower-contrast ground so characters always stand out.

### Buildings and scenes

Reference image: `Abandoned Gas Station Diorama.png`

This is the benchmark for world art: isometric angle, flat-topped roofs seen from above, faded red trim, boarded windows, weeds through cracks, and no readable text on signs.

**Building rules**

- Same outline weight and top-left light as the characters.
- Weathered and abandoned: rust, peeling paint, plywood over windows, vegetation breaking through.
- Signs show shapes and color only, never words.
- Generate buildings as stand-alone pieces on the slate background so they can be placed on any ground.

### Props

Reference image: `Post-Apocalyptic Prop Asset Sheet.png` (car, barrel, crates, fence, dumpster, street lamp)

**Prop rules**

- One prop per cell, evenly spaced, nothing touching.
- Same isometric angle as the camera references.
- Heavy wear: rust patches in #853A33, dents, broken glass, faded paint.
- Size props relative to a character. A car is roughly 2 character heights long; a barrel reaches about mid-thigh.

### Ground

Style reference: `Post-Apocalyptic Terrain stlye Sheet.png` (asphalt, grass, mud, concrete)

The terrain sheet is a **style reference only**. It shows the colors and rendering for each ground type, but the tiles have borders and are too bold to tile. Use it to guide new tiles, not as tiles.

Production tile: `Seamless Cracked Asphalt Texture.png`

The asphalt texture is the first production tile. A seam check shows the left and right edges match well; top and bottom are slightly weaker. It is 1303 x 1207 pixels, so crop it square and resize to a power of two (1024 x 1024) before use.

**Ground rules**

- Seamless edge to edge, no border or frame.
- Lower contrast and slightly darker than characters.
- Even detail with no large standout features. Big cracks, puddles, potholes and blood go on top as decals.
- Thinner outlines than characters.

**Decision needed: square or diamond tiles.** Your characters, props and gas station are isometric, but the asphalt tile is drawn straight down as a square. Both can work. If your engine uses an isometric tilemap, convert a square seamless texture to a diamond by rotating it 45 degrees and squashing it to half its height. If you instead use one large ground image under the scene, the square texture works as is. Pick one and record it here.

### Ground decals

Reference image: `Grayscale Splash Decal Collection.png`

Splash decals are white shapes on black. Tint them in the engine: deep red for blood (#9D222A), olive for zombie fluid, near-black for oil, pale blue-gray for water. One sheet covers all four.

---

## Effects

Effects are isolated, multi-frame sprite strips with hard-edged cel shading, the same as the characters. Nothing is attached to them: no gun, no ground, no rubble.

### Approved effects

| Effect | File | Notes |
| --- | --- | --- |
| Muzzle flash | `Muzzle Flash Animation Sprite Sheet.png` | 4 frames, ignition to smoky fade, pointing right. Rotate in the engine for each aim direction. |
| Blood burst | `Animated Blood Splatter Sequence.png` | 6 frames, small spray to full burst to scattered droplets. Plays on hit, then a tinted splash decal stays on the ground. |
| Fire | `Six-Frame Stylized Fire Sprite Sheet.png` | 6-frame loop. Place over burning barrels, cars and buildings. |

### Effects rules

- One effect per image, frames in a single evenly spaced row.
- Glowing effects (fire, flash, sparks, explosions) go on pure black so the engine can use additive blending.
- Non-glowing effects (blood, smoke, dust) go on flat slate or gray.
- Effects use the palette: blood reds from the Blood row, fire from #FEDE7C through orange to #9D222A at the edges.

### Made in the engine, not with AI

| Effect | Why |
| --- | --- |
| Zombie eye glow | Two small glowing points layered on the sprite. Cheaper and consistent in every frame. |
| Bullet impact sparks | Particle effect. Looks better in motion and costs nothing. |
| Smoke and dust puffs | Particle effect with soft fade. |
| Screen shake, hit flash | Engine feedback, not art. |

---

## Prompt library

Start every session with the Setup Prompt, then use one template per image. Fill in the brackets; paste character descriptions from the Characters table word for word.

### Setup prompt (paste once per conversation)

Attach the golden references and one camera reference with it.

```
I'm making an isometric 2D zombie game. The attached images define the art style and camera. Every image you make in this conversation must match them exactly:

STYLE: hand-painted cel-shaded game art, bold dark brown-black outlines, hard-edged shading with 2 to 3 tones, desaturated muted colors, olive and khaki zombie skin, deep red blood in flat splotches, glowing yellow eyes on zombies only.
CAMERA: 3/4 isometric view looking down at about 45 degrees, the same angle as the camera reference.
LIGHT: single soft light from the top left.
BACKGROUND: solid flat dark slate (#2F3137) unless I say otherwise. No ground shadow, no text, no labels, no borders.

Reply "ready" and wait for my requests.
```

### Character turnaround

```
Character turnaround of [CHARACTER DESCRIPTION]. Five views in a single row, evenly spaced, the exact same neutral standing pose with arms hanging slightly forward, rotated in place: front, front-right, right side, back-right with the face turned away, back. Identical scale, all feet on the same ground line, same camera angle in every view. Asymmetric details stay on the same body side in every view. No text.
```

### Animation (video model, turnaround view as first frame)

```
The character performs a [ANIMATION, e.g. slow shambling walk cycle] in place, body facing [DIRECTION]. Locked camera: no zoom, no pan, no rotation. The character stays centered and the same size the whole time, feet on the same ground line. Background stays solid flat dark slate. Character design, colors and outfit stay identical. Seamless loop.
```

One-shot animations: replace "Seamless loop" with "Ends holding the final pose." Deaths: add "The character falls and lies still, fully inside the frame."

### Prop sheet

```
Prop sheet of [NUMBER] environment objects, evenly spaced in a grid, nothing touching, same isometric camera angle: [LIST OF PROPS]. Heavily weathered with rust, dents and faded paint. Same outline weight and shading as the characters. No text.
```

### Building

```
A [BUILDING] seen from the same isometric angle, abandoned and weathered, boarded windows, faded signage with no readable text, weeds growing through cracks. Stand-alone on the flat slate background. Same outline weight and shading as the characters.
```

### Ground tile

```
A single seamless tileable ground texture of [SURFACE], viewed from directly above. The texture fills the entire image edge to edge with no border, no frame and no outline around it. Left and right edges match, top and bottom edges match. Low contrast and slightly darker than the characters. Even detail with no large standout features. Same cel-shaded style and palette as the references.
```

### Splash decals

```
Six different liquid splatter decals viewed from directly above, evenly spaced in a 3x2 grid. Pure white shapes with slightly darker gray edges and a few small droplets around each one. Hand-painted cel-shaded game art style with hard edges. Solid flat black background. No text.
```

If ChatGPT refuses anything with blood, describe it as paint or liquid instead. The shape is what matters; color is set in the engine.

### Effect strip

```
Sprite sheet of a [EFFECT] effect only, no objects, no ground, no debris. [FRAMES] frames in a single evenly spaced row showing [START] to [END]. Hard-edged cel-shaded style matching the references. Pure black background. No text.
```

### Fixing drift

When an image drifts, reply instead of re-prompting:

```
Closer to the attached reference style: thicker dark brown outlines, harder-edged shading, more muted colors, same camera angle as the camera reference.
```

---

## Do not

Mistakes already seen in this project, and the fix for each. Rejected images live in a separate Do Not folder and are never attached to prompts or used for training.

| Do not | Seen in | Fix |
| --- | --- | --- |
| Change the pose between directions | First runner turnaround (five different lunges) | Turnaround prompt: "exact same neutral standing pose, rotated in place" |
| Show the face in the NE view | First runner turnaround | Specify "back-right with the face turned away"; generate NE alone from the N view if needed |
| Let scale, foot line or camera tilt drift between views | First runner turnaround | "Identical scale, all feet on the same ground line, same camera angle in every view" |
| Move a wound, weapon or feature to the other side | Second runner turnaround (knee wound swapped legs) | Name the side in the description ("bloody wound on the right knee") |
| Put labels or text in the image | First runner turnaround | End every prompt with "No text" |
| Put borders or frames around ground tiles | First terrain sheet | One tile per image, "fills the entire image edge to edge" |
| Make ground as bold and contrasty as characters | First terrain sheet | "Low contrast and slightly darker than the characters" |
| Bake big features (puddles, large rocks) into tiles | First terrain sheet | Make them separate decals |
| Bake ground, rubble or objects into effects | First effects sheet (gun attached to muzzle flash) | "Effect only, no objects, no ground, no debris" |
| Draw an effect as a single frame | First effects sheet | Ask for a frame strip in a single row |
| Draw a whole character when you want an effect on a character | First effects sheet (eye glow became a new zombie) | Do overlays like eye glow in the engine |
| Remove the background with a halo left behind | Walker golden reference | Generate on flat slate and cut cleanly, or re-export |
| Use off-palette colors | Runner turnaround N view (pink hand) | Compare against the palette; repaint or regenerate |

---

## Production rules

### Approval checklist

Run every new asset through this before it goes in the Good folder.

1. Rendering matches the golden references: bold brown-black outline, 2 to 3 hard tones, muted colors.
2. Camera matches the camera references.
3. Light comes from the top left.
4. Colors sit inside the palette. Saturation only on blood, fire and eye glow.
5. Character details match the description and the approved turnaround exactly.
6. Clean flat background, no halo, no text, nothing extra attached.
7. Still readable when shrunk to in-game size. Squint test: can you tell what it is at a glance?
8. For tiles: seamless when repeated 3 x 3. For animations: no sliding, no size change, no design drift between frames.

### File naming

Pattern: `character_animation_direction_frames.png`

| Example | Meaning |
| --- | --- |
| walker_walk_SE_8f.png | Walker, walk cycle, facing south-east, 8 frames |
| butcher_swing_N_10f.png | Butcher, cleaver swing, facing north, 10 frames |
| player_turnaround.png | Player master turnaround |
| tile_asphalt_01.png | First asphalt ground tile |
| decal_splash_set01.png | First splash decal sheet |
| fx_fire_loop_6f.png | Fire effect, looping, 6 frames |

### Folders

- **Good:** approved assets and references only.
- **Do Not:** rejected images, each with a one-line note on what went wrong. Never attached to prompts.
- **Masters:** one approved turnaround per character, the source for all animation.
- **Sprites:** finished sprite sheets, one subfolder per character.

### Open decisions

- Square or diamond ground tiles (see Environment).
- Sprite canvas size per character class. Suggested starting point: 128 px for humans and standard zombies, 192 px for the butcher.
- Game engine. This decides which effects are made in the engine and how sprite sheets are packed.
- Whether the alternate survivor joins the cast, and in what role.
- Coach turnaround still to be made.
