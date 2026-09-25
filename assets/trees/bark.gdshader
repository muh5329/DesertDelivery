// Bark of the imported Quaternius trees (m-7). The pack's bark map is a dark grey (sRGB ~70/255)
// and the decimated trunks keep thin branch strips that are seen from both sides; with the plain
// imported material (x a brown tint, back faces culled, no mipmaps) the trunks rendered as black,
// zebra-striped shards. Here: the map is only a pattern over a warm bark colour (in the reference's
// #4a3b31 trunks' key), both faces light as the front, a small ambient floor keeps the trunk under
// its own canopy readable (it follows the hour, like the leaves' floor), and the map is mipmapped
// (TexMips) so the stripes do not moire.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;

global uniform vec3 dn_fill;
uniform sampler2D bark_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
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
	if (!FRONT_FACING) { NORMAL = -NORMAL; }
	EMISSION = alb * ambient_floor * dn_fill;
}
