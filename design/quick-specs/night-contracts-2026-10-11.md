# Quick Design Spec: Handler contracts and the stalk-then-rage night

**Type**: New Small System
**System**: Night structure (contracts, dawn clock, alarm rhythm)
**Design reference**: `prompts/core-design.md`, "Night structure" and "Encounter rhythm"
**Date**: 2026-10-11
**Prior specs**: `volatile-powers-2026-10-11.md` (powers this night is built around; no conflicts)

## Overview

A night in Haft Hoz runs from 23:00 to dawn at 05:30, compressed into 15 real
minutes. The handler (رابط) radios in Persian with one contract at a time. Finishing
all three before dawn wins the night. At dawn the volatile has to retreat and the
night is lost. While no soldier knows where you are, the night is in **stalk**:
quiet music and your own heartbeat, which gets louder near soldiers. When a soldier
spots you, it flips to **rage**: alarm music, Persian shouts, and reinforcements
from the station if the alarm lasts. If every soldier loses sight of you for long
enough, it goes back to stalk.

## Contracts (Haft Hoz)

| # | Contract | Targets | Done when |
|---|----------|---------|-----------|
| 1 | Silence the lookouts | 2 rooftop lookouts over the south boulevard | Both downed, fed on or dead |
| 2 | Feed on the officer | The officer at the checkpoint | You have fed on him |
| 3 | Take the station | The heavy gunner and two guards at the station door | All three downed, fed on or dead |

Targets of the current contract carry a small red marker. It is hidden by walls, so
it's not a wallhack.

## Rhythm rules

- **Rage** starts the moment any soldier is alerted. **Stalk** returns once none is.
- An alerted soldier who can't see you for 10 s loses track and goes back to patrolling.
- After 25 s of continuous rage, two riflemen come out of the station hunting you. This happens at most twice a night.
- Soldiers shout in Tehrani Persian when they spot you (اونجاست!), when they panic (عقب‌نشینی!) and when they lose you (گمش کردیم!).

## Audio

These are placeholder tracks generated in code. Licensed files can be dropped in later
under the same names in `assets/audio/music/placeholders/` and `assets/audio/sfx/`:

- `hunt_stalk.ogg` and `hunt_rage.ogg` are two layers that crossfade with the rhythm.
- `heartbeat.ogg` plays in stalk only. It is louder and faster the closer the nearest unaware soldier is (up to 18 m).

## Tuning

Every number is in `assets/data/haft_hoz_contracts.json`:

- `night.*` sets the clock.
- `alarm.*` sets lose-track, reinforcements and the heartbeat range.
- `contracts[]` holds the contract list. Each contract has a tag, a goal (`down` or `feed`), and the string keys for its briefing and objective.

## Acceptance Criteria

- [ ] The intro briefing names contract 1, and the HUD shows its objective as 0/2.
- [ ] Downing both lookouts advances to contract 2 and its briefing. Feeding on the officer advances to contract 3. Clearing the station wins the night.
- [ ] The clock reaching 05:30 loses the night.
- [ ] Alerting a soldier switches to rage. Losing them for the lose-track time switches back to stalk.
- [ ] Twenty-five seconds of rage spawns two hunting riflemen at the station, no more than twice.
- [ ] Retained screenshots of a briefing, rage and the win screen are in `production/qa/evidence/night-contracts/`.
