# Quick Design Spec: Tendril grab, scream and rage form

**Type**: Addition
**System**: Volatile player powers (skill tree via feeding)
**Design reference**: `prompts/core-design.md`, "Player powers" and "Encounter rhythm"
**Date**: 2026-10-11
**Prior specs**: none

## Change

The mutation meter already unlocks the three powers (25, 50 and 100 mutation), but
none of them does anything yet. This adds them. Every number lives in
`assets/data/volatile_powers.json`.

| Power | Input | What it does |
|-------|-------|--------------|
| **Tendril grab** | Q / pad Y | Fires a tendril at the soldier nearest the crosshair (22 m, 7° aim cone, needs line of sight). It yanks them to your feet in an arc, over walls and off roofs, and drops them downed and ready to feed. It's silent: nearby squads are not alerted. 6 s cooldown. |
| **Scream** | F / pad B | A shockwave in a 55° cone, 16 m long. Soldiers caught in it are stunned for 2.5 s and then panic for 6 s: they run away from you and don't shoot. Anyone else within 35 m hears it and turns hostile. 12 s cooldown. |
| **Rage form** | R / pad RB | Needs a full mutation meter and spends all of it. For 12 s the volatile is 25% bigger and 40% faster, its claw downs in one hit, and it takes 15% damage. Soldiers who can see it within 20 m panic. The screen gets a pulsing red, distorted filter and the camera pulls back. |

## Rules

- Each power works only after it is unlocked. Unlocks stay after rage spends the meter.
- A grabbed soldier ignores damage while airborne and lands downed.
- Stunned and panicking soldiers can still be clawed, pounced and grabbed.
- A scream on a panicking soldier restarts their panic.
- A rage form can't start while one is running or while feeding.

## Acceptance Criteria

- [ ] With tendril unlocked, a soldier on the crosshair 12 m away ends up downed within 3 m of the volatile, and no other soldier is alerted.
- [ ] A scream stuns soldiers in the cone, who then flee and don't fire. A soldier behind the volatile within 35 m becomes alerted.
- [ ] Rage needs 100 mutation, spends it, reduces damage taken to 15% and ends after its duration. Unlocks are kept.
- [ ] The HUD shows each unlocked power with its key and greys it out while it's cooling down.
- [ ] Retained screenshots of all three powers are in `production/qa/evidence/`.
