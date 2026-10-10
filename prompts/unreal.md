# Blood Hunter: Unreal Engine Prompt

> Use with `core-design.md`. Prompt for a coding agent: "Read `prompts/core-design.md` and `prompts/unreal.md`, then build the game in Unreal Engine following both."

## Engine

- **Unreal Engine 5, latest stable release**, Windows PC, DX12. C++ for core systems, Blueprints for content and tuning.
- Enhanced Input, Gameplay Ability System for powers (pounce, tendril, scream, rage form, feed), State Trees or Behavior Trees for militia AI, AI Perception for sight and hearing.

## Graphics: ultra

- **Lumen** with **hardware ray tracing** enabled on Ultra for GI and reflections (wet streets, windows), and virtual shadow maps. Software Lumen on lower presets.
- **Nanite** for buildings and street props; World Partition for districts.
- Exponential height fog with volumetric fog, local fog volumes for streetlight shafts, smoke and fire.
- TSR upscaling (DLSS/FSR plugins optional), scalability presets (Ultra RT, High, Medium, Low).

## Persian and RTL

Slate/UMG shapes Arabic-script text via HarfBuzz and supports RTL flow. Import Vazirmatn as a Font asset, set text flow direction to RTL, and use the Localization Dashboard for Persian + English.

## Characters, animation, gore

- Mixamo, Quaternius or Kenney rigs retargeted to the UE5 Mannequin via IK Retargeter, so all animation sets share one skeleton. Motion Matching or an Animation Blueprint with blend spaces for locomotion, climb, wall-run and pounce.
- **Dismemberment:** hide the bone below the cut (`HideBoneByName`), spawn a pre-cut limb actor with a cap mesh and physics, Niagara blood, and pooled decals. Ragdolls via Physics Asset.
- Faces: project the generated face onto the head texture in Blender, or use MetaHuman Creator with fictional faces once the owner's models arrive.

## Structure

```
Source/BloodHunter/   (Player/, Abilities/, AI/, Gore/, UI/)
Content/   (Maps/, Characters/, Environment/, Audio/Music/Placeholders/, Fonts/, Localization/)
Docs/licenses.md
```
