# Island asset library

Original meshes authored in the local Blender scene through Blender MCP for this project.
The supplied images guided the silhouettes, clothing and architectural palette; they are
not used as image planes or pasted into the game.

- `courier_bike.glb`: retro red courier bike, curved windscreen, spoked tires and pivoted fork/wheels.
- `courier_character.glb`: articulated stylized courier, shared by the rider and resident palettes.
- `town_house_*`: six terrace, dome and barrel-vault variants with balconies and awnings.
- `village_house_*`: rural tiled-roof houses.
- `island_car.glb`: compact car with independently rolling wheels and front steering pivots.
- `harbour_palm`, `olive_tree`, `limestone_cliff`: reusable landscape kit.
- `fishing_boat`, `sheep`, `deer`, `dog`, `rabbit`, `gull`: ambient world actors.

Editable Blender files are in `../source/`; reproduction scripts are in `../../tools/blender/`.
Authoring coordinates are converted to Godot metres with forward along -Z by `common.py`.
Static geometry is joined by articulation pivot before glTF export to reduce draw overhead.
