# Independent review of incremental world streaming

Reviewed `world/streaming/chunk.gd` and `world_streamer.gd` for interrupted building, recipe ownership, collider preservation, focus changes and synchronous compatibility. The shared build budget stops between atomic recipes, nearest chunks receive work first, and a partial chunk is not reported ready by `is_loaded_at`. Each chunk saves/restores its own RNG continuation without disturbing unrelated use of the shared kit RNG.

Oversized recipes retain their live node container when ownership moves to a surviving chunk. All departing chunks leave the loaded-owner set before transfer, preventing repeated handoffs through owners that are also leaving. Reparenting preserves world placement and physics identity. Radius-zero recipes correctly avoid extra containers because they map to exactly one chunk. `load_all_pending` drains both partial and not-yet-started work; `load_everything` remains synchronous and disables ongoing streaming.

Two concrete findings were corrected before acceptance:

- Per-recipe rounding overstated construction time. The implementation now accumulates microseconds and derives milliseconds from the total.
- Deferred deletion allowed a same-frame unload/reload to retain old colliders alongside rebuilt ones. Retired chunk colliders now lose collision layers/masks immediately, after surviving recipes transfer out.

Independently executed `tests/streaming_budget_tests.gd`: **13 checks passed, zero failures**, with clean output. Evidence includes an oversized bridge retaining the same node ID, physics RID and world transform, a successful raycast after two owners leave, deterministic resumed RNG, partial-readiness and both synchronous helpers, and disabled old colliders during same-frame reload.

No remaining blocking source issue was identified. The 3 ms setting is a soft construction budget checked between atomic recipes, not a hard frame-time cap. A single expensive recipe, unloading, ownership transfer or focus replanning can still exceed it. Actual long-distance traversal and the existing full-world teleport test remain required integration evidence; the synthetic fixture alone does not establish a hitch-free world.
