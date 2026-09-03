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
  Dunes Lookout (`Level.HUB_TABLE`, `Level.hub(name)` → `Hub`). A Hub knows its centre, ground
  height, delivery ring, stone **walls** (`wall_top(x)`) and **bench** (`bench_top(fraction)`).
- **Ring** — a delivery pickup / drop-off zone; `Level.locations` maps ring names to positions.
- **Ground** — one question, one answer: `Terrain.probe(pos)` returns the heightfield height or
  whatever is built on top (roof, deck, pier); `Terrain.nearest_road(pos)` returns the nearest road
  point and tangent from a spatial grid.
- **Road** — a dirt track stamped into the heightfield along a curve; the autopilot's graph and the
  reset key both use the road samples. Over water a road becomes a **bridge**; over a **viaduct**
  (`Terrain.viaducts`) it rides a fixed deck on an **arcade** of arches; both get **ramps** on the banks.
- **Biome** — what the painting says a cell is: SEA, LIMESTONE (NW massif), FOREST (centre), FARM (SW
  vineyards), BADLANDS (SE hoodoos), TOWN (NE island), BEACH, LAKE. Colour, relief and props follow it.
- **Map** — `data/island_map.png`, extracted from the painting by `tools/mapgen/extract.py`; painting
  pixels convert to world XZ with `Level._px`.
- **WorldKit** — the builders every level shares (houses, kits, arcades, sea); `Level` is the island.
