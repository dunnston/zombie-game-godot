"""The building kit: the pieces the 3D stage dresses a wall tile with.

    "<blender>" --background --python tools/build_kit.py
    (tools\\build_kit.cmd does this)

Writes `assets/models/buildings/kit.glb`: one object per piece, every piece a
few boxes at exact metres with named materials, which is what a script does
well and a generator does badly. The stage (`Buildings3D`) takes each piece's
mesh by its object name, swaps the materials for its own by their names, and
lays the pieces along the walls the sim generated; the siding, brick and
shingle textures are painted at boot (`FacadeArt`) and tinted per house.

The kit is the Synty way (POLYGON Town Pack, the owner's target, 2026-10-13):
a wide siding panel per face, windows and door trim as inserts, the roof built
per building by the stage because every building is a different rectangle.

Frame: a piece is modelled for one face of one 1 m wall tile. The origin is
the middle of that face's bottom edge; X runs along the face, Z is up,
**-Y is outward** (the glTF export turns Blender's -Y into Godot's +Z, so a
piece faces +Z in the game and is turned by the stage for the other three
sides). `core` alone is centred on the tile. Heights are at `H`; the stage
scales a piece to `Config.STAGE3D.wall_h`.

Materials, by name, replaced in the game: siding, brick, trim, glass, plaster,
shingle. UVs tile in metres (u along the face, v up) so one painted metre
repeats cleanly across neighbouring tiles.
"""
import os
import sys

import bmesh
import bpy
from mathutils import Vector

H = 2.2           # the authored wall height, metres
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "buildings", "kit.glb")

# Base colours are only what Blender shows; the game's materials replace them.
MATERIALS = {
    "siding": (0.90, 0.85, 0.72),
    "brick": (0.55, 0.26, 0.20),
    "trim": (0.33, 0.45, 0.62),
    "glass": (0.22, 0.28, 0.34),
    "plaster": (0.72, 0.68, 0.60),
    "shingle": (0.24, 0.25, 0.28),
}
# How many metres one repeat of a tiling texture covers, (u, v).
TILING = {"siding": (1.0, 1.0), "brick": (1.0, 0.5), "shingle": (1.0, 1.0)}


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        r, g, b = MATERIALS[name]
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value = 1.0
    return m


class Piece:
    """One kit object: boxes (and the odd prism) joined into one mesh."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.slots = []

    def _slot(self, mat):
        if mat not in self.slots:
            self.slots.append(mat)
        return self.slots.index(mat)

    def prism(self, corners, mat):
        """A convex hexahedron from 8 corners: bottom 4 then top 4, each ring
        counter-clockwise seen from outside its own face."""
        v = [self.bm.verts.new(Vector(c)) for c in corners]
        faces = [
            (v[0], v[3], v[2], v[1]),  # bottom
            (v[4], v[5], v[6], v[7]),  # top
            (v[0], v[1], v[5], v[4]),  # front
            (v[1], v[2], v[6], v[5]),  # right
            (v[2], v[3], v[7], v[6]),  # back
            (v[3], v[0], v[4], v[7]),  # left
        ]
        slot = self._slot(mat)
        tile = TILING.get(mat, (1.0, 1.0))
        for quad in faces:
            f = self.bm.faces.new(quad)
            f.material_index = slot
            f.smooth = False
            n = f.normal if f.normal.length > 0 else Vector((0, 0, 1))
            for loop in f.loops:
                loop[self.uv].uv = self._project(loop.vert.co, n, tile)
        self.bm.normal_update()

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        self.prism([
            (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
            (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1),
        ], mat)

    @staticmethod
    def _project(co, n, tile):
        # Planar UVs in metres: the two axes the face lies along, scaled to
        # the material's repeat, so siding courses line up tile to tile.
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        if az >= ax and az >= ay:
            u, v = co.x, co.y
        elif ay >= ax:
            u, v = co.x, co.z
        else:
            u, v = co.y, co.z
        return (u / tile[0], v / tile[1])

    def finish(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for mat in self.slots:
            me.materials.append(material(mat))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob


def facade_panel(p):
    # The siding panel, a brick skirt proud of it, a frieze board under the eave.
    p.box(-0.5, 0.5, -0.06, 0.0, 0.0, H, "siding")
    p.box(-0.5, 0.5, -0.10, 0.0, 0.0, 0.45, "brick")
    p.box(-0.5, 0.5, -0.09, 0.0, H - 0.14, H, "trim")


def build():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)

    # The tile itself: plaster on every side, seen from inside a house and on
    # the partition walls, which have no outward face.
    p = Piece("core")
    p.box(-0.5, 0.5, -0.5, 0.5, 0.0, H, "plaster")
    p.finish()

    p = Piece("facade")
    facade_panel(p)
    p.finish()

    # A window: frame proud of the siding, glass just in front of the panel,
    # two muntins, a sill. Synty's inserts sit proud of the panel too.
    p = Piece("facade_window")
    facade_panel(p)
    wx0, wx1, wz0, wz1 = -0.34, 0.34, 0.95, 1.95
    t = 0.06
    p.box(wx0 - t, wx1 + t, -0.14, -0.06, wz0 - t, wz0, "trim")   # bottom rail
    p.box(wx0 - t, wx1 + t, -0.14, -0.06, wz1, wz1 + t, "trim")   # top rail
    p.box(wx0 - t, wx0, -0.14, -0.06, wz0, wz1, "trim")           # left stile
    p.box(wx1, wx1 + t, -0.14, -0.06, wz0, wz1, "trim")           # right stile
    p.box(wx0, wx1, -0.075, -0.06, wz0, wz1, "glass")
    p.box(-0.02, 0.02, -0.10, -0.06, wz0, wz1, "trim")            # vertical muntin
    p.box(wx0, wx1, -0.10, -0.06, 1.43, 1.47, "trim")             # horizontal muntin
    p.box(wx0 - 0.10, wx1 + 0.10, -0.20, -0.06, wz0 - 0.12, wz0 - t, "trim")  # sill
    p.finish()

    # The reveal beside a doorway: the whole face in trim, like a door frame.
    p = Piece("jamb")
    p.box(-0.5, 0.5, -0.08, 0.0, 0.0, H, "trim")
    p.box(-0.5, 0.5, -0.10, 0.0, 0.0, 0.45, "brick")
    p.finish()

    # A corner board: square in plan, centred on the tile corner, a little
    # proud of both facades so the two sidings meet in trim.
    p = Piece("corner_board")
    p.box(-0.1, 0.1, -0.1, 0.1, 0.0, H + 0.02, "trim")
    p.finish()

    # A canopy over a 2 m doorway: a shingled slab sloping out from the
    # wall, fascia in trim, a post at each side outside the walking lane.
    p = Piece("porch_roof")
    d, th = 0.9, 0.10
    zh, zl = H + 0.30, H + 0.02
    p.prism([
        (-1.1, 0.0, zh - th), (1.1, 0.0, zh - th), (1.1, -d, zl - th), (-1.1, -d, zl - th),
        (-1.1, 0.0, zh), (1.1, 0.0, zh), (1.1, -d, zl), (-1.1, -d, zl),
    ], "shingle")
    p.box(-1.1, 1.1, -d - 0.04, -d + 0.04, zl - th - 0.04, zl + 0.02, "trim")  # fascia
    for x in (-1.05, 1.05):
        p.box(x - 0.06, x + 0.06, -d + 0.02, -d + 0.14, 0.0, zl - th, "trim")
    p.finish()

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.abspath(OUT), export_format="GLB", export_yup=True,
        export_apply=True, export_materials="EXPORT", export_texcoords=True,
        export_normals=True, export_animations=False, export_skins=False,
        export_cameras=False, export_lights=False, export_extras=False,
    )
    print("KIT wrote", os.path.abspath(OUT), "pieces:", [o.name for o in bpy.data.objects])


if __name__ == "__main__":
    build()
