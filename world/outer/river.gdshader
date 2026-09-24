// Rivers of the outer world (outer_rivers.gd ribbons). UV.x runs across the channel (0..1), UV.y
// along it in metres, downstream. COLOR.r = the local drop (rapids), COLOR.g = width / 40.
// Flowing water: two noise normals scrolled downstream at different speeds, a clear green-brown
// tint that deepens with the water's thickness over the bed (depth buffer), white water on the
// rapids and a soft foam line where the water meets the banks, a Fresnel sky reflection.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 shallow : source_color = vec3(0.16, 0.22, 0.15);
uniform vec3 deep : source_color = vec3(0.05, 0.13, 0.12);
uniform vec3 sky : source_color = vec3(0.42, 0.56, 0.68);
uniform vec3 foam_col : source_color = vec3(0.92, 0.93, 0.90);
uniform float speed = 0.9;

varying vec3 wpos;
varying vec2 flow_uv;
varying float drop;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	flow_uv = UV;
	drop = COLOR.r;
}

float lin_depth(vec2 suv, mat4 inv_proj) {
	float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(suv * 2.0 - 1.0, d * 2.0 - 1.0);
#else
	vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void fragment() {
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	// the flow: noise in (across, along) space scrolled downstream; faster and choppier on the rapids
	float sp = speed * (1.0 + drop * 3.0);
	vec2 f1 = vec2(flow_uv.x * 6.0, flow_uv.y / 3.0 - TIME * sp * 0.33);
	vec2 f2 = vec2(flow_uv.x * 11.0 + 0.37, flow_uv.y / 1.3 - TIME * sp * 0.71);
	float a = texture(noise_tex, f1).r; float b = texture(noise_tex, f2).r;
	float e = 0.02;
	float ax = texture(noise_tex, f1 + vec2(e, 0.0)).r - a; float ay = texture(noise_tex, f1 + vec2(0.0, e)).r - a;
	float bx = texture(noise_tex, f2 + vec2(e, 0.0)).r - b; float by = texture(noise_tex, f2 + vec2(0.0, e)).r - b;
	float amp = (0.9 + drop * 1.2) * (1.0 - smoothstep(80.0, 600.0, dist) * 0.8);
	vec3 n = normalize(vec3((ax + bx) * amp * 6.0, 1.0, (ay + by) * amp * 6.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// water thickness over the bed along the view ray
	float surf = -VERTEX.z;
	float scene = lin_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float thick = max(scene - surf, 0.0);
	float t = smoothstep(0.0, 2.5, thick);
	vec3 bed = texture(screen_tex, SCREEN_UV + n.xz * 0.01 * clamp(thick, 0.0, 1.0)).rgb;
	vec3 col = mix(mix(bed, shallow, 0.45), deep, t);
	// banks: the water thins to a foam line where it meets the ground; rapids go white
	float edge = 1.0 - smoothstep(0.0, 0.35, thick);
	// the rivers run steep (4-7 % is common here): white water only in patches where both noise
	// bands peak and only on the steepest reaches; the mip-averaged noise far off stays below the
	// threshold, so a distant river is water, not a grey sheet of froth
	float froth = smoothstep(0.66, 0.82, a * 0.6 + b * 0.5) * smoothstep(0.55, 1.0, drop);
	float foam = clamp(edge * 0.3 * smoothstep(0.45, 0.7, b) + froth * 0.8, 0.0, 1.0) * (1.0 - smoothstep(300.0, 900.0, dist));
	float ndv = clamp(dot(NORMAL, normalize(-VERTEX)), 0.0, 1.0);
	float fres = 0.03 + 0.97 * pow(1.0 - ndv, 5.0);
	col = mix(col, sky, fres * 0.35);
	col = mix(col, foam_col, foam);
	ALBEDO = col;
	// no screen-space reflections on a transparent surface: the engine's specular mirrors only the
	// blurred sky radiance, and at the rider's grazing angles its Fresnel turned the whole river into
	// a flat pale-grey slab (a concrete channel). Specular off (F0 = 0 also zeroes Godot's f90); the
	// small hand-made sky Fresnel above is all the reflection the river keeps
	ROUGHNESS = mix(0.32, 0.6, foam);
	SPECULAR = 0.0;
	// fade into the banks: no hard edge where the ribbon meets the ground
	ALPHA = clamp(0.35 + smoothstep(0.0, 0.25, thick) + foam, 0.0, 1.0);
}
