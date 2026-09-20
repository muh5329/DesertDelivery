# Performance and controls pass — September 20, 2026

Measured in the actual rendered game at 1600×900 on Apple M4 Pro, with VSync disabled. Desktop now uses Forward+ (Vulkan on macOS), keeping 4× MSAA, 320 m shadows and the existing world density. Distant residents use a matching 13,451-triangle rig instead of the 103,650-triangle hero mesh; cosmetic pose updates run less frequently at distance while simulation and collision retain their normal rate. The playable character retains its full mesh.

| Scene | Initial GL Compatibility FPS | Forward+/Vulkan FPS | Final p95 frame time |
| --- | ---: | ---: | ---: |
| Village | 37.8 | 50.0 | 28.29 ms |
| Wilderness | 182.9 | 217.3 | 5.48 ms |
| Dense meadow | 161.7 | 164.9 | 6.84 ms |
| Harbour | Not sampled | 149.9 | 9.21 ms |
| Coast | Not sampled | 68.4 | 15.69 ms |

These are observed samples, not a guaranteed frame rate or an isolated LOD speedup. The table uses the latest `lod-preserved/benchmark.json`; earlier Vulkan village samples reached 74.4 FPS, but later repeated samples ranged 46–50 FPS. The village still falls below a locked 60 FPS and its p95 remains near the initial baseline. Keeping the test window on top did not resolve that variation. The final three-scene runs reported an unfocused window; baseline and coastal runs reported focused windows. Renderer, LOD and scheduling changes are combined. Reported village video memory increased from 291 to 425 MiB; engine static memory from 282 to 361 MiB. See `benchmark-independent-review.md` and the raw JSON files for caveats and frame-time tails. Metal was evaluated but Vulkan was selected after correct rendered captures; the low-detail rig also passed the isolated native Metal transition smoke test.

Imported tree and prop surface extraction now preserves the importer’s distance LOD index buffers and compressed vertex layout instead of reconstructing only the base arrays. Thirteen surfaces across olive, palm and twisted-tree assets retain byte-identical buffers; original mesh resources, instance transforms and material overrides are preserved. The final village benchmark shows only a modest observed gain, so this correction is not credited with a large FPS increase.

Chunk creation now yields between recipes under a shared 3 ms allowance. Structures spanning chunks transfer their existing nodes and collision bodies instead of rebuilding. Partial chunks are not reported ready. Independent review added accurate timing and immediate retirement of old colliders during same-frame reloads. An individual recipe remains atomic, so the allowance is a soft limit.

The final moving-gameplay sample measured **71.0 FPS**, median **13.92 ms**, p95 **19.66 ms**, p99 **26.61 ms**, and maximum **29.83 ms** over 1,800 frames. The earlier sample reached **846.03 ms**; incremental streaming alone reduced that to **61.77 ms**. Exact prebuilt rock meshes eliminated the remaining procedural mesh-generation spikes on the sampled route. The final run had no frames over 35 ms, with maximum asynchronous streaming work of 8.79 ms. This test uses a time-driven route for a fixed number of frames, so duration, path and displacement differ between runs (final displacement 234 m); it is evidence of the final run's behavior, not a controlled universal speedup. Longer trips, cold storage, other hardware and intentional teleport loading can still hitch.

The 180 prebuilt rock resources add **21.97 MiB** on disk. Every mesh attribute, LOD and hull array matches fresh generation byte-for-byte. Resources load individually on demand, with procedural fallback for missing or unknown variants. Follow [the cache instructions](../../assets/rocks/generated/README.md) when rebuilding or exporting: this project has no export preset, so packaged resource inclusion is not yet verified.

## Handling

- Bike ground adhesion was replaced with unilateral spring/damper wheel support: suspension can push the chassis upward but cannot pull it down onto a crest. Airborne steering preserves travel momentum. A 20 m/s crest fixture produced 0.70 seconds of airtime and one landing, with 1.1 cm peak-height difference between 60 and 120 Hz.
- Wheel contact is sampled after movement. The authored fork, mudguard, swingarm and shocks now articulate with the axles; the polished geometry is preserved. Final takeoff, apex, landing and settled captures were independently reviewed.
- On-foot movement now has camera-relative analog acceleration/braking, airborne momentum, variable-height jumps, coyote time, jump buffering and slope handling. Manual orbit retains its direction. Volume-based camera obstruction handles initial overlap and smooth recovery; a very compressed camera hides the character without translucent artifacts. Jump and landing poses were revised after two graphical review rounds.

## Verification and evidence

Bike/controller/gameplay suites: 112 checks; suspension articulation: 5; character fit: 15; third-person controller: 24; streaming: 13; rock library: 8 checks including all 180 exact geometry comparisons. Architecture integration also passes with zero failures. NPC rig, palette, attachment and transition checks pass. Actual game screenshots accompany the numerical tests. Existing image-import/deprecation warnings and small fixture shutdown leaks remain documented in logs; they are not assertion failures.

- [Bike physics and visual review](../handling-pass/bike-physics-review.md)
- [Third-person review](../overhaul-2026-09-19/third-person-review.md)
- [Streaming review](streaming-review.md)
- [Scenery LOD review](scenery-lod-review.md)
- Final on-foot screenshots: `on-foot-final/`; final bike screenshots: `../handling-pass/bike_*.png`.

The final `visual-final/villa.png` and `cliff_coast.png` captures retain complete tree crowns, foliage placement, nearby model detail and the original rock shapes after the cache and LOD changes. Root inspected both for missing surfaces or obvious detail-loss regressions.

Reproduce performance with `Godot --path . -- --test=overhaul_benchmark --out=res://artifacts/performance-controls/final` and moving gameplay with `Godot --path . -- --test=traversal_benchmark`. Run only one graphical benchmark at a time. Controls have automated physical evidence and screenshot review; these do not certify subjective feel on every controller or terrain configuration.
