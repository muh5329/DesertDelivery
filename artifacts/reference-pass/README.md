# Character reference and optimization pass

The user's supplied turnaround is the visual target: swept copper hair, soft almond eyes, blue rolled-sleeve shirt, coral scarf, flax Y suspenders, high-waisted wide ochre trousers, fingerless gloves and brown shoes. Level and motorcycle screenshots are visual references, not implementation instructions.

## Implemented

- Rebuilt the character through the live Blender MCP using `tools/blender/character.py`; saved editable source at `assets/source/courier_reference.blend` and exported the runtime `assets/models/courier_character.glb`.
- Replaced protruding spherical eyes with shallow almond surfaces and lids, reshaped the nose and face, and authored asymmetrical tapered hair locks.
- Raised the waistband, widened/lengthened the breeches, softened sleeves, flattened suspenders, rounded gloves and soles. Added knee cloth and tucked hem overlap after checking the seated pose.
- Preserved animation pivots, material palette categories, right-hand attachment and the shared resident rig. Corrected motorcycle leg angles to the actual footpegs while retaining the existing car/truck seating pose. Polished individual components before batching instead of subdividing the entire merged face/clothing mesh.
- Protected the rebuilt character from the older bulk regrade and merged-mesh polish scripts, which would otherwise restore obsolete geometry.
- Cached resident vehicle wheel/steering references at setup, removing repeated hierarchy searches. No FPS gain is claimed for this small cleanup.

## Evidence

Actual Godot renders, not generated concept images:

- `before/`: previous asset, original review lighting.
- `pass1/`, `pass2/`, `pass3/`: intermediate character iterations; review lighting was corrected between passes.
- `final/`: front, profile, rear, three-quarter and portrait under consistent final studio lighting.
- `bike-fit/`: final motorcycle-specific footpeg pose and closed tucked-shirt overlap.
- `bike-final/`: preceding pose used to identify the footpeg/waist issues.
- `character-review.md`: independent visual critic.

The old/new screenshots are not a controlled lighting A/B. The asset benchmark separately isolates old/new GLBs under the same runtime conditions.

## Rejected runtime experiments

Stationary-resident terrain support caching and conditional rock-noise calculations added complexity without a measurable village benefit: 52.27 → 51.77 FPS in the matched sample. Both were removed. Full records are in `../overhaul-2026-09-19/runtime-baseline`, `runtime-candidate`, and `performance-review.md`.

This pass does not establish AAA quality or an exact sculpt match. The segmented procedural rig still has limitations compared with a fully skinned production character; the environment and motorcycle retain visual differences from the supplied references.

## Final measured asset budget and validation

Final exported mesh after waist/hip joint coverage fixes (see `asset-counts.json`):

| Metric | Previous | Final | Reduction |
|---|---:|---:|---:|
| GLB bytes | 1,692,648 | 1,202,432 | 29.0% |
| Vertices | 33,088 | 27,625 | 16.5% |
| Triangles | 60,950 | 51,141 | 16.1% |
| Material surfaces | 43 | 43 | unchanged |

The earlier 48.1→52.2 FPS observation included another running preview and an intermediate asset. A later attempt after closing that preview was highly unstable with other applications still running. **No reliable FPS improvement or regression is claimed.** Structural asset reductions above are independently inspectable and apply to the delivered GLB.

- Character fit integration: 9 checks pass (both boot/fairing/peg positions, right hand, car/truck pose, grip reach).
- Feature, truck and life integration suites: pass, zero failures. Feature/life shutdown logs each report one ObjectDB leak warning; this pass does not resolve that shutdown warning.
- Walk and aim captures inspected. Closed exposed upper-leg caps found during the walk check. Rigid joint seams remain a production-quality limitation.
- `git diff --check` passes.
