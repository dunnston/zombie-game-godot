"""A grey figure at human height with a marked face: the camera test. It
exists so the owner can approve angle, outline weight and canvas size before
any real character is modelled. Not a game asset."""
import math

import bpy

import common

NAME = "mannequin"
HEIGHT = 1.8


def _cyl(name, r, depth, loc, mat, parent, tilt=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=24)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = tilt
    o.data.materials.append(mat)
    common.smooth(o)
    o.parent = parent
    return o


def _ball(name, r, loc, mat, parent):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=24, ring_count=12)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    common.smooth(o)
    o.parent = parent
    return o


def build(scene) -> dict:
    root = common.root_empty(NAME)
    grey = common.toon("mannequin", "#8E8E86")
    face = common.toon("mannequin_face", "#8A4A3A")
    for sx, side in ((-1, "L"), (1, "R")):
        _cyl("leg_" + side, 0.09, 0.85, (sx * 0.11, 0.0, 0.425), grey, root)
        _cyl("arm_" + side, 0.06, 0.60, (sx * 0.29, -0.03, 1.15), grey, root,
             tilt=(math.radians(-6.0), 0.0, 0.0))
        _ball("hand_" + side, 0.065, (sx * 0.29, -0.06, 0.83), grey, root)
    _cyl("torso", 0.21, 0.60, (0.0, 0.0, 1.15), grey, root)
    _ball("head", 0.13, (0.0, 0.0, 1.62), grey, root)
    # A coloured plate on the chest, so front and back read at a glance even
    # at this camera, where the face is a foreshortened sliver.
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, -0.19, 1.18))
    plate = bpy.context.object
    plate.name = "chest"
    plate.scale = (0.26, 0.06, 0.34)
    plate.data.materials.append(face)
    plate.parent = root
    return {"name": NAME, "root": root, "rig": None, "height": HEIGHT}
