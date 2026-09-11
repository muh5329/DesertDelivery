# 0006 — A pool owns whether a view exists; the EntityManager owns how much it runs

**Status:** accepted · September 2026

## Context

`IslandLife` and `IslandWildlife` each implemented the same loop — hysteresis radius, `register`,
`queue_free`, `unregister` — with their own radii (105/125, 95/115, 210/230), none of them findable
from `EntityManager`, whose documented job (§11–12) was exactly this. `ResidentActor` opted out
with `func set_simulation_tier(_tier): pass  # The manager owns distance-based instantiation`,
which was inverted: the manager did not own it, and because the actor was registered only *after*
the decision to spawn it, the tier system never saw the entity it was meant to tier.

## Decision

`ViewPool` owns instantiation: given records with an id and a position, a spawn radius, a keep
margin and a factory, keep exactly the near ones alive. Radii live in `WorldConfig` beside the
tier radii. `EntityManager` keeps tiering, and `set_simulation_tier` now does something real —
below FULL an actor drops its name tag and fine animation.

## Consequences

- "Why is this Resident not visible?" has one file.
- Hysteresis is tested for the first time, without a booted island.

## Reopen if

A population needs its view driven by something other than distance (a story beat, an interior).
Give the pool an `awake_for` predicate rather than a second pool.
