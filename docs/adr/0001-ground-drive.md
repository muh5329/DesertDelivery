# 0001 — One GroundDrive behind every wheeled vehicle

**Status:** accepted · September 2026

## Context

`Vehicle` was 69 lines of which five methods were `pass`, and the three with bodies were
overridden by both subclasses anyway. Apply the deletion test: deleting it moved almost nothing,
because every caller already reached concrete state (`bike.airborne`, `truck.cargo_build_mode`).
It was a type tag, not a deep module.

Meanwhile the module that *would* earn its keep — given a ControlIntent and a VehicleDefinition,
produce speed, yaw, pitch, ground normal, grounded, drift, wall scrubs, landings and a road
recovery — existed twice, near-verbatim, in `bike.gd` and `truck.gd`. Two adapters, so a real
seam. The copies had already drifted in at least a dozen constants (slope gain 5.5 vs 4.5, coast
drag 1.2 vs 1.0, collision scrub 0.85 vs 0.75) with nothing recording whether that was a decision,
and the truck's reverse was silently broken because its standstill hold ran without the bike's
`_rev_hold` guard.

## Decision

`GroundDrive` owns the shared kinematics. `Vehicle` owns a drive and reads through to it, so
`bike.speed` still works everywhere. Everything the drive drives by is a field on
`VehicleDefinition`, so the difference between a bike and a truck is `data/vehicles/*.tres`.
A vehicle overrides `_drive_mods()` when its load, fuel or upgrades change how it drives this
tick — the drive never learns about the economy.

## Consequences

- A car is a `.tres` plus a `_ready()` that calls `_build_drive(offsets)`. `ARCHITECTURE.md`
  promised this before it was true.
- The riding-feel table runs against every vehicle in `data/vehicles`. That is how the truck's
  broken reverse surfaced; it now reverses at −2.4 m/s.
- Tuning the bike and tuning the truck are now separate, deliberate edits to data. If you want
  them to feel different, say so in the `.tres` rather than in a branch.

## Reopen if

A vehicle appears whose ground motion is not "wheels on a heightfield" — a boat, something with
real suspension. Give it its own drive rather than growing this one a mode flag.
