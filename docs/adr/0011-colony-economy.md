# 0011 — The colony economy ticks by rates; shipping is distance along a route

**Status:** accepted · September 2026

## Context

The courier game grew a colony layer (`ColonySystem`: residents with roles gathering on a 4 m
grid round the villa). The brief asked for a build-and-manage colony sim across every town, with
production chains, needs, growth and shipping lanes between the ports — while staying a layer on
the courier game, keeping the architecture's one rule (nothing cares whether a town is loaded),
costing under 1 ms a frame, and keeping the existing tools and saves working.

## Decision

**Records, not nodes.** A colony is a `ColonyTown` (RefCounted): stockpile, building records,
colonist records, needs, happiness. A ship and a lane are Dictionaries in `ShippingNetwork`. The
whole economy ticks at 4 Hz inside `ColonyEconomy.tick` by rates, the same code whether a town is
drawn or 20 km away. `ColonyViews` reads the records and draws only what is near the viewer:
buildings (the architecture kit plus a props yard), porters and workers (townsfolk from
`CharacterLook`, at most 24), ships (`ShipModel`, at most 6), and the Mayor map overlay.

**Logistics are real but abstract.** Each producer has a porter record (`carry`): out to the
nearest storage with the building's produce, back with inputs for two cycles; goods move only
when the porter arrives. The drawn porter walks exactly that trip (its position is the trip's
fraction along a path from `ColonyRoads.route`), so what you see is what the numbers do.

**Regions make trade necessary.** Raw producers need their colony's land (`COLONIES[*].raw`):
timber, stone and ore in Valdoro; grain at Campo Real; olives and grapes on the core; fish on
the coasts; salt, cotton and dates at Sarmada. Chains (sawmill, mill + bakery, press, winery,
smithy, weaver, smokehouse, mason) and needs (six foods with a variety bonus, four goods,
housing) pull goods across the map.

**Sea routes from the ground.** A 50 m water grid (500 x 500) is derived from the outer data
(the highest ground in each cell, from the 12.5 m heights, skipping whole 200 m leaves by their
min/max) and the core `Terrain` inside the core square; a cell is navigable 2 m deep with no land
in its neighbours. It is built on a worker thread at boot (~1 s). `AStarGrid2D` (plan sea lanes
cheaper, the coast dearer), string-pulling and corner rounding over navigable cells make a route;
each port joins it by a checked straight approach from its mooring point. A ship's state is its
distance along the route, so far ships sail by the clock; pirate raid risk comes from uncleared
pirate coves near the route and drops to zero when the combat system clears them.

**Saves.** `ColonySystem` save version 2 = the v1 fields + `economy` (towns, lanes, ships, time
scale), validated field by field before anything changes. A v1 save loads with the economy at its
start and its warehouse as the core colony's stockpile (item ids kept: wood, olive, stone, ore,
berry are the economy's own).

## Consequences

- The economy never needs a loaded town; the cost is one 4 Hz tick (~0.1 ms with every town a
  busy colony, measured by `colony_economy_tests`).
- Colony buildings are not WorldDatabase recipes: they are few, change at run time, and are
  drawn from records by `ColonyViews` (one BuildingKit build per frame).
- Ships do not collide or steer round each other or the courier; they follow their route (in
  port they lie in a line along the quay, the first at the jetty).
- Townsfolk meshes build on worker threads, so the game waits for in-flight builds when it
  quits (`Game._exit_tree`).

## Reopen if

Goods should move by road (carts or the courier's truck as a logistics layer), ships should
avoid each other, or the colonies need to share workers across towns.
