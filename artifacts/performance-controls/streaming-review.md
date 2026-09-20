# Incremental streaming review

Chunks now retain a recipe cursor and private RNG continuation state. Normal streaming checks a shared 3 ms construction allowance between individual recipe calls, rather than building every recipe in a chunk at once. Nearer chunks are built first; a partial chunk is not reported collision-ready and emits its loaded event only on completion. `load_all_pending` and `load_everything` still complete synchronously for deliberate callers.

Only oversized recipes receive dedicated containers. On a group unload, all departing owners are removed first, then existing oversized containers transfer to surviving chunks without rebuilding. Node identity, physics RID and world transforms are preserved. Non-oversized recipes keep direct chunk children to avoid thousands of additional wrapper nodes. Retired colliders are disabled immediately before deferred deletion, preventing overlap during a same-frame reload.

The simulation agent independently reviewed the code and reran `streaming_budget_tests.gd`: 13 passes, zero failures. Checks cover interrupted construction, readiness, RNG determinism, synchronous draining, grouped ownership transfer without repeated builds, preserved collider identity and raycast support, last-owner release, immediate collision retirement, same-frame return, and synchronous full-world loading.

Profiling fields: `last_build_ms`, `max_build_ms`, `total_build_ms`, `max_recipe_ms`, and `worst_recipe`. Per-chunk build times accumulate microseconds before converting to milliseconds, avoiding inflation from rounding every small recipe.

The 3 ms allowance is a soft scheduling budget, not a hard frame-time guarantee. A builder remains atomic and can exceed the allowance; replan/unload work can also exceed it. The new metrics expose those cases. GPU shader compilation, render submission, physics synchronization and deferred deletion are not made bounded by this change. A full moving-world profile remains necessary before claiming the observed traversal hitch is resolved.
