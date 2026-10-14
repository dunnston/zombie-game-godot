"""The building kit: every part a Synty-style house is built from, in Blender.

    "<blender>" --background --python tools/build_kit.py
    (tools\\build_kit.cmd does this)

Writes, under `assets/models/buildings/`:
  * `parts.blend`      the parts laid out on a labelled grid, to open and look at;
  * `parts.glb`        the same parts for the game (no labels), one object each;
  * `parts_sheet.png`  a render of the grid.

(`kit.glb` beside them is the first, six-piece kit the 3D stage still lays
out, from this script as it was at commit 4f18d14; it goes when `Buildings3D`
is rebuilt on these parts.)

The owner's target is POLYGON Town Pack (2026-10-13): low-poly, flat
colours, wide siding panels with cut-outs, windows and doors as inserts
that drop into the cut-outs, roof segments, gables, dormers, porches,
floors, stud framing. Every part is boxes at exact metres: a 3 m storey, a
0.25 m wall, a 1 m grid (the game's tile), clapboard as real lapped boards
so the flat shading draws the lines. Materials are flat colours named by
swatch (`PALETTE`); a part's look is a material swap, which is how one wall
is a cream house, a grey shop or a base wall of raw planks.

Frame: X runs along a part, Z is up, **-Y is outward** (the glTF export
turns Blender's -Y into Godot's +Z). A wall's origin is the middle of its
bottom edge on the outer face plane; its body runs inward to +Y. An insert
(a window, a door) shares that origin with the wall it drops into, so the
two are placed with one transform.
"""
import math
import os

import bmesh
import bpy
from mathutils import Vector

H = 3.0          # storey height
T = 0.25         # wall thickness
B = 0.25         # a siding board's height
LAP = 0.045      # how far a board's bottom edge stands proud of the one below
PITCH = math.radians(30.0)
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "models", "buildings"))

PALETTE = {
    "siding_white": (0.90, 0.88, 0.84), "siding_cream": (0.85, 0.78, 0.62),
    "siding_blue": (0.60, 0.68, 0.74), "siding_sage": (0.65, 0.68, 0.55),
    "siding_grey": (0.52, 0.54, 0.52),
    "trim_white": (0.94, 0.92, 0.88), "trim_blue": (0.30, 0.43, 0.58),
    "trim_green": (0.29, 0.42, 0.29), "trim_brown": (0.40, 0.29, 0.21),
    "brick": (0.53, 0.29, 0.23), "plaster": (0.72, 0.69, 0.63), "concrete": (0.56, 0.55, 0.52),
    "roof_slate": (0.23, 0.24, 0.27), "roof_green": (0.31, 0.42, 0.31),
    "roof_terracotta": (0.60, 0.31, 0.23), "roof_charcoal": (0.18, 0.20, 0.21),
    "glass": (0.24, 0.30, 0.36), "door_red": (0.56, 0.23, 0.20), "door_blue": (0.21, 0.31, 0.48),
    "wood_raw": (0.55, 0.42, 0.28), "wood_dark": (0.35, 0.26, 0.19),
    "floor_wood": (0.48, 0.35, 0.23), "floor_tile_a": (0.81, 0.79, 0.74), "floor_tile_b": (0.37, 0.35, 0.33),
    "metal": (0.42, 0.42, 0.44),
}


def material(name):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        r, g, b = PALETTE[name]
        bsdf.inputs["Base Color"].default_value = (r, g, b, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.9
        m.diffuse_color = (r, g, b, 1.0)
    return m


class Piece:
    """One kit object: boxes and wedges joined into one flat-shaded mesh."""

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
        """A hexahedron from 8 corners: bottom ring then top ring, each ring
        in the same order going round."""
        v = [self.bm.verts.new(Vector(c)) for c in corners]
        quads = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        slot = self._slot(mat)
        for q in quads:
            try:
                f = self.bm.faces.new([v[i] for i in q])
            except ValueError:
                continue
            f.material_index = slot
            f.smooth = False
            n = f.normal if f.normal.length > 0 else Vector((0, 0, 1))
            for loop in f.loops:
                loop[self.uv].uv = self._project(loop.vert.co, n)

    def box(self, x0, x1, y0, y1, z0, z1, mat):
        self.prism([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
                    (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], mat)

    def board(self, x0, x1, z0, z1, mat, y_back=0.0, lap=LAP):
        """A lapped siding board on the face plane: its bottom edge stands
        `lap` proud of the plane, its top edge sits on it."""
        self.prism([(x0, -lap, z0), (x1, -lap, z0), (x1, y_back + 0.02, z0), (x0, y_back + 0.02, z0),
                    (x0, 0.0, z1), (x1, 0.0, z1), (x1, y_back + 0.02, z1), (x0, y_back + 0.02, z1)], mat)

    def siding(self, x0, x1, z0, z1, mat, holes=()):
        """Boards from z0 to z1 across x0..x1, leaving `holes`
        ((hx0, hx1, hz0, hz1)) open."""
        z = z0
        while z < z1 - 1e-6:
            top = min(z + B, z1)
            spans = [(x0, x1)]
            for hx0, hx1, hz0, hz1 in holes:
                if top <= hz0 + 1e-6 or z >= hz1 - 1e-6:
                    continue
                cut = []
                for a, b in spans:
                    if hx1 <= a or hx0 >= b:
                        cut.append((a, b))
                        continue
                    if a < hx0:
                        cut.append((a, hx0))
                    if hx1 < b:
                        cut.append((hx1, b))
                spans = cut
            for a, b in spans:
                self.board(a, b, z, top, mat)
            z = top

    @staticmethod
    def _project(co, n):
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        if az >= ax and az >= ay:
            return (co.x, co.y)
        if ay >= ax:
            return (co.x, co.z)
        return (co.y, co.z)

    def finish(self, rotation=None):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for mat in self.slots:
            me.materials.append(material(mat))
        ob = bpy.data.objects.new(self.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if rotation is not None:
            ob.rotation_euler = rotation
            bpy.context.view_layer.objects.active = ob
            ob.select_set(True)
            bpy.ops.object.transform_apply(rotation=True)
            ob.select_set(False)
        return ob


# ------------------------------------------------------------------ walls --

def wall_panel(name, w, holes=(), siding="siding_white", skirt=True):
    """A siding wall `w` metres wide: boards on the outer face, the body
    behind them, a brick skirt at the foot, plaster inside."""
    p = Piece(name)
    hx = -w / 2.0
    p.box(hx, -hx, 0.03, T, 0.0, H, "plaster")
    p.siding(hx, -hx, 0.45 if skirt else 0.0, H, siding, holes)
    if skirt:
        # The skirt stops at a hole that reaches the floor (a door).
        spans = [(hx, -hx)]
        for hx0, hx1, hz0, hz1 in holes:
            if hz0 > 0.01:
                continue
            cut = []
            for a, b in spans:
                if a < hx0 - 0.06:
                    cut.append((a, hx0 - 0.06))
                if hx1 + 0.06 < b:
                    cut.append((hx1 + 0.06, b))
            spans = cut
        for a, b in spans:
            p.box(a, b, -0.06, 0.03, 0.0, 0.45, "brick")
    # Frame the holes: a reveal through the wall in trim.
    for hx0, hx1, hz0, hz1 in holes:
        t = 0.06
        p.box(hx0 - t, hx1 + t, -0.05, T, hz0 - t, hz0, "trim_white")
        p.box(hx0 - t, hx1 + t, -0.05, T, hz1, hz1 + t, "trim_white")
        p.box(hx0 - t, hx0, -0.05, T, hz0 - t, hz1 + t, "trim_white")
        p.box(hx1, hx1 + t, -0.05, T, hz0 - t, hz1 + t, "trim_white")
    return p


WINDOW = (-0.5, 0.5, 0.9, 2.3)       # a single window's hole in a wall
DOOR = (-0.5, 0.5, 0.0, 2.2)         # a single door's hole
WIDE = (-0.9, 0.9, 0.9, 2.3)         # a double window's hole


def build_walls():
    out = []
    for w in (1, 2, 3):
        out.append(wall_panel("wall_%dm" % w, w).finish())
    out.append(wall_panel("wall_window_2m", 2, [WINDOW]).finish())
    out.append(wall_panel("wall_window_wide_3m", 3, [WIDE]).finish())
    out.append(wall_panel("wall_door_2m", 2, [DOOR]).finish())
    # A whole 2 m doorway: the game's way in is two tiles wide.
    out.append(wall_panel("wall_doorway_2m", 2, [(-0.94, 0.94, 0.0, 2.4)]).finish())
    out.append(wall_panel("wall_upper_1m", 1, skirt=False).finish())
    out.append(wall_panel("wall_upper_2m", 2, skirt=False).finish())
    out.append(wall_panel("wall_upper_window_2m", 2, [WINDOW], skirt=False).finish())
    # An interior partition: plaster both sides, no skirt, no boards.
    for w in (1, 2):
        p = Piece("wall_interior_%dm" % w)
        p.box(-w / 2.0, w / 2.0, 0.0, T, 0.0, H, "plaster")
        p.box(-w / 2.0, w / 2.0, -0.02, T + 0.02, 0.0, 0.12, "trim_white")
        out.append(p.finish())
    # A corner post, square in plan, that both facades meet in.
    p = Piece("corner_post")
    p.box(-0.14, 0.14, -0.14, 0.14, 0.0, H + 0.02, "trim_white")
    out.append(p.finish())
    # The frieze under the eave, and a skirt on its own for a plain panel.
    p = Piece("frieze_2m")
    p.box(-1.0, 1.0, -0.08, 0.0, H - 0.18, H, "trim_white")
    out.append(p.finish())
    p = Piece("foundation_2m")
    p.box(-1.0, 1.0, -0.06, T, 0.0, 0.45, "brick")
    out.append(p.finish())
    # Stud framing: what a wall is before its boards go on, and what a
    # built wall can be while it is going up.
    p = Piece("wall_frame_2m")
    p.box(-1.0, 1.0, 0.05, 0.15, 0.0, 0.1, "wood_raw")
    p.box(-1.0, 1.0, 0.05, 0.15, H - 0.1, H, "wood_raw")
    x = -1.0
    while x <= 1.0 + 1e-6:
        p.box(x - 0.025, x + 0.025, 0.05, 0.15, 0.1, H - 0.1, "wood_raw")
        x += 0.5
    out.append(p.finish())
    return out


# ---------------------------------------------------------------- inserts --

def window_insert(name, hole, muntins=True, boarded=False, shutters=False):
    hx0, hx1, hz0, hz1 = hole
    p = Piece(name)
    f = 0.07
    # Frame inside the reveal, a little proud of the face.
    p.box(hx0, hx1, -0.10, -0.02, hz0, hz0 + f, "trim_white")
    p.box(hx0, hx1, -0.10, -0.02, hz1 - f, hz1, "trim_white")
    p.box(hx0, hx0 + f, -0.10, -0.02, hz0, hz1, "trim_white")
    p.box(hx1 - f, hx1, -0.10, -0.02, hz0, hz1, "trim_white")
    p.box(hx0 + f, hx1 - f, -0.04, -0.02, hz0 + f, hz1 - f, "glass")
    if muntins:
        cx = (hx0 + hx1) / 2.0
        cz = (hz0 + hz1) / 2.0
        p.box(cx - 0.02, cx + 0.02, -0.07, -0.03, hz0 + f, hz1 - f, "trim_white")
        p.box(hx0 + f, hx1 - f, -0.07, -0.03, cz - 0.02, cz + 0.02, "trim_white")
    # The sill, proud and a touch wider than the frame.
    p.box(hx0 - 0.08, hx1 + 0.08, -0.16, -0.02, hz0 - 0.08, hz0, "trim_white")
    if boarded:
        for k, (a, b) in enumerate(((0.25, 0.55), (0.6, 0.9), (0.1, 0.4))):
            z0 = hz0 + 0.15 + k * 0.45
            p.box(hx0 - 0.1, hx1 + 0.1, -0.15, -0.10, z0, min(z0 + 0.22, hz1 + 0.05), "wood_raw")
    if shutters:
        sw = (hx1 - hx0) * 0.45
        p.box(hx0 - sw - 0.04, hx0 - 0.04, -0.09, -0.02, hz0 - 0.02, hz1 + 0.02, "trim_green")
        p.box(hx1 + 0.04, hx1 + sw + 0.04, -0.09, -0.02, hz0 - 0.02, hz1 + 0.02, "trim_green")
    return p


def door_insert(name, mat="door_red", open_=False):
    hx0, hx1, hz0, hz1 = DOOR
    p = Piece(name)
    if open_:
        # Hinged on the hole's left edge, swung outward a quarter turn.
        p.box(hx0, hx0 + 0.06, -1.0, 0.0, 0.0, hz1, mat)
        p.box(hx0 + 0.005, hx0 + 0.055, -0.85, -0.2, 0.3, 1.0, "wood_dark")
        p.box(hx0 + 0.005, hx0 + 0.055, -0.85, -0.2, 1.2, 2.0, "wood_dark")
        p.box(hx0 + 0.06, hx0 + 0.1, -0.9, -0.84, 1.0, 1.08, "metal")
    else:
        p.box(hx0 + 0.02, hx1 - 0.02, 0.02, 0.08, 0.0, hz1 - 0.02, mat)
        p.box(hx0 + 0.12, hx1 - 0.12, -0.005, 0.02, 0.3, 1.0, "wood_dark")
        p.box(hx0 + 0.12, hx1 - 0.12, -0.005, 0.02, 1.2, 2.0, "wood_dark")
        p.box(hx1 - 0.18, hx1 - 0.10, -0.04, 0.02, 1.0, 1.08, "metal")
    return p


def build_inserts():
    out = [
        window_insert("window_single", WINDOW).finish(),
        window_insert("window_wide", WIDE).finish(),
        window_insert("window_shutters", WINDOW, shutters=True).finish(),
        window_insert("window_boarded", WINDOW, boarded=True).finish(),
        door_insert("door_closed").finish(),
        door_insert("door_open", open_=True).finish(),
        door_insert("door_blue", mat="door_blue").finish(),
    ]
    return out


# ------------------------------------------------------------------ roofs --

def roof_slope(name, w, run, mat="roof_slate", courses=True):
    """A shingled slab `w` wide along the ridge and `run` down the slope
    (slope length), modelled flat and tilted to PITCH; its upper edge lies
    on the ridge line at the origin."""
    p = Piece(name)
    th = 0.12
    p.box(-w / 2.0, w / 2.0, 0.0, run, -th, 0.0, mat)
    if courses:
        s = 0.3
        while s < run - 1e-6:
            p.box(-w / 2.0, w / 2.0, s, min(s + 0.05, run), 0.0, 0.025, mat)
            s += 0.5
    # Fascia along the eave and the rakes.
    p.box(-w / 2.0, w / 2.0, run - 0.04, run + 0.04, -th - 0.03, 0.02, "trim_white")
    return p.finish(rotation=(-PITCH, 0.0, 0.0))


def gable_end(name, span, mat="siding_white"):
    """The triangle of siding that closes a roof over a `span` m deep
    building: boards shortened row by row."""
    p = Piece(name)
    rise = (span / 2.0) * math.tan(PITCH)
    p.prism([(-span / 2.0, 0.0, 0.0), (span / 2.0, 0.0, 0.0), (span / 2.0, T, 0.0), (-span / 2.0, T, 0.0),
             (-0.001, 0.0, rise), (0.001, 0.0, rise), (0.001, T, rise), (-0.001, T, rise)], "plaster")
    z = 0.0
    while z < rise - 1e-6:
        top = min(z + B, rise)
        half = (span / 2.0) * (1.0 - (z + B / 2.0) / rise)
        if half > 0.05:
            p.board(-half, half, z, top, mat)
        z = top
    return p.finish()


def build_roofs():
    out = []
    run = 3.6
    out.append(roof_slope("roof_slope_2m", 2.0, run))
    out.append(roof_slope("roof_slope_3m", 3.0, run))
    out.append(roof_slope("roof_slope_green_2m", 2.0, run, "roof_green"))
    out.append(roof_slope("roof_slope_terracotta_2m", 2.0, run, "roof_terracotta"))
    # A ridge cap along the top where two slopes meet.
    p = Piece("roof_ridge_2m")
    c = math.cos(PITCH)
    s = math.sin(PITCH)
    for side in (-1, 1):
        p.prism([(-1.0, 0.0, 0.08), (1.0, 0.0, 0.08), (1.0, side * 0.3 * c, 0.08 - 0.3 * s), (-1.0, side * 0.3 * c, 0.08 - 0.3 * s),
                 (-1.0, 0.0, 0.14), (1.0, 0.0, 0.14), (1.0, side * 0.3 * c, 0.14 - 0.3 * s), (-1.0, side * 0.3 * c, 0.14 - 0.3 * s)], "roof_slate")
    out.append(p.finish())
    out.append(gable_end("gable_end_6m", 6.0))
    out.append(gable_end("gable_end_8m", 8.0))
    # A flat roof for a shop, with a parapet all round.
    p = Piece("roof_flat_3m")
    p.box(-1.5, 1.5, -1.5, 1.5, -0.1, 0.0, "concrete")
    for x0, x1, y0, y1 in ((-1.5, 1.5, -1.5, -1.3), (-1.5, 1.5, 1.3, 1.5), (-1.5, -1.3, -1.5, 1.5), (1.3, 1.5, -1.5, 1.5)):
        p.box(x0, x1, y0, y1, 0.0, 0.5, "siding_white")
        p.box(x0 - 0.03, x1 + 0.03, y0 - 0.03, y1 + 0.03, 0.5, 0.58, "trim_white")
    out.append(p.finish())
    # A dormer: a little gabled box with a window, sat on a slope.
    p = Piece("dormer")
    w, d, h = 1.4, 1.2, 1.2
    p.box(-w / 2, w / 2, 0.0, d, 0.0, h, "plaster")
    p.siding(-w / 2, w / 2, 0.0, h, "siding_white", holes=[(-0.35, 0.35, 0.25, 1.05)])
    f = 0.06
    p.box(-0.35, 0.35, -0.08, -0.02, 0.25, 0.25 + f, "trim_white")
    p.box(-0.35, 0.35, -0.08, -0.02, 1.05 - f, 1.05, "trim_white")
    p.box(-0.35, -0.35 + f, -0.08, -0.02, 0.25, 1.05, "trim_white")
    p.box(0.35 - f, 0.35, -0.08, -0.02, 0.25, 1.05, "trim_white")
    p.box(-0.35 + f, 0.35 - f, -0.03, -0.02, 0.25 + f, 1.05 - f, "glass")
    rise = (w / 2.0) * math.tan(PITCH)
    for side in (-1, 1):
        x_out = side * (w / 2.0 + 0.2)
        p.prism([(0.0, -0.2, h + rise), (x_out, -0.2, h - 0.2 * math.tan(PITCH) * 0 + h - h), (x_out, d + 0.1, h), (0.0, d + 0.1, h + rise),
                 (0.0, -0.2, h + rise + 0.1), (x_out, -0.2, h + 0.1), (x_out, d + 0.1, h + 0.1), (0.0, d + 0.1, h + rise + 0.1)], "roof_slate")
    out.append(p.finish())
    # A chimney.
    p = Piece("chimney")
    p.box(-0.35, 0.35, -0.35, 0.35, 0.0, 1.6, "brick")
    p.box(-0.42, 0.42, -0.42, 0.42, 1.6, 1.75, "concrete")
    p.box(-0.2, 0.2, -0.2, 0.2, 1.75, 1.95, "metal")
    out.append(p.finish())
    return out


# ------------------------------------------------------------ porch, etc --

def build_porch():
    out = []
    p = Piece("porch_deck_2m")
    p.box(-1.0, 1.0, -1.5, 0.0, 0.0, 0.32, "concrete")
    x = -1.0
    while x < 1.0 - 1e-6:
        p.box(x + 0.01, min(x + 0.2, 1.0) - 0.01, -1.5, 0.0, 0.32, 0.36, "floor_wood")
        x += 0.2
    out.append(p.finish())
    p = Piece("porch_post")
    p.box(-0.07, 0.07, -0.07, 0.07, 0.0, H - 0.3, "trim_white")
    p.box(-0.1, 0.1, -0.1, 0.1, 0.0, 0.12, "trim_white")
    out.append(p.finish())
    p = Piece("porch_railing_1m")
    p.box(-0.5, 0.5, -0.04, 0.04, 0.85, 0.95, "trim_white")
    p.box(-0.5, 0.5, -0.03, 0.03, 0.08, 0.14, "trim_white")
    x = -0.4
    while x <= 0.4 + 1e-6:
        p.box(x - 0.02, x + 0.02, -0.02, 0.02, 0.14, 0.85, "trim_white")
        x += 0.2
    out.append(p.finish())
    p = Piece("porch_roof_2m")
    d = 1.2
    for x0, x1 in ((-1.0, 1.0),):
        p.prism([(x0, 0.0, H - 0.12), (x1, 0.0, H - 0.12), (x1, -d, H - 0.42), (x0, -d, H - 0.42),
                 (x0, 0.0, H), (x1, 0.0, H), (x1, -d, H - 0.3), (x0, -d, H - 0.3)], "roof_slate")
    p.box(-1.0, 1.0, -d - 0.04, -d + 0.04, H - 0.46, H - 0.28, "trim_white")
    out.append(p.finish())
    p = Piece("stairs_3step")
    for k in range(3):
        p.box(-1.0, 1.0, -0.3 * (k + 1), -0.3 * k, 0.0, 0.32 - 0.1 * k, "concrete")
    out.append(p.finish())
    return out


def build_floors():
    out = []
    p = Piece("floor_wood_1m")
    x = -0.5
    while x < 0.5 - 1e-6:
        p.box(x + 0.005, min(x + 0.2, 0.5) - 0.005, -0.5, 0.5, 0.0, 0.05, "floor_wood")
        x += 0.2
    out.append(p.finish())
    p = Piece("floor_tile_1m")
    for i in range(2):
        for j in range(2):
            p.box(-0.5 + i * 0.5, i * 0.5, -0.5 + j * 0.5, j * 0.5, 0.0, 0.05, "floor_tile_a" if (i + j) % 2 == 0 else "floor_tile_b")
    out.append(p.finish())
    p = Piece("floor_concrete_1m")
    p.box(-0.5, 0.5, -0.5, 0.5, 0.0, 0.05, "concrete")
    out.append(p.finish())
    return out


# ----------------------------------------------------------------- layout --

def label(text, at):
    cu = bpy.data.curves.new(type="FONT", name="label_" + text)
    cu.body = text
    cu.size = 0.28
    cu.align_x = "CENTER"
    ob = bpy.data.objects.new("label_" + text, cu)
    ob.location = at
    bpy.context.scene.collection.objects.link(ob)
    labels = bpy.data.collections.get("Labels")
    if labels is None:
        labels = bpy.data.collections.new("Labels")
        bpy.context.scene.collection.children.link(labels)
    labels.objects.link(ob)
    bpy.context.scene.collection.objects.unlink(ob)
    return ob


def lay_out(rows):
    """Rows of objects on a grid: each row 6 m apart, each part spaced by
    its width plus a metre, labels on the ground in front."""
    y = 0.0
    bounds = [0.0, 0.0, 0.0, 0.0]
    for title, objects in rows:
        x = 0.0
        label(title.upper(), (x - 1.0, -y + 1.2, 0.0))
        for ob in objects:
            dims = ob.dimensions
            w = max(dims.x, 1.0)
            ob.location = (x + w / 2.0, -y, 0.0)
            label(ob.name, (x + w / 2.0, -y - 1.0, 0.0))
            x += w + 1.0
        bounds[1] = max(bounds[1], x)
        y += 7.0
    bounds[3] = y
    return bounds


def render(bounds, path):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.shadow_intensity = 0.35
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = "BOTH"
    scene.display.shading.cavity_ridge_factor = 1.5
    scene.display.shading.cavity_valley_factor = 1.5
    scene.display.shading.curvature_ridge_factor = 1.0
    scene.display.shading.curvature_valley_factor = 1.0
    scene.display.shading.show_object_outline = True
    scene.render.resolution_x = 2600
    scene.render.resolution_y = 1700
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.27, 0.27, 0.29, 1.0)
    cam_data = bpy.data.cameras.new("SheetCamera")
    cam_data.type = "ORTHO"
    w = bounds[1]
    h = bounds[3]
    tilt = math.radians(32.0)
    cam_data.ortho_scale = max(w + 2.0, (h * math.cos(tilt) + 1.0) * 2600.0 / 1700.0) * 1.0
    cam = bpy.data.objects.new("SheetCamera", cam_data)
    scene.collection.objects.link(cam)
    # Three-quarter view from the front: pitched 55° down, looking north.
    cx = w / 2.0 - 1.0
    cy = -(h / 2.0) + 3.5
    cam.location = (cx, cy - 60.0 * math.tan(tilt), 60.0)
    cam.rotation_euler = (tilt, 0.0, 0.0)
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


def build():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    rows = [
        ("walls", build_walls()),
        ("inserts", build_inserts()),
        ("roofs", build_roofs()),
        ("porch", build_porch()),
        ("floors", build_floors()),
    ]
    os.makedirs(OUT_DIR, exist_ok=True)
    # The game's file: parts only, every part at the origin.
    for ob in bpy.data.objects:
        ob.location = (0.0, 0.0, 0.0)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, "parts.glb"), export_format="GLB", export_yup=True,
        export_apply=True, export_materials="EXPORT", export_texcoords=True,
        export_normals=True, export_animations=False, export_skins=False,
        export_cameras=False, export_lights=False, export_extras=False,
    )
    # The owner's file: the grid, labelled, and its picture.
    global _ROWS
    _ROWS = rows
    bounds = lay_out(rows)
    render(bounds, os.path.join(OUT_DIR, "parts_sheet.png"))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT_DIR, "parts.blend"), compress=True)
    names = [o.name for o in bpy.data.objects if o.type == "MESH"]
    print("KIT wrote %d parts to %s: %s" % (len(names), OUT_DIR, ", ".join(names)))


if __name__ == "__main__":
    build()


def render_rows(rows, out_dir):
    """Close-ups, one per row, for checking the parts (not shipped)."""
    scene = bpy.context.scene
    cam = scene.camera
    for title, objects in rows:
        xs = [ob.location.x - ob.dimensions.x / 2.0 for ob in objects] + [ob.location.x + ob.dimensions.x / 2.0 for ob in objects]
        y = objects[0].location.y
        w = max(xs) - min(xs) + 2.0
        cam.data.ortho_scale = max(w, 9.0 * 2600.0 / 1700.0)
        tilt = math.radians(28.0)
        cam.rotation_euler = (tilt, 0.0, 0.0)
        cam.location = ((max(xs) + min(xs)) / 2.0, y + 1.0 - 30.0 * math.tan(tilt), 30.0)
        scene.render.filepath = os.path.join(out_dir, "row_%s.png" % title)
        bpy.ops.render.render(write_still=True)


if os.environ.get("KIT_ROWS"):
    render_rows(_ROWS, os.environ["KIT_ROWS"])
