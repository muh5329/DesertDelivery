# Reference fidelity critique — rebuild intake

The previous asset does not satisfy a defensible 90% reference-match claim. Earlier acceptance covered specific improvements and motorcycle fit defects; it was not reference-fidelity approval. This review supplies concrete targets for a deeper rebuild. No model edits or renderers were used.

## Measurement method

Landmarks below are hand-read from the full-resolution supplied turnaround and `final/character_0.png`. Normalize vertical distance from the highest hair point (0) to the lowest sole (1), excluding shadows. Reference front: approximately y58–869, H811 pixels. Current front: y174–784, H610 pixels. Approximate hand-reading uncertainty is 2–5 pixels, larger at soft silhouettes. The current camera is perspective and the stance differs, so these are screen-space targets rather than exact anatomical dimensions. Use a level orthographic camera and the reference A-pose for subsequent controlled comparisons.

| Front landmark | Reference pixel y | Reference normalized | Current pixel y | Current normalized |
|---|---:|---:|---:|---:|
| Eye center | 142 | .104 | 242 | .111 |
| Chin | 197 | .171 | 299 | .205 |
| Upper shoulder | 230 | .212 | 325 | .248 |
| Waistband top | 377 | .393 | 434 | .426 |
| Rolled sleeve bottom | 403 | .425 | 402 | .374 |
| Crotch split | 507 | .554 | 519 | .566 |
| Lowest fingertip | 548 | .604 | 519 | .566 |
| Trouser cuff bottom | 750 | .853 | 724 | .902 |
| Boot top | 805 | .921 | 741 | .930 |
| Sole bottom | 869 | 1.000 | 784 | 1.000 |

| Front width or span | Reference / H | Current / H | Interpretation |
|---|---:|---:|---|
| Face around cheek/ear region | ~.112 | ~.134 | Underlying face reads about 20% too wide relative to height |
| Total hair width | ~.152 | ~.157 | Keep fullness when reducing underlying face |
| Shirt torso at belt region | ~.158 | ~.156 | Torso width itself is close; shoulder construction is not |
| Overall lower trouser span | ~.277 | ~.230 | Widen flaring lower trousers about 20% |

## Highest-impact geometry changes

1. Reduce crown-to-chin proportion from about .205H toward .171H. The oversized, elongated face pushes the shirt and belt down. Shorten the underlying face/head roughly 15–17%, preserving the voluminous hair silhouette. Raise shirt and belt approximately .03H while reconciling the neck.
2. Replace separate trouser tubes and the visible crotch tab with a continuous waist/seat/crotch surface branching into broad legs. The reference has flared, almost skirt-width lower legs, not narrow cylindrical columns. Raise cuffs about .05H and expose the long golden sock segment. Preserve gathered cuffs and controlled roundness at the hem.
3. Extend sleeves substantially: reference rolled cuffs terminate slightly below the waistband top, whereas current cuffs terminate substantially above it. Remove balloon-like detached shoulder caps, join sleeve smoothly into shoulder, and place elbows/cuffs correctly. Use the reference's roughly 20–25 degree arm splay before judging arm width or length. Match fingertip level near .60H.
4. Re-author hair direction. In the reference front, broad upper masses sweep toward viewer-right with layered outward curls on that side; the long frontal lock also descends toward viewer-right. The current dominant bang descends toward viewer-left and the highest cowlick sits viewer-right. Match asymmetry to the front reference, checking all turnaround views for consistency.
5. Treat face as continuous anatomy. Reference has a tapered jaw, subtle integrated nose, shaped lips, eyelids, and softly inset eyes. Current round elongated face, tiny constructed nose, and minimal mouth remain a different identity even though eyes improved over earlier iterations.

## Profile silhouette

Reference hair projects forward as a broad curved crest, with substantial rounded volume over and behind the ear, ending in layered outward curls at the nape. Current profile has thin upright prongs over the forehead, a tight cap behind the skull, and long straight needle-like nape strands. Change primary masses before adding surface grooves.

The reference forehead/nose/lips/chin form a gently articulated continuous contour; current face is a long convex mask with small discrete projections. The reference trouser seat and thigh form a connected tailored volume and flare gently toward the cuff; current hip has an obvious horizontal junction over a nearly parallel-sided trouser column. Boots need the reference ankle collar, toe rise, lace area, and distinct heel/sole silhouette rather than a simple rounded shoe mass.

## Back silhouette and landmarks

Reference back bounds are approximately y64–869 (H805), with suspender Y junction at y303, or .297H. Current back bounds are y174–774 (H600), junction y405, or .385H. Raise the Y junction roughly .09H, retain broad diagonal ribbons, and extend the vertical stem down to the waistband. The current low junction changes the shirt's main graphic pattern.

Reference hair has irregular overlapping lobes with curls spreading around the ears and neck. Current back is a row of similar straight pointed strands. Reference back trousers have continuous seat, a natural center seam and broad lateral flare; current rear hip panel and separate legs expose construction seams and a narrow tubular silhouette.

## Review protocol for the rebuild

Capture front, both profiles, back, and portrait with matched orthographic scale and reference A-pose. Compare normalized landmarks before detailed material polish. Major body landmarks should approach the table within approximately .01–.015H as a practical iteration target, with matched front/profile silhouette and correct asymmetric hair direction. This tolerance is a work target, not a validated 90% similarity metric. Then test idle, walking, seated bike, steering/lean extremes, truck, and accessories separately. Continuous clothing or skinning should preserve the reference silhouette without reopening pose seams.

A numerical match percentage should only be reported if its definition and measurement are specified. Landmark agreement alone cannot establish identity, likeness, shading quality, or animation quality.
