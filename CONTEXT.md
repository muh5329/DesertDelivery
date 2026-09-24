# Desert Delivery — domain language

Names the code uses for the things in the game. Architecture terms (module, interface, seam,
adapter, depth, leverage, locality) follow the codebase-design vocabulary.

## People and things

- **Rider** — the boy. Also the name of the module (`scripts/rider.gd`) that owns what he is
  doing right now and every transition between those states.
- **Mode** — the Rider's state: `RIDING`, `FLYING`, `ON_FOOT`, `SWIMMING`. Only the Rider changes it;
  everyone else reads `rider.mode` or reacts to `mode_changed(from, to)`.
- **Bike** — the red courier motorbike (`scripts/bike.gd`). Has **wings** that fold out (plane
  mode); when the wings are out and the bike is airborne the Rider is `FLYING`. A **parked** bike is
  one the Rider has hopped off.
- **Package** — rides on the bike's rear rack between a **pickup ring** and a **drop-off ring**.
- **Job** — one pickup → drop-off pair. Four chain across the map (`GameManager`).
- **Garand** — the courier's M1 Garand, his rifle from the start (`GunSystem`, `GarandModel`).
  **Slung** on his back, **shouldered** while aiming (ADS), at the **hip** for snap shots. Fed by
  8-round **en-bloc clips**; the empty clip leaves with a **ping**. **Reserve** = full clips in the
  pouch (+ loose rounds from a part clip ejected by a manual reload). The **ammo cache** at the
  Dunes Lookout (where the old pistol lay) and camp **ammo crates** refill it. **Tin cans** on the
  farm wall and the lookout bench are practice targets.
- **Spread** — the half-angle of the shot cone: hip vs aimed, plus movement, air and **bloom**.
- **Bandit / Pirate** — an `Enemy`: bandits (dusters, hats, lever rifles, revolvers) hold
  **camps** inland and **roadblocks** on the highways; pirates (headscarves, striped shirts,
  carbines) hold **coves** on the shore. AI states: IDLE, SUSPICIOUS, COMBAT (cover, peek, flank),
  SEARCH, FLEE (morale broke), DEAD.
- **Camp** — an encounter: id, kind, position, facing, size; props and men spawned near the
  courier (`EncounterDirector`, `CampKit`). **Cleared** when nobody is left standing (a bounty).
  **Ambush** — a transient roadblock camp set ahead of a courier carrying a package on an outer
  highway.
- **Vitals** — the courier's `Health` (regenerating), **knocked out** at zero: fade, **respawn** on
  the nearest road to the **last safe spot**, a small coin penalty, a moment of invulnerability.

## Control

- **ControlIntent** (`Controls.Intent`) — everything the rider asks for in one physics tick:
  throttle, brake, steer, pitch, move, run, aim, look, and the edge-triggered presses (jump, fire,
  reload, interact, wings, reset). Physics modules consume intents; they never read `Input`.
- **ControlSource** (`Controls.Source`) — the seam that produces intents. Two adapters:
  **Keyboard** (`Controls.Keyboard`, the only reader of `Input.*` and the only place a key's meaning
  per mode is decided) and **Scripted** (`Controls.Scripted`, driven by the Autopilot and the tests).
- **Autopilot** — drives the bike along the road graph through a Scripted source (`--autotest`).

## Camera

- **Framing** — how the camera looks at its target: `BIKE`, `FOOT`, `SWIM`, `PLANE`
  (`ChaseCamera.Framing`, a data table). Chase framings ease behind the target; orbit framings
  (foot, swim) make the view direction exactly (yaw, pitch) so the crosshair and `view_ray()` agree.
- **Aiming** — the over-the-shoulder framing while the aim button is held.

## World

- **Hub** — a named place with geometry other modules build on: Villa Rosa, Hilltop Farm, Harbour,
  Dunes Lookout, San Telmo Monastery, the Marble Quarry, Cala Blanca, the Salinas
  (`Island.HUB_TABLE`, `db.hub(id)` → `Hub`). A Hub knows its centre, ground height, delivery ring,
  stone **walls** (`wall_top(x)`) and **bench** (`bench_top(fraction)`).
- **Place** — a named location without a hub but with a ring and some geometry: Town Square,
  Lighthouse, Hamlet, Windmill Ridge, Hill Chapel, Refugio, Lakeside Camp, Bodega, Torre Vieja
  (`Island.PLACE_TABLE`, `_build_place`).
- **Ring** — a delivery pickup / drop-off zone; `db.locations` maps ids to positions.
- **Ground** — one question, one answer: `Terrain.probe(pos)` returns the heightfield height or
  whatever is built on top (roof, deck, pier); `Terrain.nearest_road(pos)` returns the nearest road
  point and tangent from a spatial grid.
- **Road** — a dirt track stamped into the heightfield along a curve; the autopilot's graph and the
  reset key both use the road samples. Over water a road becomes a **bridge**; over a **viaduct**
  (`Terrain.viaducts`) it rides a fixed deck on an **arcade** of arches; both get **ramps** on the banks.
- **Biome** — what the map says a cell is: SEA, LIMESTONE (NW massif), FOREST (centre), FARM (SW
  vineyards and the bodega), BADLANDS (SE hoodoos and the southern headland), TOWN (NE island), BEACH,
  LAKE (the badlands lake and the southern lagoon), DUNES (south-west shore), MOOR (the northern
  Highlands), SALTFLAT (the salinas). Texture, tint, relief and props follow it.
- **Map** — `data/island_map.png` (417 px, 3 m cells, 1248 m core). `world/mapgen/extract.py` reads
  the painting into the 720 m map; `expand.py` scales that by K = 1248/720 and grows the Highlands
  and the Southern Shore into the sea; painting pixels convert to world XZ with `Island._px`.
- **Terrain3D** — the plugin that draws and collides the ground. `Terrain.build()` still produces the
  3 m heightfield (roads, bridges, pads); `_build_terrain3d()` resamples it to 1.5 m, paints a
  **control map** (base texture per biome, rock overlay by slope, dirt overlay by road distance) and a
  **colour map** (tints: field strips, heather, seabed depth), and imports all three. `height_at` /
  `normal_at` read Terrain3D's data afterwards, so gameplay stands on exactly what is drawn.
- **WorldKit** — the builders every level shares (houses, kits, arcades, sea); `Level` is the island.
- **RockGen** — `world/kit/rock_gen.gd` builds every rock mesh (boulders, cliff walls, arches,
  stacks, talus) as bedded limestone with baked crease occlusion; `rock.gdshader` lights it with a
  warm sun term, a sun-gated cool shade fill and a sky fill on the tops.
- **Atmosphere** — the one dict in `WorldKit` that sets the sun (yaw/elevation/colour), ambient,
  fog, sky shader stops, clouds and sea colours; the reference look lives there, and
  `reference/` holds the targets it is measured against (`BRIEF.md`, `compare.py`, spots).

## The outer world

- **Core** — the hand-built 1248 m island at the centre (Terrain3D, `Island`). Everything beyond
  it is the **outer world** (`OuterWorld`, `world/outer`, data in `data/outer`, ADR 0010).
- **Lagoon** — the sea ring round the core; the mainland begins 1.4-1.7 km out. The **estuary**
  runs from its east shore to the eastern bay; the **strait** parts the big western island.
- **Core exits** — the four core roads appended last in `Island._define_roads` (north past the
  monastery, east by the lighthouse, south under Torre Vieja, west off the coast road). The outer
  **spokes** start exactly on their last samples.
- **Lattice** — the outer ground's definition: triangles on a 6.25 m grid, each point the bilinear
  data height plus **micro relief** x (1 - **flatten**). Drawn, collided and queried identically.
- **Road classes** — **highway** (11 m, 7 % grade: the **ring** joining the five towns and the four
  spokes), **road** (7 m, 10 %: hamlets, country roads, the **causeway**), **track** (4.5 m, 14 %:
  mountains, desert, capes), **street** (a town's main street, from its **gate** to its plaza).
- **Town** — Puerto Alto (`puerto`), Valdoro (`valdoro`), Sarmada (`sarmada`), Isola Serena
  (`isola`), Campo Real (`campo`); **hamlets** take the style of the nearest town. Each is a
  location with its delivery ring on the plaza.
- **Plot** — one building site in `plan.json`: id, style, kind, x/z, y (the pad), yaw (the street
  side faces `(sin yaw, 0, cos yaw)`), w (frontage), d, floors, seed, tags, ground_min. The
  contract with the architecture kit (`BuildingKit.build_group`).
- **BuildingKit / style** — the architecture kit (`world/kit/building_kit.gd`) and a town's look:
  `puerto` (Porto/Lisbon rowhouses, azulejo, iron balconies), `valdoro` (alpine rubble, timber,
  slate), `sarmada` (whitewashed desert port, blue shutters, crenellated ochre walls), `isola`
  (pastel island cubes, vaults, loggias, outside stairs), `campo` (honey stone and brick, porticoes,
  barns, granaries, windmills) and `core` (the island's whitewash and terracotta). A **module** is
  an instanced piece (window, door, balcony, chimney...); a **party wall** is a side a plot shares
  with its neighbour (`BuildingKit.annotate`): no windows, no eaves there.
- **Sea lane** — a shipping route between **ports** (the core harbour, Puerto Alto, Sarmada, Isola
  Serena) through water >= 8 m deep and >= 60 m from the coast; bridges over them clear 12 m.
- **Camp** (in the plan) — a bandit camp or pirate cove point the `EncounterDirector` reads.

## Architecture (see ARCHITECTURE.md)

- **Game** — the root node: boots the managers and wires them; `Game.current` for tests/tools.
- **WorldDatabase** — the authoritative description of the world: build **recipes** per chunk,
  **locations** (id → position) and **hubs**. Exists whether or not anything is loaded.
- **Chunk / WorldStreamer** — 60 m squares; the streamer keeps a 7×7 ring of chunks around the
  **focus** (bike or boy) instantiated and frees the rest.
- **Recipe** — a Callable that builds one prop with a WorldKit builder into the chunk (`kit.sink`).
- **Entity / EntityManager** — anything simulated, registered by a **stable id**
  (`vehicle.bike`, `can.hilltop_farm.2`); the manager assigns a **simulation tier**
  (FULL / REDUCED / ABSTRACT / DORMANT) by distance to the focus.
- **Definition** — a read-only Resource in `data/` (VehicleDefinition, JobDefinition, WorldConfig).
- **Events** — the EventBus autoload; **Saves** — the SaveManager autoload (diffs keyed by id).
