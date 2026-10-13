extends SceneTree
## Bakes the owner's Mixamo exports into what the 3D stage loads.
##
##   <godot> --headless --path . -s tools/build_anims.gd
##   <godot> --headless --path . -s tools/build_anims.gd -- zombie     (one character)
##
## Reads `Meshy Models/Animations/` (the owner's inbox: ignored, not the
## project's) and writes, per character:
##   * `assets/models/**.glb`  the rigged mesh from its `*_Mixamo.fbx`, in metres
##                             and 1.7 m tall, with no animations in it;
##   * `assets/anims/<name>.res` one AnimationLibrary, the clips under game
##                             names, which `ActorModel` adds to the model.
## Eight megabytes of FBX per clip stays in the inbox; a library is kilobytes.
##
## Mixamo clips are not in place: a walk carries 1.6 m of hips travel and the
## sim moves the body. So each clip has its hips' X and Z held at the first
## frame (Y is kept: a death drops the hips to 10 cm, a crawl runs at 15) and
## the distance it travelled is stored as the animation's `speed` meta, in
## metres per second, which is what playback is paced against.
##
## Every Mixamo rig names its bones alike, so a clip from one body plays on
## another: tracks for a bone the target lacks are dropped and counted.

const SRC := "Meshy Models/Animations/"
const HEIGHT := 1.7

const LOCO := "Main Character/Locomotion Pack.zip#"
const SHOOT := "Main Character/Shooter Pack.zip#"
const BOW := "Main Character/Pro Longbow Pack.zip#"
const WZIP := "Zombie Walker Annimation/Scary Zombie Pack.zip#"
const RZIP := "zombie runner aminations/Scary Zombie Pack (1).zip#"
const COACH := "coach animations/"

## A clip: `src` is `file.fbx` or `pack.zip#entry.fbx`; `loop` makes it a
## cycle; `range` keeps only [from, to] seconds of it; `strike` is the second
## (after the range is cut) at which the blow lands, the ball leaves the hand,
## the whistle sounds — measured as the hand's fastest moment — so the stage
## can fit a clip to a telegraph and have the hit fall where the sim's does.
const CHARS := {
	"player": {
		"model": LOCO + "Rugged_Trailblazer_Mixamo_v2.fbx",
		"glb": "res://assets/models/characters/player.glb",
		"lib": "res://assets/anims/player.res",
		"clips": {
			"idle": {"src": LOCO + "idle.fbx", "loop": true},
			"walk": {"src": LOCO + "walking.fbx", "loop": true},
			"run": {"src": LOCO + "running.fbx", "loop": true},
			"attack": {"src": "Main Character/Punching.fbx"},
			"hurt": {"src": "Main Character/Hit To Body.fbx"},
			"die": {"src": BOW + "standing death backward 01.fbx"},
			"downed": {"src": BOW + "standing death forward 01.fbx"},
			"dash": {"src": BOW + "standing dodge forward.fbx"},
			"collect": {"src": "Main Character/Pick Fruit.fbx"},
			"throw": {"src": "Main Character/Throw Object.fbx"},
			"shoot": {"src": SHOOT + "firing rifle.fbx"},
			"aim": {"src": SHOOT + "rifle aiming idle.fbx", "loop": true},
		},
	},
	"walker": {
		"model": WZIP + "Undead_Clown_Mixamo.fbx",
		"glb": "res://assets/models/enemies/walker.glb",
		"lib": "res://assets/anims/walker.res",
		"clips": {
			"idle": {"src": WZIP + "zombie idle.fbx", "loop": true},
			"walk": {"src": WZIP + "zombie walk.fbx", "loop": true},
			"run": {"src": WZIP + "zombie run.fbx", "loop": true},
			"attack": {"src": WZIP + "zombie attack.fbx"},
			"bite": {"src": WZIP + "zombie neck bite.fbx"},
			# Low to the ground: what a crawler swings with.
			"bite_low": {"src": WZIP + "zombie biting (2).fbx"},
			"scream": {"src": WZIP + "zombie scream.fbx"},
			"die": {"src": WZIP + "zombie death.fbx"},
			"crawl": {"src": WZIP + "zombie crawl.fbx", "loop": true},
			"crawl_fast": {"src": WZIP + "running crawl.fbx", "loop": true},
			# From the Coach's rig: this body has no reaction or get-up of its own.
			"hurt": {"src": COACH + "Zombie Reaction Hit.fbx"},
			"getup": {"src": COACH + "Zombie Stand Up.fbx"},
		},
	},
	"runner": {
		"model": RZIP + "Ravenous_Undead_Mixamo.fbx",
		"glb": "res://assets/models/enemies/runner.glb",
		"lib": "res://assets/anims/runner.res",
		"clips": {
			"idle": {"src": RZIP + "zombie idle.fbx", "loop": true},
			"walk": {"src": RZIP + "zombie walk.fbx", "loop": true},
			"run": {"src": RZIP + "zombie run.fbx", "loop": true},
			"attack": {"src": RZIP + "zombie attack.fbx"},
			"bite": {"src": RZIP + "zombie neck bite.fbx"},
			# Low to the ground: what a crawler swings with.
			"bite_low": {"src": RZIP + "zombie biting (2).fbx"},
			"scream": {"src": RZIP + "zombie scream.fbx"},
			"die": {"src": RZIP + "zombie death.fbx"},
			"crawl": {"src": RZIP + "zombie crawl.fbx", "loop": true},
			"crawl_fast": {"src": RZIP + "running crawl.fbx", "loop": true},
			"hurt": {"src": COACH + "Zombie Reaction Hit.fbx"},
			"getup": {"src": COACH + "Zombie Stand Up.fbx"},
		},
	},
	"coach": {
		"model": COACH + "Orc Idle.fbx",
		"glb": "res://assets/models/enemies/coach.glb",
		"lib": "res://assets/anims/coach.res",
		"clips": {
			"idle": {"src": COACH + "Orc Idle.fbx", "loop": true},
			"walk": {"src": COACH + "Mutant Walking.fbx", "loop": true},
			"run": {"src": COACH + "Mutant Run.fbx", "loop": true},
			"attack": {"src": COACH + "Zombie Neck Bite.fbx"},
			"hurt": {"src": COACH + "Reaction.fbx"},
			"die": {"src": COACH + "Dying Backwards.fbx"},
			"wake": {"src": COACH + "Zombie Stand Up.fbx", "range": [1.3, 3.1]},
			"slam": {"src": COACH + "Jump Attack.fbx", "range": [0.0, 1.8], "strike": 0.6},
			"charge_wind": {"src": COACH + "Standing To Crouched.fbx", "strike": 0.63},
			"charge_go": {"src": COACH + "Crouched To Sprinting.fbx"},
			"stun": {"src": COACH + "Dizzy Idle.fbx", "loop": true},
			"throw": {"src": COACH + "Goalie Throw.fbx", "range": [0.6, 2.6], "strike": 1.05},
			"whistle": {"src": COACH + "Taunt Gesture.fbx", "strike": 0.95},
			"roar": {"src": COACH + "Roar.fbx", "range": [0.3, 2.3]},
			"agony": {"src": COACH + "Agony.fbx"},
			"scream": {"src": COACH + "Zombie Scream.fbx"},
			"shove": {"src": COACH + "Shove Reaction.fbx"},
		},
	},
}

var _tmp := ProjectSettings.globalize_path("user://anim_build/")
var _inbox := ProjectSettings.globalize_path("res://" + SRC)


func _init() -> void:
	var only := OS.get_cmdline_user_args()
	var failed := false
	for who in CHARS:
		if not only.is_empty() and not (who in only):
			continue
		if not _build(who, CHARS[who]):
			failed = true
	quit(1 if failed else 0)


func _build(who: String, spec: Dictionary) -> bool:
	print("== %s" % who)
	var model := _load(String(spec.model))
	if model == null:
		return false
	var skel := _find(model, "Skeleton3D") as Skeleton3D
	var mesh := _find(model, "MeshInstance3D") as MeshInstance3D
	if skel == null or mesh == null:
		printerr("  no skeleton or mesh in %s" % spec.model)
		return false
	var bones := {}
	for i in skel.get_bone_count():
		bones[skel.get_bone_name(i)] = true
	var k := HEIGHT / mesh.get_aabb().size.y
	_to_metres(skel, mesh, k)

	var lib := AnimationLibrary.new()
	for clip in spec.clips:
		var c: Dictionary = spec.clips[clip]
		var scene := _load(String(c.src))
		if scene == null:
			return false
		var ap := _find(scene, "AnimationPlayer") as AnimationPlayer
		var a := ap.get_animation(ap.get_animation_list()[0]).duplicate() as Animation
		scene.free()
		if c.has("range"):
			a = _slice(a, float(c.range[0]), float(c.range[1]))
		var dropped := _fit_to(a, bones)
		_scale_positions(a, k)
		var travel := _hold_hips(a)
		a.loop_mode = Animation.LOOP_LINEAR if c.get("loop", false) else Animation.LOOP_NONE
		a.set_meta("travel", travel)
		a.set_meta("speed", travel / a.length if a.length > 0.0 else 0.0)
		if c.has("strike"):
			a.set_meta("strike", float(c.strike))
		lib.add_animation(clip, a)
		print("  %-11s %5.2fs  travel %.2fm  %.2f m/s%s%s" % [clip, a.length, travel,
				travel / a.length, "  loop" if c.get("loop", false) else "",
				"  (%d tracks for bones this body lacks)" % dropped if dropped > 0 else ""])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(String(spec.lib)).get_base_dir())
	if ResourceSaver.save(lib, String(spec.lib)) != OK:
		printerr("  could not save %s" % spec.lib)
		return false

	var ap0 := _find(model, "AnimationPlayer")
	if ap0 != null:
		ap0.get_parent().remove_child(ap0)
		ap0.free()
	model.name = who
	_own(model, model)
	var doc := GLTFDocument.new()
	doc.image_format = "JPEG"
	doc.lossy_quality = 0.92
	var st := GLTFState.new()
	if doc.append_from_scene(model, st) != OK or doc.write_to_filesystem(st, String(spec.glb)) != OK:
		printerr("  could not write %s" % spec.glb)
		return false
	print("  -> %s  (x%.1f to %.1f m)  %s" % [spec.glb, k, HEIGHT, spec.lib])
	model.free()
	return true


## The first animation of an FBX, as a scene. `pack.zip#entry` is pulled out
## of the zip into a scratch folder first: the importer wants a file.
func _load(ref: String) -> Node:
	var path := _inbox + ref
	if "#" in ref:
		var parts := ref.split("#")
		var zr := ZIPReader.new()
		if zr.open(_inbox + parts[0]) != OK:
			printerr("  cannot open %s" % parts[0])
			return null
		var out := _tmp + parts[0].get_file().validate_filename() + "/" + parts[1]
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var bytes := zr.read_file(parts[1])
		zr.close()
		if bytes.is_empty():
			printerr("  no %s in %s" % [parts[1], parts[0]])
			return null
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		path = out
	var doc := FBXDocument.new()
	var st := FBXState.new()
	if doc.append_from_file(path, st) != OK:
		printerr("  cannot read %s" % ref)
		return null
	return doc.generate_scene(st)


## Drops the tracks for bones the body does not have. Returns how many.
func _fit_to(a: Animation, bones: Dictionary) -> int:
	var n := 0
	for i in range(a.get_track_count() - 1, -1, -1):
		var p := String(a.track_get_path(i))
		var bone := p.get_slice(":", 1) if ":" in p else ""
		if not p.begins_with("Skeleton3D:") or not bones.has(bone):
			a.remove_track(i)
			n += 1
	return n


## Holds the hips at the first frame's X and Z. Returns the horizontal
## distance the clip travelled, first frame to last (the clip is in metres by now).
func _hold_hips(a: Animation) -> float:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D or not String(a.track_get_path(i)).ends_with(":mixamorig_Hips"):
			continue
		var n := a.track_get_key_count(i)
		var p0: Vector3 = a.track_get_key_value(i, 0)
		var pn: Vector3 = a.track_get_key_value(i, n - 1)
		for j in n:
			var p: Vector3 = a.track_get_key_value(i, j)
			a.track_set_key_value(i, j, Vector3(p0.x, p.y, p0.z))
		return Vector2(pn.x - p0.x, pn.z - p0.z).length()
	return 0.0


## The FBX loads about 179 times too small. Rather than leave a scale on the
## root (which would shrink everything hung on a bone with it), the skeleton's
## rest, the skin's bind poses and the vertices are multiplied through, so the
## model is 1.7 m of real metres and a weapon in its hand is a real size.
func _to_metres(skel: Skeleton3D, mesh: MeshInstance3D, k: float) -> void:
	for i in skel.get_bone_count():
		var r := skel.get_bone_rest(i)
		r.origin *= k
		skel.set_bone_rest(i, r)
	skel.reset_bone_poses()
	var src := mesh.mesh as ArrayMesh
	var dst := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] *= k
		arrays[Mesh.ARRAY_VERTEX] = v
		dst.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
		dst.surface_set_material(s, src.surface_get_material(s))
	mesh.mesh = dst
	var skin := mesh.skin.duplicate() as Skin
	for i in skin.get_bind_count():
		var b := skin.get_bind_pose(i)
		b.origin *= k
		skin.set_bind_pose(i, b)
	mesh.skin = skin


func _scale_positions(a: Animation, k: float) -> void:
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_POSITION_3D:
			continue
		for j in a.track_get_key_count(i):
			a.track_set_key_value(i, j, (a.track_get_key_value(i, j) as Vector3) * k)


## Keeps [from, to] of a clip, re-timed to start at zero.
func _slice(a: Animation, from: float, to: float) -> Animation:
	var b := Animation.new()
	b.length = minf(to, a.length) - from
	for i in a.get_track_count():
		var t := a.track_get_type(i)
		var j := b.add_track(t)
		b.track_set_path(j, a.track_get_path(i))
		for key in a.track_get_key_count(i):
			var at := a.track_get_key_time(i, key)
			if at >= from and at <= to:
				b.track_insert_key(j, at - from, a.track_get_key_value(i, key))
	return b


func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var f := _find(c, cls)
		if f != null:
			return f
	return null
