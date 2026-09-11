# 0005 — The Resident is a type, and owns its own persistence

**Status:** accepted · September 2026

## Context

The Resident was the central concept of the island-life simulation and existed only as an
anonymous 25-key `Dictionary`, built in `IslandLife.setup` and read by five other modules. Which
keys were guaranteed was stated nowhere, so `ResidentActor` hedged with
`record.get("surface_normal", Vector3.UP)` in one line and read `record.scale` bare in the next.
The field list existed three times — creation listed 25, `save_state` 14, `load_state` 12 — and
they had drifted: `activity`, `blocked_time` and `station_validated` were persisted by nobody.

## Decision

`Resident` is a class. It owns its fields, its schedule (`schedule_for`, `task_at`), its stations,
and one `SAVED` list that both `to_dict()` and `apply_dict()` read. `lifetime_totals()` /
`restore_lifetime()` name the counters that a time skip must carry across.

## Consequences

- Adding a field is one edit, and the save round-trip follows from it. A test walks `SAVED` and
  fails if any field is dropped.
- `IslandLife.advance_to(minute)` became possible. "Rest until morning" used to synthesise a whole
  save payload from a `CanvasLayer` and hand-copy three lifetime counters back into it, because
  any field it omitted was silently reset by `load_state`. It is one call now, and the totals
  carry across by construction.
- `world.database.residents` was written and never read; it is gone.

## Reopen if

Residents diverge into genuinely different kinds. Prefer composition over a second dictionary.
