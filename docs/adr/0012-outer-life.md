# 0012 — The outer towns' people, traffic and boats are records drawn only near the viewer

**Status:** accepted · September 2026

## Context

The five towns and fourteen hamlets of the outer world (ADR 0010) were built but empty, the
~200 km of outer roads carried no traffic and only colony ships moved on the sea. The brief asked
for a few hundred people in Puerto Alto (a handful in a hamlet) with routines and trades that fit
the place, traffic and fishing boats, all under ~1 ms a frame of simulation, at most ~40 detailed
and ~120 light bodies at once, and no hitch on entering a town — on a 2-CPU machine where a
detailed townsperson mesh takes ~90 ms to build.

## Decision

**A town is data until the viewer is near.** `TownPopulation` turns a plan.json town into spots
(doors, stalls, shop doors and windows, bench seats, cafe chairs, net racks, quays, crates, gardens, barns,
chat spots), a walking graph on its streets (sidewalk lanes, a grid over plazas and quays, every
node and edge midpoint clear of the plots and props) and people (~0.7 per plot; occupation from
the spot they work, a home near it, a daily routine). Generation is pure data and runs on a worker
thread when the viewer comes within 1.6 km of the town; routes are A* on the town graph, computed
in batches on a worker, one batch per town at a time. Far towns are never touched.

**Positions are functions of the clock.** A walker's position is the distance
`(now - depart) * speed` along its route; a dockworker's crate loop and a fishing boat's trip are
periodic in the clock. Nothing integrates per frame; the routine slice (every person re-checked
twice a second) only starts walks. Activating a town places everybody where the routine says,
spread over frames.

**Bodies are pooled and budgeted.** `TownFolk` hands the 160 people nearest the viewer (150 m) a
pooled `TownBody` (a RiderModel with owner-supplied meshes), at most 12 new ones per pass,
nearest first; the 40 nearest may show the detailed mesh within ~24 m. Meshes are
`PersonBuilder` *parts* (near and far separately), assembled and committed on worker threads, so
the main thread only swaps a finished mesh in. Poses are throttled by distance; still, far people
are not touched between updates.

**Traffic and boats are local too.** `OuterTraffic` spawns vehicles 300-600 m from the viewer
(from 150 m behind the camera), routes them through `RoadNavigation` to a town or hamlet gate in
the right-hand lane of each road class at its limit, with following, junction yielding and a stop
for the courier, and forgets them beyond 900 m. `OuterBoats` plans each harbour's moorings,
fishing grounds and water routes (string-pulled A* on a 20 m water grid, every point checked
below -2 m) on a worker thread within 3.2 km.

**Enemies wear the same bodies.** Bandits and pirates are CharacterLook townsfolk in the
`bandit` / `pirate` styles (eight pinned, prebuilt variants per kind) with EnemyOutfit's hats,
bandanas, bandoliers, sashes and earrings refitted to the townsfolk rig; the rifle IK is the
RiderModel's, unchanged.

**Colonies ask the courier for help.** `UrgentSupply` watches founded town colonies; a food (or,
after the first needs period, a good) shortage posts an optional truck job through the
DeliverySystem's override (`start_extra_job`), which resumes the route afterwards.

## Consequences

- Townsfolk live only while their town is active: their live state (who sits where) is not saved,
  and re-entering a town re-places everybody by the routine. Their looks, homes and trades are
  deterministic, so nothing needs saving.
- People do not avoid each other; they spread over the street by a personal lane offset and stop
  for the courier. Seats and chat spots are reserved one person each.
- Colony buildings placed after a town's graph was built are not obstacles to its walkers (colony
  sites must be clear of streets and plazas anyway).
- Traffic does not overtake; slow tractors and carts keep to tracks and country roads.

## Reopen if

Townsfolk should remember where they were (a save of the live state), react to the courier
beyond stepping aside, or when towns get interiors people enter.
