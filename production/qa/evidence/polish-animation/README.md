# Volatile animation / movement / camera polish: evidence

Each JPG is BEFORE (HEAD e6a2143) | AFTER, rendered through the game camera by
`tests/render/motion_frames.gd` (tendril shot: `tests/power_screens.gd ... tendril`;
the BEFORE frame is the earlier `volatile-powers/01_tendril_grab.jpg`, resized).
Lighting differs between the two sides because the lighting pass landed in parallel.

| Shot | What to look at |
|---|---|
| run_a/b/c | stride-matched sprint (no moonwalking), start/stop blend, sprint FOV |
| claw_a_hit1, claw_b_hit2 | second claw plays combo hit 2 instead of restarting hit 1 |
| pounce_b_launch, pounce_c_flight | the leap itself, not the clip's 1.6 s run-up |
| pounce_d_landing | landing blend back into run |
| climb_a | climb clip advances with climb speed (was frozen) |
| wallrun_a | wall run holds (was flickering every frame) with roll lean |
| feed_a_kneel | hunched over the body with a bobbing feed motion |
| power_a_scream | three HDR shock rings + ground dust ring |
| power_b_rage | rage scale kept while turning (was reset by facing) |
| 01_tendril_grab | tendril lash-out, glow light and swollen tip |

Probe (`tests/render/motion_probe.gd`, headless). Camera judder at 144 fps, worst
per-frame jolt (cm), excluding teleports:

| Segment | Before | After |
|---|---|---|
| walk_hold | 42.97 | 1.05 |
| sprint | 42.97 | 1.79 |
| claw_combo_still | 43.38 | 2.65 |
| scream_rage | 40.32 | 1.50 |

Worst facing step (deg/frame, 144 fps): turn_180 36.0 -> 11.5; feed 180 -> 18.3.

Regression test: `tests/integration/animation/volatile_animation_test.gd` (6 checks,
all fail on HEAD e6a2143, all pass after).
