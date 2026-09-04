# Desert Delivery — progress log

Target: playable third-person bike courier loop in Godot 4.3, matching *Into the Wind* footage,
the Reference Images (bike + boy) and the Level folder (arid Mediterranean coast).
Budget: 12 attempts. Verifier = headless autotest (autopilot drives pickup → delivery, exit 0) +
rendered screenshots compared against the references.

## Round 1 — project skeleton, terrain, bike, delivery loop
- **Changed:** Created the project from scratch (no prior project existed in the folder — only
  `ReferenceImages`). Procedural heightfield terrain with stamped dirt roads, flat building pads,
  HeightMapShape3D collision; arcade bike controller (CharacterBody3D, terrain-aligned, lean, dust);
  procedural bike + rider visual; chase camera; GameManager with 4 chained jobs; HUD (compass badge,
  day card, speedometer strip, objective/messages); autopilot + `--autotest` / `--shots` flags.
- **Evidence:** `godot --headless -- --autotest` → `AUTOTEST PASS: 1 deliveries in 47.7s`.
- **Score:** loop ✔, launch ✔, visuals ✘ (not yet rendered).
- **Failed approach:** bike spawned inside the pickup ring (instant pickup); parked truck blocked the
  farm approach (autopilot oscillated for ~25 s). Fixed by moving spawn 40 m down the road and the truck
  off the drive.
- **Next:** render frames under Xvfb and compare.

## Round 2 — first render: terrain invisible
- **Changed:** added `tools/view.gd` fixed-camera renderer.
- **Evidence:** screenshots showed the ground as the sea/sky colour with only slivers of terrain.
  Tested: plain material (same), no vertex colours (same), tangents (same), de-indexed (same),
  magenta sky ground + green terrain (proved the mesh was not drawn).
- **Failed approach:** blamed materials / NoiseTexture / vertex format — none of it.
- **Root cause:** Godot's front faces are **clockwise**; both SurfaceTool meshes (terrain, rocks)
  had CCW winding and were back-face culled. Flipped the winding → terrain + rocks render.

## Round 3 — lighting / palette / composition
- **Changed:** `vertex_color_is_srgb`, exposure 0.82, sun 0.95, ambient 0.5, warmer fog, sea plane
  6 km with sky ground matching the sea (removed the hard horizon band), road ruts + pale packed-sand
  road, darker ochre/olive grass, rock vertex-colour strata, more relief, cypress/olive/bush planting
  around the three hubs, thinner beacon.
- **Evidence:** `view_*.png` — villa square, coast + aqueduct, farm approach and harbour all read as
  the reference's pale-limestone-cliffs / dirt-road / cypress composition (stylised low-poly).
- **Score:** environment composition ~7/10 vs Level folder (cliffs, sea, roads, villa, farm, harbour,
  aqueduct, signposts present; no cobbled town, no rock arch yet).

## Round 4 — bike + rider model pass
- **Changed:** `tools/bike_view.gd` turntable; slimmer nose cone, tall riveted cream windscreen,
  long tan seat, chrome rack + struts, shorter exhausts, chrome no longer renders black
  (metallic 0.45), rider slimmed with boots outside the fairing, logo decals moved outboard.
- **Evidence:** `bike_0..3.png` — silhouette matches the bike sheet (red fairing, cream nose,
  knobby wheels, rack with crate) and the boy (orange hair, blue shirt, coral neckerchief, tan
  trousers, suspenders, brown boots). Clean placeholder quality, no ugly custom meshes.
- **Full loop:** `--autotest --deliveries=4` → `AUTOTEST PASS: 4 deliveries in 75.3s` (1247 m ridden,
  all four hubs reachable via the road graph).
- **Delivered** the project into `Documents/Projects/DesertDelivery` (project.godot, scripts/, scenes/,
  tools/, README.md).
- **Remaining budget:** 8 attempts.
- **Next:** gameplay-camera screenshots after camera lowering, second-pass polish (villa flagstones,
  harbour cobbles, rock arch on the coast, engine/wind audio), then independent final review.

## Round 5 — polish + independent review
- **Changed:** procedural engine/wind audio (AudioStreamGenerator, no assets), 2.5 s hand-off pause
  between chained jobs, flagstone squares at the villa and harbour, coastal rock arch, title card,
  denser dust, camera pulled in (3.9 m / 1.3 m / FOV 56).
- **Evidence:** `--autotest --deliveries=4` → PASS (82.8 s). Gameplay shots show the bike in the
  lower-centre third with the horizon high, as in the reference footage.
- **Independent review** (fresh reviewer agent, read all scripts, ran its own probe scripts):
  2 critical, 5 major, 6 minor defects; ranked visual gaps: road legibility, framing, cliff palette,
  ground-cover density, bike proportions.

## Round 6 — review fixes
- **Changed (critical):** camera no longer flips 180° when braking to a stop / reversing (it only
  swings for the explicit look-back key), reverse engages only after the brake is held 0.35 s at
  standstill, brake holds the bike on slopes.
- **Changed (major):** auto-reset when the bike falls into the sea (faces back inland); inverted
  slope-gravity sign fixed; front-fork rake mirrored so the front wheel sits under the nose cone;
  StaticBody colliders for aqueduct pillars, lamp posts, pot plants, barrels, hay bales, windsock,
  cows; HUD delivery counter now reaches 4/4; message queue so "Delivered!" is not overwritten;
  R-reset keeps the rider's heading; camera ray-cast so it never clips through walls; physics at
  120 Hz for smoother high-refresh displays; delivery rings moved off the house walls.
- **Changed (visual):** darker rutted brown road (reference road legibility), warmer limestone,
  slightly denser fog for depth, 3× grass / 2× bush density, six cows beside the farm road,
  rider sits more upright with knees at the tank and a larger head (reference sheet proportions).
- **Evidence:** new `tools/edge_tests.gd` (brake-to-stop must not reverse; reverse still works;
  camera stays behind while reversing; sea auto-reset) → `EDGE TESTS: PASS (0 failures)`;
  `--autotest --deliveries=4` → PASS (84.3 s, 1248 m). Screenshot `shot_002.png` vs reference
  road image: same composition (rutted track, scrub, cypresses, cliffs, cows, dust plume).
- **Failed approach:** first sea-reset re-used the rider's heading, so a held throttle drove straight
  back into the water; fixed by orienting the reset away from the sea. First brake-hold fix still
  let the bike roll backward on slopes (-0.31 m/s) before reverse engaged; fixed by a standstill hold.
- **Score:** loop ✔ launch ✔ controls ✔ collisions ✔ objectives ✔ perf ✔ (≈140 fps headless
  dummy; ~1450 nodes, MultiMesh vegetation). Reference match: composition/camera/HUD good,
  art is deliberately stylised low-poly placeholders (preferred over poor custom meshes).
- **Remaining budget:** 6 attempts unused.
- **Known gaps / next:** no clouds in the sky; cliffs are noise-displaced spheres rather than
  sculpted limestone; no NPCs or town street; no pause menu (Esc quits); no 3D physics interpolation
  in Godot 4.3 (mitigated with 120 Hz physics). Everything is hand-testable on the Mac: open
  `project.godot` in Godot 4.3 and press F5.

## Round 7 — new features: dismount/walk, swim, pistol, plane
- **Changed:** `rider_model.gd` (animated standalone boy), `player.gd` (walk/run/jump/swim, camera-relative,
  water hysteresis), `gun.gd` (pickup at the lookout, OTS hitscan, tracer/flash/puff, 9 tin-can targets on
  the farm wall + lookout bench), plane mode in `bike.gd` (T folds wings, takeoff > 15 m/s + climb,
  arcade lift/stall/ground-effect, ceiling 120 m, world-edge turn-back, landings), fold-out wing art with
  twin fins + pusher prop in `bike_visual.gd`, mode state machine + mount/dismount in `main.gd`, true
  orbit camera on foot (mouse / right stick, aim-hold), HUD (crosshair, ammo/cans, mode line), procedural
  gunshot / prop audio, new input actions (interact, transform, fire, jump, run, aim; gamepad stick Y).
- **Evidence:** `tools/feature_tests.gd` (dismount → run 16 m → remount; swim 51 m and climb out;
  pistol pickup, aimed shot pops a can through the real camera path; wings, takeoff, right bank turns
  right, ceiling respected, landing, fold) → PASS; `tools/edge_tests.gd` → PASS; `--autotest --deliveries=4`
  → PASS (83 s). Renders `feature_0..3.png` compared with reference on-foot / flying frames.

## Rounds 8–11 — adversarial critic loop (AAA-standard reviewer agent, 4 passes)
- **Pass 1 (24 findings):** flight banked right but turned LEFT; pistol pointed backwards; roof landing +
  dismount soft-lock; plane escaped ceiling/world; Space was handbrake AND climb; no stick-Y; crosshair
  unaimable (no look camera); firing froze legs; knees/elbows bent backwards; swim pose buried the face;
  dismount into props / mid-air; deliveries on foot with the package 200 m away; stall = free elevator;
  engine audio while walking; camera cuts; compass tracked the bike on foot; swim state flapping; aqueduct
  deck no collision; wings inflated from a point; silent denials; cans floating; short capsule; tests
  validating unreachable paths. → all addressed (orbit camera + muzzle ray, hinge-fold wings, roof
  colliders, R-on-foot rescue, shape-cast dismount spots, hysteresis, message queue, etc.).
- **Pass 2 (15 findings):** start heading drove into the plinth (regression) → start placed ON the road,
  hub props moved off it, hub bushes non-solid; aim pose stuck; no mouse in swim; hard-landing read
  post-snap velocity; pistol didn't pitch with aim; cans off the wall top; crosshair always on; walk
  through the parked bike; Esc instant-quit; gamepad aim on R3; boundary margin; swimmer height;
  engine cut; on-foot ring hint; stale comments → all addressed.
- **Pass 3 (8 findings):** Esc still instant while riding; brake-hold reverse blocked hop-off; click
  recapture while swimming; landing hint vs physics; spawn cypress; crosshair contrast; occlusion mask;
  duplicate comment → all addressed (two-step Esc in all modes, reverse needs a fresh brake press,
  ground-effect cushion + sink > 8 threshold, etc.).
- **Pass 4 (sign-off):** D1–D8 all FIXED with probes; no new blockers/majors; verdict: *shippable at the
  small-indie bar*.
- **Failed approaches worth remembering:** first free-look camera used look_at on a near point, so the
  crosshair never matched the camera ray (fixed by a true yaw/pitch orbit); the first aim-pose sign was
  backwards because +X rotation swings a hanging limb forward in this rig; sea-reset re-used the rider's
  heading; handbrake shared Space with climb.
- **Budget:** feature work 1 round + 4 critic rounds; all three suites green at hand-off.

## Round 13 — flight controls hotfix
- Flight now follows stick convention: on the takeoff roll W throttles and S (pull back) lifts off once past takeoff speed (S never brakes near takeoff speed with wings out); in the air throttle cruises automatically (Shift boosts), S raises the nose, W lowers it. Probe with real key presses: takeoff + climb 8→48 m on S, dive on W. All suites PASS.

## Round 13 — architecture: five deepenings (see the architecture review page)
- **1 Rider module** (`rider.gd`): single owner of mode {RIDING, FLYING, ON_FOOT, SWIMMING} and of
  mount / dismount / wings / reset choreography; `mode_changed` signal. Removed the nine scattered
  mode flags (main enum, gm.actor, hud._on_foot, cam.mode strings...). main.gd is wiring only (267 → 195 lines).
- **2 ControlIntent seam** (`controls.gd`): `Controls.Keyboard` is the only reader of `Input.*`
  and the only place a key's meaning per mode lives; `Controls.Scripted` drives the Autopilot and
  the tests. Bike and Player consume intents (`apply(intent)`), no `external_input` forks — the
  autopilot and the player now fly the same bike. Tests drive the game by pressing intents.
- **3 Camera framing intents**: `follow(target, Framing)`, `look(delta)`, `set_aiming`, `view_ray()`;
  no public state fields, no mouse capture inside the camera (the Rider owns it).
- **4 Hubs** (`hub.gd`, `Level.HUB_TABLE`, `Level.hub()`, `build_terrain()` + `build_hub(name)`):
  one source of truth for hub centres/pads; the gun asks `hub.wall_top(x)` / `hub.bench_top(f)`
  instead of re-deriving the wall geometry.
- **5 Ground** (`Terrain.probe`, `Terrain.nearest_road`): heightfield-or-built-surface answer used by
  dismount and reset; road lookups via a spatial grid instead of full scans.
- **Evidence:** feature_tests (28 checks incl. mode_changed, mount refused while riding / swimming,
  cannot hop off mid-air), edge_tests, `--autotest --deliveries=4` → all PASS after each step.
- `CONTEXT.md` added with the domain language.

## Round 14 — the island from the painting (critic judged against the reference image)
- **What changed:** the whole world is now generated from the reference painting. `tools/mapgen/extract.py`
  classifies the painting (PIL/numpy/scipy) into `data/island_map.png` (R = height, G = biome, B = tree
  density; 241×241 cells over a 720 m world), `data/island_meta.json` (islets, px/m) and `data/sea_depth.png`
  (a 1000 m depth field for the sea shader). `Terrain` is map-driven: biomes {SEA, LIMESTONE, FOREST, FARM,
  BADLANDS, TOWN, BEACH, LAKE}, per-biome relief, roads bridge water and ride viaducts (`Terrain.viaducts`,
  `bridges`), earthen ramps with cut/fill, 28 % grade limit, junction height reconciliation, causeways for
  streams, flat-shaded facet mesh with per-face painted colour. `WorldKit` (new) holds the reusable builders
  and kits (pine, hoodoo, arcade, pier, boat, tower, lighthouse, water tower); `Level` lays out the island:
  roads traced in painting pixels (`_px`), NW limestone massif with hill villages, NE harbour town on its own
  island (channel carved) joined by a 6-arch aqueduct across the strait, lighthouse at the tip, quay wall /
  piers / ~40 boats / crates & barrels, hamlet by the bay, water tower, SW vineyard parcels + cypress lines +
  farmhouses + villa, SE banded-hoodoo badlands (12 kits, mushroom caps, tilt) round a lake with a viaduct
  over a carved gorge, sea stacks and islets, depth-banded sea shader (turquoise shelf → mid → navy).
- **Critic loop (adversarial AAA art director, judged against the painting):** 4.5 → 5.5 → 6.5 → 7 → 7.5 →
  8 → 8 → **8.5 / 10 fidelity, 8 / 10 trailer — SIGN OFF at round 8**. Fixed along the way: green blob →
  limestone/olive rebalance; snow-white massif → warm limestone (and the rocks were inside-out: winding fixed);
  airbrushed gradients → flat facets + coarse painted patches; traffic-cone hoodoos → banded ochre stacks;
  empty harbour → working waterfront; invisible vineyards → parcels/rows/cypresses; concrete flyovers →
  arcades; flat sea → depth-banded shader with meandering band edges; town joined to the mainland → its own
  island; hero framing to the painting's vantage.
- **Evidence:** `--autotest --deliveries=4` PASS (all 4 jobs across bridges/viaducts), edge_tests PASS,
  feature_tests PASS (28 checks, swim moved to the badlands lake, sea test to the south coast); renders
  `tools/view.gd` (9 fixed views) and `tools/feature_shots.gd`.
- **Failed approaches:** bridge decks at the bank height only (bike fell at the ramp lips) → ramps + deck
  covering the embankment; per-road smoothing without junction reconciliation (5 m steps where two roads
  met) → endpoint blending; sea "shallows" plane → replaced by the depth shader; a sea map clipped to the
  painting's 405 m height (straight shelf edges) → grid-space distance field on a 1000 m map.
- **Remaining polish (non-blocking per critic):** 3 m sawtooth on the shoreline, aqueduct piers not
  tapered, quay props sparse.
- **Budget:** 1 build round + 8 critic rounds.

## Round 15 — restructure into an open-world foundation (before NPCs and cars)
- **What changed:** the project is now "a small engine on top of Godot" (see `ARCHITECTURE.md`):
  feature-based folders (`core/ world/ entities/ gameplay/ ai/ ui/ data/ tests/`); a small runtime tree
  (`Game → WorldManager / EntityManager / GameplayManager / Rider / ChaseCamera / UI / Debug`); two
  autoloads only (`Events` bus, `Saves`); definitions as Resources (`VehicleDefinition`,
  `JobDefinition`, `WorldConfig` in `data/`); `Vehicle` base class with a `VehicleDefinition`
  (the bike reads its tunables from `data/vehicles/bike.tres`); the island generator writes a
  `WorldDatabase` of build recipes per 60 m chunk plus locations/hubs, and a `WorldStreamer`
  instantiates a 7×7 ring of `Chunk`s around the focus and frees the rest (terrain, sea, sky stay
  resident); `EntityManager` registers everything by stable id and assigns simulation tiers by
  distance; `SaveManager` writes diffs keyed by id (delivery, gun/cans, bike, rider) to
  `user://saves/<slot>.json` (F5/F9); `DebugOverlay` (F3) with chunk/entity/draw-call stats and
  teleport / reload-chunk / streaming toggles; the HUD subscribes to events instead of being wired to
  systems; tests run inside the booted game via `--test=NAME` (a test runner in `Game`).
- **Evidence:** `--autotest --deliveries=4` PASS (streaming live: 41 of 90 chunks loaded, tree
  ~5 k nodes instead of ~10 k), new `architecture_tests` (21 checks: database independent of loading,
  chunks load/unload as the focus teleports, bounded chunk count, ids, tiers, save/load round trip,
  definitions, tree shape) PASS, edge_tests PASS, feature_tests PASS (28), fixed-view and feature
  renders identical to round 14.
- **Failed approaches:** running the SceneTree-script tests with autoloads present (Godot's `-s`
  mode never registers autoload globals) → tests became nodes run by the game; 120 m chunks with
  radius 2 loaded the whole island (streaming did nothing) → 60 m chunks, radius 3; `--nostream`
  renders lost far chunks because the streamer kept unloading → `load_everything()` disables streaming.
- **Known:** the autopilot still cuts corners into props occasionally (its own reset recovers);
  a benign "ObjectDB instances leaked" warning can appear on quit(0) mid-frame.
- **Budget:** 1 round.

## Round — Terrain3D, 3x island, twice the places
- **Changed:** the ground is now rendered and collided by the Terrain3D plugin: `Terrain.build()` keeps
  producing the 3 m heightfield (roads, bridges, viaducts, pads), then `_build_terrain3d()` resamples it
  to 1.5 m (cubic) with a little per-biome micro relief, writes a control map (texture per biome, rock
  on slopes, dirt on roads, ploughed strips in the fields) and a colour map (tints), and imports them;
  `height_at` / `normal_at` read Terrain3D's data so props, rings and the bike all sit on the drawn
  ground. Textures: ambientCG Ground037 + Rock030 (CC0) and five baked by `world/mapgen/textures.py`.
  World 720 m → 1248 m (3x area): `expand.py` scales the painted island by 1.733 (roads/hubs in painting
  pixels follow through `_px`; world-metre constants scaled) and grows the Highlands (MOOR) north and
  the Southern Shore (DUNES, SALTFLAT, FARM, BADLANDS headland, lagoon) south. New hubs: monastery,
  quarry, cala_blanca, salinas; new places: bodega, torre_vieja, lakeside_camp, windmill_ridge, chapel,
  refugio; new roads (pass, quarry loop, coast road, links); 10 chained jobs; new kits (windmill, fort
  tower, crane, tents, campfire, cloister, sheep, salt heaps, dykes, reeds, heather, dune grass).
- **Evidence:** architecture / feature / edge tests pass headless (test coordinates moved to the new
  map); `--autotest --deliveries=10` drives the whole loop; `--test=view` renders 20+ views under Xvfb.
- **Known:** world generation is ~8.5 s in the cloud container (heightfield 2.4 s, Terrain3D maps
  1.7 s, scatter 4 s); the bike's turn-back edge and the streaming grid follow `Terrain.SIZE`.

## Round — foliage and the propeller
- **Changed:** the plane's propeller moved from the tail to the nose (`bike_visual.gd`). All
  vegetation is now alpha-cut texture cards baked by `world/mapgen/foliage.py` into
  `assets/foliage`: pines / olives / cypresses / bushes / heather / vines are crossed-card canopies
  (`WorldKit._tier`, up-facing normals so leaves take the ground's light), and grass, dry grass,
  dune grass and wild flowers (~280k plants) go through Terrain3D's instancer
  (`Terrain.plant_ground_cover`, density per biome, never on roads/pads/steep ground, 110 m fade).
- **Evidence:** tests pass; `--test=view --close` renders show grass, canopies and vines.
- **Known:** `Terrain3DInstancer.add_transforms(..., update=false)` needs one `update_mmis(true)`
  afterwards or the earlier mesh ids never get their MultiMeshes. Generation is now ~12 s here.
