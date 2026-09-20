# Environment render iterations

Actual Godot OpenGL screenshots, not concept art:

- `atmosphere/baseline/town_0.png`: original muted lavender/grey sky.
- `atmosphere/pass1/town_0.png`: first summer palette. Rejected yellow/cyan cast and amorphous cloud noise after visual inspection.
- `atmosphere/pass2/town_0.png`: neutralized grade, lower exposure, explicit cumulus. Critic identified clipped ribbon-like high clouds and overly lime palm assets.
- `atmosphere/final/cliff_coast.png`: cloud banks lowered into the visible horizon, blue underside shading, turquoise shelf water and cream foam. Reduced microscopic rock normal/albedo contrast after a further actual render comparison.
- `atmosphere/final/villa.png`: countryside foliage and lighting check.

Independent critic: simulation_overhaul reviewed town and coastal screenshots.
The final coastal pass has readable rounded cloud contours, layered green canopy,
and differentiated shallow/deep water. Remaining cloud masses are stylized layered
shapes; this is not an AAA-quality signoff. Palm geometry/color feedback was sent
to the root agent's Blender asset pass.

Leaf-card shader has restrained height-weighted breeze. Sky now honors the
simulation's existing daylight uniform. Core map dimensions and gameplay physics
were not changed by the environment pass.

# Remote wilderness render iterations

`wilderness/pass1/outer_0.png` and `outer_1.png` exposed overly sparse low-detail
vegetation. Critic requested density improvements and found the north-road
shoulder used a hardcoded X coordinate. The final `wilderness/outer_0.png` and
`outer_1.png` use denser 320 m streaming tiles, richer shared crown geometry,
20-blade meadow clumps, and the actual viaduct anchor for shoulder clearance.

Observed final snapshots: 25 loaded tiles each, 28,651 and 55,510 transforms
respectively, below the 63,000 worst-case bound. One tile builds each frame;
all meshes/materials are shared between tiles. No whole-island prop allocation.
Independent critic accepted the bounded implementation and visible density gain;
large steep slopes and the low-poly wilderness remain scope/quality limitations.

`tests/world_expanse_tests.gd` passes extent, terrain/deck raycast, and collision/
dressing budget checks. Runtime frame-rate measurements are handled separately
by the simulation agent; these screenshots alone do not establish 30 or 60 fps.
