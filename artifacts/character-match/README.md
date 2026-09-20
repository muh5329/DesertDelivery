# Courier character reference rebuild

The supplied four-view character turnaround was used throughout thirteen Blender MCP author/render/review passes. The runtime model is `assets/models/courier_character.glb`; editable source is `assets/source/courier_reference.blend`; run `tools/blender/character.py` inside Blender to reproduce it.

## What changed

- Reference facial albedo projected from the supplied image onto a continuous sculpted head, with blended cheek/chin transitions and a packed 1K texture.
- Swept layered copper hair, staggered nape tips, corrected head/jaw proportions.
- Continuous skinned blouse and branching trouser topology; fitted suspenders, high waistband, folded collar, soft scarf, rolled cuffs, tapered socks, fingerless gloves and laced ankle shoes.
- Thirteen-joint skin bridge follows existing gameplay pivots, including nonuniform NPC proportions. Required initialization runs outside debug assertions.
- Motorcycle pose now places the pelvis on the saddle with hands on grips and boots on footpegs. Car/truck branch retains its prior pose.

## Evidence

`final-turnaround.png` is the actual Godot-imported character in front/profile/back/profile views. `studio.png` is a Blender studio render of the same authored geometry. `bike-final/` contains actual bike/rider captures. `walk/` and `aim/` record the final animation review.

- `fit-tests.log`: 15 integration checks pass, including actual skinned saddle contact, hand reach, boot placement, imported skeleton binding, and shirt-to-waistband overlap while leaning.
- `skin-tests.log`: 10 bridge checks pass, including rest-space correctness, nonuniform scaling, late pose updates, missing/freed pivots and prop-parent preservation.
- `feature-tests.log`: gameplay feature suite passes, including riding, takeoff and landing.
- Godot import and visual capture succeed. The headless dummy renderer emits a null-material diagnostic during teardown; an earlier feature-suite run reported an ObjectDB leak, absent from the final rerun. These are recorded in the logs rather than hidden.

## Budget

The final exported GLB contains 52,965 exported vertices, 103,650 triangles, 41 material primitives and is 2,921,388 bytes. The pre-optimization candidate contained 65,736 vertices, 128,866 triangles and was 4,161,372 bytes. This is approximately 20% fewer triangles and 30% smaller than that candidate. The final asset is more detailed than the old rejected model; these numbers are not a claim of faster whole-game frame rate. Godot import generates mesh LODs.

## Review limits

The reviewed proportions, palette and costume are substantially closer to the reference. Hair crest shape, facial texture sharpness and fine tailoring remain stylized approximations. No objective image-similarity metric establishes a 90% match; do not label this a measured 90% result or AAA certification. See the independent visual review notes for the remaining differences.
