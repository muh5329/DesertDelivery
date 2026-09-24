// Leaf cards of the imported Quaternius trees (Compatibility renderer). The pack's leaf atlases are
// flat single-colour silhouettes (red / lime), so only their alpha is used; the colour is painted
// from a baked top-lit gradient over the tree's object-space height (the art research asks for
// baked canopy shading rather than card-lighting), tinted by the MultiMesh instance colour and a
// per-instance hue jitter. Alpha scissor keeps the cards in the opaque pass (depth, shadows,
// no sorting).
// Round 2 critique item 5: every canopy rendered blue-teal (H198-210) because the albedo was
// V 0.18-0.29 and the blue sky ambient out-lit the sun on the side leaves. The albedo is now
// ~2x brighter, the normal dome is weaker so side leaves still face the sun, and the custom
// light() wraps the sun round the shade side (half-lambert) with a warm olive shade colour so
// the ambient never supplies most of the light there. Shadows are not received: the canopy
// self-shadowed its whole shade side to ambient-only (the baked gradient already carries the
// canopy's own shading). `use_tex` = 1 colours from the texture instead of the gradient, for
// the baked foliage cards (assets/foliage) which share this light model.
// Round 3 critique item 6: the canopies read lime-yellow and flat (villa tree S 0.23, shade side
// brown, sky-facing edges teal, 1-px confetti at distance). Saturation up / value down on the
// defaults, the shade floor is a cool olive (never brown, never the sky), the wrap is tighter so
// the shade side is really darker, the sky ambient is replaced by a flat olive floor of our own
// (`ambient_light_disabled`: the environment's blue ambient was the teal), and the alpha is
// boosted with the mip level so a card seen 4x minified stays an opaque silhouette instead of
// confetti round the scissor threshold.
// Round 4 critique items 5 / 7: the 0.45 mip bias turned every canopy into a smooth opaque blob
// (texture energy -74 in the tree cells) - bias 0.2 with a higher cut, and the lobe atlases are
// eroded (world/mapgen/leaf_erode.py) so the silhouette breaks up again. Crest trees at 150-250 m
// rendered lime (p50 0.39 vs the reference's hazed #4a5667): a distance tint pulls the far canopy
// down and toward the haze before the fog does.
shader_type spatial;
render_mode cull_disabled, specular_disabled, shadows_disabled, ambient_light_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 col_dark : source_color = vec3(0.18, 0.31, 0.20);   // #3a4a28 canopy underside
uniform vec3 col_lit : source_color = vec3(0.52, 0.67, 0.35);    // #86a444 sunlit top
uniform vec3 shade_warm : source_color = vec3(0.45, 0.62, 0.48); // shade side multiplier: olive (the grade cools it), never brown or blue
uniform vec3 ambient_floor : source_color = vec3(0.38, 0.46, 0.32); // our own flat ambient (x albedo), replaces the sky's blue
uniform float y_bottom = 2.0;
uniform float y_top = 16.0;
uniform float alpha_cut : hint_range(0.0, 1.0) = 0.38;
uniform float hue_jitter : hint_range(0.0, 0.2) = 0.05;
uniform float wrap : hint_range(0.0, 1.0) = 0.5;    // half-lambert wrap: 0 = plain lambert
uniform float use_tex : hint_range(0.0, 1.0) = 0.0;  // 1: albedo = texture colour x tint (foliage cards)
uniform vec3 card_tint : source_color = vec3(1.0);   // material tint for the texture mode
uniform vec3 far_tint : source_color = vec3(0.81, 0.88, 0.83); // canopy multiplier past far_end (hazed, darker, cooler)
uniform float far_start = 100.0;
uniform float far_end = 220.0;
// Polish pass: seen from under the canopy the lower crown read nearly black (col_dark x the wrap's
// shade x no sky). Leaves are thin: the sun comes THROUGH a card lit from its far side
// (translucency, strongest low in the crown where the camera looks up into it), and the crown's
// underside gets a little of the ground's warm bounce in the ambient floor.
uniform float translucency : hint_range(0.0, 1.0) = 0.38;
uniform vec3 translucent_tint : source_color = vec3(0.78, 0.92, 0.42);
uniform float under_lift : hint_range(0.0, 1.0) = 0.45;

varying float grad;
varying float jit;
varying vec3 tint;
varying float view_dist;

void vertex() {
	grad = clamp((VERTEX.y - y_bottom) / max(y_top - y_bottom, 0.01), 0.0, 1.0);
	vec3 world_anchor = MODEL_MATRIX[3].xyz;
	float breeze = sin(TIME * 1.15 + world_anchor.x * 0.037 + world_anchor.z * 0.023);
	VERTEX.x += breeze * grad * grad * 0.085;
	VERTEX.z += sin(TIME * 0.77 + world_anchor.x * 0.025) * grad * 0.045;
	// the instance colour carries the scatter's tint; its channel spread doubles as a jitter seed
	tint = COLOR.rgb;
	jit = clamp((COLOR.r - COLOR.b) * 4.0, -0.5, 0.5);
	// leaf normals: a soft dome so the canopy takes sun on top, weak enough that side leaves still
	// see the low sun (0.45 -> 0.25, critique r2 item 5)
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.25));
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	// mip-biased coverage: the alpha of a minified card averages toward the scissor threshold and
	// the canopy dissolves into confetti; thicken it with the (derivative-estimated) mip level
	vec2 ts = vec2(textureSize(leaf_tex, 0));
	vec2 ddx = dFdx(UV) * ts; vec2 ddy = dFdy(UV) * ts;
	float mip = max(0.0, 0.5 * log2(max(dot(ddx, ddx), dot(ddy, ddy))));
	ALPHA = t.a * (1.0 + mip * 0.2);
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	vec3 c = mix(mix(col_dark, col_lit, grad * grad), t.rgb * card_tint, use_tex);
	c *= tint * (1.0 + jit * 0.25);
	// the jitter only ever warms (r up, b down): a cool-shifted leaf would go teal under the fog
	c.r += abs(jit) * hue_jitter; c.b -= abs(jit) * hue_jitter * 0.6;
	// far canopies: darker and cooler with distance (the reference's crest trees are hazed
	// #4a5667-class at 200 m, ours stayed lit lime under the fog)
	c *= mix(vec3(1.0), far_tint, smoothstep(far_start, far_end, view_dist));
	ALBEDO = max(c, vec3(0.0));
	ROUGHNESS = 1.0;
	// the flat olive ambient stands in for the sky ambient the render mode switched off; the lower
	// crown also catches the ground's bounce
	EMISSION = ALBEDO * ambient_floor * (1.0 + under_lift * (1.0 - grad));
}

void light() {
	// two-sided (cull_disabled): a card seen from behind still faces the sun
	float nl = dot(NORMAL, LIGHT);
	nl = abs(nl) * 0.6 + nl * 0.4;
	// half-lambert wrap: the shade side keeps a cool olive floor from the sun instead of going to
	// the (blue) ambient only
	float w = clamp((nl + wrap) / (1.0 + wrap), 0.0, 1.0);
	vec3 shade = ALBEDO * shade_warm;
	DIFFUSE_LIGHT += mix(shade * 0.55, ALBEDO, w) * LIGHT_COLOR * ATTENUATION;
	// sun through the leaves: the light behind the card as seen from the camera (view and light on
	// opposite sides), a soft forward lobe
	float back = clamp(dot(-VIEW, LIGHT), 0.0, 1.0);
	float through = pow(back, 2.0) * (0.35 + 0.65 * (1.0 - grad));
	DIFFUSE_LIGHT += ALBEDO * translucent_tint * through * translucency * LIGHT_COLOR * ATTENUATION;
}
