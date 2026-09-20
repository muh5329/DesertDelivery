# Independent review: optional pivot-to-Skeleton3D bridge

Status: helper implementation reviewed; independent native-engine fixture passes 10 checks. Imported continuous-clothing asset and rendered extreme poses still require visual validation.

A direct headless probe against Godot 4.7 verified that bone poses are complete local transforms. Setting a bone rest at (1,2,3) does not make a later pose position (4,5,6) mean rest+pose: its resulting global position is (4,5,6). reset_bone_pose copies the rest transform into the pose. Rest must not be multiplied a second time. Tests should allow skeleton updates to flush before reading global poses; immediate queries during initialization returned stale cached transforms.

Correct general mapping, including differently oriented authored bone axes:

- Capture neutral offset = inverse(pivot_global_at_bind) × skeleton_global_at_bind × bone_global_rest.
- Desired bone global pose in skeleton space = inverse(current_skeleton_global) × current_pivot_global × offset.
- Solve hierarchy parent-first; local pose = inverse(desired_parent_global) × desired_bone_global, or desired_bone_global for a root bone.

Use affine inverses. The model includes scaled heads, resident torso-width changes and 1.35× riding-arm scale, so orthonormal-only inverses are incorrect. Capture neutral offsets before resident identity proportions change.

Required acceptance checks:

1. Neutral imported skin produces identity deformation, with no rest double-application or mesh-instance double transform.
2. Root translation/model rotation/scale and non-identity authored bone axes still map the hand/knee/head to their legacy pivot targets.
3. Test nonuniform resident torso scale and riding-arm scale, not only uniform unit-scale fixtures.
4. Explicitly map both elbows/knees through their owning limbs. Their runtime child names are duplicated (Elbow/Knee), so a global name search can silently map the right side to the left.
5. Walk, run, aim, swim, seated-car and motorcycle poses preserve hand-prop attachment trajectories. Work-activity arm overrides happen after animate(), so sync must see those final same-frame transforms.
6. Preserve imported mesh transforms, Skin inverse-bind matrices and all weighted-joint mappings. The bridge must not apply the pivot world transform a second time to skinned meshes.
7. Old assets without Skeleton3D retain their existing animation path and do not fail.

No performance or visual-quality signoff is implied by correct matrix algebra alone. Rendered cloth must also be checked at shoulder, crotch, knee and elbow seams under extreme poses.


## Implementation review and independent test result

Reviewed entities/player/pivot_skin_bridge.gd. It captures the neutral offset correctly, traverses actual parent relationships rather than assuming index order, computes full local poses, retains unmapped local bones, and disables safely on invalid bindings/lifecycle changes. No blocking helper defect found for the declared dedicated-skeleton contract.

Independent persistent test: tests/pivot_skin_bridge_tests.gd, run via Godot --headless --path . --script res://tests/pivot_skin_bridge_tests.gd. **10 checks passed, zero failures.** Tests use the actual engine Skeleton3D implementation and verify inverse-bind neutrality, model and Skeleton relocation, the real 1.16× torso-width and 1.35× riding-arm scales, unchanged prop parents/transforms, activity-pose propagation, missing-joint rejection, legacy fallback and freed-pivot shutdown.

The nonuniform-scale case requires bone rest axes aligned to the legacy pivot axes. Skeleton3D decomposes local transforms into translation/rotation/scale and cannot preserve arbitrary shear. A rotated bone-axis correction combined with nonuniform pivot scaling may produce such shear; this is an authoring constraint, not solved by affine matrix inversion alone. The synthetic activity check allows engine update frames and does not by itself establish a zero-frame rendered latency guarantee.

## Imported continuous garment audit

A read-only native Godot audit of the imported CourierClothRig found one Skeleton3D with all 13 expected bones and correct torso/arm/elbow/hand and leg/knee parent relationships. ContinuousShirt and ContinuousTrousers each have 13 Skin binds, identity mesh transforms relative to their skeleton, and no vertex referencing an invalid joint index. Maximum error in global-rest × inverse-bind identity was 6.7e-8. Maximum vertex weight sum error was 3.1e-5 for the shirt and 4.6e-5 for trousers, consistent with quantized import. This closes the imported bind-space check; it does not replace visual acceptance of deformed extreme poses. The audited iteration contained 25,279 shirt vertices and 10,494 trouser vertices; these are garment-only counts, not final character totals.

Integration review found a release-build blocker: RiderModel initially invoked `_skin_bridge.bind(...)` inside `assert(...)`. Since assertions are omitted from release builds, required binding must be evaluated before the assertion, storing its boolean result for validation. Reported to the integration owner for correction; helper math and imported weights are unaffected.

The owner corrected the release binding call, independently verified in source. Updated `tests/character_fit_tests.gd` passes 13 checks against the actual imported character: active 13-joint runtime binding, posed hand-bone correspondence, final shoe centers at ±.05, peg overlap, and physical palm-to-grip distance. The earlier 1.12 arm scale left hands visibly short of the handlebars; after the owner's 1.25 reach adjustment, palm centers lie 2.41 cm from the authored grip segments, within the 6 cm combined glove/grip allowance. Assertions now test physical reach instead of preserving an obsolete scale constant. Headless teardown emits dummy renderer null-material diagnostics; no assertion failed.

Runtime motorcycle-pose captures are in `artifacts/character-match/seated-review/`. Front/profile/back views show continuous garments without obvious open joints. Rigid suspenders still float ahead of the lower torso in profile, and the back strap ends above the belt; those visual findings were returned to the garment author. Shoe profile refinement remains in progress and these captures are iteration evidence, not final visual acceptance.

## Motorcycle seated-fit revision

The subsequent actual bike render exposed a standing-on-pegs silhouette despite acceptable foot/grip proximity. Motorcycle-only root placement and limb pose were solved against the authored saddle, pegs and grips; the car branch retains its prior values. The new fit places sole centers at approximately (±.39875,.40695,.21049) and palm centers at (±.32003,1.11001,-.42250). The torso leans forward .65 radians and the thigh bends .90 radians, producing visible seated knees in `artifacts/character-match/bike-seated/bike_1.png`.

The integration suite now has **14 passing checks**, including CPU evaluation of the actual imported trouser vertices through Skin inverse binds and current Skeleton3D poses. Fifty-one rear-pelvis vertices lie within 2.5 cm of the saddle surface; nearest separation is 9.6 mm. A temporary regression probe restoring the old pelvis/leg stance yields zero nearby vertices and fails this criterion. This is a contact-region check, not a cloth collision guarantee: nearby broad garment vertices can intersect the saddle. Final material/accessory iteration remains owned by the art author.

## Separate waist-continuity regression

An independent visual critic correctly identified an open waist wedge and dangling rigid shirt placket in the deeper mounted lean. Passing contact checks above did not establish clothing continuity. The art owner revised the shirt/accessory pelvis blend and skinned the placket/buttons. A separate test now evaluates actual skinned shirt vertices in the lower overlap band against the root-attached waistband's elliptical volume. The regenerated asset has 288 samples, zero outside the overlap, and maximum normalized radial extent .970 (limit 1.04). Reconstructing the previous 1.09–1.22 blend on the same geometry yields extent 1.314, correctly outside the belt. The current integration suite therefore passes **15 checks**; visual acceptance of the regenerated mounted view remains distinct from this bounded seam test.
