#!/usr/bin/env python3
"""Blood Hunter asset generator.

Characters: image API concept -> Meshy image-to-3D -> Meshy auto-rigging (+ walk/run clips).
Props:      image API concept -> Meshy image-to-3D.
Textures:   image API only (tileable albedo).

Everything listed in manifest.json lands under assets/ where the game picks it up
automatically. Finished Meshy task ids are cached in state.json so re-runs never pay twice.

Environment:
  IMAGE_API_KEY   key for the OpenAI-compatible image API (falls back to OPENAI_API_KEY)
  IMAGE_API_BASE  default https://ai.nubixshop.ir/v1
  IMAGE_MODEL     default gpt-image-1
  MESHY_API_KEY   Meshy API key

Usage:
  python3 tools/assets/generate.py                 # everything missing
  python3 tools/assets/generate.py --kind textures
  python3 tools/assets/generate.py --only volatile --force
  python3 tools/assets/generate.py --dry-run       # print prompts, call nothing
"""

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STATE_PATH = HERE / "state.json"
MESHY = "https://api.meshy.ai/openapi/v1"

IMAGE_BASE = os.environ.get("IMAGE_API_BASE", "https://ai.nubixshop.ir/v1").rstrip("/")
IMAGE_KEY = os.environ.get("IMAGE_API_KEY") or os.environ.get("OPENAI_API_KEY", "")
IMAGE_MODEL = os.environ.get("IMAGE_MODEL", "gpt-image-1")
MESHY_KEY = os.environ.get("MESHY_API_KEY", "")


# --- HTTP -------------------------------------------------------------------

def http(method, url, key, payload=None, timeout=300):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {key}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{method} {url} -> HTTP {e.code}: {e.read().decode(errors='replace')[:500]}")


def download(url, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=600) as r, open(dest, "wb") as f:
        f.write(r.read())
    print(f"    saved {dest.relative_to(ROOT)}")


# --- Image API ----------------------------------------------------------------

def json_prompt(style, prompt):
    """Builds the structured JSON prompt the image model gets."""
    body = {"style": style}
    body.update(prompt if isinstance(prompt, dict) else {"subject": prompt})
    return json.dumps(body, ensure_ascii=False)


def generate_image(prompt_text, dest, size):
    print(f"  image -> {dest.relative_to(ROOT)}")
    res = http("POST", f"{IMAGE_BASE}/images/generations", IMAGE_KEY, {
        "model": IMAGE_MODEL,
        "prompt": prompt_text,
        "size": size,
        "n": 1,
    })
    item = res["data"][0]
    dest.parent.mkdir(parents=True, exist_ok=True)
    if item.get("b64_json"):
        dest.write_bytes(base64.b64decode(item["b64_json"]))
    else:
        download(item["url"], dest)


# --- Meshy --------------------------------------------------------------------

def meshy_wait(kind, task_id):
    while True:
        task = http("GET", f"{MESHY}/{kind}/{task_id}", MESHY_KEY)
        status = task.get("status")
        print(f"    meshy {kind} {task_id}: {status} {task.get('progress', '')}%")
        if status == "SUCCEEDED":
            return task
        if status in ("FAILED", "CANCELED", "EXPIRED"):
            raise SystemExit(f"Meshy {kind} task {task_id} {status}: {task.get('task_error')}")
        time.sleep(10)


def find_urls(obj, suffix="glb_url"):
    """Collects every '<name>_glb_url' style field from a Meshy response, wherever it sits."""
    found = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            if isinstance(v, str) and k.endswith(suffix):
                found[k] = v
            else:
                found.update(find_urls(v, suffix))
    return found


def image_to_3d(state, key, image_path):
    task_id = state.get(f"{key}:i23d")
    if not task_id:
        data_uri = "data:image/png;base64," + base64.b64encode(image_path.read_bytes()).decode()
        task_id = http("POST", f"{MESHY}/image-to-3d", MESHY_KEY, {
            "image_url": data_uri,
            "enable_pbr": True,
            "should_remesh": True,
            "topology": "triangle",
            "target_polycount": 40000,
            "should_texture": True,
        })["result"]
        state[f"{key}:i23d"] = task_id
        save_state(state)
    return task_id, meshy_wait("image-to-3d", task_id)


def rig(state, key, i23d_task_id, height):
    task_id = state.get(f"{key}:rig")
    if not task_id:
        task_id = http("POST", f"{MESHY}/rigging", MESHY_KEY, {
            "input_task_id": i23d_task_id,
            "height_meters": height,
        })["result"]
        state[f"{key}:rig"] = task_id
        save_state(state)
    return meshy_wait("rigging", task_id)


# --- Steps --------------------------------------------------------------------

def do_character(c, style, state, force, dry):
    out = ROOT / "assets/characters" / c["id"]
    if (out / "model.glb").exists() and not force:
        print(f"skip character {c['id']} (exists)")
        return
    print(f"character {c['id']}")
    prompt = json_prompt(style["character_sheet"], c["prompt"])
    if dry:
        print("  " + prompt)
        return
    concept = out / "concept.png"
    if force or not concept.exists():
        generate_image(prompt, concept, "1024x1536")
    i23d_id, _ = image_to_3d(state, f"char:{c['id']}", concept)
    rigged = rig(state, f"char:{c['id']}", i23d_id, c.get("height_m", 1.8))
    urls = find_urls(rigged)
    model_url = next((v for k, v in urls.items() if "rigged" in k or "character" in k), None)
    if not model_url:
        raise SystemExit(f"no rigged glb in Meshy response: {list(urls)}")
    download(model_url, out / "model.glb")
    for k, v in urls.items():
        for clip in ("walking", "running"):
            if clip in k:
                download(v, out / f"{clip}.glb")


def do_prop(p, style, state, force, dry):
    out = ROOT / "assets/props" / p["id"]
    if (out / "model.glb").exists() and not force:
        print(f"skip prop {p['id']} (exists)")
        return
    print(f"prop {p['id']}")
    prompt = json_prompt(style["prop_sheet"], p["prompt"])
    if dry:
        print("  " + prompt)
        return
    concept = out / "concept.png"
    if force or not concept.exists():
        generate_image(prompt, concept, "1024x1024")
    _, task = image_to_3d(state, f"prop:{p['id']}", concept)
    glb = task.get("model_urls", {}).get("glb")
    if not glb:
        raise SystemExit(f"no glb for prop {p['id']}")
    download(glb, out / "model.glb")


def do_texture(t, style, force, dry):
    dest = ROOT / "assets/textures" / f"{t['id']}.png"
    if dest.exists() and not force:
        print(f"skip texture {t['id']} (exists)")
        return
    print(f"texture {t['id']}")
    prompt = json_prompt(style["texture"], t["prompt"])
    if dry:
        print("  " + prompt)
        return
    generate_image(prompt, dest, "1024x1024")


# --- Main ---------------------------------------------------------------------

def load_state():
    return json.loads(STATE_PATH.read_text()) if STATE_PATH.exists() else {}


def save_state(state):
    STATE_PATH.write_text(json.dumps(state, indent=2))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--kind", choices=["characters", "props", "textures"])
    ap.add_argument("--only", help="generate just this id")
    ap.add_argument("--force", action="store_true", help="regenerate even if files exist")
    ap.add_argument("--dry-run", action="store_true", help="print prompts without calling any API")
    args = ap.parse_args()

    manifest = json.loads((HERE / "manifest.json").read_text())
    style = manifest["style"]
    kinds = [args.kind] if args.kind else ["textures", "characters", "props"]

    if not args.dry_run:
        if not IMAGE_KEY:
            sys.exit("IMAGE_API_KEY (or OPENAI_API_KEY) is not set")
        if any(k in kinds for k in ("characters", "props")) and not MESHY_KEY:
            sys.exit("MESHY_API_KEY is not set")

    state = load_state()
    for kind in kinds:
        for item in manifest[kind]:
            if args.only and item["id"] != args.only:
                continue
            if kind == "characters":
                do_character(item, style, state, args.force, args.dry_run)
            elif kind == "props":
                do_prop(item, style, state, args.force, args.dry_run)
            else:
                do_texture(item, style, args.force, args.dry_run)
    print("done")


if __name__ == "__main__":
    main()
