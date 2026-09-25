# 0014 — The Jeep replaces the cargo truck; the Cart makes a Rig

**Status:** accepted · September 2026

## Context

The user asked for the Jeep of their LegendOfJeep project to replace the cargo truck, and for
Red Sea Baron's towed cart to be hitched behind the bike or the Jeep and loaded with equipment.
Both sources are Godot 4 projects, but neither fits this game's seams as-is:

- LegendOfJeep's Jeep is a `RigidBody3D` with four raycast springs, slip-based tyre forces, and a
  buoyancy/planing model on its own ocean. Every vehicle here is a kinematic `CharacterBody3D`
  driven by `GroundDrive` from a `VehicleDefinition` (ADR 0001) through a `Controls.Scheme`
  (ADR 0002).
- Red Sea Baron's cart is tied to its `BikeController`, its `InputBindings` (C = hitch, V = load
  pack — V is our reload) and its own item catalogue.
- The truck carried two ideas of "load": the Tetris rack (blocks that only ever trimmed its top
  speed) and the urgent supply jobs ("must be carried by the cargo truck"), which never looked at
  the rack at all.

## Decision

**The Jeep is a Vehicle on the GroundDrive.** Its feel — 24 m/s, a strong low-speed torque,
LegendOfJeep's steering that tightens less at speed, a handbrake drift, a 2.2 s boost tank that
refills — is `data/vehicles/jeep.tres` (new Boost, Water and Towing groups on
`VehicleDefinition`). Water is **its own drive**, `PlaningDrive`, as ADR 0001 asks of "a
boat": deep water under the body lifts the hull to its draught, the propellers push it to a
planing top speed well below the road's, a rudder that needs flow turns it, and a shallow bed
under the front wheels hands it back to the GroundDrive — the enter/exit hysteresis is the
source's. `PlaningDrive` drives the GroundDrive's own state (speed, yaw, pedals), so nothing that
reads `vehicle.speed` learns which drive is in charge. The GLB is the source's realistic model
with its node contract; `JeepVisual` animates it as `JeepMesh` did (steer, spin, per-wheel
travel from the wheel rays, body lean and squash, the one-blend amphibious transformation).
The truck's winch moved to the Jeep's front bumper unchanged.

**The Tetris rack is replaced, not moved.** One goods model now serves everything: Red Sea
Baron's `Inventory` (known items, whole quantities, a kg capacity, two-sided transfers that
commit before they notify). The courier's pack (30 kg), the Jeep's bed (120 kg) and the Cart
(240 kg) are Inventories; the colonies' warehouses and the road shops are the stores; the load
panel (G) moves items between whatever is in reach. The rack's blocks meant nothing to any other
system; a sack of grain in the cart is the same `grain` the colonies make, eat and trade.

**The Rig.** A `CargoCart` hitched to a vehicle makes a Rig. The cart solves its drawbar from
the real axle-to-hitch direction every tick (the source's rule), turns only where the turned box
is clear, and poses its visual to the ground under it. The tow vehicle gets the other half of the
source's drawbar rule as a **tether on the GroundDrive** (`tether_anchor` / `tether_length`): the
part of a tick's velocity that would stretch the drawbar is removed, and `speed` follows — an
over-stretched drawbar slows the rig. While towing, the vehicle's mask also includes the
vehicles layer, so it physically cannot swing through its own cart. Mass (the cart, its load, a
parcel in it) scales top speed and acceleration by `tow_mass_half` and burns fuel by
`cargo_kg_per_extra_tank`, per vehicle.

**What a cart forbids.** The bike cannot unfold its wings with a cart hitched (and cannot hitch
with them out), as in the source. A cart does not float: the Jeep towing one does not plane —
deep water is a splash, and the whole rig recovers to the road. (A floating cart was considered
and dropped: a towed hull would need its own planing solve and the drawbar rule on water, for a
use — ferrying goods across the lagoon — the ships and lanes already cover.)

**Controls.** H hitches / unhitches (free in every scheme; C stays look-back), G opens the load
panel (freed by the rack). Both are "the same whatever you are sitting on", so the Keyboard
presses them like E and R; the Rider only routes them (`hitch_requested`, `cargo_requested`).

**Saves.** The Jeep saves under `jeep`; `Saves.alias("truck", "jeep")` hands an old save's truck
block to it (the rack's contents are dropped), the rider's `"vehicle": "truck"` reads as the
Jeep, and an urgent run saved with `vehicle = "truck"` is a `cargo` run. The cart saves under
`cart` (where, what it carries, what it is hitched to) through the HitchSystem, the pack under
`cargo`, the Jeep's tank inside `journey`.

## Consequences

- An urgent colony supply job needs the Jeep or a rig towing the cart ("cargo"); collected with
  the cart hitched, a heavy or urgent load rides in the cart, and the cart in the drop-off ring
  delivers it.
- Land trade by cart: load at one colony's hall or warehouse, unload at another's.
- The old truck's files are gone; `courier_truck.glb` stays for the traffic lorries, and
  `tests/truck_tests.gd` is a one-line alias of `tests/jeep_tests.gd` for suite lists.

## Known limits

- Planing is kinematic: a synthetic swell and bow lift, no buoyancy points or waves under the hull.
- Many of the island's beaches drop a metre or two at the waterline; out of the water the Jeep
  claws up such a bank for a few seconds (a lift like the winch's) rather than climbing it on
  springs.
- A vehicle that is not towing still passes through a parked cart (and the bike through the
  jeep), as the bike and the truck always did: only a tow vehicle collides with the vehicles layer.
- The coach refuses a cart; a parked cart far from the courier holds still (its ground may not be
  collided out there) and is recovered to a road if it ever falls.

## Reopen if

A second towable appears (a trailer for the Jeep only, a boat trailer): make the Cart's drawbar
rule a component the tow side and the towed side share, instead of a tether plus a solver.
