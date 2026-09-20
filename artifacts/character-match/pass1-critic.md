# Deep rebuild pass 1 — independent visual critique

Compared actual `pass1.png` with the user turnaround. Measurements are approximate manually read screen-space landmarks, not a validated similarity score. Front bounds: y49–838, H789. No geometry edits or renderers were used.

| Landmark | Reference normalized | Pass 1 normalized | Result |
|---|---:|---:|---|
| Chin | .171 | .172 | Major improvement; now close |
| Waistband top | .393 | .402 | Close; still slightly low |
| Sleeve cuff bottom | .425 | .409 | Slightly too high |
| Fingertip | .604 | .606 | Close |
| Crotch | .554 | .573 | Raise about .019H |
| Trouser cuff bottom | .853 | .875 | Raise about .022H |
| Boot top | .921 | .939 | Taller boot collar needed |
| Back Y junction | .297 | .302 | Major improvement; close |
| Overall lower trouser width | .277 | .274 | Major improvement; close |

The head/body proportion, waist position, broad trouser silhouette, hand level, and suspender graphic now materially approach the reference. These improvements do not establish 90% likeness.

## Highest priority next changes

1. Remove the obvious hip ledge and rectangular upper trouser volume. Continuous topology alone has not produced a continuous tailored silhouette: the prior component shapes remain visible. Form a single smooth waist-to-seat-to-crotch surface.
2. Space the legs and feet farther apart. Current ankle center span is about .114H versus reference .149H; moving each leg outward roughly .017H approaches the reference stance. Reference lower inner-leg clearance is about .025–.03H; current legs nearly touch. Reconcile this with a smooth crotch and retain broad trouser legs.
3. Hair still reads as a helmet capped with a row of hanging cones in profile/back. Replace the horizontal cap-to-strand boundary with broad overlapping locks across the crown and nape. Curve and flare the nape locks outward rather than merely tapering straight spikes. Front sweep direction is improved.
4. Smooth and narrow the box shoulders. Current upper shoulder span is roughly .265H versus reference .239H. Reduce around 10% and blend the sleeve root smoothly into the torso. Avoid the hard shoulder notch and geometric elbow corner.
5. Correct the profile jaw: current chin retreats around .033H behind the nose tip versus about .020H in reference. Move chin forward and soften the face contour instead of retaining the pointed projecting nose over a strongly receding jaw.
6. Build recognizable boots. Current low slippers lack the reference's taller ankle collar, lace/vamp structure, distinct heel, and raised rounded toe. Raise the collar target by approximately .018H.
7. Replace thin wire-like finger spikes with substantial relaxed fingers, shaped palm and thumb, and readable fingerless glove coverage. The reference's hands are more anatomically coherent and less miniature.
8. Reduce blown highlights before color matching: trousers currently read lemon yellow rather than muted golden ochre, skin is washed out, and shirt is pale cyan rather than subdued periwinkle. Geometry and flat silhouette should remain the primary next pass.

These are still substantial identity differences. Require a new front/profile/back review after structural changes, then animation checks after static silhouette approval.
