# Desert Delivery

A third-person courier game on a **25 km × 25 km** country: a detailed 1.248 km Mediterranean island at the centre, ringed by a lagoon, and round it a generated country — an alpine range with a dammed lake in the north, an arid plateau of mesas and canyons in the south, farmland plains and an estuary in the east, a rugged coast and an archipelago in the west. Five towns (the port city of Puerto Alto, the alpine hill town of Valdoro, the walled desert port of Sarmada, the island village of Isola Serena, the plains market town of Campo Real) and fourteen hamlets are joined by ~220 km of highways, roads and tracks with 40+ bridges, and by sea lanes between the ports. See [ADR 0010](docs/adr/0010-outer-world.md).

The September 2026 overhaul adds a hand-painted, Ghibli-inspired summer palette, an ImageGen gouache surface used by terrain and object materials, a newly authored Blender delivery truck, regraded existing GLBs, and individually generated townsfolk for all 64 residents (see Island life). The courier's model and most existing topology remain. Godot **4.7 Forward+ (Vulkan)** is the current renderer on macOS; Terrain3D draws and collides the detailed core.

The gameplay pass adds explicit player/resident states, responsive bike and truck handling (the truck is now the Jeep), buffered/coyote jumps, safe mounting, blocked-route recovery, spatial traffic lookup, and atomic delivery payouts with saved receipts. Implementation, real screenshots, adversarial findings and remaining quality gaps are in [the overhaul review](artifacts/overhaul-2026-09-19/README.md). AAA quality has not been demonstrated.

## Run it

1. Install Godot 4.7 (standard build) from https://godotengine.org/download.
2. Open Godot → **Import** → pick `project.godot` in this folder → **Edit** → press **F5** (Play).
   Or from a terminal: `godot --path /path/to/DesertDelivery`.
   Desktop uses Forward+; macOS selects Vulkan after full-render profiling. For older GPUs, use `godot --path /path/to/DesertDelivery --rendering-method gl_compatibility`.
   The Terrain3D GDExtension ships in `addons/terrain_3d` (binaries for macOS, Windows, Linux, iOS, Android, web);
   it does not need to be enabled as an editor plugin for the game to run. `--facet` on the command line
   (after `--`) renders the old flat-shaded terrain instead, for comparison.

## Controls

| Action | Keys | Gamepad |
| --- | --- | --- |
| Accelerate | W / ↑ | Right trigger / A |
| Brake / reverse | S / ↓ | Left trigger / B |
| Steer | A D / ← → | Left stick |
| Handbrake (drift) | Space | X |
| Reset active vehicle to the nearest road | R | Y |
| Look back | C | — |
| Aim the Garand (hold, on foot) | Right mouse | LB |
| Fire the Garand (on foot) | Left mouse / F | RB |
| Reload (a part-empty clip pings out first) | V | D-pad left |
| Boost (driving the jeep; a short tank that refills) | Shift | — |
| Fire / release the jeep's winch (driving the jeep) | Q | RB |
| Hitch / unhitch the cart (stopped; driving, or on foot beside the cart) | H | — |
| Load / unload: the pack, the jeep's bed, the cart and a warehouse or shop in reach (stopped) | G | — |
| In the load panel: column / line · destination · move 1 / 10 / all · empty the column · use · close | A D / ← → · W S / ↑ ↓ · Tab · Space / Shift+Space / Enter · X · U · G / Esc | — |
| Courier counter / fuel station (stopped on its apron) | B | B |
| Island journal | N | — |
| Full-screen map: drag / WASD pan, wheel / +- zoom, click sets a waypoint, right click clears it, C centres on you, R heading-up / north-up minimap, M / Esc closes | M | Start (left stick pans, triggers zoom, A waypoint at the cross, X clears, B closes) |
| Minimap zoom: close / medium / far (it also widens with speed and in flight) | Z | D-pad down |
| Minimap heading-up / north-up | Shift+Z | — |
| Take an urgent colony supply job | U | — |
| Close journal / quit | Esc | B closes journal |

## Beyond the bike

- **E** exits the current vehicle (when stopped) — walk with WASD, Shift to run, Space to jump, mouse / right stick to look. E beside either vehicle mounts it. R brings the active vehicle and rider back to the nearest road.
- Hold Space for a higher on-foot jump; tap for a short hop. Movement follows the camera, and manual orbit keeps your chosen direction. The camera retracts around obstacles and hides the character when pushed too close.
- **The Jeep** — an amphibious 4x4 (from the LegendOfJeep project: its realistic Blender model and its handling) is parked a short walk behind the starting bike; it took over the old cargo truck's jobs. E beside it to drive: a strong pull from low speed, a handbrake drift (Space) and a short **boost** tank (Shift) that refills on its own. Drive it down a beach into the sea, the lagoon, the estuary or a lake: the side pontoons swing down, the propellers fold out and it **planes** across the water (slower than on the road, and thirstier); drive up any beach or slipway and the wheels take over again. Behind the seats its bed carries up to 120 kg of goods.
- **Winch** — while driving the jeep, Q fires the front cable at a tree, rock, building, or other solid obstacle up to 38 m ahead. It reels in automatically and can pull the jeep up steep walls when the anchor is high; press Q again to release it.
- **The Cart** (from the Red Sea Baron project) — a wooden two-wheeled cart waits on the lane behind the jeep. Back the bike or the jeep up to its drawbar, stop, and press **H** to hitch it (or walk up to it and press H with a vehicle backed up to it); H again, stopped, unhitches it. It follows on its drawbar round bends, over hills and bridges, and its tyres roll with it; the tow vehicle slows with the weight (240 kg of load at most) and burns more fuel. The bike cannot unfold its wings with the cart on, and the jeep cannot float with it (a cart sinks: deep water puts the rig back on the road). A cart that falls or sinks comes back to the road with its load.
- **Loading** — stopped, press **G** by the cart, the jeep, a colony's hall or warehouse, or a road station's or courier counter's shop: a parchment panel shows your pack (30 kg), the jeep's bed, the cart and the store side by side. Colony goods (timber, planks, stone blocks, tools, bread, fish, cloth...) come out of and go into your colonies' stock free — load at one colony, unload at another: land trade by cart. Shops sell **fuel cans** (a quarter tank; U uses one) and **ammunition crates** (four Garand clips). A heavy consignment or an urgent colony supply run collected with the cart hitched rides in the cart, and the cart in the drop-off ring delivers it.
- **Swim** — wade into the sea and the boy swims (slower, can't shoot); the bike auto-resets if it ends up in the water.
- **M1 Garand** — the courier's rifle from the first minute: slung across his back on foot (and on the bike), shouldered when you hold RMB / LB (a tight over-the-shoulder view with a narrower field of view and a much smaller shot cone), fired from the hip otherwise (bigger spread). Semi-automatic, 8-round en-bloc clips: the 8th shot throws the empty clip out with the famous *ping*, then a fresh clip goes in and the bolt slams home (V reloads early; the part clip pings out and its rounds are pocketed). Reserve clips show in the Garand panel; enemies drop clips, camps keep an ammo crate, and the crate at the Dunes Lookout where the old pistol used to lie is now a cache of clips. Tin cans still line the farm's stone wall and the lookout bench (9 total) for practice.
- **Bandits and pirates** — bandits (dusters, bandanas, wide hats, lever rifles and revolvers) hold camps in the badlands and out along the highways; pirates (headscarves, striped shirts, sashes, carbines) hold coves on the shore. A bandit camp sits in the badlands east of the Dunes Lookout and a pirate cove in the dunes of the south-west shore, a short ride from the start; ten more bandit camps and four coves are out in the country. They notice you in their sight cone or hear your shots, shout to each other, take cover, peek and shoot (worse at range and against a moving or covered target), reload, flank, and run when their nerve breaks. Carrying a package on an outer highway, you may find a bandit roadblock ahead. Clearing a camp pays a 20-coin bounty; cleared camps stay cleared (saved).
- **Health** — 100, regenerating after 5 s without a hit; red arcs show where shots come from and the screen edges redden when you are hurt (a heartbeat below 30 %). Riding or driving you take 60 % (and moving fast makes you hard to hit). Knocked out, you wake on the nearest road to your last safe spot, a few coins lighter (10 %, at most 25), with a moment of invulnerability.
- **Plane** — T / D-pad-up folds the wings out. Throttle (W) past 54 km/h, then pull back (S / ↓) to lift off. In the air the engine cruises on its own: S/↓ raises the nose, W/↑ lowers it, A/D bank, Shift boosts. To land, nose down gently and pull up just before touchdown; T folds the wings again.
- Flight can climb to **5,000 m above sea level**, well above the outer island mountains.
- **Fuel** — a full tank rides about 30 km on the level (heavy freight burns a third more, flying 1.6x per metre); the HUD shows the range and, below a quarter tank, the nearest pump. Run dry and the bike limps on at 25 km/h. Red **FUEL** signs mark the stations: one at the edge of every town, highway service stops every ~5 km, and the courier counters. Stop on the apron and press **B**: a service stop fills the tank for coins, a town station opens its window (fuel and **coach & ferry** tickets: fast travel with the bike to any town you have already ridden to, for coins and game time).
- **Loading screen** — the boot draws a loading screen from its first frame (key art, the stage being built, a progress bar driven by the real boot stages, gameplay tips) and keeps it up until the world round the courier is built and the frames are smooth. Coach and ferry tickets, F6, a far respawn and a far quick load show it too.
- **Minimap and map** — top right, under the day card: the country painted as a storybook map, heading-up (Shift+Z: north-up), centred on you. It shows the pickup and drop-off (pinned to the rim with a pointer when beyond it), your waypoint, the parked bike, jeep and cart, fuel stations and courier counters, the bandit camps and pirate coves you have found, colony halls, sea lanes and ships near a port, and place names. Z cycles three zoom levels, which widen with speed and in flight. M opens the full map: click to set a waypoint (it shows on the minimap and as a blue diamond on the compass, and clears itself when you get there).
- Esc twice within 3 s quits (the first press also frees the mouse; click to re-capture).

## The loop

Ride to the glowing ring at the pickup, slow to a stop inside it to load the package onto the rear
rack, then follow the compass (top-left) to the destination ring and stop again to hand it over.
Walking, the jeep and a parcel in the cart also support handoffs. Stay grounded and below 2.5 m/s in the
ring for half a second. Coins are awarded once on delivery, and F5/F9 preserves the current
package, job and wallet. Fifteen jobs chain round the island and out into the country: Villa Rosa Office (SW vineyards) → Hilltop Farm (NW massif) → Harbour Cafe
(NE town, over the strait aqueduct) → Dunes Lookout (badlands, over the gorge viaduct) → Lakeside Camp →
Bodega San Marco (the southern vineyards) → the Salinas (salt pans) → Cala Blanca (fishing cove) → the Marble
Quarry and San Telmo Monastery (the northern Highlands, over the mountain pass) → back to the Villa, and on out
over the lagoon bridges: Campo Real (the plains) → Puerto Alto (over the estuary bridge) → Sarmada (the south coast)
→ Isola Serena (over the causeway) → Valdoro (up the switchbacks in the north).
Signposts at each hub and at every outer junction point the way; F6 teleports to the next hub.

## The country

Beyond the lagoon: the alpine range with its dammed lake, snowfields and pine forests in stands and
glades (shrubs, ferns and fallen trunks underneath, meadows in flower above); rivers running from the
mountains to the lagoon, the estuary and the sea, bridged where the roads cross; the green farmland of
the east with its hedged parcels, vineyards, hay and orchards; the south's red-banded mesas and
canyons, dry wadis lined with oleander and tamarisk, dark gravel plains, a sand sea of dunes east of
the mesas and irrigated palm oases down the Rambla to Sarmada; the rugged west with dry-stone field
walls. Masonry arch bridges and a stone causeway carry the country roads, concrete viaducts the
highways; the roads have shoulders, kilometre stones, delineators, bend chevrons and lit approaches to
the towns. The towns' plazas have fountains, planted trees, benches, lamps, markets and cafe tables;
the ports have stone quays, bollards, moored and bobbing boats, jetties, cranes, nets and moles with
their lighthouses; Valdoro's slopes are terraced. On Forward+ the look adds SSAO, SSIL, a thin
volumetric fog and four shadow cascades (`--nopost` turns the post stack off to compare).

## Places

Eight hubs with delivery rings — Villa Rosa, Hilltop Farm, the Harbour, Dunes Lookout, San Telmo Monastery,
the Marble Quarry, Cala Blanca and the Salinas — and nine more named places to find: the Town Square and the
Lighthouse on the town island, the Hamlet by the bay, Windmill Ridge, the Hill Chapel, the Refugio on the pass,
the Lakeside Camp, the Bodega and Torre Vieja (the old fort on the southern headland).

## Life in the country

The towns and hamlets are lived in: about 1,200 townsfolk (Puerto Alto ~460, Sarmada and Campo
Real ~200, Valdoro ~120, Isola Serena ~110, a hamlet 4-10), each dressed in the town's style and
working a trade that fits the place — vendors behind the market stalls, shopkeepers sweeping
their doorsteps, dockworkers carrying crates along the quays, fishers mending nets and fishing off
the quay, farmers hoeing the gardens and working at the barns, shepherds and woodcutters in
Valdoro, porters and weavers in Sarmada's souk. They keep a daily routine on the island clock
(home, work, lunch on a bench or at a cafe table, back to work, an errand, the evening on the
plaza, home at night) and walk the streets between, never through the buildings. Cars, lorries
and country buses run on the highways, tractors and donkey carts on the country roads and tracks,
in their lanes, at the road's speed, yielding at junctions and stopping for you; fishing boats
leave the harbours of Puerto Alto, Sarmada and Isola Serena for their grounds and come home.
Bandits and pirates are townsfolk-style people too (dusters, bandanas over the face, wide hats;
headscarves, striped shirts, sashes, earrings). All of it only exists near you (ADR 0012).

When a colony you founded runs short of food (or goods), it posts an **urgent supply job** on
the HUD — "URGENT · 20 bread → Isola Serena · +64 coins · U to take it". Press **U** to take it:
collect the load with the jeep (or any rig towing the cart) where it is sold, deliver it for the bonus, and your route
resumes where it was.

## Colonies and shipping lanes

A build-and-manage layer over the courier game (ADR 0011). The villa on the core island is a colony
from the start; each of the five towns becomes available when you first ride into it, and a
**founding charter** (120 coins, from your delivery wallet) raises a colony hall with a warehouse
beside the port (or plaza), brings five settlers and a starter stock of planks, stone blocks,
tools and food. Colonies pay taxes into your wallet in proportion to their size and happiness.

- **Build** inside a colony's area (320 m round its hall; the whole core island for the villa) on
  dry, flat ground clear of roads, streets, plots, landmarks and delivery rings — the ghost turns
  red and the footer says why. Buildings are the towns' own architecture (the architecture kit in
  the colony's style) with a working yard (log piles, fish racks, salt pans, vats, a forge, dye
  frames, a slipway...), and rise on a staked foundation and a scaffold before they open.
- **Produce**: raw goods depend on the land — timber, stone and ore at Valdoro; grain at Campo
  Real; olives and grapes on the core; fish on the coasts; salt, cotton and dates at Sarmada —
  so the chains need trade. Each producer's porter walks its goods to the nearest warehouse and
  brings back inputs; near you they are real townsfolk carrying crates.
- **People**: colonists take jobs by themselves, eat (bread, fish, preserved fish, dates, olives,
  berries — variety helps), want goods (cloth, tools, olive oil, wine) and houses. Happiness
  follows; happy, housed colonies grow (a new colonist in the town's dress), hungry ones shrink.
- **Ships**: a shipyard at a port colony lays down a *motor coaster* (40 units, fast) or a
  *topsail schooner* (90 units, needs cloth for sails). A **lane** joins two port colonies (the core
  harbour, Puerto Alto, Sarmada, Isola Serena) with cargo rules — "load up to 40 grain at Puerto
  Alto, unload at Isola Serena; return with 30 fish". Ships follow sea routes computed over the
  real water (out of the lagoon through the estuary, between red and green channel buoys), moor
  alongside timber jetties at the berths (sails struck), load and unload, and loop. Far ships sail
  by the clock; near ones are modelled ships with a wake. A lane passing
  an uncleared **pirate cove** risks a raid each leg (part of the cargo lost, you are told); clear
  the cove and the risk is gone.

| Raw | Where | Processing | Makes |
| --- | --- | --- | --- |
| Timber (woodcutter's lodge) | Valdoro, Campo Real, core | Sawmill | 2 timber -> 2 planks |
| Stone (quarry) | Valdoro, Puerto Alto, core | Mason's yard | 2 stone -> 2 blocks |
| Ore (mine) | Valdoro | Smithy | 2 ore + 1 plank -> 1 tools |
| Grain (farm) | Campo Real | Flour mill, bakery | 3 grain -> 2 flour; 2 flour -> 4 bread |
| Olives (grove) | core, Isola Serena, Campo Real | Olive press | 3 olives -> 1 oil |
| Grapes (vineyard) | core, Isola Serena | Winery | 3 grapes -> 1 wine |
| Fish (fishing hut, by the water) | coasts | Smokehouse | 2 fish + 1 salt -> 3 preserved fish |
| Salt (salt pans, by the water) | Sarmada, Puerto Alto, core | | |
| Cotton (field) | Sarmada | Weaver | 2 cotton -> 1 cloth |
| Dates (palm grove) | Sarmada | | food |

Houses: cottage (4 colonists), townhouse (8). Storage: warehouse (+800 capacity). Port: shipyard.
Costs, workers, cycle times and storage are in `gameplay/colony/economy_catalog.gd`.

### Mayor view (F4, on foot)

| Action | Mouse | Keys |
| --- | --- | --- |
| Switch colony (the camera flies there) | colony list, top bar | — |
| Colony overview: population, needs, happiness, stock, buildings, notices, charter | **Colony** tab | — |
| Place a building | **Build** tab, pick one, click the map | **R** rotates, **Esc** cancels |
| Inspect a building (workers, flow, buffers, efficiency, pause, demolish) | click it (Select) | — |
| Ships, lanes, cargo rules, raid risk, trip log | **Trade** tab | — |
| Pan / zoom / rotate the map | right-drag / wheel | WASD / — / Q, E |
| Colony speed 1x / 2x / 4x, pause | top bar | — |
| Core island residents' jobs, resource areas, paths | **Jobs**, **Areas**, **Paths** tabs | — |
| Save / leave | top bar | F5 / F4 or Esc |

## Island life and journal

Press **N** to open the parchment field journal. Search or sort the 64 named residents,
select a person, then choose a weekday in the weekly grid or day selector to read their exact
itinerary. Field notes and the selected resident are saved with F5; F9 restores them. Closing
the journal consumes that input so it cannot also fire the pistol or quit the game.

Each resident has an occupation, home, daily routine and weekly overrides in
`data/life/residents.json`. The seven-day calendar repeats after Sunday, with 48 real minutes
per island day. Residents walk to activity stations, work with job props, eat, shop and rest;
16 delivery drivers travel between island destinations and unload before their next journey.
Records continue travelling when their models are outside streaming range. The clock, routes,
completed work and notes persist in the existing save system.

Traffic uses the road graph, finite acceleration/braking, junction priority, ground and bridge support, animated
wheels and steering, and nearby body collisions. Wildlife includes grazing sheep, deer,
rabbits and dogs, circling gulls, and two boats on validated water routes. Sky clouds drift
while daylight changes with the simulation clock.

These are stylized game assets inspired by the supplied references. Every resident is their
own person (`CharacterLook`, `entities/people`): sex, age (elders stoop and grey), height, build
(slim / average / heavy bodies), skin tone, a sculpted face (jaw, chin, nose, brow, cheekbones,
lips, eye size and spacing), eye colour, brows, stubble, moustaches and beards, 13 hair styles in
12 colours, and clothing with real silhouettes — shirts, T-shirts, blouses, sweaters, waistcoats,
jackets, long coats, dresses, skirts, overalls, tunics and robes over trousers, shorts, shoes,
boots or sandals — in cotton, linen, wool, knit, denim and leather with stripes, checks, plaid,
dots and cable knits, dressed by town palette (the Lisbon-like port, the alpine hill town, the
desert port, the pastel fishing island, the plains market town) and by occupation (bakers'
aprons and toques, fishermen's knits, farm overalls and straw hats, dockworkers' caps). Bodies
are generated on the courier's animated rig, so they walk, work, sit and drive as before; each
person is one draw call. Looks come from the resident's id, so nothing extra is saved. Their
occupations are outdoor activity stations with timed work cycles, rather than enterable shops
with a production economy.

## Blender assets

The assets were authored through Blender MCP. Editable sources are in `assets/source/`, with
`.gdignore` preventing automatic Blender conversion during game import. Runtime files are
in `assets/models/`. Reproduction scripts are in `tools/blender/`: `common.py`, `bike.py`,
`character.py`, `island_kit.py`, `town_revision.py` and `hero_finish.py`. The old courier truck (now only a traffic lorry) is generated by `storybook_truck.py`; `storybook_assets.py` applies a reproducible paint/roughness pass to the other GLBs using archived originals. The palm revision uses `town_revision.py` with broader sage fronds. The generated surface and exact ImageGen prompt are in `assets/storybook/README.md`. They use the project
path at the top of `common.py`; update it when moving the repository. Run the generators
through Blender in that order, with `hero_finish.py` last, then let Godot import the GLBs.

## Automated checks

All checks run inside the booted game through the test runner (`--test=NAME` loads `tests/NAME.gd`):

```
godot --headless --path . -- --autotest --deliveries=10 --maxtime=2800   # drives the whole loop, exits 0 on success
godot --headless --path . -- --test=outer_world_tests           # outer world: data, surface == collision, roads, towns, plots, budgets
godot --headless --path . -- --test=control_regression_tests    # analog, buffered/coyote jumps, controls
godot --headless --path . -s tests/third_person_tests.gd       # movement, jump height, slopes, camera obstruction
godot --headless --path . -s tests/bike_dynamics_tests.gd      # suspension, crest airtime, landing and timestep parity
godot --headless --path . -s tests/streaming_budget_tests.gd   # incremental construction and collider ownership
godot --headless --path . -- --test=architecture_tests          # streaming, world database, tiers, events, save/load
godot --headless --path . -- --test=edge_tests                  # brake/reverse, sea reset, camera
godot --headless --path . -- --test=feature_tests               # dismount, swim, the Garand and the cans, plane
godot --headless --path . -- --test=combat_tests                # clip/ping/reload, spread, damage, headshots, enemies, death, camps, save
xvfb-run -a godot --path . --rendering-driver vulkan -s tests/garand_view.gd -- --out=/tmp/garand    # rifle close-ups + poses (studio)
xvfb-run -a godot --path . --rendering-driver vulkan -- --facet --test=combat_view --out=/tmp/combat  # aiming, camp fight, cove, lineup, ambush
godot --headless --path . -- --test=jeep_tests                  # the jeep: mount, drive, boost, ramp, winch, fuel, into the sea and out, bed, saves (truck_tests is an alias)
godot --headless --path . -- --test=cart_tests                  # the cart: hitch bike / jeep, tow, bends, bridge, recovery, loads, parcel, colony goods, saves
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver vulkan --resolution 1280x720 -- --facet --quality=low --no-outer-life --test=vehicle_shots --out=/tmp/vehicles   # jeep, rig, water, panel (see the script for memory)
godot --headless --path . -- --test=delivery_tests              # all handoffs, wallet, loaded stage, on-foot / jeep
godot --headless --path . -- --test=life_tests                  # routines, navigation, grounding and collisions
godot --headless --path . -- --test=colony_system_tests         # core colony jobs, orders, roads, save v2 / v1 migration
godot --headless --path . -- --test=colony_economy_tests        # chains, needs/growth, placement, charters, views, tick budget, saves
godot --headless --path . -- --test=shipping_tests              # sea routes over water, round trips, far ships, pirates, saves
godot --headless --path . -- --test=mayor_view_tests            # Mayor view modal, pages, ghost, switcher, projection
godot --headless --path . -- --test=town_life_tests             # townsfolk, traffic, boats, new-look enemies, urgent supply jobs
xvfb-run -a godot --path . --rendering-driver vulkan -- --facet --test=town_life_view --out=/tmp/life   # towns, souk, harbour, highway, camps
xvfb-run -a godot --path . --rendering-driver vulkan -- --facet --test=colony_shots --out=/tmp/colony   # Mayor view, ships, district
godot --path . -- --test=catalogue_view --out=/tmp/journal.png   # actual UI checks and two viewport captures
godot --path . -- --test=town_world_view --out=/tmp/town         # streamed street and aerial captures
godot --path . -- --test=life_view --out=/tmp/residents          # real working resident and driver views
godot --headless --path . -s tests/character_look_tests.gd      # townsfolk looks: deterministic, diverse, budgets, rig
xvfb-run godot --path . --rendering-driver vulkan -- --facet --test=character_lineup --out=/tmp/people   # lineups, crowds, styles, faces
xvfb-run godot --path . --rendering-driver vulkan -- --facet --test=people_benchmark   # draw calls: old residents vs townsfolk
xvfb-run godot --path . --rendering-driver opengl3 -- --test=feature_shots --out=/tmp/fshots
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --out=/tmp/view   # 20+ fixed views, streamed
xvfb-run godot --path . --rendering-driver opengl3 -- --shots=/tmp/shots --autotest   # + screenshots
python3 world/mapgen/extract.py [painting.png]   # painting -> world/mapgen/island_map_720.png (the 720 m map)
python3 world/mapgen/expand.py                   # 720 m map -> data/ (1248 m world with the new land)
python3 world/mapgen/textures.py                 # pack / bake the ground textures in assets/terrain
python3 world/mapgen/outer_textures.py           # bake meadow / alpine / snow / asphalt / cobble textures
python3 world/mapgen/outer.py                    # generate the outer world into data/outer (~1 min)
godot --headless --path . -- --test=minimap_export   # refresh world/mapgen/minimap_core.json (the core's roads, houses, places)
python3 world/mapgen/minimap.py                  # bake the minimap into data/minimap (overview + 1.5 m insets, ~30 s)
python3 world/mapgen/key_art.py SHOT.png         # grade a beauty shot (tests/uiux_shots.gd --views=keyart) into the loading screen's key art
godot --headless --path . -- --test=uiux_tests   # boot stages, loading screen readiness, the baked map, markers, waypoint, zoom, full map
xvfb-run -a -s "-screen 0 1600x900x24" godot --path . --rendering-driver vulkan -- --facet --quality=low --test=uiux_shots --out=/tmp/uiux --views=highway,town,flying --boot-shot=/tmp/uiux/boot   # the loading screen per stage, the minimap

godot --headless --path . -- --test=dump_core_exits   # refresh world/mapgen/core_exits.json after changing the core exits
python3 world/mapgen/foliage.py                  # bake the leaf / grass cards in assets/foliage (--bleed: re-bleed only)
python3 world/mapgen/tree_bark.py [--extract]    # the trees' bark tubes (from world/mapgen/tree_skeletons.json)
python3 world/mapgen/tree_impostors.py           # the trees' far impostors (assets/trees/impostors)
godot --headless --path . -- --test=tree_asset_tests   # bark closed + in budget, leaves untouched, impostors
xvfb-run -a godot --path . --rendering-driver vulkan -- --facet --test=tree_showcase --out=/tmp/trees --quality=low   # near vs far trees
xvfb-run godot --path . --rendering-driver opengl3 -- --test=view --spots=cliff_coast --out=/tmp/x
python3 reference/compare.py /tmp/x/cliff_coast.png reference/ref_cliff_coast.png   # similarity vs the reference
```
`tests/view.gd` pins the island clock at `DayNight.REFERENCE_HOUR` (14:44), the hour whose sun is the
reference's (48° up, south-west); `--hour=H` overrides it.

Debug keys in game: **F3** overlay (fps, chunk, loaded chunks, entities per tier, draw calls...),
**F5/F9** quick save/load, **F6** teleport to the next hub, **F7** reload the chunk under you, **F8** toggle streaming.
**F10** graphics quality (Low / Medium / High / Ultra, saved; High is the default, tuned for an M4 Pro at a
Retina window; `--quality=low|medium|high|ultra` overrides it for one run). The island runs a 48-minute
day: dusk at ~19:40, night until ~5:30 (`--hour=H` pins the clock for renders).

The latest measured frame rates, controller changes, visual reviews and limitations are in [the performance and controls report](artifacts/performance-controls/README.md).

## Layout

See `ARCHITECTURE.md` for the full picture; `CONTEXT.md` for the domain vocabulary.

- `core/` – `Game` root (boot + wiring), `Events` bus, `Saves`, definitions, utils
- `world/` – `WorldManager`, `WorldDatabase` (recipes per chunk, locations, hubs), `WorldStreamer` + `Chunk`, `Terrain` (heightfield → Terrain3D), `WorldKit` builders, the `Island` generator, `outer/` (the outer world), `mapgen/` (extract, expand, textures, outer)
- `assets/terrain/` – ground textures (seven packed CC0 ambientCG sets + four baked ones; see `assets/CREDITS.md`)
- `assets/rock/`, `assets/trees/` – rock textures and the Quaternius CC0 trees with `leaf.gdshader`
- `reference/` – reference screenshots, brief, camera spots, `compare.py`, per-round critiques and changelogs
- `assets/foliage/` – grass / flower / leaf-clump cards (baked by `world/mapgen/foliage.py`) for the tree canopies and Terrain3D's instancer grass
- `addons/terrain_3d/` – the Terrain3D plugin
- `entities/` – `EntityManager` (ids + simulation tiers), player (`Player`, `Rider`, `RiderModel`), vehicles (`Vehicle` base, `GroundDrive`, `Bike`, `Jeep` + `PlaningDrive`, the `CargoCart` + `HitchSystem`), camera, enemies (`Enemy`, `EnemyOutfit`, `EnemyWeapons`)
- `gameplay/` – `GameplayManager`, `Controls` seam, `DeliverySystem` + `JobDefinition`, cargo (`Inventory`, `ItemDefinition`, `CargoSystem`, `CargoPanel`), weapons (`GunSystem`, `GarandModel`, `MeshKit`, `WeaponAudio`), combat (`EncounterDirector`, `CampKit`, `PlayerVitals`, `Health`, `CombatFx`)
- `ai/` – `Autopilot`
- `ui/` – `HUD`, `DebugOverlay`, `loading/` (`LoadingScreen`), `map/` (`WorldMap`, `Minimap`, `FullMap`, `MapIcons`, `map.gdshader`)
- `data/` – island maps, `outer/` (outer world heights, maps and plan), `minimap/` (the baked map), `config/world.tres`, vehicle definitions (`bike.tres`, `jeep.tres`), `jobs/*.tres`
- `tests/` – test nodes and render tools

## Credits: the Jeep and the Cart

The Jeep is from the author's own **LegendOfJeep** project (its realistic amphibious GLB, the
JeepMesh node contract and transformation, the Jeep controller's handling, ported onto this
game's GroundDrive and a new PlaningDrive). The Cart is from the author's own **Red Sea Baron**
project (CargoCart, CartVisual, CartCanopy, HitchSystem, VehicleClearance, GroundPose, the
Inventory and its item catalogue). See `assets/CREDITS.md` and ADR 0014.
