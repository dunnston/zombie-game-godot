"""The one camera, one light, one outline and one palette of the Style Bible,
as a Blender scene; plus the renderer that turns a scripted character and an
animation into bible-named sprite sheets.

Runs inside Blender's own Python (`tools\\sprites.cmd`), never standalone.
Every number an owner might want to argue with is a constant at the top.
"""
import json
import math
import os

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

# ---- the bible's camera -----------------------------------------------------
CANVAS = 128            # px, square; the bible's suggested human canvas
PITCH_DEG = 45.0        # camera looks down this many degrees below horizontal
FRAME_M = 2.0           # metres of world across the canvas (ortho scale)
TARGET_Z = 0.8          # metres above the feet that sits at canvas centre
# Yaw of the character root per rendered direction. The character is built
# facing -Y, which is toward the camera: S. The engine mirrors for SW, W, NW.
DIRECTIONS = {"S": 0, "SE": 45, "E": 90, "NE": 135, "N": 180}

# ---- light and shading --------------------------------------------------------
# Direction the light travels: from the top left of the screen, a little from
# the front, so the face toward the camera is lit and the right side falls
# into shadow. The bible: one soft light, shadows down and to the right.
LIGHT_DIR = Vector((0.6, 0.45, -1.0))
SHADOW_BELOW = 0.30     # N.L under this is the shadow tone
HIGHLIGHT_ABOVE = 0.75  # N.L over this is the highlight tone
SHADOW_MUL = 0.62       # derived shadow tone = base * this (sRGB)
HIGHLIGHT_MUL = 1.18    # derived highlight tone = base * this (sRGB)

# ---- outline and backgrounds --------------------------------------------------
OUTLINE_HEX = "#2F292B"  # bible: dark brown-black, never pure black
LINE_PX = 2.0            # Freestyle thickness in pixels at CANVAS
CREASE_DEG = 60.0        # interior lines only on folds sharper than this; silhouettes
                         # between parts already draw every seam that matters
SLATE_HEX = "#2F3137"    # review background only; sheets are transparent


# ---- colour helpers -----------------------------------------------------------
def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h: str) -> tuple:
    """'#RRGGBB' to sRGB floats 0..1."""
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def linear(h: str) -> tuple:
    """'#RRGGBB' to linear RGBA for a shader input. With the Standard view
    transform this is what makes the rendered pixel equal the hex."""
    return tuple(_srgb_to_linear(c) for c in hex_rgb(h)) + (1.0,)


def shade(h: str, k: float) -> str:
    """Scale a hex colour in sRGB and clamp: the derived shadow or highlight."""
    return "#" + "".join("%02X" % int(min(1.0, c * k) * 255 + 0.5) for c in hex_rgb(h))


# ---- materials ------------------------------------------------------------------
def toon(name: str, base: str, shadow: str = None, highlight: str = None):
    """A cel material: three hard tones chosen by N.L (bible: 2 to 3 tones,
    no soft gradients). Pass palette hexes for all three or let the shadow
    and highlight derive from the base."""
    shadow = shadow or shade(base, SHADOW_MUL)
    highlight = highlight or shade(base, HIGHLIGHT_MUL)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.diffuse_color = linear(base)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    dif = nt.nodes.new("ShaderNodeBsdfDiffuse")
    dif.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    s2r = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    e0, e1 = ramp.color_ramp.elements
    e0.position, e0.color = 0.0, linear(shadow)
    e1.position, e1.color = SHADOW_BELOW, linear(base)
    e2 = ramp.color_ramp.elements.new(HIGHLIGHT_ABOVE)
    e2.color = linear(highlight)
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(dif.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def smooth(obj) -> None:
    """Smooth shading, so the toon ramp bands follow the form, not the facets."""
    for p in obj.data.polygons:
        p.use_smooth = True


# ---- the scene --------------------------------------------------------------------
def new_scene(size: int = CANVAS):
    """Factory-fresh scene with the bible's camera, light and outline. Returns
    the scene; the character goes at the origin, feet at z=0, facing -Y."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    r = sc.render
    r.engine = "BLENDER_EEVEE_NEXT"
    r.resolution_x = r.resolution_y = size
    r.resolution_percentage = 100
    r.film_transparent = True
    r.filter_size = 1.0
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.image_settings.color_depth = "8"
    sc.eevee.taa_render_samples = 16
    sc.eevee.use_shadows = True
    # Standard, not AgX or Filmic: a palette hex must come out as that hex.
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0

    world = bpy.data.worlds.new("world")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    bg.inputs["Strength"].default_value = 0.0

    cam_data = bpy.data.cameras.new("camera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = FRAME_M * size / CANVAS
    cam_data.clip_start, cam_data.clip_end = 0.1, 100.0
    cam = bpy.data.objects.new("camera", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    pitch = math.radians(PITCH_DEG)
    forward = Vector((0.0, math.cos(pitch), -math.sin(pitch)))
    cam.rotation_euler = (math.radians(90.0 - PITCH_DEG), 0.0, 0.0)
    cam.location = Vector((0.0, 0.0, TARGET_Z)) - forward * 10.0

    sun_data = bpy.data.lights.new("sun", "SUN")
    # Energy pi makes a white diffuse surface read exactly N.L into the ramp.
    sun_data.energy = math.pi
    sun_data.angle = math.radians(2.0)
    # No cast shadows: at CANVAS they are blotches, not form. The three
    # ramp tones carry the volume on their own.
    sun_data.use_shadow = False
    sun = bpy.data.objects.new("sun", sun_data)
    sc.collection.objects.link(sun)
    sun.rotation_euler = LIGHT_DIR.normalized().to_track_quat("-Z", "Y").to_euler()

    r.use_freestyle = True
    r.line_thickness_mode = "ABSOLUTE"
    r.line_thickness = LINE_PX
    vl = sc.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    fs.crease_angle = math.radians(CREASE_DEG)
    # The empty factory scene still carries a "LineSet" with no line style,
    # and Freestyle's script dies on it. Ours is the only one.
    for stray in list(fs.linesets):
        fs.linesets.remove(stray)
    ls = fs.linesets.new("outline")
    ls.linestyle = bpy.data.linestyles.new("outline")
    ls.linestyle.color = linear(OUTLINE_HEX)[:3]
    ls.linestyle.thickness = LINE_PX
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_edge_mark = True
    # Small details (straps, eyes, a beard) are a few pixels wide at CANVAS;
    # an outline of their own would swallow them. They render, but the
    # outline pass skips everything in this collection. See detail().
    det = bpy.data.collections.new("detail")
    sc.collection.children.link(det)
    ls.select_by_collection = True
    ls.collection = det
    ls.collection_negation = "EXCLUSIVE"
    return sc


def detail(obj):
    """Render `obj` without an outline of its own (see new_scene)."""
    det = bpy.data.collections["detail"]
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    det.objects.link(obj)
    return obj


def root_empty(name: str):
    """The object every part of a character hangs from. The renderer yaws it."""
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    return root


def link(obj, parent=None):
    """Put a freshly created object in the scene under `parent`."""
    if obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
    return obj


# ---- building characters -----------------------------------------------------------
# A character is a tree of empties (the joints) with primitive meshes hanging
# off them. Rotating a joint swings everything below it, so an animation is
# a handful of sines on joint rotations and nothing more. Locations are in
# the parent's frame, metres, Z up, the character facing -Y.

def joint(name: str, parent, loc=(0.0, 0.0, 0.0)):
    j = bpy.data.objects.new(name, None)
    j.empty_display_size = 0.05
    bpy.context.scene.collection.objects.link(j)
    j.parent = parent
    j.location = loc
    return j


def _finish(obj, name, mat, parent, loc, rot, scale, smooth_it):
    obj.name = name
    obj.parent = parent
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    obj.data.materials.append(mat)
    if smooth_it:
        smooth(obj)
    return obj


def cyl(name, mat, parent, loc, r, depth, rot=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=24)
    return _finish(bpy.context.object, name, mat, parent, loc, rot, scale, True)


def ball(name, mat, parent, loc, r, scale=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=24, ring_count=12)
    return _finish(bpy.context.object, name, mat, parent, loc, (0.0, 0.0, 0.0), scale, True)


def box(name, mat, parent, loc, size, rot=(0.0, 0.0, 0.0)):
    """`size` is the full extent on each axis."""
    bpy.ops.mesh.primitive_cube_add(size=1.0)
    return _finish(bpy.context.object, name, mat, parent, loc, rot, size, False)


def key(obj, frame: int, rot=None, loc=None, scale=None) -> None:
    """Set and keyframe a joint's pose on `frame`. Rotations in degrees; a
    None component keeps what the character set at build time (a splayed
    foot, a tilted head)."""
    if rot is not None:
        cur = obj.rotation_euler
        obj.rotation_euler = tuple(cur[i] if a is None else math.radians(a) for i, a in enumerate(rot))
        obj.keyframe_insert("rotation_euler", frame=frame)
    if loc is not None:
        obj.location = loc
        obj.keyframe_insert("location", frame=frame)
    if scale is not None:
        obj.scale = scale
        obj.keyframe_insert("scale", frame=frame)


# ---- pixels --------------------------------------------------------------------------
def load_pixels(path: str) -> np.ndarray:
    """A PNG as float32 RGBA, rows top-down."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1].copy()


def save_pixels(arr: np.ndarray, path: str) -> None:
    """float32 RGBA rows top-down to an 8-bit PNG with straight alpha."""
    h, w, _ = arr.shape
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=True)
    img.alpha_mode = "STRAIGHT"
    img.pixels.foreach_set(np.ascontiguousarray(arr[::-1]).ravel().astype(np.float32))
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def over_slate(arr: np.ndarray) -> np.ndarray:
    """Composite onto the bible's slate for a review image."""
    slate = np.array(hex_rgb(SLATE_HEX) + (1.0,), dtype=np.float32)
    a = arr[..., 3:4]
    out = arr * a + slate * (1.0 - a)
    out[..., 3] = 1.0
    return out


def upscale(arr: np.ndarray, k: int) -> np.ndarray:
    return np.repeat(np.repeat(arr, k, axis=0), k, axis=1)


# ---- the renderer ---------------------------------------------------------------------
def render(char: dict, anim, out_dir: str, dirs=None, size: int = CANVAS) -> list:
    """Render `anim` on `char` in every direction, pack each into a strip
    named `<character>_<animation>_<dir>_<n>f.png` with a JSON sidecar, and
    write one contact sheet of all directions on slate. Returns the strips."""
    sc = bpy.context.scene
    dirs = dirs or list(DIRECTIONS)
    frames, fps = anim.FRAMES, anim.FPS
    sc.frame_start, sc.frame_end = 1, frames
    sc.render.fps = fps
    os.makedirs(out_dir, exist_ok=True)
    # Per animation, so two renders of one character can run side by side.
    tmp = os.path.join(out_dir, ".frames_" + anim.NAME)
    os.makedirs(tmp, exist_ok=True)

    # Where the feet are on the canvas, so the engine can anchor the sprite.
    feet = world_to_camera_view(sc, sc.camera, Vector((0.0, 0.0, 0.0)))
    anchor = [round(feet.x * size, 2), round((1.0 - feet.y) * size, 2)]

    root = char["root"]
    base = "%s_%s" % (char["name"], anim.NAME)
    strips, written = [], []
    for d in dirs:
        root.rotation_euler.z = math.radians(DIRECTIONS[d])
        imgs = []
        for f in range(1, frames + 1):
            sc.frame_set(f)
            path = os.path.join(tmp, "%s_%s_%02d.png" % (base, d, f))
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            imgs.append(load_pixels(path))
        strip = np.concatenate(imgs, axis=1)
        fn = os.path.join(out_dir, "%s_%s_%df.png" % (base, d, frames))
        save_pixels(strip, fn)
        with open(fn[:-4] + ".json", "w") as fh:
            json.dump({"character": char["name"], "animation": anim.NAME,
                       "direction": d, "frames": frames, "fps": fps,
                       "loop": anim.LOOP, "size": size, "anchor": anchor}, fh, indent=1)
        strips.append(strip)
        written.append(fn)

    contact = over_slate(np.concatenate(strips, axis=0))
    save_pixels(upscale(contact, 2), os.path.join(out_dir, base + "_contact.png"))
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    return written
