extends "res://tests/test_case.gd"
## The building kit as Godot imports it (`tools/build_kit.py` →
## `assets/models/buildings/kit.glb`) and the stage that lays it out: every
## piece is there at its size with the materials the stage knows how to
## replace, the town comes up as one MultiMesh per piece and a roof per
## building, and the roof over the local player comes off.


func test_the_kit_has_every_piece_at_its_size_in_known_materials() -> void:
	var ps := Models.scene(Buildings3D.KIT)
	ok(ps != null, "the kit imports")
	if ps == null:
		return
	var root := ps.instantiate()
	for p in Buildings3D.PIECES:
		var n := root.find_child(p, true, false) as MeshInstance3D
		ok(n != null and n.mesh != null, "the kit has '%s'" % p)
		if n == null or n.mesh == null:
			continue
		for s in range(n.mesh.get_surface_count()):
			var m := n.mesh.surface_get_material(s)
			ok(m != null and FacadeArt.PARTS.has(m.resource_name), "'%s' surface %d is a known material, not '%s'" % [p, s, m.resource_name if m != null else "null"])
	var facade := root.find_child("facade", true, false) as MeshInstance3D
	if facade != null:
		var b := facade.get_aabb()
		near(b.size.x, 1.0, 0.01)
		near(b.size.y, Buildings3D.KIT_H, 0.01)
		near(b.position.x, -0.5, 0.01)
		ok(b.position.z >= -0.001 and b.end.z <= 0.25, "a facade stands proud of the face toward +z, not into the tile")
	var core := root.find_child("core", true, false) as MeshInstance3D
	if core != null:
		var b := core.get_aabb()
		near(b.position.x, -0.5, 0.01)
		near(b.position.z, -0.5, 0.01)
		near(b.size.z, 1.0, 0.01)
	root.free()


func test_the_town_is_dressed_and_the_roof_comes_off_indoors() -> void:
	var sim := new_sim()
	var b := Buildings3D.new()
	b.build(sim.world)
	eq(b._roofs.size(), b.plan.rects.size())
	for p in Buildings3D.PIECES:
		ok(b._mmi.has(p), "the town uses '%s'" % p)
	var ri := -1
	for i in range(b.plan.rects.size()):
		if b.plan.rects[i].position == Vector2i(150, 150):
			ri = i
	ok(ri >= 0, "the starter house")
	var p := sim.players[0]
	b.local = p
	p.pos = Vector2(153.5, 153.5) * Config.TILE
	b.frame()
	ok(not b.roof_visible(ri), "indoors, the roof is off")
	var others := 0
	for i in range(b._roofs.size()):
		if i != ri and b.roof_visible(i):
			others += 1
	eq(others, b._roofs.size() - 1)
	p.pos = Vector2(140.5, 153.5) * Config.TILE
	b.frame()
	ok(b.roof_visible(ri), "outside, the roof is back")
	b.free()
