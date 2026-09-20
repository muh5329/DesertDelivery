# Third-person controller revision and independent review

The on-foot controller now accelerates and brakes camera-relative movement, uses the current input yaw immediately, and preserves horizontal momentum after leaving the ground. Constant-speed floor movement, a 48-degree walkable slope limit, floor snapping and stop-on-slope behavior keep ordinary hills traversable without idle sliding. Coyote time and buffered jump presses remain, held/released input now changes jump height, descent uses stronger gravity, and a ceiling impact cancels ascent. Teleports clear transient locomotion state.

Manual orbit no longer automatically fights the chosen view. Horizontal camera tracking and mouse rotation respond immediately, vertical tracking absorbs steps, and obstruction distance retracts immediately before recovering smoothly. Camera collision uses a volume rather than only a center ray, includes prop collisions, and resolves initial sphere overlaps before sweeping. The overlap resolution was added after the independent controls critic identified a parallel-wall clipping case. Aim rays update when look input arrives, before a same-tick shot; physics priorities explicitly route Rider input before body motion and camera following.

## Validation

`tests/third_person_tests.gd`: **21 behavioral checks passed**, using actual Godot bodies, ramp/wall/ceiling collision shapes and camera queries. Tests cover analog speed, bounded stopping, current-frame aim/movement, airborne momentum, consumed jump edges, held/tap jump height, coyote and buffered jumping, ceiling cancellation, slope rest/ascent, new-wall retraction, recovery, parallel-wall initial overlap, manual orbit, aim-FOV timing, held-button mapping and teleport recovery. Held/tap jump peaks were approximately 1.113 m / .514 m at 60 Hz, with physical 120 Hz repeats within .08 m. The earlier control-regression suite also passes all assertions at the project's default 120 Hz.

The independent world critic found no further blocking movement/state issue and requested the added physical 60/120 Hz comparison. The controls critic's initial-overlap camera case is now a permanent regression fixture. Camera volume queries add CPU work; no claim about their full-game performance is made without profiling.

`tests/third_person_view.gd` provides a separate 7-second graphical review fixture, capturing run, jump, landing, manual orbit, camera obstruction and aim. Run with Godot `--path . --script res://tests/third_person_view.gd -- --out=/tmp/on-foot-review`. This agent only syntax-checked the graphical runner; root owns graphics execution and final visual review.

Headless runs emit small ObjectDB/resource teardown diagnostics already seen in related asset fixtures. All behavioral assertions complete, with exit code zero. Contact and input tests do not establish finished animation quality or arbitrary stair-climbing support.

## Independent motorcycle review

Reviewed the opt-in ray spring/damper implementation, airborne horizontal inertia, wheel travel and wing transition. Independently reproduced the crest/landing suite: .700 s airborne at both 60/120 Hz, peak .378/.367 m above the 3 m crest, and one measured 9.69 m/s landing event. The author corrected an early wing-touchdown threshold identified in review, updates post-motion wheel rays, and added a flight-to-suspension touchdown test requiring exactly one landing event. Trucks retain their existing ground solver.

## Graphical controller review

Reviewed all six Forward+ Vulkan captures in `artifacts/performance-controls/on-foot/`: idle after landing and orbit show planted feet, the running stride is readable, and the aiming shoulder view leaves the center unobstructed. The wall-retracted camera remains outside the mesh, but the avatar occupies most of that compressed view. The airborne frame also exposed a rigid idle posture. These two findings prompted a player-only airborne limb overlay and instance-level avatar fading for camera distances below 1.35 m, restoring visibility on reset or target change. They do not modify shared character materials or physics.

The expanded suite passes **24 checks**, including airborne visual tucking, compressed-camera fading and restored visibility. The updated graphical fixture still needs root's second capture; a screenshot review cannot certify subjective mouse/controller feel. The fixture has no pistol or combat HUD, so its aim image establishes framing only. The existing running animation remains procedural rather than a foot-IK or motion-captured gait.

The second graphical review rejected alpha fading: layered face, hair and clothing became an x-ray image. That implementation was removed. The current close-camera policy fully hides the player's visual below 1.10 m and restores it above 1.25 m; the intervening band preserves state to prevent flicker. The jump pose now retains asymmetric leg tucking through the apex and spreads the arms outward, extending as descent accelerates. The 24-check fixture passes again, and a direct four-step hysteresis probe passes. Final screenshot validation remains with root.

Root completed the final Forward+/Vulkan capture in `artifacts/performance-controls/on-foot-final/` and accepted all six frames. The jump has a readable asymmetric tuck; the wall view hides the avatar cleanly without transparency artifacts. Run, landing, orbit and aim preserve the character and usable framing. This closes the screenshot gate, while subjective handling still benefits from a human play session.
