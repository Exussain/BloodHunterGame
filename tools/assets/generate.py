#!/usr/bin/env python3
"""Blood Hunter asset generator.

Characters: concept image (A-pose) -> Meshy image-to-3D -> Meshy auto-rigging (+ walk/run clips).
Props:      concept image -> Meshy image-to-3D.
Textures:   image only (tileable albedo).

Images come from Meshy's text-to-image (GPT Image 2.5 by default) or, with
IMAGE_PROVIDER=openai, from an OpenAI-compatible endpoint. Everything listed in
manifest.json lands under assets/, where the game picks it up automatically.
Finished task ids are cached in state.json so re-runs never pay twice.

Environment:
  MESHY_API_KEY   Meshy API key (required)
  IMAGE_PROVIDER  meshy (default) or openai
  MESHY_IMAGE_MODEL  default gpt-image-2-5-flare
  IMAGE_API_KEY   key for the OpenAI-compatible image API (IMAGE_PROVIDER=openai only)
  IMAGE_API_BASE  default https://ai.nubixshop.ir/v1
  IMAGE_MODEL     default gpt-image-1

Usage:
  python3 tools/assets/generate.py                 # everything missing
  python3 tools/assets/generate.py --kind textures
  python3 tools/assets/generate.py --only volatile --force
  python3 tools/assets/generate.py --stage image   # stop after concept images, to review them
  python3 tools/assets/generate.py --dry-run       # print prompts, call nothing
"""

import argparse
import base64
import concurrent.futures
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STATE_PATH = HERE / "state.json"
# Concept art stays out of the Godot project so it isn't imported into the game.
CONCEPTS = HERE / "concepts"
MESHY = "https://api.meshy.ai/openapi/v1"

MESHY_KEY = os.environ.get("MESHY_API_KEY", "")
IMAGE_PROVIDER = os.environ.get("IMAGE_PROVIDER", "meshy")
MESHY_IMAGE_MODEL = os.environ.get("MESHY_IMAGE_MODEL", "gpt-image-2-5-flare")
IMAGE_BASE = os.environ.get("IMAGE_API_BASE", "https://ai.nubixshop.ir/v1").rstrip("/")
IMAGE_KEY = os.environ.get("IMAGE_API_KEY") or os.environ.get("OPENAI_API_KEY", "")
IMAGE_MODEL = os.environ.get("IMAGE_MODEL", "gpt-image-1")

_state_lock = threading.Lock()
_forgotten = set()
_print_lock = threading.Lock()


def log(msg):
    with _print_lock:
        print(msg, flush=True)


# --- HTTP -------------------------------------------------------------------

def http(method, url, key, payload=None, timeout=300):
    data = json.dumps(payload).encode() if payload is not None else None
    attempt = 0
    while True:
        attempt += 1
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {key}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")[:500]
            if e.code == 429 and "NoMorePendingTasks" in body and attempt < 120:
                # The plan caps how many tasks can queue at once; wait for a slot.
                time.sleep(20)
                continue
            if e.code in (429, 500, 502, 503, 504) and attempt < 5:
                # Meshy sends Retry-After on rate limits; honour it.
                time.sleep(int(e.headers.get("Retry-After") or 5 * attempt))
                continue
            raise RuntimeError(f"{method} {url} -> HTTP {e.code}: {body}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if attempt < 5:
                time.sleep(5 * attempt)
                continue
            raise RuntimeError(f"{method} {url} -> {e}")


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=600) as r:
                dest.write_bytes(r.read())
            log(f"    saved {dest.relative_to(ROOT)}")
            return
        except Exception:
            if attempt == 3:
                raise
            time.sleep(5)


# --- State --------------------------------------------------------------------

def load_state():
    return json.loads(STATE_PATH.read_text()) if STATE_PATH.exists() else {}


def save_state(state):
    # Merge with what's on disk so parallel runs don't drop each other's task ids.
    with _state_lock:
        disk = load_state()
        disk.update(state)
        for k in [k for k in disk if k not in state and k in _forgotten]:
            del disk[k]
        STATE_PATH.write_text(json.dumps(disk, indent=2, sort_keys=True))


def forget(state, prefix):
    for k in [k for k in state if k.startswith(prefix)]:
        del state[k]
        _forgotten.add(k)
    save_state(state)


# --- Meshy tasks ----------------------------------------------------------------

def meshy_wait(kind, task_id):
    last = None
    while True:
        task = http("GET", f"{MESHY}/{kind}/{task_id}", MESHY_KEY)
        status = task.get("status")
        if status != last:
            log(f"    meshy {kind} {task_id[:8]}: {status}")
            last = status
        if status == "SUCCEEDED":
            return task
        if status in ("FAILED", "CANCELED", "EXPIRED"):
            raise RuntimeError(f"Meshy {kind} task {task_id} {status}: {task.get('task_error')}")
        time.sleep(8)


def meshy_task(state, key, kind, payload):
    """Creates (or resumes) a Meshy task and waits for it."""
    task_id = state.get(key)
    if not task_id:
        task_id = http("POST", f"{MESHY}/{kind}", MESHY_KEY, payload)["result"]
        state[key] = task_id
        save_state(state)
    try:
        return task_id, meshy_wait(kind, task_id)
    except RuntimeError:
        # Drop the failed task so the next run starts a fresh one.
        state.pop(key, None)
        _forgotten.add(key)
        save_state(state)
        raise


def first_image_url(task):
    for k in ("image_urls", "images"):
        v = task.get(k)
        if isinstance(v, list) and v:
            return v[0] if isinstance(v[0], str) else v[0].get("url")
    for k, v in task.items():
        if isinstance(v, str) and v.startswith("http") and "image" in k:
            return v
    raise RuntimeError(f"no image url in task: {list(task)}")


# --- Images -------------------------------------------------------------------

def json_prompt(style, prompt):
    body = {"style": style}
    body.update(prompt if isinstance(prompt, dict) else {"subject": prompt})
    return json.dumps(body, ensure_ascii=False)


def make_image(state, key, prompt, dest, aspect, pose=None):
    """Returns the Meshy text-to-image task id (None for the OpenAI provider)."""
    log(f"  image -> {dest.relative_to(ROOT)}")
    if IMAGE_PROVIDER == "openai":
        size = {"2:3": "1024x1536", "1:1": "1024x1024"}[aspect]
        res = http("POST", f"{IMAGE_BASE}/images/generations", IMAGE_KEY,
                   {"model": IMAGE_MODEL, "prompt": prompt, "size": size, "n": 1})
        item = res["data"][0]
        dest.parent.mkdir(parents=True, exist_ok=True)
        if item.get("b64_json"):
            dest.write_bytes(base64.b64decode(item["b64_json"]))
        else:
            download(item["url"], dest)
        return None
    payload = {"ai_model": MESHY_IMAGE_MODEL, "prompt": prompt[:2000], "aspect_ratio": aspect}
    if pose:
        payload["pose_mode"] = pose
    task_id, task = meshy_task(state, key + ":img", "text-to-image", payload)
    download(first_image_url(task), dest)
    return task_id


def image_to_3d(state, key, image_task_id, image_path, polycount):
    payload = {
        "ai_model": "latest",
        "should_texture": True,
        "enable_pbr": True,
        "texture_resolution": "2k",
        "should_remesh": True,
        "topology": "triangle",
        "target_polycount": polycount,
    }
    if image_task_id:
        payload["input_task_id"] = image_task_id
    else:
        payload["image_url"] = "data:image/png;base64," + base64.b64encode(image_path.read_bytes()).decode()
    return meshy_task(state, key + ":i23d", "image-to-3d", payload)


# --- Steps --------------------------------------------------------------------

def do_character(c, style, state, args):
    out = ROOT / "assets/characters" / c["id"]
    key = f"char:{c['id']}"
    if args.force:
        forget(state, key)
    done = (out / "model.glb").exists() and ((out / "animations.glb").exists() or not c.get("actions"))
    if done and not args.force and args.stage == "all":
        log(f"skip character {c['id']} (exists)")
        return
    prompt = json_prompt(style["character_sheet"], c["prompt"])
    if args.dry_run:
        log(f"character {c['id']}\n  {prompt}")
        return
    log(f"character {c['id']}")
    concept = CONCEPTS / f"characters_{c['id']}.png"
    img_id = make_image(state, key, prompt, concept, "2:3", "a-pose")
    if args.stage == "image":
        return
    i23d_id, _ = image_to_3d(state, key, img_id, concept, 30000)
    rig_id, rigged = meshy_task(state, key + ":rig", "rigging",
                                {"input_task_id": i23d_id, "height_meters": c.get("height_m", 1.8)})
    result = rigged.get("result", rigged)
    download(result["rigged_character_glb_url"], out / "model.glb")
    optimize_glb(out / "model.glb")
    actions = args.action_sets.get(c.get("actions", ""), {})
    if actions:
        animate(state, key, rig_id, actions, out)


def animate(state, key, rig_id, actions, out):
    """Bakes the preset actions into one animations.glb and writes animations.json,
    mapping the names the game plays (idle, run, ...) to the clip names inside it."""
    _, task = meshy_task(state, key + ":anim", "animations",
                         {"rig_task_id": rig_id, "action_ids": list(actions.values())})
    result = task.get("result", task)
    download(result["animation_glb_url"], out / "animations.glb")
    optimize_glb(out / "animations.glb")
    names = library_names()
    (out / "animations.json").write_text(json.dumps(
        {name: names.get(action_id, str(action_id)) for name, action_id in actions.items()}, indent=2))


_library = None


def library_names():
    global _library
    if _library is None:
        lib = http("GET", f"{MESHY}/animations/library?page_size=1000", MESHY_KEY)
        _library = {a["action_id"]: a["key"] for a in lib}  # "key" is the exported clip name
    return _library


def do_model(kind, sheet, p, style, state, args):
    """Props and buildings: concept image -> image-to-3D, saved to assets/<kind>/<id>/model.glb."""
    out = ROOT / "assets" / kind / p["id"]
    key = f"{kind[:-1]}:{p['id']}"
    if args.force:
        forget(state, key)
    if (out / "model.glb").exists() and not args.force and args.stage == "all":
        log(f"skip {kind[:-1]} {p['id']} (exists)")
        return
    prompt = json_prompt(style[sheet], p["prompt"])
    if args.dry_run:
        log(f"{kind[:-1]} {p['id']}\n  {prompt}")
        return
    log(f"{kind[:-1]} {p['id']}")
    concept = CONCEPTS / f"{kind}_{p['id']}.png"
    img_id = make_image(state, key, prompt, concept, "1:1")
    if args.stage == "image":
        return
    _, task = image_to_3d(state, key, img_id, concept, p.get("polycount", 20000 if kind == "props" else 50000))
    download(task["model_urls"]["glb"], out / "model.glb")
    # Buildings fill the screen, so they keep the full 2K texture.
    optimize_glb(out / "model.glb", 2048 if kind == "buildings" else 1024)
    if kind == "buildings":
        make_window_emission(out / "model.glb", out / "windows.png")


def do_prop(p, style, state, args):
    do_model("props", "prop_sheet", p, style, state, args)


def do_building(p, style, state, args):
    do_model("buildings", "building_sheet", p, style, state, args)


def do_texture(t, style, state, args):
    dest = ROOT / "assets/textures" / f"{t['id']}.png"
    key = f"tex:{t['id']}"
    if args.force:
        forget(state, key)
    if dest.exists() and not args.force:
        log(f"skip texture {t['id']} (exists)")
        return
    prompt = json_prompt(style["texture"], t["prompt"])
    if args.dry_run:
        log(f"texture {t['id']}\n  {prompt}")
        return
    log(f"texture {t['id']}")
    make_image(state, key, prompt, dest, "1:1")
    make_seamless(dest)


def optimize_glb(path, texture_size=1024):
    """Shrinks a Meshy GLB about 8x (WebP textures, 1K by default, pruned data) with gltf-transform,
    keeping plain geometry so Godot imports it without extensions it lacks."""
    import shutil
    import subprocess
    if not shutil.which("gltf-transform"):
        log("    (gltf-transform not installed; GLB left full size: npm i -g @gltf-transform/cli)")
        return
    tmp = path.with_suffix(".opt.glb")
    subprocess.run(["gltf-transform", "optimize", str(path), str(tmp), "--compress", "false",
                    "--texture-compress", "webp", "--texture-size", str(texture_size), "--simplify", "false",
                    "--instance", "false", "--flatten", "false", "--join", "false"],
                   check=True, capture_output=True)
    tmp.replace(path)
    log(f"    optimized {path.relative_to(ROOT)} ({path.stat().st_size // 1024} KB)")


def glb_base_color(path):
    """The first material's base colour image from a GLB, as a Pillow image."""
    import io
    import struct
    from PIL import Image
    data = path.read_bytes()
    json_len = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + json_len])
    binary = data[20 + json_len + 8:]
    tex = doc["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    texture = doc["textures"][tex]
    # gltf-transform's WebP output moves the image index into EXT_texture_webp.
    source = texture.get("source", texture.get("extensions", {}).get("EXT_texture_webp", {}).get("source"))
    view = doc["bufferViews"][doc["images"][source]["bufferView"]]
    start = view.get("byteOffset", 0)
    return Image.open(io.BytesIO(binary[start:start + view["byteLength"]])).convert("RGB")


def make_window_emission(glb, dest):
    """Finds the window glass in a building's base colour: dark, unsaturated or bluish
    panes, plus any warm lights Meshy kept from the concept. Saves it as a greyscale
    mask; the game's window shader lights a random share of it at night."""
    import numpy as np
    from PIL import Image, ImageFilter
    img = glb_base_color(glb)
    rgb = np.asarray(img, dtype=np.float32) / 255.0
    value = rgb.max(axis=2)
    sat = (value - rgb.min(axis=2)) / np.maximum(value, 1e-4)
    dark = (value < 0.32) & (sat < 0.45)
    bluish = (rgb[..., 2] > rgb[..., 0] + 0.04) & (value < 0.55)
    warm_lit = (value > 0.8) & (sat > 0.3) & (rgb[..., 0] > rgb[..., 2])
    mask = Image.fromarray(((dark | bluish | warm_lit) * 255).astype(np.uint8))
    # An opening drops thin dark lines (railings, cracks, seams) and keeps the panes.
    mask = mask.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(0.8))
    mask.save(dest, optimize=True)
    log(f"    window mask -> {dest.relative_to(ROOT)} ({np.asarray(mask).mean() / 2.55:.1f}% glass)")


def _period(signal):
    """Strongest repeat length (px) in a 1-D signal via autocorrelation, or None."""
    import numpy as np
    x = signal - signal.mean()
    n = len(x)
    ac = np.fft.irfft(np.abs(np.fft.rfft(x, 2 * n)) ** 2)[:n]
    if ac[0] <= 0:
        return None
    ac = ac / ac[0]
    lo, hi = 24, n // 2
    k = lo + int(np.argmax(ac[lo:hi]))
    return k if ac[k] > 0.35 else None


def make_seamless(path, raw_dir=HERE / "raw"):
    """Makes a generated texture tile: crops regular patterns (tiles, bricks) to a
    whole number of repeats, then cross-fades a thin border with a half-offset copy."""
    try:
        import numpy as np
        from PIL import Image
    except ImportError:
        log("    (numpy/Pillow not installed; texture left as generated)")
        return
    raw_dir.mkdir(exist_ok=True)
    raw = raw_dir / path.name
    if not raw.exists():
        raw.write_bytes(path.read_bytes())
    img = Image.open(raw).convert("RGB")
    w, h = img.size
    grey = np.asarray(img.convert("L"), dtype=np.float64)
    px, py = _period(grey.mean(axis=0)), _period(grey.mean(axis=1))
    cw = (w // px) * px if px else w
    ch = (h // py) * py if py else h
    if (cw, ch) != (w, h):
        img = img.crop((0, 0, cw, ch)).resize((w, h), Image.LANCZOS)
    a = np.asarray(img, dtype=np.float64)
    shifted = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    # Weight 1 keeps the original; it falls to 0 only within ~10% of each edge.
    yy = np.minimum(np.arange(h), np.arange(h)[::-1]) / (h * 0.1)
    xx = np.minimum(np.arange(w), np.arange(w)[::-1]) / (w * 0.1)
    m = np.clip(np.minimum.outer(yy, xx), 0, 1)
    # Smoothstep so the blend has no visible edge.
    m = (m * m * (3 - 2 * m))[..., None]
    out = a * m + shifted * (1 - m)
    Image.fromarray(out.astype(np.uint8)).save(path)
    log(f"    seamless {path.name} (period {px or '-'}x{py or '-'})")


# --- Main ---------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--kind", choices=["characters", "props", "buildings", "textures"])
    ap.add_argument("--only", help="comma-separated ids to generate")
    ap.add_argument("--force", action="store_true", help="regenerate from scratch even if files exist")
    ap.add_argument("--stage", choices=["image", "all"], default="all", help="'image' stops after concept images")
    ap.add_argument("--jobs", type=int, default=4, help="parallel assets")
    ap.add_argument("--dry-run", action="store_true", help="print prompts without calling any API")
    args = ap.parse_args()

    manifest = json.loads((HERE / "manifest.json").read_text())
    style = manifest["style"]
    args.action_sets = {k: v for k, v in manifest.get("action_sets", {}).items() if not k.startswith("_")}
    kinds = [args.kind] if args.kind else ["textures", "characters", "props", "buildings"]
    only = set(args.only.split(",")) if args.only else None

    if not args.dry_run:
        if not MESHY_KEY:
            sys.exit("MESHY_API_KEY is not set")
        if IMAGE_PROVIDER == "openai" and not IMAGE_KEY:
            sys.exit("IMAGE_API_KEY (or OPENAI_API_KEY) is not set")

    state = load_state()
    steps = {"characters": do_character, "props": do_prop, "buildings": do_building, "textures": do_texture}
    jobs = [(steps[kind], item) for kind in kinds for item in manifest[kind]
            if only is None or item["id"] in only]

    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=1 if args.dry_run else args.jobs) as pool:
        futures = {pool.submit(fn, item, style, state, args): item["id"] for fn, item in jobs}
        for f in concurrent.futures.as_completed(futures):
            try:
                f.result()
            except Exception as e:
                failures.append(futures[f])
                log(f"FAILED {futures[f]}: {e}")
    log("done" if not failures else f"done with failures: {', '.join(failures)}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
