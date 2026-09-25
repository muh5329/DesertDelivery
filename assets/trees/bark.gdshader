// Bark of the imported Quaternius trees (m-7). The pack's bark map is a dark grey (sRGB ~70/255):
// the map is only a pattern over a warm bark colour (in the reference's #4a3b31 trunks' key), a
// small ambient floor keeps the trunk under its own canopy readable (it follows the hour, like the
// leaves' floor), and the map is mipmapped (TexMips) so the stripes do not moire.
// The trunks and limbs are closed procedural tubes (world/mapgen/tree_bark.py: the decimated pack
// trunks were shards), so the faces are culled like any solid and the pack's normal map is back:
// the tubes' UVs run up the limb and round it.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

global uniform vec3 dn_fill;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D bark_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float use_normal = 0.0;
uniform float normal_depth = 0.8;
uniform vec3 bark_color : source_color = vec3(0.40, 0.31, 0.24);
uniform float pattern = 0.55;               // how much of the map's light/dark shows
uniform vec3 ambient_floor : source_color = vec3(0.34, 0.31, 0.26);

void fragment() {
	vec3 t = texture(bark_tex, UV).rgb;
	float l = dot(t, vec3(0.3, 0.55, 0.15));
	// the map's mean is ~0.06 linear: normalise it to 1 and keep `pattern` of its contrast
	vec3 alb = bark_color * mix(1.0, clamp(l / 0.065, 0.3, 2.2), pattern) * COLOR.rgb;
	ALBEDO = alb;
	ROUGHNESS = 1.0;
	if (use_normal > 0.5) {
		NORMAL_MAP = texture(bark_normal, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	EMISSION = alb * ambient_floor * dn_fill;
}
