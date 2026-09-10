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
- `start()` is the front half of loading, not just of a new game. Anything a
  run accumulates and a save does not carry has to be cleared there, or it
  survives the load: a raid mid-wave, bullets in the air, the quiet field.
- A view that caches the world's own dictionaries has to be rebuilt when the
  world object is replaced. The prop renderers bucket them by tile.
- When a rule has a refresh and an expiry, they must ask the same question.
  Aggro refreshed on sight and expired on distance, so a wall never broke a
  chase — a bug that survived Phase 2's review and the prototype.
- A free tile is not room for a body. Check the radius, not the centre: 56
  of 400 ambient spawns were starting inside geometry.

## An autoload must never share its name with a class_name (2026-09-08)

Registering `Sfx="*res://src/core/sfx.gd"` while the script says
`class_name Sfx` makes the autoload's *instance* shadow the class. In the
running game that mostly works. Under `godot --headless -s` there is no
autoload, so `Sfx` resolves to a bare GDScript resource and every static call
fails with "Nonexistent function 'build' in base 'GDScript'" — 91 test
failures that look like the script is broken rather than the name.

`Bindings`/`KeyBinds` had already established the working pattern, one PR
earlier, for exactly this reason, and I did not carry it across.

**Rule:** when a script needs both an autoload and a `class_name`, the two
names must differ. `Bindings`/`KeyBinds`, `Audio`/`Sfx`.

## Assert on what the code decided, not on what fed it (2026-09-08)

Three times in Phase 4:

- 4c: features built and not connected, with tests calling the function
  instead of pressing the key.
- 4d: `KeyBinds.primary_label` had no callers; the HUD still said "E".
- 4d audio: the bow had a cue, and every gun sound hung on the `muzzle` event
  — which a bow deliberately never emits. My test asserted "firing a bow emits
  a shot event", which was true the whole time the bow was silent.

The shape is always the same: the assertion sits *upstream* of the decision.

**Rule:** for anything that maps input to a choice — an event to a sound, a
key to an action, a binding to a prompt — the function must **return the
choice**, and the test must assert on that return. If the seam does not exist,
add it; `SfxView.on_event` returns a cue name for exactly this reason.

The check: break the mapping and re-run. If nothing fails, the test was
watching the wrong end. Reverting `"shot"` to `"muzzle"` fails twelve
assertions now and failed none before.

## Anything a headless run writes under user:// needs its own path (2026-09-08)

`user://` is shared with the real game the owner plays. Three times in Phase 4
a test or a smoke run wrote into it:

- The save-slot tests used slots 3/4/5 — real player slots — before moving to
  90–92, outside `Saves.MAX_SLOTS`.
- The binding tests called `reset_all()` in `after_each`, which writes the
  store, so the first headless run on a machine erased the player's controls.
- The smoke run called `set_muted(false)` at the end of its audio step, which
  wrote into the player's `user://audio.json` — and a player who *was* muted
  would also have seen the run fail for it.

**Rule:** every `user://` path a headless run can write is a `static var`, not
a `const`, and the test or the smoke redirects it. `Saves` uses slots above
`MAX_SLOTS`; `KeyBinds.STORE` is redirected per test case; `Sfx.STORE` is
redirected when `--smoke` is on the command line.

The corollary that cost the third one: **check the cmdline, not another
autoload.** Autoloads run in declaration order, so `Smoke.enabled` is not set
yet when an earlier autoload's `_ready` wants to know.

## 2026-09-09 (Phase 5)

- Two player records as Dictionaries put a snapshot over ENet's MTU on their
  own. The engine warned in the socket test; the loopback never would have.
  Pack entities as flat float arrays and assert the byte count in a test.
- Read the inbox before checking whether the link is open: a reject and the
  hang-up that follows it arrive in the same poll.
- Loopback ends that reference each other, and a hub and its links, are
  reference cycles: `close()` must break them or every session leaks.
- `ENetMultiplayerPeer.poll()` on a disconnected peer is an engine error per
  frame. Check `get_connection_status()` first.
- The smoke cannot run `--headless`: `frame_post_draw` never fires. Xvfb
  runs the real thing on a headless Linux box.
- `var x := t.sim.structs.count()` where `t` is a Dictionary is a Variant and
  fails to parse: type anything pulled out of a Dictionary.
- A `var` declared inside an `else` at function scope still clashes with a
  later `var` of the same name in the same function: GDScript scopes are the
  function's, not the block's, for the parser's duplicate check.
- The prop renderers hold references to the world's prop dictionaries from
  build time, so removing a prop from `world.props` did not stop it drawing.
  Solo had this bug all along; the guest mirror made it visible.
- `load()` on a test file with a parse error returns a script object that
  cannot be instantiated and has no methods: the runner counted it as zero
  tests and zero failures, and eighteen network tests vanished from a run
  that reported green. `can_instantiate()` is the check; it is in `run.gd`.
- A press on an unreliable channel is not a press. Edges go reliably, once;
  held state goes every step. The two must not both carry the edge, or a
  gate opens and closes on the same tap.
- `_set` is a virtual on Object; naming a method `_set` with a different
  signature is a parse error in the caller's script chain, not in the file.
- A GDScript `WebRTCPeerConnectionExtension` can carry the real
  `WebRTCMultiplayerPeer` through offer, answer and peer-connected — but a
  `WebRTCDataChannelExtension` gets `_put_packet(pointer, size)`, which a
  script cannot fill. Test the handshake with the fake; test bytes with the
  native extension.
- GitHub's pages and API are 403 through this session's proxy; only exact
  release download URLs pass. A release asset whose name you do not know
  cannot be found from here — leave a fetch script and the URL to the owner.
- `UPNP.discover` outlasts its own timeout on a machine with no router:
  eight seconds to say "nobody". Run it on a thread, and never join that
  thread from STOP HOSTING — orphan it and reap it from `_process`.
- `is_action_pressed` is already true on the frame `is_action_just_pressed`
  fires. Any tap/hold split that reads the held flag on the press frame will
  always take the hold branch. `Interact`'s vehicle case did, so tap-to-drive
  was unreachable from the day it shipped and only a bug report found it. A
  hold is a channel with a duration, never a flag read once.
- Reproduce a bug report through the surface the reporter used. "Trees stay
  after chopping and drop nothing" does not reproduce when you call
  `chop_prop` directly — it reproduces when you swing at where the mouse is
  pointing and miss, which is silent. The headless test and the owner were
  both right about different things.
- A test whose setup depends on a bug will defend that bug. The smoke run
  stood the player on the wall beside a nightstand and searched through it;
  fixing wall-looting broke that step and cascaded into five more, all one
  root cause. Read the first failure before believing the other five.
- Measure a rule's cost before believing a survey that says it is expensive.
  A first pass said the new sight rule stranded six containers; it had been
  measuring `best_target`, which was answering "recruit" because a survivor
  was standing there. Isolating the predicate showed it stranded none.
- Anything on a touching tile is in reach — no line is drawn. Furniture
  stands against walls and some of it in alcoves whose only standable spot is
  a diagonal neighbour, so a sight rule that samples the whole segment makes
  those impossible to open.
- The global RNG stream is shared. Changing how many draws happen anywhere —
  a `continue` that skips a `pick_type` — changes every roll after it, so a
  smoke step that depends on having looted well will fail for reasons that
  have nothing to do with it. Steps should stock their own preconditions.
- A clock and the fields that only mean something while it runs must be
  cleared together, in the one place it runs out. Bleed zeroed `bleed_t` on
  expiry and left `bleed_dps` and `bleed_by` behind, so the "keep the deeper
  wound" rule compared the next cut against a wound that had already
  finished: a knife opening something a machete had bled dry bled at the
  machete's rate and paid the machete's owner the kill. The bug is invisible
  in the mechanic's own tests, because every one of them opens a wound and
  watches it end — none opened a *second* one afterwards. (Codex, PR #23.)
- When a card says a system is missing, confirm it still is before building
  it. A card asked for three and one had shipped the day before;
  the audit line predated the merge. Grep for the field name before planning
  to build it — half an hour of reading beat rebuilding a working system.

## 2026-09-10 (raised beds)

- `p.pos = x` in a smoke leg keeps whatever velocity the last leg left, so
  the player drifts out of reach of the thing they were just teleported to
  before the key is pressed. Three legs failed on it and none of the messages
  mentioned movement. `_smoke_stand_at` zeroes velocity, previous position
  and the intent's axes; use it for every teleport from here.
- A smoke assertion against `_craft_rows()` is an assertion about the height
  of the panel. Adding one bench-0 recipe pushed the Refined Suppressant off
  the visible page and failed a checkpoint about the *station gate*. Assert
  the rule against `visible_recipes`, then scroll the row into shot for the
  photograph — two assertions, and each fails for its own reason.
- A test that says "every food is findable" is worth extending rather than
  weakening. Crops are found the long way round — the seed is in a loot table
  and a bed turns it into the crop — so teaching the test that third source
  kept its teeth: a crop whose seed exists nowhere still fails it.
- Stock a smoke leg for what it actually spends. A round twenty of everything
  paid for one of four raised beds; the other three came back as empty
  dictionaries and the *next* line crashed the coroutine, so the run lost
  thirty checkpoints to a materials bug.
- Draw the earliest stage of anything as something. A bed sown this morning
  drew nothing at all, so it looked exactly like an empty one and the row of
  beds lied about what was in it.
- Lay out a new panel mode against the panel it shares, not against the
  screen. The bed's two gauges started at the pack grid's x and ran to the
  panel edge, straight through thirty inventory cells. The empty column to
  the right of that grid was where they belonged.
- A field that moves every frame cannot go on the world diff at full
  precision. The diff re-sends any structure whose packed record changed, so
  a bed's water and growth would have re-sent a garden twice a second for
  ever. Round them coarsely, and round *down*, so a guest is behind the host
  rather than ahead of it — a guest that ripens first offers a harvest the
  host refuses. A running generator's fuel already had this shape and nobody
  noticed, because a base has one generator and a garden has twelve beds.
- Absence of a flag is not exclusion. `protect` only *weights* `raid_target`
  and `base_centre`; not setting it still left a raised bed anchoring a base
  and drawing raiders. If a piece must be excluded from a rule, exclude it —
  do not infer the exclusion from a flag that means something else.
- Before excluding a thing from a list, find out what the list is for. Taking
  beds out of `raid_target` looked obviously right and would have made them
  indestructible, because an enemy's `pending_struct` comes from its
  `objective` and nowhere else. The fix was to exclude them from the *other*
  function and push them to the back of this one.
- A number applied in the sim and not in the screen that predicts it is a lie
  with a delay on it. `loot_mul` was in the harvest and not in the band the
  bed panel printed. Whenever a screen promises a range, the range and the
  roll want to be the same expression or the same short list of factors.
## 2026-09-10 (off Notion)

- `notion-fetch` returns a cached snapshot, stamped "as of" — comment
  threads in it were a day stale (3 of 14 on one page, 2 of 9 on another).
  `notion-get-comments` with `include_all_blocks` and `include_resolved` is
  the live read; use it before migrating or quoting anyone.
- `row.key = v` on a Dictionary makes a StringName key, and a plain
  `Array.sort()` orders every StringName after every String. Anything that
  serialises keys sorts by `String(k)`.
- Linear autolinks anything shaped like a domain: `combat.gd:150` and
  `PROJECT.md:879` became `http://` links (`.gd` and `.md` are real TLDs).
  Wrapping `file:line` in a code span did not stop it; writing the file in
  a code span and the line outside it ("`combat.gd` line 150") did.

- The owner's rule was "every cost key exists in RES"; the game's rule is
  "a cost is anything that stacks", and five recipes pay in consumables.
  The first integrity check refused every save. Read the test that already
  enforces a rule before writing a second enforcer of it.
- `node.append(array)` and `replaceChildren(array)` stringify the array —
  "[object HTMLButtonElement]" — where a helper that flattens does not.
  `node --check` passed it; only the screenshot showed it.
- Browser pane: navigating to the same URL with a new `#hash` does not
  reload, so the old script keeps running after an edit. Add `?r=N`.
- Browser pane: the `key` action does not edit a focused input (Backspace
  changed nothing, even in a plain number box). Set `.value` and dispatch
  an `input` event to exercise the handler; a field that will not clear
  under automation is not a page bug until that also fails.

- Stopping a background `tools/edit.sh` from the agent's task tool kills
  the shell and leaves its Godot child holding the port, so the restart
  fails with "could not listen". `exec` in the script does **not** fix it
  under Git Bash on Windows — tried and measured: the Godot PID survived
  the stop. Find the process on the port (`netstat -ano`, then its command
  line via `Get-CimInstance Win32_Process`) and kill that PID, and check
  what it is first — the other Godot on this machine was the owner's
  editor. A person pressing Ctrl+C in the console is a different path and
  was not tested here.
- The first catalog-art test caught a real waste, not a test bug: the
  ground fallback loaded the icon file a second time instead of reusing
  the cached texture. Asserting identity (`eq(ground, icon)`) rather than
  "both are non-null" is what found it.

- The owner types commands in Windows PowerShell 5.1. I gave them
  `cd "…" && tools/edit.sh` and it failed twice over: no `&&` in that
  PowerShell, and it cannot run a `.sh`. Commands for the owner are
  `.\tools\<name>.cmd`, one per line; the `.sh` twins are for Git Bash
  and Linux.
- "Subcategories for melee and ranged weapons" meant the owner's weapon
  *classes* (Improvised, Blunt, Bladed… Handguns, Shotguns…) and what each
  class is for — not a melee/ranged split of the list. I built the split
  and the owner had to correct it with screenshots. When the owner names a
  grouping, find it in their own design source (Notion's class tables)
  and show it back with its words before building the view around it.

## 2026-09-10 (raised beds, continued)

- A review finding can be right about the fact and wrong about the target.
  (See the entry below for the owner's first playtest.)

## 2026-09-10 (the owner's first playtest)

- Look at the photograph before reading the renderer. "The torch gave no
  light" read like a `LightView` fault; the smoke's `torch_lit` PNG showed a
  torch that lit and a night bright enough to hide it. One look, one cause
  for two notes.
- A rule about what may stand on a tile meets every test that builds on the
  shared world, because the generator scatters litter on the plots those
  tests use. Fix the helper to do what a player now has to (clear the
  ground), not the rule — and put the new refusal where a player meets it in
  the order: after "You are standing there", before the cost.
- Estimate a feel number, then measure it through the real path before
  telling the owner. "About a hundred trees" was four chops a tree in my
  head and six in the game; the test that divided durability by the swing's
  own damage caught it at 66.
- Scaling a curve that gameplay reads as well as the eye sees: scale its
  normaliser by the same factor, and the gameplay reading is unchanged at
  every point. Assert that at the keys, against the old numbers.
  The stash has been reachable from anywhere since Phase 3 and every system
  that spends inherits it; fixing it in farming alone would have made the one
  new system the odd one out. Correct the claim, raise the real card.
