// Road surfaces of the outer world (ribbon meshes from outer_roads.gd). UV.x runs across the
// road (0..1), UV.y along it in metres. `kind`: 0 highway, 1 road, 2 track, 3 street (setts),
// 4 lane (setts), 5 plaza (large flags), 6 quay (flags). Markings are procedural: highways get
// solid edge lines and a dashed centre pair, roads a dashed centre line and thin edge lines.
// The ribbon is pulled a hair toward the camera so it never z-fights the ground it drapes over.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform int kind = 0;
uniform float width = 11.0;
uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sett_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sett_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 tint = vec3(1.0);

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(v.xyz);
	// pull toward the camera: a few cm near, more far away (depth precision)
	v.xyz -= normalize(v.xyz) * (0.03 + d * 0.0012);
	POSITION = PROJECTION_MATRIX * v;
}

float line(float x, float c, float w) { return 1.0 - smoothstep(w * 0.5 - 0.02, w * 0.5 + 0.02, abs(x - c)); }

void fragment() {
	float across = (UV.x - 0.5) * width;       // metres from the centre line
	float along = UV.y;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n1 = texture(noise_tex, wpos.xz / 23.0).r;
	float n2 = texture(noise_tex, wpos.xz / 4.1).r;
	vec3 col; vec3 nm; float rough;
	if (kind <= 1) {
		vec2 uv = wpos.xz / 3.2;
		col = texture(asphalt_tex, uv).rgb;
		nm = texture(asphalt_nrm, uv).rgb * 2.0 - 1.0;
		rough = 0.78;
		// wear: lighter in the wheel tracks, patches, a darker centre stripe of oil
		float lanes = kind == 0 ? 2.0 : 1.0;
		float wheel = 0.0;
		for (float s = -1.0; s <= 1.0; s += 2.0) {
			float lc = s * width * 0.25;
			wheel += line(across, lc - 0.9, 0.8) + line(across, lc + 0.9, 0.8);
		}
		col *= 0.92 + 0.14 * n1;
		col = mix(col, col * 1.15 + 0.02, wheel * 0.35);
		col *= 1.0 - 0.12 * line(across, width * 0.25, 0.6) - 0.12 * line(across, -width * 0.25, 0.6);
		// markings
		float m = 0.0;
		float dash = step(0.5, fract(along / (kind == 0 ? 12.0 : 9.0)));
		if (kind == 0) {
			m += line(across, width * 0.5 - 0.55, 0.22) + line(across, -width * 0.5 + 0.55, 0.22);
			m += (line(across, 0.18, 0.14) + line(across, -0.18, 0.14));
		} else {
			m += dash * line(across, 0.0, 0.14);
			m += line(across, width * 0.5 - 0.3, 0.12) + line(across, -width * 0.5 + 0.3, 0.12);
		}
		m *= 0.75 + 0.25 * n2;                   // worn paint
		vec3 paint = kind == 0 ? vec3(0.86, 0.85, 0.80) : vec3(0.84, 0.82, 0.74);
		col = mix(col, paint, clamp(m, 0.0, 1.0) * (1.0 - smoothstep(300.0, 900.0, dist) * 0.5));
		// the edge crumbles into the verge
		float edge = smoothstep(width * 0.5 - 0.25, width * 0.5, abs(across));
		col = mix(col, vec3(0.34, 0.31, 0.26), edge * 0.6);
	} else if (kind == 2) {
		vec2 uv = wpos.xz / 4.0;
		col = texture(dirt_tex, uv).rgb * vec3(1.02, 0.94, 0.82);
		nm = texture(dirt_nrm, uv).rgb * 2.0 - 1.0;
		rough = 0.95;
		// two ruts and a grassy crown
		float rut = line(across, 0.8, 0.6) + line(across, -0.8, 0.6);
		float crown = line(across, 0.0, 0.5) * smoothstep(0.35, 0.65, n2);
		col *= 1.0 - 0.18 * rut;
		col = mix(col, vec3(0.30, 0.34, 0.18), crown * 0.5);
		float edge = smoothstep(width * 0.5 - 0.8, width * 0.5, abs(across));
		col = mix(col, vec3(0.36, 0.38, 0.22), edge * 0.5 * n1);
	} else {
		float s = kind >= 5 ? 1.9 : 1.2;
		vec2 uv = wpos.xz / (4.0 * s);
		col = texture(sett_tex, uv).rgb;
		nm = texture(sett_nrm, uv).rgb * 2.0 - 1.0;
		rough = 0.82;
		col *= 0.9 + 0.2 * n1;
		if (kind == 6) {
			// the quay's edge stones
			float kerb = smoothstep(width * 0.5 - 0.9, width * 0.5 - 0.7, abs(across));
			col = mix(col, vec3(0.62, 0.60, 0.55), kerb);
		}
		col *= tint;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	float dn = 1.0 - smoothstep(40.0, 250.0, dist);
	NORMAL_MAP = normalize(vec3(nm.xy * dn, 1.0)) * 0.5 + 0.5;
}
