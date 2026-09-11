# 0008 — A Hub declares its surfaces; the geometry is derived from them

**Status:** accepted · September 2026

## Context

Every Hub's walls existed as two independent literals — once in `_build_*` calling `_stone_wall`,
once in `_define_*` calling `add_wall`, usually nine lines apart. `Hub.wall_top` re-implemented
`_stone_wall`'s segment maths from the outside and said so in its docstring: *"Mirrors how Level
builds the wall."* The Dunes Lookout bench had already drifted: the plank's top was at `g + 0.55`
and the record said `g + 0.55`, but only because someone had done the arithmetic by hand.

`WorldKit._stone_wall` already took an optional `Hub` and called `add_wall` on it — and none of its
18 call sites passed one, because `_build_*` runs at chunk-load time inside a Recipe while
`_define_*` must run at generation time. A hypothetical seam with zero adapters.

## Decision

Invert it. `_define_*` declares walls and the bench on the `Hub`; `_build_*` renders those records
(`Island._hub_walls`). `Hub.wall_top` reads the record the mesh was built from.

## Consequences

- Moving a wall is one edit.
- `wall_top` still answers with the chunk unloaded, which is the whole point of the Hub
  (ARCHITECTURE.md §7).
- Wall *order* is now part of the record: `GunSystem` puts tin cans on wall 0 of the farm.

## Reopen if

A hub needs geometry that cannot be described as a record — then build it in `_build_*` and do not
pretend the Hub knows about it.
