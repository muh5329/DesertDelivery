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
- **Pistol** — found on a crate at the Dunes Lookout; pops **tin cans** on the farm wall and the
  lookout bench (`GunSystem`).

## Control

- **ControlIntent** (`Controls.Intent`) — everything the rider asks for in one physics tick:
  throttle, brake, steer, pitch, move, run, aim, look, and the edge-triggered presses (jump, fire,
  interact, wings, reset). Physics modules consume intents; they never read `Input`.
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
- **Map** — `data/island_map.png` (417 px, 3 m cells, 1248 m world). `world/mapgen/extract.py` reads
  the painting into the 720 m map; `expand.py` scales that by K = 1248/720 and grows the Highlands
  and the Southern Shore into the sea; painting pixels convert to world XZ with `Island._px`.
- **Terrain3D** — the plugin that draws and collides the ground. `Terrain.build()` still produces the
  3 m heightfield (roads, bridges, pads); `_build_terrain3d()` resamples it to 1.5 m, paints a
  **control map** (base texture per biome, rock overlay by slope, dirt overlay by road distance) and a
  **colour map** (tints: field strips, heather, seabed depth), and imports all three. `height_at` /
  `normal_at` read Terrain3D's data afterwards, so gameplay stands on exactly what is drawn.
- **WorldKit** — the builders every level shares (houses, kits, arcades, sea); `Level` is the island.

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
