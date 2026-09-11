# 0002 — The controlled thing owns what the keys mean

**Status:** accepted · September 2026

## Context

`Controls.Keyboard` was handed a `Controls.Context` describing the vehicle — `wings_out`,
`airborne`, `at_takeoff_speed`, `driving_truck`, `cargo_build_mode` — so it could decide what S
and Space meant this tick. Vehicle state flowed backwards through the seam every frame, and the
truck's Tetris mode reached all the way into the key reader. Adding one control meant editing the
Intent, `clear_edges`, `Keyboard.read`, `Context`, and both halves of `Scripted` — six edits at
the seam that was supposed to absorb change. `Scripted.read` hand-copied 21 fields with nothing
asserting the list was complete.

## Decision

The seam runs one way. A `Source` turns a device into a `Controls.Reading` — axes, look, and which
actions were pressed. A `Controls.Scheme`, owned by whatever is being controlled, turns that
Reading into an Intent. `Controls.Foot` is the boy; `Vehicle.control_scheme()` answers with the
vehicle's own (`Bike.BikeScheme` knows the flight stick, `Truck.TruckScheme` knows the rack).
Edge-triggered controls travel as named commands (`Controls.WINGS`, `Controls.CARGO_PLACE`), and
`Intent.copy()` copies by reflection.

## Consequences

- Adding a control is a name in `Controls` and a line in one Scheme.
- `Controls.Context` is gone. The Keyboard reads `Input` and nothing else.
- A test asserts every Intent field and every command survives the scripted seam, which is what
  the hand-written copy never had.

## Reopen if

Two vehicles need to share a non-trivial scheme. Extend `Vehicle.GroundScheme` rather than
passing state back to the Keyboard.
