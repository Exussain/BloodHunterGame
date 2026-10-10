# Blood Hunter: Core Design (engine-neutral)

> This is the shared game design. Pair it with one engine file in this folder (`godot.md`, `threejs.md`, `unity.md`, `unreal.md`). The engine file decides tech, rendering and tooling; this file decides the game. See `README.md`.

---

## Role and goal

You are the lead developer on **Blood Hunter**, a brutal 18+ single-player action game targeting **desktop PC** in the engine named by the paired engine file. Build it incrementally: a playable vertical slice first, then expand. Commit working, playable states often. Ask before adding paid assets.

## Age gate

Show a full-screen Persian + English warning on first launch before anything else:
"این بازی شامل خشونت شدید و صحنه‌های خونین است. فقط برای بزرگسالان ۱۸+. مناسب کودکان نیست."
("Extreme violence and gore. Adults 18+ only. Not suitable for children.") The player must confirm they are 18+ to continue.

## Concept

You play the **last and only volatile in Tehran**: a lone apex predator in a red human outfit, a single red figure tearing through the city. The government has set you loose on a **traitor militia in Sipah-style uniforms** who betrayed the state and killed innocent protesters. They have seized parts of the city, starting with a police station (کلانتری) in Haft Hoz. Your handler radios you contracts. You stalk, strike, feed, grow, and go berserk.

There are no UV lights or anti-volatile tech. The militia's threat is **numbers, firepower and fortification**: assault rifles, heavy machine guns on armed pickups, RPGs, grenades, Molotovs and fire, barricades, sandbagged checkpoints, searchlights and alarms that call in reinforcements.

## Setting and language

- **Realistic Tehran at night.** Dusk to dawn, with sodium streetlights, wet asphalt, apartment blocks with balconies and AC units, shuttered shops, Persian signage, murals, motorbikes, Paykan and Pride cars, power lines and rooftops you can traverse.
- **Everything in Persian.** All UI, menus, subtitles, signs, radio and barks are in Persian with correct RTL text shaping (use a Persian font such as Vazirmatn; see the engine file for how RTL is handled). Include an optional English subtitle toggle.
- **District plan:**
  1. **Vertical slice: Haft Hoz (Narmak).** The square and surrounding streets, rooftops and alleys, centered on the **captured کلانتری**. The station has an outer perimeter with checkpoints and armed pickups, rooftop approach routes, an interior with lobby, cells, armory and records room, and the **militia commander's office as the boss room**.
  2. **Expansion 1: Enghelab.**
  3. **Expansion 2: میدان علیخانی.**
  Each district is a separate scene, with loading between districts.

## Core loop

Each night is a set of **handler contracts** delivered by radio in Persian, e.g. kill the checkpoint commander, destroy the ammo truck, free hostages in the cells, cut the station's radio. The player chooses the order.

Every encounter follows a **stalk-then-rage rhythm**:
1. **Stalk.** Silent approach over rooftops and walls, picking off isolated militia, avoiding searchlights. You hear your own heartbeat.
2. **Strike.** Pounce, grab and kill. Enemies who see a body or hear a scream raise the alarm.
3. **Rage.** Once spotted, the fight goes loud: reinforcements, pickups and RPGs. You fight through with feeding and powers, or break line of sight and return to stalking.

The night ends when all contracts are done, or at dawn (fail state: retreat to your lair).

## Player powers (skill tree via feeding)

Feeding on downed enemies restores health and fills a **mutation meter**. Each tier unlocks the next power.

| Tier | Power | Description |
|---|---|---|
| Start | **Pounce and wall-run** | Climb any wall, run along walls, leap across rooftops, dive onto targets from above. |
| Start | **Feed** | Eat a downed enemy to heal and gain mutation. Leaves you vulnerable for the duration. |
| Tier 1 | **Tendril grab** | Yank an enemy off a rooftop or out of cover (like the L4D Smoker). |
| Tier 2 | **Scream** | Stun a squad in a cone; enemies panic, drop weapons, scatter. |
| Tier 3 | **Rage form** | Timed super-volatile state: bigger, faster, near-unkillable, with a distorted audio/visual filter. |

Controls follow Dying Light's "Be the Zombie" Night Hunter as the feel reference: fast third-person (or first-person, configurable) predator movement, momentum-based leaps, and sticky wall contact.

## Enemies (traitor militia)

- **Look:** a mix of varied civilian clothes and **Sipah-style uniforms**. Use Sipah-inspired uniforms with invented insignia and unit names, not the real emblem.
- **Archetypes:** rifleman, heavy machine gunner (pickup-mounted), RPG gunner, Molotov thrower, officer (buffs squad, calls reinforcements), checkpoint commander (mini-boss), station commander (district boss).
- **AI:** patrols, investigates noises and bodies, raises alarms, takes cover, suppresses, flanks, panics at low morale or after a scream, and flees from rage form.
- **Barks in Tehrani Persian:** spotting ("اونجاست!"), panic ("عقب‌نشینی!"), calls for help, radio chatter.

## Gore (maximum, phased)

- **Phase 1 (slice):** full dismemberment (limbs, decapitation), persistent blood decals on walls and floors, blood pools, bodies that stay where they fall, wound decals. Implement on the shared humanoid skeleton (see the engine file for the approach).
- **Phase 2 (after custom models):** close-up finisher animations on feed and tendril grab.

## Art pipeline

- **Placeholder characters:** free, publicly available **rigged** humanoids (Mixamo, Quaternius, Kenney) on one shared humanoid skeleton, so animations retarget and the owner's final 3D models can drop in later.
- **Custom faces:** generate fictional faces with ChatGPT's image generator from the JSON template below. Apply them to the head mesh using a face-projection or texture-baking step. Faces must be fictional people, never real, identifiable individuals.
- **Environment:** the highest-quality night lighting the engine allows: volumetric fog, wet-road reflections, sodium streetlights. Use realistic urban kits (CC0 or properly licensed) dressed with Persian signage, and keep asset licenses in `docs/licenses.md`.
- **Interchange format:** keep characters and props as **glTF 2.0 (.glb)** where possible, with FBX as a fallback, so the same assets work in every engine.

### JSON prompt template for face textures

```json
{
  "task": "game-ready face texture for 3D character head projection",
  "subject": {
    "gender": "male",
    "age": 35,
    "ethnicity": "Iranian",
    "features": "short dark beard, thick eyebrows, weathered skin",
    "identity": "fictional person, not resembling any real individual"
  },
  "framing": "perfectly front-facing, head and neck only, centered, eyes level, symmetrical",
  "expression": "neutral, mouth closed, eyes open",
  "lighting": "flat, even, shadowless studio light; no specular highlights; no rim light",
  "exclusions": ["hair over face", "hats", "glasses", "makeup", "text", "background objects", "dramatic shadows"],
  "background": "plain mid-grey",
  "style": "photorealistic skin texture, pores visible, color-accurate albedo",
  "output": { "aspect_ratio": "1:1", "resolution": "2048x2048" }
}
```

Vary `subject` per character. For a side profile, duplicate the entry with `"framing": "exact 90-degree left profile"` for better projection.

## Audio

- **Voice:** Persian voice acting for the handler and the militia. Placeholders use generic AI-generated voices performing as Sipah-style soldiers and officers. No cloning of real, identifiable people's voices. Replace with real actors later.
- **Music:** dark Rammstein-style industrial metal for the hunt, with intensity layers for stalk vs. rage. Build with **silent or simple generated placeholder tracks** in a clearly named folder (`Audio/Music/Placeholders/`) so the owner can drop in licensed files with matching names.
- **Volatile:** screams, breathing, growls, your own heartbeat while stalking, and a distorted soundscape in rage form.
- **City ambience:** distant sirens, the call to prayer at dusk, motorbikes, dogs, radio static from the captured station.

## Build order

1. Engine project setup (per engine file), folder structure, Persian RTL UI, and the age gate.
2. Player controller: wall-climb, wall-run, pounce, feed.
3. One militia rifleman with patrol, alert and combat AI. Add dismemberment and blood decals.
4. Haft Hoz greybox with the کلانتری exterior and interior.
5. Handler contract system with radio and subtitles. Add a dawn timer.
6. Remaining enemy archetypes, alarms and reinforcements.
7. Mutation meter and skill tree: tendril grab, scream, rage form.
8. Commander boss fight in the station office.
9. Audio pass (placeholders), lighting and art pass.
10. Enghelab, then میدان علیخانی.

Keep each step playable before moving on.
