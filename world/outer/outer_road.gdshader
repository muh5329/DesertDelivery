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
varying float shoulder;
varying float plaza_len;              // plaza ribbons: the plaza's length (COLOR.r x 200; its centre is at along = len / 2)
varying float style;                  // town style (COLOR.g x 8): 0 campo, 1 puerto, 2 valdoro, 3 sarmada, 4 isola

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shoulder = COLOR.a;
	plaza_len = COLOR.r * 200.0;
	style = floor(COLOR.g * 8.0 + 0.5);
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
		// patches of newer (darker, smoother) asphalt, a lane wide and a few metres long
		vec2 pc = vec2(floor(across / (width * 0.5)), floor(along / 9.0));
		float ph = fract(sin(dot(pc, vec2(12.9898, 78.233))) * 43758.5453);
		float pf = fract(along / 9.0);
		float patch_ = step(0.82, ph) * smoothstep(0.08, 0.14, pf) * (1.0 - smoothstep(0.62 + ph * 0.3, 0.7 + ph * 0.3, pf));
		col = mix(col, col * 0.72, patch_ * 0.8);
		rough = mix(rough, 0.62, patch_);
		// cracks: thin dark lines (longitudinal near the edges, a web elsewhere) and sealed tar snakes
		float cn = texture(noise_tex, vec2(wpos.x + wpos.z, along) / vec2(1.7, 5.0)).r;
		float crack = (1.0 - smoothstep(0.0, 0.018, abs(cn - 0.5))) * smoothstep(0.45, 0.7, n2);
		float edge_crack = (1.0 - smoothstep(0.0, 0.03, abs(abs(across) - width * 0.5 + 0.9 + (n1 - 0.5) * 0.6))) * step(0.5, n2);
		float tar = (1.0 - smoothstep(0.0, 0.05, abs(texture(noise_tex, wpos.xz / 3.3 + 0.21).r - 0.5))) * smoothstep(0.55, 0.75, n1);
		float d_fade = 1.0 - smoothstep(25.0, 90.0, dist);
		col = mix(col, col * 0.45, clamp(crack + edge_crack * 0.8, 0.0, 1.0) * d_fade * 0.8);
		col = mix(col, vec3(0.07, 0.07, 0.075), tar * d_fade * 0.7);
		rough = mix(rough, 0.35, tar * d_fade);
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
		// setts: small granite cubes in the streets, larger flags on the quays; the plazas a size
		// between (the old 7.6 m tile drew 1 m "cobbles")
		float s = kind == 6 ? 1.6 : (kind == 5 ? 0.8 : 0.75);
		vec2 uv = wpos.xz / (4.0 * s);
		col = texture(sett_tex, uv).rgb;
		nm = texture(sett_nrm, uv).rgb * 2.0 - 1.0;
		rough = 0.82;
		col *= 0.9 + 0.2 * n1;
		// by town: pale limestone calcada in Puerto Alto, honey sandstone in Campo, grey granite in
		// Valdoro, beaten ochre in Sarmada, pale stone in Isola
		vec3 stone_tint = style == 1.0 ? vec3(1.28, 1.25, 1.18) : (style == 2.0 ? vec3(0.9, 0.92, 0.95) : (style == 3.0 ? vec3(1.22, 1.06, 0.84) : (style == 4.0 ? vec3(1.2, 1.17, 1.1) : vec3(1.14, 1.04, 0.88))));
		col *= stone_tint;
		if (style == 1.0 && kind == 5) {
			// Lisbon: black basalt waves laid through the white limestone
			float wave = sin(along * 0.42 + sin(across * 0.21) * 2.2) * 0.5 + 0.5;
			float band = 1.0 - smoothstep(0.08, 0.16, abs(wave - 0.5));
			col = mix(col, vec3(0.12, 0.12, 0.13) * (0.85 + 0.3 * n2), band * 0.9);
		}
		if (kind == 5) {
			// the plaza: a border of long kerb stones, bands of pale stone every 8 m across a darker
			// field, a compass rosette at the centre, wear in the middle
			float L = max(plaza_len, 1.0);
			float u = along - L * 0.5;
			float border = step(width * 0.5 - 1.6, abs(across)) + step(L * 0.5 - 1.6, abs(u));
			float bands = (1.0 - smoothstep(0.35, 0.5, abs(fract(across / 8.0) - 0.5) * 8.0)) + (1.0 - smoothstep(0.35, 0.5, abs(fract(u / 8.0) - 0.5) * 8.0));
			float r = length(vec2(across, u));
			float ang = atan(u, across);
			float rose = (1.0 - smoothstep(0.1, 0.25, abs(r - 6.0))) + (1.0 - smoothstep(0.1, 0.25, abs(r - 3.5)))
				+ step(r, 6.0) * (1.0 - smoothstep(0.02, 0.06, abs(sin(ang * 4.0)) * r / 6.0)) * step(0.5, r);
			vec3 pale = texture(sett_tex, wpos.xz / 2.6 + 0.4).rgb * vec3(1.18, 1.12, 1.02);
			col = mix(col * vec3(0.9, 0.88, 0.86), pale, clamp(border + bands * 0.8, 0.0, 1.0));
			col = mix(col, vec3(0.62, 0.36, 0.26), clamp(rose, 0.0, 1.0) * step(r, 6.3) * 0.8);
			col *= 1.0 - 0.08 * (1.0 - smoothstep(4.0, 16.0, r));
		}
		if (kind == 6) {
			// the quay's edge stones
			float kerb = smoothstep(width * 0.5 - 0.9, width * 0.5 - 0.7, abs(across));
			col = mix(col, vec3(0.62, 0.60, 0.55), kerb);
		}
		col *= tint;
	}
	// the shoulder strip beyond the asphalt / the track's edge: packed gravel and dust thinning out
	// into the verge (its outer edge sinks under the grass)
	if (shoulder > 0.01) {
		vec2 guv = wpos.xz / 2.2;
		vec3 gravel = texture(dirt_tex, guv).rgb * vec3(0.95, 0.9, 0.82) * (0.85 + 0.3 * n2);
		col = mix(col, gravel, smoothstep(0.02, 0.35, shoulder));
		nm = mix(nm, texture(dirt_nrm, guv).rgb * 2.0 - 1.0, smoothstep(0.02, 0.35, shoulder));
		rough = mix(rough, 0.95, shoulder);
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	float dn = 1.0 - smoothstep(40.0, 250.0, dist);
	NORMAL_MAP = normalize(vec3(nm.xy * dn, 1.0)) * 0.5 + 0.5;
}
