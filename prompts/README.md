# Blood Hunter prompts

The game design lives in one engine-neutral file. Each engine has its own file for tech, rendering and tooling.

| File | What it is |
|---|---|
| `core-design.md` | The game: concept, Tehran setting, Persian language, powers, militia, gore, art pipeline, face JSON template, audio, build order. |
| `godot.md` | Godot 4 (Forward+, SDFGI/SSR ultra, GDScript, Jolt). The current main target. |
| `threejs.md` | Browser build with Three.js (WebGPU, TSL, Rapier). Easiest to share, least realistic. |
| `unity.md` | Unity 6 HDRP with DXR ray tracing. |
| `unreal.md` | Unreal Engine 5 with Lumen hardware ray tracing and Nanite. |

## How to use

Give a coding agent (Claude Code etc.) this, replacing the engine file:

> Read `prompts/core-design.md` and `prompts/godot.md`, then build the game following both. Start with build-order step 1 and keep every step playable.

If the agent can't read files, paste `core-design.md` followed by the engine file.

## Ray tracing by engine

| Engine | Real-time hardware ray tracing |
|---|---|
| Unreal Engine 5 | Yes (Lumen HWRT) |
| Unity HDRP | Yes (DXR) |
| Godot 4 | No; best equivalent is SDFGI + SSR + SSIL + volumetric fog |
| Three.js | No (browser); path tracing for still images only |
