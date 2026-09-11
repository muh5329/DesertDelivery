# Terrain3D 1.0.2 notes (what we learned)
- Node must be inside the scene tree before `data.import_images([height, control, color], pos, 0, 1)`.
- Height image FORMAT_RF; control FORMAT_RF holding uint32 bits via `Terrain3DUtil.as_float(enc_base(id) | enc_overlay(id) | enc_blend(0..255))`; colour RGBA8 (A = roughness, 0.5 neutral).
- All texture assets: same size (512) + same mipmap flag. `Terrain3DTextureAsset`: albedo_texture (RGB+height in A), normal_texture (RGB+roughness in A), albedo_color, uv_scale, normal_depth, ao_strength, detiling_*.
- Material params: `material.set_shader_param("blend_sharpness"|"enable_macro_variation"|"macro_variation1/2"|"macro_variation_slope"|"noise1_scale"...)`; `material.world_background = Terrain3DMaterial.NONE`.
- Instancer: `assets.set_mesh_asset(id, Terrain3DMeshAsset)` (TYPE_TEXTURE_CARD, generated_faces, generated_size, material_override is a StandardMaterial3D, lod0_range, fade_margin), `instancer.add_transforms(id, xforms, colors, false)` then ONE `instancer.update_mmis(true)`.
- Collision: `collision.mode = Terrain3DCollision.FULL_GAME`. Queries: `data.get_height(pos)`, `data.get_normal(pos)`.
- `set_camera(cam)` re-enables its physics process if the first camera grab failed.
- Cubic `Image.resize` overshoots at cliffs: heights are clamped to the 4 surrounding cells.
