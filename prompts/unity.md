# Blood Hunter: Unity Prompt

> Use with `core-design.md`. Prompt for a coding agent: "Read `prompts/core-design.md` and `prompts/unity.md`, then build the game in Unity following both."

## Engine

- **Unity 6 (latest LTS)**, **HDRP**, Windows PC, DX12. C# scripts.
- Input System package, Cinemachine for the predator camera, AI Navigation package (NavMesh) for the militia.

## Graphics: ultra

- **Ray tracing (DXR) on Ultra:** ray-traced reflections (wet streets, puddles, station windows), ray-traced ambient occlusion, ray-traced shadows for key lights, and ray-traced or SSGI global illumination. Fall back to screen-space versions on lower presets and non-RT GPUs.
- Volumetric fog with local volumetric fog volumes for streetlight shafts, smoke and fire.
- Physically based sky at night, sodium streetlights as area/point lights with shadow budget, and HDRP decals for blood.
- DLSS / FSR upscaling, TAA, and quality presets (Ultra RT, High, Medium, Low).

## Persian and RTL

TextMeshPro does not shape Persian by itself. Use the open-source **RTLTMPro** package (or equivalent) for correct letter joining and RTL, the Vazirmatn font as a TMP font asset, and the Localization package for Persian + English tables.

## Characters, animation, gore

- Mixamo, Quaternius or Kenney rigs imported as **Humanoid** so Mecanim retargets every animation. Animator with blend trees for locomotion, climb, wall-run and pounce.
- **Dismemberment:** a gore/dismemberment asset compatible with Humanoid rigs (ask before buying), or a custom version: scale bone to zero, spawn pre-cut limb prefab with cap, VFX Graph blood, pooled HDRP decals.
- Ragdolls via Character Joints.

## Structure

```
Assets/   (Scenes/, Scripts/, Prefabs/, Characters/, Environment/, Audio/Music/Placeholders/, Fonts/, Localization/)
Docs/licenses.md
```

Each district is a scene loaded additively with a loading screen.
