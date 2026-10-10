# Blood Hunter: Three.js (Browser) Prompt

> Use with `core-design.md`. Prompt for a coding agent: "Read `prompts/core-design.md` and `prompts/threejs.md`, then build the game with Three.js following both."

## Reality check

A browser build is the easiest to share but the weakest at realism. Scale expectations: one compact Haft Hoz block and the کلانتری, fewer simultaneous enemies (8 to 12), and baked lighting doing most of the work. There is **no real-time ray tracing in the browser**; a path tracer can be used only for marketing stills.

## Stack

- **Three.js, latest release**, using **WebGPURenderer** with automatic WebGL 2 fallback. Write materials and effects in TSL (Three Shading Language) so they compile for both.
- **TypeScript + Vite.**
- **Physics:** Rapier (`@dimforge/rapier3d-compat`) for the character controller, ragdolls and severed limbs.
- **Assets:** glTF 2.0 (.glb) with Draco or Meshopt geometry compression and KTX2 (Basis) textures. Use `three-mesh-bvh` for fast raycasts against city geometry.
- **Audio:** Three.js PositionalAudio on the Web Audio API.

## Graphics: ultra in a browser

- Baked lightmaps and AO for the district (bake in Blender), plus dynamic lights only for streetlights near the player, muzzle flashes and fire.
- Post-processing: GTAO or N8AO for ambient occlusion, SSR for wet roads where WebGPU is available, bloom, ACES tonemapping, and a rage-form chromatic/red vignette pass.
- Fog: height fog plus cheap volumetric light cones on streetlights.
- Shadows: cascaded shadow map for moonlight, limited shadow-casting spot lights.
- Quality presets (Ultra, High, Low) that scale resolution, shadow size, post effects and enemy count. Target 60 fps on a mid-range laptop at High.

## Persian and RTL

Build UI as an HTML/CSS overlay with `dir="rtl"` and `lang="fa"`; the browser shapes Persian natively. Ship Vazirmatn as a web font. For in-world text (signs), use `troika-three-text`, which handles bidi and Arabic-script shaping, or bake signs into textures.

## Characters, animation, gore

- Mixamo, Quaternius or Kenney rigs converted to .glb, all on one skeleton. Retarget with `SkeletonUtils.retargetClip` or by exporting clips onto the shared rig in Blender.
- `AnimationMixer` with crossfades for locomotion, climb, wall-run and pounce.
- **Dismemberment:** pre-split each character into limb meshes in Blender (cap meshes at cut points), hide a limb by scaling its bone to zero, spawn the matching limb as a Rapier rigid body, and add blood particles (instanced sprites) and decals (`DecalGeometry`, pooled and capped).
- Faces: project the generated face onto the head texture in Blender, then re-export.

## Structure

```
index.html
src/   (main.ts, player/, enemies/, world/, ui/, audio/, gore/)
public/assets/   (characters/, districts/, audio/music/placeholders/, fonts/)
docs/licenses.md
```

Lazy-load each district's .glb and audio. Run `tsc --noEmit` and `vite build` before each commit.
