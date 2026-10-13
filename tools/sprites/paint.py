"""The paint stage: turns Blender's cel renders (`art/render/<char>/`) into
sprites in the bible's painted style (`assets/sprites/<char>/`).

Each frame goes through the owner's ComfyUI as an image-to-image pass with
IP-Adapter holding the approved turnaround as the style and identity
reference. The render supplies pose, camera, direction and silhouette; the
model supplies the paint. Denoise 0.5 keeps the pose, 0.7 loses the camera
(tested 2026-10-01). The render's alpha, slightly grown, cuts the result
out, so every frame's silhouette is exactly the render's and the background
never flickers.

Runs under the `deadline-art` conda env (`tools\\paint.cmd`). Starts ComfyUI
headless if it is not already answering on its port.

    tools\\paint player walk [--denoise 0.5] [--weight 0.8] [--seed 7] [--dirs S,SE]
"""
import argparse
import glob
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(HERE))

# ---- ComfyUI on this machine -----------------------------------------------------
COMFY = r"C:\Users\ryans\ComfyUI"
API = "http://127.0.0.1:8188"
# ComfyUI's own .venv points at a Python 3.10 that no longer exists (the
# owner removed the global install; see CLAUDE.md). Its packages are intact,
# so miniconda's base 3.10 runs it with those packages on the path.
COMFY_PY = r"C:\Users\ryans\miniconda3\python.exe"
COMFY_SITE = os.path.join(COMFY, ".venv", "Lib", "site-packages")

CHECKPOINT = "juggernautxlRagnarok.k3mq.safetensors"
IPADAPTER = "ip-adapter-plus_sdxl_vit-h.safetensors"
CLIP_VISION = "CLIP-ViT-H-14-laion2B-s32B-b79K.bin"
GEN_PX = 1024          # SDXL's native size; frames go up to it and back down
MASK_GROW_PX = 2       # at sprite size: room for the painted outline
HALO_KEY = 60          # colour distance (sum of RGB) from the background that counts as paint
SLATE = (0x2F, 0x31, 0x37)

# The approved turnaround per character, five evenly spaced views in a row
# in the bible's order. Columns map to the rendered directions.
TURNAROUNDS = {
    "player": "Zombie Game Art/Good/Rugged Survivor Character Turnaround.png",
}
VIEW_ORDER = ["S", "SE", "E", "NE", "N"]

# The bible's style words plus the character's description, pasted word for
# word as the bible asks.
STYLE = ("hand-painted cel-shaded game art, bold dark brown-black outlines, hard-edged shading "
         "with 2 to 3 tones, desaturated muted colors, 3/4 view from above, full body, ")
DESCRIPTIONS = {
    "player": ("adult man with messy brown hair and a short beard, olive green canvas overshirt with "
               "rolled sleeves over a cream undershirt, brown leather belt, faded gray-blue jeans, "
               "brown lace-up boots, bare hands, large brown canvas backpack"),
}
# Seen from behind the model still wants to paint a face, so the back views
# get their own wording and a negative that forbids one.
FROM_BEHIND = {
    "player": ("adult man seen from behind, back of the head with messy brown hair, face hidden, "
               "large brown canvas backpack on his back, olive green canvas overshirt with rolled "
               "sleeves, faded gray-blue jeans, brown lace-up boots, bare hands"),
}
BACK_VIEWS = ("NE", "N")
NEGATIVE = ("photo, photorealistic, blurry, soft airbrushed shading, gradient, text, watermark, logo, "
            "signature, multiple people, cropped, deformed hands, extra limbs, glowing eyes, weapon, "
            "pedestal, base, platform, ground shadow")
NEGATIVE_BEHIND = NEGATIVE + ", face, eyes, beard, mouth, looking at viewer"


# ---- the server ------------------------------------------------------------------------
def server_up() -> bool:
    try:
        urllib.request.urlopen(API + "/system_stats", timeout=3)
        return True
    except Exception:
        return False


def ensure_server() -> None:
    if server_up():
        return
    print("starting ComfyUI headless ...")
    env = dict(os.environ, PYTHONPATH=COMFY_SITE, PYTHONNOUSERSITE="1")
    log = open(os.path.join(PROJECT, "art", "comfy.log"), "w")
    subprocess.Popen([COMFY_PY, "main.py", "--listen", "127.0.0.1", "--port", "8188", "--disable-auto-launch"],
                     cwd=COMFY, env=env, stdout=log, stderr=subprocess.STDOUT,
                     creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    for _ in range(90):
        time.sleep(2)
        if server_up():
            return
    sys.exit("ComfyUI did not come up; see art/comfy.log")


def workflow(render_name, ref_name, prompt, denoise, weight, seed, prefix, negative=NEGATIVE) -> dict:
    return {
        "1": {"class_type": "CheckpointLoaderSimple", "inputs": {"ckpt_name": CHECKPOINT}},
        "2": {"class_type": "LoadImage", "inputs": {"image": render_name}},
        "3": {"class_type": "LoadImage", "inputs": {"image": ref_name}},
        "4": {"class_type": "IPAdapterModelLoader", "inputs": {"ipadapter_file": IPADAPTER}},
        "5": {"class_type": "CLIPVisionLoader", "inputs": {"clip_name": CLIP_VISION}},
        "6": {"class_type": "IPAdapterAdvanced", "inputs": {
            "model": ["1", 0], "ipadapter": ["4", 0], "image": ["3", 0], "clip_vision": ["5", 0],
            "weight": weight, "weight_type": "style transfer", "combine_embeds": "concat",
            "start_at": 0.0, "end_at": 1.0, "embeds_scaling": "V only"}},
        "7": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": prompt}},
        "8": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["1", 1], "text": negative}},
        "9": {"class_type": "VAEEncode", "inputs": {"pixels": ["2", 0], "vae": ["1", 2]}},
        "10": {"class_type": "KSampler", "inputs": {
            "model": ["6", 0], "seed": seed, "steps": 30, "cfg": 6.0, "sampler_name": "dpmpp_2m",
            "scheduler": "karras", "positive": ["7", 0], "negative": ["8", 0],
            "latent_image": ["9", 0], "denoise": denoise}},
        "11": {"class_type": "VAEDecode", "inputs": {"samples": ["10", 0], "vae": ["1", 2]}},
        "12": {"class_type": "SaveImage", "inputs": {"images": ["11", 0], "filename_prefix": prefix}},
    }


def run_workflow(wf: dict, timeout: float = 600.0) -> str:
    """Submit, wait, return the path of the image ComfyUI wrote."""
    req = urllib.request.Request(API + "/prompt", data=json.dumps({"prompt": wf}).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r:
        d = json.load(r)
    if "error" in d or d.get("node_errors"):
        sys.exit("ComfyUI refused the workflow:\n" + json.dumps(d, indent=1))
    pid = d["prompt_id"]
    t0 = time.time()
    while time.time() - t0 < timeout:
        with urllib.request.urlopen(API + "/history/" + pid) as r:
            h = json.load(r)
        if pid in h:
            st = h[pid].get("status", {})
            if st.get("status_str") == "error":
                sys.exit("ComfyUI failed:\n" + json.dumps(st, indent=1)[:3000])
            for node in h[pid]["outputs"].values():
                for im in node.get("images", []):
                    return os.path.join(COMFY, "output", im["subfolder"], im["filename"])
        time.sleep(1)
    sys.exit("ComfyUI timed out on a frame")


# ---- images --------------------------------------------------------------------------------
def on_slate(rgba: Image.Image) -> Image.Image:
    bg = Image.new("RGBA", rgba.size, SLATE + (255,))
    bg.alpha_composite(rgba)
    return bg.convert("RGB")


def to_input(img: Image.Image, name: str) -> str:
    """Save into ComfyUI's input folder at generation size; return the name."""
    img.resize((GEN_PX, GEN_PX), Image.LANCZOS).save(os.path.join(COMFY, "input", name))
    return name


def reference(character: str, direction: str) -> str:
    """The turnaround view for this direction, squared on slate, as a ComfyUI
    input. Built from the approved sheet by splitting it into five equal
    columns, which the bible's turnaround rules guarantee."""
    name = "dl_%s_ref_%s.png" % (character, direction)
    path = os.path.join(COMFY, "input", name)
    if os.path.exists(path):
        return name
    sheet = Image.open(os.path.join(PROJECT, TURNAROUNDS[character])).convert("RGBA")
    col = sheet.width / len(VIEW_ORDER)
    i = VIEW_ORDER.index(direction)
    view = sheet.crop((int(i * col), 0, int((i + 1) * col), sheet.height))
    side = max(view.size)
    sq = Image.new("RGBA", (side, side), SLATE + (255,))
    sq.alpha_composite(view, ((side - view.width) // 2, (side - view.height) // 2))
    to_input(sq.convert("RGB"), name)
    return name


def cut_out(painted: Image.Image, render: Image.Image, size: int) -> Image.Image:
    """Shrink the painted frame to sprite size and give it the render's
    silhouette, grown a little so the painted outline survives. In the grown
    ring, anything the colour of the painted background is dropped: that is
    the halo, not the character."""
    small = painted.convert("RGB").resize((size, size), Image.LANCZOS)
    px = np.asarray(small).astype(np.int16)
    base = np.asarray(render.split()[3]) > 0
    grown = np.asarray(render.split()[3].filter(ImageFilter.MaxFilter(2 * MASK_GROW_PX + 1))) > 0
    ring = grown & ~base
    # the painted background: the median of the corners, which the render never touches
    c = np.concatenate([px[:8, :8].reshape(-1, 3), px[:8, -8:].reshape(-1, 3),
                        px[-8:, :8].reshape(-1, 3), px[-8:, -8:].reshape(-1, 3)])
    bg = np.median(c, axis=0)
    dist = np.abs(px - bg).sum(axis=2)
    keep = base | (ring & (dist > HALO_KEY))
    out = small.convert("RGBA")
    out.putalpha(Image.fromarray((keep * 255).astype(np.uint8)))
    return out


def paint(character: str, animation: str, dirs, denoise: float, weight: float, seed: int) -> list:
    src_dir = os.path.join(PROJECT, "art", "render", character)
    out_dir = os.path.join(PROJECT, "assets", "sprites", character)
    os.makedirs(out_dir, exist_ok=True)
    prompt_front = STYLE + DESCRIPTIONS[character] + ", solid flat dark slate background"
    prompt_back = STYLE + FROM_BEHIND[character] + ", solid flat dark slate background"
    written, strips = [], []
    for d in dirs:
        hits = glob.glob(os.path.join(src_dir, "%s_%s_%s_*f.png" % (character, animation, d)))
        if not hits:
            sys.exit("no render for %s %s %s; run tools\\sprites first" % (character, animation, d))
        strip = Image.open(hits[0]).convert("RGBA")
        size = strip.height
        n = strip.width // size
        ref = reference(character, d)
        frames = []
        for i in range(n):
            t = time.time()
            fr = strip.crop((i * size, 0, (i + 1) * size, size))
            name = to_input(on_slate(fr), "dl_%s_%s_%s_%02d.png" % (character, animation, d, i))
            # One seed for the whole sheet: the model's noise is the same on
            # every frame, so what changes between frames is the pose.
            behind = d in BACK_VIEWS
            result = run_workflow(workflow(name, ref, prompt_back if behind else prompt_front, denoise,
                                           weight, seed, "dl_%s_%s_%s" % (character, animation, d),
                                           NEGATIVE_BEHIND if behind else NEGATIVE))
            frames.append(cut_out(Image.open(result), fr, size))
            print("  %s %s frame %d/%d  %.0fs" % (animation, d, i + 1, n, time.time() - t))
        out = Image.new("RGBA", (size * n, size), (0, 0, 0, 0))
        for i, fr in enumerate(frames):
            out.paste(fr, (i * size, 0))
        fn = os.path.join(out_dir, os.path.basename(hits[0]))
        out.save(fn)
        side = hits[0][:-4] + ".json"
        if os.path.exists(side):
            meta = json.load(open(side))
            meta.update({"painted": True, "denoise": denoise, "ipadapter_weight": weight, "seed": seed})
            json.dump(meta, open(fn[:-4] + ".json", "w"), indent=1)
        written.append(fn)
        strips.append(out)
    # the review sheet: every direction on slate at 2x
    w = max(s.width for s in strips)
    sheet = Image.new("RGBA", (w, sum(s.height for s in strips)), SLATE + (255,))
    y = 0
    for s in strips:
        sheet.alpha_composite(s, (0, y))
        y += s.height
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.NEAREST)
    sheet.convert("RGB").save(os.path.join(out_dir, "%s_%s_contact.png" % (character, animation)))
    return written


def main() -> int:
    p = argparse.ArgumentParser(prog="tools\\paint")
    p.add_argument("character")
    p.add_argument("animation")
    p.add_argument("--dirs", default=",".join(VIEW_ORDER))
    p.add_argument("--denoise", type=float, default=0.5)
    p.add_argument("--weight", type=float, default=0.8, help="IP-Adapter style weight")
    p.add_argument("--seed", type=int, default=7)
    a = p.parse_args()
    if a.character not in TURNAROUNDS:
        p.error("no approved turnaround registered for %r (see TURNAROUNDS)" % a.character)
    dirs = [d.strip().upper() for d in a.dirs.split(",") if d.strip()]
    ensure_server()
    written = paint(a.character, a.animation, dirs, a.denoise, a.weight, a.seed)
    print("PAINT_OK %d sheets -> %s" % (len(written), os.path.relpath(os.path.dirname(written[0]), PROJECT)))
    for w in written:
        print("  " + os.path.basename(w))
    return 0


if __name__ == "__main__":
    sys.exit(main())
