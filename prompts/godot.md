# Blood Hunter: Godot Engine Prompt

> Use with `core-design.md`. Prompt for a coding agent: "Read `prompts/core-design.md` and `prompts/godot.md`, then build the game in Godot following both."

## Engine and language

- **Godot 4, latest stable release**, **Forward+** renderer, Vulkan (D3D12 allowed on Windows). Target Windows PC; keep Linux export working.
- **GDScript** with static typing everywhere (`var hp: int`). C# only if a hot path proves too slow.
- **Physics:** Jolt (the built-in Jolt option in Project Settings), for stable ragdolls and many bodies.

## Graphics: "ultra" in Godot, honestly

Stock Godot 4 has **no hardware ray tracing** (no DXR/RT-core GI, reflections or shadows). Do not promise it or add unmaintained forks. Get the closest look with its real-time GI stack, and keep the renderer swappable in case official ray tracing lands later.

Ultra preset (default), with High, Medium and Low presets in the settings menu:
- **Global illumination:** SDFGI on the open streets (high cascades, occlusion on, bounce feedback). Use VoxelGI or baked LightmapGI for the کلانتری interior.
- **Reflections:** SSR (enhanced) for wet asphalt and puddles, plus ReflectionProbes at street corners and indoors.
- **Ambient:** SSAO + SSIL at ultra quality.
- **Fog:** volumetric fog with FogVolumes for streetlight shafts, smoke and fire.
- **Shadows:** 4096 directional and positional shadow atlas, soft shadows (PCSS-style filter quality ultra), sodium streetlights as shadow-casting OmniLights with a distance fade budget.
- **Anti-aliasing:** TAA + FSR 2 upscaling (quality mode), with MSAA as an option.
- **Post:** glow, ACES or AgX tonemapping, auto exposure, depth of field on feed/finisher, chromatic and red-vignette shader for rage form.
- **Materials:** StandardMaterial3D or ORMMaterial3D PBR, with wet-surface shader (roughness down, darker albedo, ripple normal), and decal-based blood.
- **Performance:** visibility ranges (HLOD) and occlusion culling for the district, mesh LOD on import, and a profiler pass each milestone. Target 60 fps on a mid-range GPU at High.

## Persian and RTL

Godot 4's Advanced Text Server (HarfBuzz + ICU) shapes Persian natively. Set `text_direction = RTL` on Controls, ship Vazirmatn as a FontFile, set the project locale to `fa`, and use Godot's translation system (`.po` or CSV) for Persian + English subtitles. Test ی and ک (Persian, not Arabic, code points) and Persian digits.

## Characters, animation, gore

- Import Mixamo, Quaternius or Kenney characters as **.glb** (convert FBX through Blender). Map each one to `SkeletonProfileHumanoid` with a **BoneMap** at import so all animations retarget onto one skeleton.
- Use AnimationTree with a state machine and blend spaces for locomotion, climb, wall-run and pounce. Use root motion for attacks and feeding.
- Ragdolls via PhysicalBoneSimulator3D.
- **Dismemberment:** on a severing hit, scale the bone to zero on the live skeleton (hide the limb), spawn a pre-cut limb mesh (RigidBody3D) with a cap mesh at the wound, emit blood GPUParticles3D, and spray Decal nodes. Pool decals and cap their count for performance.
- **Faces:** project the generated face texture onto the head UVs in Blender (front + profile projection, bake to the head's texture), then re-export .glb.

## AI and world

- NavigationRegion3D baked per district chunk, NavigationAgent3D for militia, with NavigationLinks for ladders and stairs.
- Enemy brain as a simple state machine (patrol, investigate, alert, combat, panic, flee). Use RayCast3D and an Area3D for perception, and hearing via signals from player noise events.
- Districts as separate scenes, loaded with `ResourceLoader.load_threaded_request` behind a loading screen.

## Project layout

```
project.godot
scenes/   (districts/, player/, enemies/, ui/)
scripts/
assets/   (characters/, environment/, audio/music/placeholders/, audio/vo/, fonts/)
localization/
docs/licenses.md
```

Run headless checks (`godot --headless --check-only` or `--quit` on main scenes) before each commit when the Godot binary is available.
