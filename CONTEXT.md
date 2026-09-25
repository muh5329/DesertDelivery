# Desert Delivery — domain language

Names the code uses for the things in the game. Architecture terms (module, interface, seam,
adapter, depth, leverage, locality) follow the codebase-design vocabulary.

## People and things

- **Rider** — the boy. Also the name of the module (`scripts/rider.gd`) that owns what he is
  doing right now and every transition between those states.
- **Mode** — the Rider's state: `RIDING`, `DRIVING` (the Jeep), `FLYING`, `ON_FOOT`, `SWIMMING`. Only the Rider changes it;
  everyone else reads `rider.mode` or reacts to `mode_changed(from, to)`.
- **Bike** — the red courier motorbike (`scripts/bike.gd`). Has **wings** that fold out (plane
  mode); when the wings are out and the bike is airborne the Rider is `FLYING`. A **parked** bike is
  one the Rider has hopped off.
- **Jeep** — the courier's amphibious 4x4 (`Jeep`, from LegendOfJeep; it replaced the cargo
  truck). Parked a short walk behind the starting bike. **Boost** (Shift) is a short burst tank
  that refills; the **winch** on its front bumper (Q) hooks an obstacle ahead and pulls; its
  **bed** behind the seats holds a small load. **Afloat** — in water too deep to ford it floats
  (the **pontoons** swing down, the **propellers** fold out: the amphibious **transformation**)
  and **planes** on its `PlaningDrive`, slower than on land, until the bed rises under its front
  wheels again (a beach, a slipway).
- **Cart** — the two-wheeled load bed from Red Sea Baron (`CargoCart`): a plank bed, slatted
  sides, a canopy rolled over its front third, a drawbar. **Hitched** to the bike or the Jeep
  (H, stopped, backed up so its drawbar eye is at the vehicle's **hitch**), otherwise parked.
- **Rig** — a tow vehicle and the Cart hitched behind it, as one assembly (Red Sea Baron's
  word). Recoveries, respawns and saves act on the rig. A rig cannot fly (the wings stay folded)
  and cannot float (a cart sinks: deep water is a splash).
- **Drawbar / tether** — the cart is always solved to sit a drawbar's length behind the hitch,
  along the real axle-to-hitch line; the tow vehicle may not get further from the cart's axle
  than hitch + drawbar + slack (`GroundDrive.tether_*`), so an over-stretched drawbar slows it.
- **Hold** — somewhere goods are: the courier's **pack** (30 kg), the Jeep's bed (120 kg), the
  Cart (240 kg) — each an `Inventory` — or a **store**: a colony's hall or warehouse (its stock,
  free to its mayor) or a road station's / courier counter's **shop** (fuel cans and ammunition
  crates for coins). The **load panel** (G) moves goods between the holds in reach.
- **Item** — one kind of carried thing (`ItemDefinition`): every colony good (timber, planks,
  stone blocks, tools, bread, fish, cloth...) plus the courier's **equipment**: an **ammunition
  crate** (four Garand clips) and a **fuel can** (a quarter tank). **Using** one (U in the panel)
  refills the pouch or pours the can into the vehicle.
- **Package** — rides on the bike's rear rack between a **pickup ring** and a **drop-off ring**.
  Or in the Cart: a heavy or urgent load collected with the cart hitched goes straight into it,
  the panel can move it between the courier and the cart, and the cart in the drop-off ring hands
  it over.
- **Job** — one pickup → drop-off pair. Fifteen chain across the core and the country (`DeliverySystem`).
- **Garand** — the courier's M1 Garand, his rifle from the start (`GunSystem`, `GarandModel`).
  **Slung** on his back, **shouldered** while aiming (ADS), at the **hip** for snap shots. Fed by
  8-round **en-bloc clips**; the empty clip leaves with a **ping**. **Reserve** = full clips in the
  pouch (+ loose rounds from a part clip ejected by a manual reload). The **ammo cache** at the
  Dunes Lookout (where the old pistol lay) and camp **ammo crates** refill it. **Tin cans** on the
  farm wall and the lookout bench are practice targets.
- **Spread** — the half-angle of the shot cone: hip vs aimed, plus movement, air and **bloom**.
- **Bandit / Pirate** — an `Enemy` (a townsfolk body in the `bandit` / `pirate` style, EnemyOutfit's
  gear on top): bandits (dusters, hats, lever rifles, revolvers) hold
  **camps** inland and **roadblocks** on the highways; pirates (headscarves, striped shirts,
  carbines) hold **coves** on the shore. AI states: IDLE, SUSPICIOUS, COMBAT (cover, peek, flank),
  SEARCH, FLEE (morale broke), DEAD.
- **Camp** — an encounter: id, kind, position, facing, size; props and men spawned near the
  courier (`EncounterDirector`, `CampKit`). **Cleared** when nobody is left standing (a bounty).
  **Ambush** — a transient roadblock camp set ahead of a courier carrying a package on an outer
  highway.
- **Vitals** — the courier's `Health` (regenerating), **knocked out** at zero: fade, **respawn** on
  the nearest road to the **last safe spot**, a small coin penalty, a moment of invulnerability.
  Saved with the game (a quick load is not a heal).
- **Tank / fuel** — each vehicle's own (`JourneySystem`): the bike 30 km a tank, the Jeep 40 km (2.2x afloat); a load, a towed Cart and a flight (1.6x)
  burn more; **limp** at walking pace when empty; a **fuel can** adds a quarter tank. **Station** — a fuel stop (`RoadServices`): a **town
  station** at each town's edge (pumps, a shop that is the **coach & ferry office**), a **service
  stop** on the highways, or a courier counter. **Coach / ferry ticket** — fast travel to a
  visited town with the bike on the roof rack, for coins and game time.

- **Resident** — one of the 64 named islanders (`data/life/residents.json`); a **ResidentActor** is
  the body drawn near the player.
- **Townsperson / look** — what a person looks like: a `CharacterLook` Dictionary decided from a
  seed, a **town style** (`island`, `puerto`, `valdoro`, `sarmada`, `isola`, `campo`) and an
  occupation — sex, age, height, build, skin, face, hair, facial hair, garments, fabrics,
  patterns, shoes, hats, aprons and accessories. A resident's look comes from their id, district
  and name, so nothing is saved. The **signature** (hair, hair colour, top, top colour) never
  repeats among residents.
- **Near / far mesh** — a townsperson's detailed body and its light version beyond ~20 m, same
  silhouette and colours.

## Control

- **ControlIntent** (`Controls.Intent`) — everything the rider asks for in one physics tick:
  throttle, brake, steer, pitch, move, run, aim, look, and the edge-triggered presses (jump, fire,
  reload, interact, wings, reset, winch, hitch, cargo). Physics modules consume intents; they never read `Input`.
- **ControlSource** (`Controls.Source`) — the seam that produces intents. Two adapters:
  **Keyboard** (`Controls.Keyboard`, the only reader of `Input.*` and the only place a key's meaning
  per mode is decided) and **Scripted** (`Controls.Scripted`, driven by the Autopilot and the tests).
- **Autopilot** — drives the bike along the road graph through a Scripted source (`--autotest`).

## Camera

- **Framing** — how the camera looks at its target: `BIKE`, `FOOT`, `SWIM`, `PLANE`, `JEEP`
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
- **River** — a channel traced by drainage from the mountains to the sea, the estuary or the lagoon
  (`world/mapgen/outer_water.py`), carved as a bed with banks; its water surface is a polyline of
  (x, level, z, width) in `plan.json` `rivers`, drawn by `OuterRivers`. Roads cross on bridges.
- **Wadi** — a dry river bed of the arid south (and the **Rambla**, the big valley down to the south
  bay): sand and braided gravel, oleander and tamarisk on the banks (`feat.png` R).
- **Erg** — the sand sea east of the mesas: a basin of transverse dunes (`feat.png` B, biome DUNES).
- **Oasis** — irrigated plots and palm groves in the desert (`feat.png` G, `oasis` landmarks).
- **Feature map** — `data/outer/feat.png`: wadi bed, irrigation, erg, cavity (valleys darker from
  afar; 0.5 = none).
- **Quay / quay wall** — a town's paved waterfront behind a `quay_edges` polyline; the water in front
  is dredged, and `OuterProps` stands a stone quay wall where the ground meets it. A **mole** is a
  breakwater filled out into the sea (Sarmada's and Puerto Alto's carry the lighthouses).
- **Prop** — a piece of town dressing (`plan.json` town `props`: kind, x, y, z, yaw, variant) placed
  by `world/mapgen/outer_props.py` and built by `OuterProps` / `ArchProps`. **Terraces** — Valdoro's
  dry-stone terrace walls along the slope's contours.

## Outer life (ADR 0012)

- **Townsperson** — one ambient person of an outer town or hamlet (`Townsperson`): seed, trade,
  home, work spot, daily routine. Not a resident, not a colonist; nothing about him is saved.
- **Town population** — a town's spots, walking graph and townspeople (`TownPopulation`), made
  from its plan record. A town is **prepared** (generated) within 1.6 km of the viewer and
  **active** (routines running, bodies drawn) within ~0.5 km.
- **Spot** — a place a townsperson can be: a **door** (home), a **stall** (vendor behind, shoppers
  in front), a **shop** door, a **seat** (bench, cafe chair), a **chat** spot (plaza, fountain), a
  **mend** / **fish** / **dock** spot on the quay, a **field** or **barn** spot.
- **Routine** — `[minute, spot, activity]` entries: home (indoors, no body), work, rest, shop.
- **Body** — a pooled `TownBody` drawing one townsperson near the viewer.
- **Traffic** — the vehicles on the outer roads round the viewer (`OuterTraffic`): car, lorry,
  bus, tractor, donkey cart. A **gate** is where a town's main street meets the country road.
- **Fishing boat** — a boat of an outer harbour (`OuterBoats`): mooring, trip out, fishing ground.
- **Urgent supply job** — an optional **cargo** delivery (the Jeep, or a rig towing the Cart) a short colony posts (`UrgentSupply`):
  "Urgent: 20 bread to Isola Serena", taken with U.

## Colonies (ADR 0011)

- **Colony** — a town run by the Mayor: `ColonyTown` (stockpile, buildings, colonists, needs,
  happiness). The core **villa colony** exists from the start; a town is **discovered** when the
  courier rides in and **chartered** (founded) for coins: a **colony hall** (warehouse), settlers,
  a starter stock. The **build area** is a ring round the hall.
- **Colonist** — a colony's person (a record; near the viewer a townsperson in the town's style).
  Not one of the 64 **residents**, who keep their own jobs on the core (Jobs / Areas / Paths).
- **Building** — a colony building record: type (EconomyCatalog.BUILDINGS), site, construction
  **progress** (foundation, scaffold, built), production **cycle**, **inbuf** / **outbuf**, and its
  **porter** (`carry`) walking goods to the nearest storage and inputs back.
- **Chain** — raw goods (regional: timber, stone, ore, grain, olives, grapes, fish, salt, cotton,
  dates) processed into planks, blocks, tools, flour, bread, oil, wine, cloth, preserved fish.
- **Needs** — food (with variety), goods, housing; **happiness** follows them; **growth** and
  **decline** follow happiness. Colonies pay **taxes** into the courier's wallet.
- **Port / berth / mooring** — the plan's ports; a ship lies alongside at the mooring point off
  the berth. **Sea route** — the water path between two ports (`ShippingNetwork.route`).
- **Lane** — two port colonies, an outbound and a return **cargo rule**, the ships assigned.
  **Ship** — coaster or schooner, built at a **shipyard**; far ships are a distance along a route.
- **Raid risk** — the chance per leg that pirates from an uncleared **pirate cove** near the route
  take part of the cargo. Coves have names (`ShippingNetwork.cove_name`) and the Trade page shows them.
- **Staple / kitchen garden** — the food a town colony's hall grows from the first day (fish,
  potatoes, dates, vegetables); **local foods** are the foods its land gives (cheese, potatoes,
  game, vegetables, fish, dates, olives...).
- **Carter / road route** — a wagon carrying goods by road between two colonies (`RoadHaulage`).

## Loading and the map

- **Boot stage** — one named step of the boot (`Game._boot_stages`): the loading screen draws a
  frame between stages; its bar is the stages' measured share (`Game.BOOT_WEIGHTS`).
- **Loading screen** — `LoadingScreen`: key art, title, the stage line, the bar, a **tip**. Up from
  the boot's first frame, and over a **long move** (a ticket, F6, a far respawn or load) until the
  world is **settled** (`WorldManager.settled()`: nothing round the focus left to build) and the
  frames are smooth.
- **Minimap** — the HUD's round map (top right), **heading-up** or **north-up**, three **zoom
  levels** widened by speed and flight. **Full map** — the M panel. Both draw the **baked map**
  (`data/minimap`: the **overview** and the **insets**) and the **markers** over it.
- **Waypoint** — a point the player sets on the full map; on the minimap, the compass rim, saved,
  cleared on arrival. **Discovered** camp — a camp or cove the courier has come near (450 m): only
  those are on the map.

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
