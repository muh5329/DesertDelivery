# Scenery LOD preservation

Imported olive, palm and forest meshes already request generated LODs. However, the two material-surface extraction paths in `IslandArt.prop_parts` and `WorldKit._tree_parts` rebuilt meshes from the base surface arrays alone. Those copies omitted every imported LOD index buffer. The resulting batched scenery always used its full geometry.

`IslandArt.extract_surface` now duplicates the imported ArrayMesh and removes unwanted surfaces. It keeps the selected surface's packed vertices, compression format, indices and LOD thresholds exactly. Source mesh resources remain unchanged. Vertices remain local and original PropPart/MultiMesh transforms remain intact, so no authored distance or scale conversion is introduced.

The helper clears the duplicated shadow_mesh because an imported whole-asset proxy cannot safely be mapped by surface index without proving correspondence. This preserves the previous extraction path's shadow behavior and avoids accidentally drawing unrelated shadow geometry.

`Godot --headless --path . --script tests/scenery_lod_tests.gd` passed: 13 surfaces across olive, palm and TwistedTree retain byte-identical geometry and LOD data. The scattered olive now contains 24 imported LOD levels. This verifies extraction correctness; frame-rate improvement and distant visual acceptance require the parent's matched graphical benchmark and captures.

Independent simulation-agent source review accepted the change with no lifecycle, scale, material or shadow-proxy blocker. Root inspected the final villa and cliff-coast captures: no missing crowns or surfaces appeared. The final fixed-camera sample measured 50.0 FPS in the village, 217.3 in wilderness and 164.9 in dense meadow; the village gain from this change alone is modest and not isolated from run variance. The overall report records the remaining village performance limitation.
