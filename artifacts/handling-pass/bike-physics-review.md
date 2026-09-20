# Bike handling pass and independent review

The former bike combined a .6 m floor snap, 2 m/s downward adhesion and a ray-grounded shortcut. The new bike opts into wheel spring support with damping relative to the road slope. Forces are unilateral: wheels can push upward but cannot pull the chassis down. Momentum therefore carries the bike off a fast crest, while a slow crest remains controlled. The truck retains its previous ground solver and winch behavior.

Airborne steering adjusts yaw without redirecting horizontal velocity. Actual spring travel replaces the time-based rider bob. Returning from wing flight transfers velocity and waits until the extended tires reach the surface, avoiding an early plane touchdown followed by another suspension touchdown.

## Measured physical fixture

The production bike crosses a connected 3 m-high convex ramp at approximately 20 m/s:

- Peak height: 223.378 m, or .378 m above the crest.
- Airtime: .700 seconds, followed by one landing event (9.69 m/s reported impact).
- 60 Hz versus 120 Hz: peak height differs by .011 m; measured airtime is .700 seconds at both rates.
- Slow 2 m/s crest crossing: longest contact loss .033 seconds.
- Flat acceleration: no airborne ticks and no measurable suspension-height oscillation after settling.
- Shallow wing landing: one touchdown, then stable wheel support.

## Verification

15 assertions in `tests/bike_dynamics_tests.gd` pass. Existing riding-feel (33), controls regression (20), truck/cargo/winch (13), and gameplay features including wing takeoff/landing (31) also pass: 112 checks across these suites. These runs were headless to avoid competing with graphical performance measurements. Existing terrain image-import/deprecation and shutdown resource warnings remain in test logs; no assertion failure occurred.

The independent simulation critic reviewed the spring/contact logic and reproduced the crest trajectory. Their wing-transition finding was addressed by the explicit shallow-landing regression. This agent also independently reviewed the on-foot/camera work and identified an initially overlapping camera sphere beside a parallel wall; that author fixed it and added a targeted regression.

## Visual reproduction

Run `Godot --path . --script tests/bike_dynamics_view.gd` without `--headless` to capture takeoff, apex, spring contact and settled riding into this folder, with measured state in `bike-dynamics-captures.json`. This script uses actual bike meshes and the same collision fixture.

The first graphical pass exposed front-tire penetration during initial landing: wheel travel was eased from a pre-motion sample. Wheel visual contact is now sampled after chassis motion/pitch and applied immediately. The polished source bike was also articulated in isolated Blender: lower fork, stanchions, swingarm and rear shocks now follow the axles as assemblies. Every vertex and triangle is retained (79,211 vertices / 142,400 triangles); all exported surfaces retain vertex-color attributes. The re-export preserves rest bounds and material assignment; Blender color conversion introduces at most .005 RGB difference (median .002), without dropping vertex paint. This adds eight material surfaces to the single hero bike rather than simplifying its appearance.

Five additional `bike_suspension_tests.gd` assertions verify authored axle rest transforms, full-travel rod/shock attachment, and unchanged rider/handlebar fit. All 15 character-fit assertions also pass. The actual production Bike rider, after pitched-body and compression updates, retains 288/288 lower-shirt samples inside the waistband with maximum normalized radius .970. No character geometry or validated riding pose was changed in this pass. The apparent large opening between chest/arms and thighs must be distinguished from a true disconnected hem in the closer recapture.

An independent source review found no articulation transform or endpoint blocker. Front fork travel includes rake-induced fore/aft displacement; contact remains a local plane approximation on curved terrain because the physical ray station stays fixed. Final closer Forward+/Vulkan captures were independently inspected: takeoff and apex show clear air separation; first landing retains the front axle inside its fork assembly without the earlier visible tire burial; settled riding restores both wheels to the ground. Front mudguard/slider, rear swingarm and damper connections remain coherent across all four states. The blue shirt hem visibly meets the yellow waistband: the large open silhouette is under the forward-reaching arms and between torso and thighs, not a detached shirt/pelvis seam. No blocking visual regression was found in this fixture. The strongly forward-bent riding silhouette and coarse smoke puff remain stylized presentation limitations; this review does not establish AAA art quality. This is an arcade kinematic suspension, not a full rigid-body motorcycle simulation. The reproducible asset articulation command is `Blender --background --factory-startup --python tools/blender/bike_suspension.py`; it operates on the polished, unarticulated GLB and keeps that input in `courier-bike-before-suspension.glb`. It deliberately refuses to apply the hierarchy operation twice.
