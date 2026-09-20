# Exact procedural rock library

These 180 compressed Godot resources contain the original RockGen mesh arrays,
LOD arrays and collision hull vertices, without simplification. Runtime lazily
loads only requested pieces, then shares them in memory. Unknown parameters or
missing/invalid resources fall back to the original deterministic generator.

Regenerate from the current world recipe set after changing rock generation:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -- --test=bake_rock_library --rebuild-rock-library
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/rock_library_tests.gd
```

The required rebuild flag bypasses disk resources, even if the schema version
was accidentally not bumped. Bump `RockGen.BAKED_SCHEMA` when the geometry
algorithm changes. Defaults and exact canonical parameter bytes participate in
the key. A successful bake removes obsolete hashed `.res` resources only within
this directory. The manifest is `artifacts/performance-controls/rock-library-build.json`.

No export preset currently exists in this project. An export must include all
resources, or explicitly include `assets/rocks/generated/*.res` when exporting
selected scenes/resources: these hashed dynamic paths are not static scene
dependencies. Missing exported resources remain functional via procedural
fallback, but lose this CPU optimization. Export-package validation is pending
creation of the project's export preset.
