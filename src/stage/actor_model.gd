class_name ActorModel
extends Node3D
## One body on the 3D stage: a rigged GLB from `Models` with its clips, or
## a capsule at the sim's radius in the sim's colour when there is no model
## yet. Faces a sim angle, plays a named state, flashes when hit, and holds
## a stand-in weapon in its hand. It never reads the sim: `Actors3D` tells
## it what to be each frame.

var table := {}
var anim: AnimationPlayer
var skeleton: Skeleton3D
var meshes: Array[GeometryInstance3D] = []
## The state playing now, and the library clip it resolved to: the clip is
## what decides whether a `play` changes anything, so the same state with a
## different weapon in hand, or the other of two swings, does.
var state := ""
var clip := ""
## Radius and height in metres, for the ring under the feet and the bars
## the overlay draws over the head.
var radius := 0.4
var height := 1.7
var ring: MeshInstance3D
var hand: BoneAttachment3D
var hand_item: MeshInstance3D
## Down on the ground: a body that dies like this lies where it crawled
## rather than standing up to fall (`Actors3D` keeps it current).
var crawling := false
var _capsule: MeshInstance3D
var _overlay: StandardMaterial3D
var _tinted := Color.TRANSPARENT

## A rigged model from a `Models` table, or a capsule when its scene is
## missing. `radius_px` and `height_m` size the capsule and the ring.
func setup(table_: Dictionary, radius_px: float, height_m: float, color: Color) -> void:
	table = table_
	radius = Units.m(radius_px)
	height = height_m
	var ps := Models.scene(String(table.get("scene", "")))
	if ps != null:
		var inst := ps.instantiate()
		add_child(inst)
		if table.has("scale"):
			inst.scale = Vector3.ONE * float(table.scale)
		skeleton = _find(inst, "Skeleton3D") as Skeleton3D
		_collect_meshes(inst)
		_add_clips(inst)
		if skeleton != null and table.has("hand"):
			# Godot's importer cannot keep a colon in a bone name, so Mixamo's
			# "mixamorig:RightHand" arrives as "mixamorig_RightHand".
			var bone := String(table.hand)
			if skeleton.find_bone(bone) < 0:
				bone = bone.replace(":", "_")
			if skeleton.find_bone(bone) >= 0:
				hand = BoneAttachment3D.new()
				skeleton.add_child(hand)
				hand.bone_name = bone
			else:
				push_warning("no bone %s on %s: nothing in its hand" % [table.hand, table.get("scene", "")])
	else:
		_capsule = MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = radius
		cm.height = maxf(height, radius * 2.2)
		_capsule.mesh = cm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1.0
		_capsule.material_override = mat
		_capsule.position.y = cm.height / 2.0
		add_child(_capsule)
		meshes.append(_capsule)
	_overlay = StandardMaterial3D.new()
	_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_overlay.albedo_color = Color(1, 1, 1, 0.0)


## A flat ring under the feet in a colour: the seat's for a player, the
## job's for a survivor. Readability in a crowd (pillar 4).
func add_ring(color: Color, r_mul := 1.3) -> void:
	ring = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius * r_mul
	cm.bottom_radius = radius * r_mul
	cm.height = 0.03
	ring.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.position.y = float(Config.STAGE3D.ground_eps)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)


## How fast a body turns toward where the sim says it looks, in radians a
## second: a half turn in a fifth of a second. The sim turns on the spot, so
## a shot goes where the mouse is on the tick it is fired; the body catches
## up over a few frames so a reversal reads as a turn rather than a pop.
const TURN_RATE := 5.0 * PI


## Faces a sim angle: east is 0, south a quarter turn. With a `dt` the body
## turns toward it at `TURN_RATE`; without one it is put there, which is the
## first frame, a corpse, and every enemy (the sim already steers them).
func face(angle: float, dt := 0.0) -> void:
	var want := Units.yaw(angle)
	if dt <= 0.0:
		rotation.y = want
		return
	var d := angle_difference(rotation.y, want)
	rotation.y += clampf(d, -TURN_RATE * dt, TURN_RATE * dt)


## Plays a state from the table, as the clip for `family` (a rifle's walk)
## when the table has one and as the bare state otherwise; `variant` picks
## among a state's several clips. The clip is what is compared: a clip that
## is already looping keeps looping and only takes a new speed; a one-shot
## that is still running is left to finish unless `restart`; a holding state
## (dead, downed) stays on its last frame. `speed` scales playback, so a
## swing's clip fits the swing's duration.
func play(s: String, speed := 1.0, restart := false, blend := 0.2, family := "", variant := 0) -> void:
	if anim == null:
		state = s
		return
	var c := _clip_for(s, family, variant)
	if c.is_empty():
		# Nothing to show for it: whatever was playing goes on.
		return
	if c == clip and not restart:
		if anim.is_playing():
			state = s
			anim.speed_scale = speed
			return
		if s in Models.HOLDING:
			return
	var same := c == clip
	state = s
	clip = c
	anim.speed_scale = speed
	# `blend` seconds of cross-fade from whatever pose it was in: a body that
	# is knocked down collapses into the crawl instead of snapping to it.
	anim.play(c, blend)
	# `play` on the clip already assigned keeps its place unless it had
	# reached the end, so a restart mid-clip — the second swing of a fast
	# weapon — is a seek, not a play.
	if same and restart:
		anim.seek(0.0, true)
	if s in Models.FROZEN:
		anim.seek(0.0, true)
		anim.pause()


## A state's clip at its last frame, held: a body left where it fell.
func hold_end(s: String) -> void:
	if anim == null:
		state = s
		return
	var c := _clip_for(s)
	if c.is_empty():
		return
	state = s
	clip = c
	anim.play(c)
	anim.seek(anim.get_animation(c).length, true)
	anim.pause()


## Whether the current one-shot is still running: a swing mid-way must not
## be cut by the walk underneath it. A holding state is a pose, not a move:
## the sim says when a body is dead or downed, and one that is up again
## gets up at once, however much of its fall was left.
func busy() -> bool:
	return anim != null and anim.is_playing() and not (state in Models.LOOPING) and not (state in Models.HOLDING)


## Whether the table has anything to show for a state, in this family or bare.
func has_clip(s: String, family := "") -> bool:
	return not _clip_for(s, family).is_empty()


## How long a state's clip runs at speed 1, or 0 when there is none.
func clip_length(s: String, family := "", variant := 0) -> float:
	var c := _clip_for(s, family, variant)
	if c.is_empty():
		return 0.0
	return anim.get_animation(c).length


## The metres per second a state's clip was animated at, or 0 when it does not
## travel: what playback is paced against so the feet keep up with the ground.
func clip_speed(s: String, family := "") -> float:
	var c := _clip_for(s, family)
	if c.is_empty():
		return 0.0
	return float(anim.get_animation(c).get_meta("speed", 0.0))


## The second of a state's clip at which its blow lands (`strike` meta), or
## 0 when the clip has none.
func clip_strike(s: String) -> float:
	var c := _clip_for(s)
	if c.is_empty():
		return 0.0
	return float(anim.get_animation(c).get_meta("strike", 0.0))


## An additive tint over the whole body: white for a hit, orange alight,
## transparent for none. Only the material is touched, never the mesh.
func tint(c: Color) -> void:
	if c == _tinted:
		return
	_tinted = c
	_overlay.albedo_color = c
	for m in meshes:
		m.material_overlay = _overlay if c.a > 0.001 else null


## Fades the whole body: 0 is solid, 1 is gone. For a corpse on its way out.
func fade(k: float) -> void:
	for m in meshes:
		m.transparency = clampf(k, 0.0, 1.0)


## A stand-in weapon in the hand: a bar in the weapon's colour, `length`
## metres along the hand bone, until the owner's props arrive.
func hold(color: Color, length: float) -> void:
	if hand == null:
		return
	if hand_item == null:
		hand_item = MeshInstance3D.new()
		hand_item.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.6
		hand_item.material_override = mat
		hand.add_child(hand_item)
	var box := hand_item.mesh as BoxMesh
	if not is_equal_approx(box.size.y, length):
		box.size = Vector3(0.05, length, 0.05)
		hand_item.position = Vector3(0.0, length / 2.0, 0.0)
	(hand_item.material_override as StandardMaterial3D).albedo_color = color


## A capsule has no die clip: it lies down instead.
func lie_down(down: bool) -> void:
	if _capsule == null:
		return
	_capsule.rotation.x = PI / 2.0 if down else 0.0
	_capsule.position.y = radius if down else (_capsule.mesh as CapsuleMesh).height / 2.0


## The library clip for a state: the family's own first (`rifle_walk`), then
## the bare state, then the nearest thing the model has. A state that names
## several clips gives the `variant`th of them, round and round.
func _clip_for(s: String, family := "", variant := 0) -> String:
	var clips: Dictionary = table.get("clips", {})
	var named: Variant = null
	if not family.is_empty():
		named = clips.get(family + "_" + s)
	if named == null:
		named = clips.get(s)
	if named == null:
		match s:
			"idle":
				named = clips.get("walk")
			"crouch":
				named = clips.get("idle")
			"downed":
				named = clips.get("die")
	var c := ""
	if named is Array:
		if not (named as Array).is_empty():
			c = String(named[posmod(variant, (named as Array).size())])
	elif named != null:
		c = String(named)
	if c.is_empty() or anim == null or not anim.has_animation(c):
		return ""
	return c


## A player for the clips: the model's own library, baked by
## `tools/build_anims.gd`. Its tracks are named from the skeleton's parent,
## so that is where the player roots, wherever the importer put the skeleton.
## The loop flags, root motion and speeds are already in the clips.
func _add_clips(inst: Node) -> void:
	var lib := Models.library(String(table.get("lib", "")))
	if lib == null or skeleton == null:
		return
	anim = AnimationPlayer.new()
	inst.add_child(anim)
	anim.root_node = anim.get_path_to(skeleton.get_parent())
	anim.add_animation_library("", lib)


static func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for k in n.get_children():
		var f := _find(k, cls)
		if f != null:
			return f
	return null


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		meshes.append(n)
	for k in n.get_children():
		_collect_meshes(k)
