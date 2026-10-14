extends "res://tests/test_case.gd"
## The building parts as Godot imports them (`tools/build_kit.py` →
## `assets/models/buildings/parts.glb`) and the stage that lays them out:
## every part the stage uses is there at its size with materials the stage
## knows how to replace, the town comes up as one MultiMesh per part and a
## roof per building and none over a yard, and the roof over the local
## player comes off.


func test_the_parts_the_stage_uses_are_there_at_their_sizes() -> void:
	var ps := Models.scene(Buildings3D.KIT)
	ok(ps != null, "the parts import")
	if ps == null:
		return
	var root := ps.instantiate()
	for p in Buildings3D.PARTS + Structures3D.WALL_PARTS:
		var n := root.find_child(p, true, false) as MeshInstance3D
		ok(n != null and n.mesh != null, "the parts have '%s'" % p)
		if n == null or n.mesh == null:
			continue
		for s in range(n.mesh.get_surface_count()):
			var m := n.mesh.surface_get_material(s)
			var name := m.resource_name if m != null else "null"
			ok(m != null and (FacadeArt.PALETTE.has(name) or FacadeArt.part_of(name) != 1), "'%s' surface %d is a known material, not '%s'" % [p, s, name])
	var wall := root.find_child("wall_1m", true, false) as MeshInstance3D
	if wall != null:
		var b := wall.get_aabb()
		near(b.size.x, 1.0, 0.01)
		near(b.size.y, Buildings3D.KIT_H, 0.01)
		near(b.position.x, -0.5, 0.01)
		ok(b.end.z <= 0.1 and b.position.z >= -0.35, "a wall's body sits behind its face, toward -z: %s" % b)
	var win := root.find_child("wall_window_2m", true, false) as MeshInstance3D
	if win != null:
		near(win.get_aabb().size.x, 2.0, 0.01)
	root.free()


func test_the_town_is_dressed_and_the_roof_comes_off_indoors() -> void:
	var sim := new_sim()
	var b := Buildings3D.new()
	b.build(sim.world)
	eq(b._roofs.size(), b.plan.roofed().size())
	for p in Buildings3D.PARTS:
		ok(b._mmi.has(p), "the town uses '%s'" % p)
	var ri := -1
	var yard := -1
	for i in range(b.plan.rects.size()):
		if b.plan.rects[i].position == Vector2i(150, 150):
			ri = i
		if b.plan.rects[i].position == Vector2i(206, 206):
			yard = i
	ok(ri >= 0, "the starter house")
	ok(yard >= 0 and not b._roofs.has(yard), "no roof over the compound")
	var p := sim.players[0]
	b.local = p
	p.pos = Vector2(153.5, 153.5) * Config.TILE
	b.frame()
	ok(not b.roof_visible(ri), "indoors, the roof is off")
	var others := 0
	for i in b._roofs:
		if i != ri and b.roof_visible(i):
			others += 1
	eq(others, b._roofs.size() - 1)
	p.pos = Vector2(140.5, 153.5) * Config.TILE
	b.frame()
	ok(b.roof_visible(ri), "outside, the roof is back")
	b.free()


func test_a_built_wall_is_the_house_panel_joined_by_posts() -> void:
	var sim := new_sim()
	var p := sim.players[0]
	p.bag.add("wood", 400)
	# On the highway beside the walls: build range, wherever the spawn fell.
	p.pos = tile_centre(Vector2i(141, 162))
	var s := Structures3D.new(sim)
	for t: Vector2i in [Vector2i(140, 160), Vector2i(141, 160), Vector2i(142, 160), Vector2i(142, 159)]:
		sim.world.unstick(Vector2(t) * Config.TILE, 4.0)
		var placed := sim.structs.place(sim, "woodWall", t.x, t.y, p)
		ok(not placed.is_empty(), "a wood wall stands at %s" % t)
	s.frame()
	var mid: Dictionary = s._nodes.get(Vector2i(141, 160), {})
	ok(not mid.is_empty() and (mid.parts as Array).size() == 2, "a wall between two walls is two half panels, no post")
	var corner: Dictionary = s._nodes.get(Vector2i(142, 160), {})
	ok(not corner.is_empty() and (corner.parts as Array).size() == 3, "a corner is two half panels and a post")
	var end: Dictionary = s._nodes.get(Vector2i(140, 160), {})
	ok(not end.is_empty() and (end.parts as Array).size() == 2, "a run's end is a half panel and a post")
	s.free()


func test_the_ground_under_a_wall_is_the_room_floor_not_the_yard() -> void:
	# The military hut is tiled inside and stands on the compound's gravel:
	# its south wall shows the tiles, however the neighbours are ordered.
	var w := world()
	var hut := Rect2i(210, 211, 10, 8)
	# The door is somewhere along that wall; take the first tile that is not it.
	var t := Vector2i(hut.position.x + 1, hut.end.y - 1)
	while w.tile(t.x, t.y) != Config.T.WALL:
		t.x += 1
	eq(w.tile(t.x, t.y), Config.T.WALL)
	eq(w.tile(t.x, t.y - 1), Config.T.FLOOR_TILE)
	eq(w.tile(t.x, t.y + 1), Config.T.GRAVEL)
	var art := TerrainRenderer.cell_art(w, t.x, t.y)
	eq(Terrain3D._ground_cell(w, t.x, t.y, art), TerrainRenderer.cell_art(w, t.x, t.y - 1).cell)
	# A street wall with grass both sides keeps its own art.
	var yard := Vector2i(206, 220)
	eq(w.tile(yard.x, yard.y), Config.T.WALL)
	var ya := TerrainRenderer.cell_art(w, yard.x, yard.y)
	eq(Terrain3D._ground_cell(w, yard.x, yard.y, ya), TerrainRenderer.cell_art(w, yard.x + 1, yard.y).cell)
