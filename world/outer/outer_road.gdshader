// Road surfaces of the outer world (ribbon meshes from outer_roads.gd). UV.x runs across the
// road (0..1), UV.y along it in metres. `kind`: 0 highway, 1 road, 2 track, 3 street (setts),
// 4 lane (setts), 5 plaza (large flags), 6 quay (flags), 7 apron (the paving round a building's
// foot, OuterTowns). Streets and lanes are paved by town (M-10; COLOR.g = style): Puerto Alto grey
// basalt setts between white calcada pavements with black waves, Campo Real red brick in basket
// weave between sandstone slabs, Valdoro granite setts in fans with granite kerbs, Sarmada packed
// earth with a stone gutter down the middle, Isola stone flags with whitewashed joints and edges and
// steps on the steep lanes. Setts are procedural (their joints fade out before they alias).
// Markings are procedural: highways get
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
// town style (COLOR.g x 8): 0 campo, 1 puerto, 2 valdoro, 3 sarmada, 4 isola. Flat, and rounded again
// in fragment(): an interpolated 3.0 is 2.99999 at some pixels, and `style == 3.0` then fell through
// to Isola's flags in a dither across Sarmada's and Valdoro's streets
varying flat float style_v;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	shoulder = COLOR.a;
	plaza_len = COLOR.r * 200.0;
	style_v = floor(COLOR.g * 8.0 + 0.5);
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float d = length(v.xyz);
	// pull toward the camera: a few cm near, more far away (depth precision); the aprons round the
	// buildings less than the streets and plazas, which always win where the two overlap
	v.xyz -= normalize(v.xyz) * (kind == 7 ? 0.008 + d * 0.0005 : 0.03 + d * 0.0012);
	POSITION = PROJECTION_MATRIX * v;
}

float line(float x, float c, float w) { return 1.0 - smoothstep(w * 0.5 - 0.02, w * 0.5 + 0.02, abs(x - c)); }

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// far away a stone's own shade fades to the mean with its joints (no sparkle where they alias)
vec3 fj(vec3 j, float detail) { return vec3(j.x, mix(0.5, j.y, detail), j.z); }

// running bond: stones `size` (x across, y along), every other row shifted half a stone.
// returns (joint mask 0..1, stone id hash, distance to the joint in m)
vec3 bond(vec2 p, vec2 size, float aa) {
	vec2 q = p / size;
	q.x += 0.5 * mod(floor(q.y), 2.0);
	vec2 f = fract(q); vec2 id = floor(q);
	float e = min(min(f.x, 1.0 - f.x) * size.x, min(f.y, 1.0 - f.y) * size.y);
	return vec3(1.0 - smoothstep(0.006, 0.014 + aa, e), hash2(id), e);
}

// basket weave bricks (pairs of 2:1 bricks turning 90 degrees cell by cell)
vec3 basket(vec2 p, float s, float aa) {
	vec2 cell = floor(p / s); vec2 f = fract(p / s);
	bool turn = mod(cell.x + cell.y, 2.0) > 0.5;
	vec2 g = turn ? f.yx : f;
	float half_ = step(0.5, g.y);
	float gy = fract(g.y * 2.0);
	float e = min(min(g.x, 1.0 - g.x) * s, min(gy, 1.0 - gy) * s * 0.5);
	return vec3(1.0 - smoothstep(0.008, 0.016 + aa, e), hash2(cell * 2.0 + vec2(half_, turn ? 1.0 : 0.0)), e);
}

// setts laid in fans (coda di pavone): arcs of stones in 1.8 m wide scallops
vec3 fans(vec2 p, float aa) {
	float W = 1.8;
	vec2 q = p / W;
	float row = floor(q.y);
	q.x += 0.5 * mod(row, 2.0);
	vec2 c = vec2(floor(q.x) + 0.5, row);
	vec2 d = (q - c) * W;
	float r = length(d); float a = atan(d.x, d.y);
	float ring = r / 0.13;
	float seg = a * r / 0.13;
	float er = min(fract(ring), 1.0 - fract(ring)) * 0.13;
	float es = min(fract(seg), 1.0 - fract(seg)) * 0.13;
	float e = min(er, es);
	return vec3(1.0 - smoothstep(0.006, 0.014 + aa, e), hash2(c * 7.0 + vec2(floor(ring), floor(seg))), e);
}

void fragment() {
	float style = floor(style_v + 0.5);
	float across = (UV.x - 0.5) * width;       // metres from the centre line
	float along = UV.y;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float n1 = texture(noise_tex, wpos.xz / 23.0).r;
	float n2 = texture(noise_tex, wpos.xz / 4.1).r;
	vec3 col; vec3 nm; float rough; float spec = 0.5;
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
		if (kind == 3 || kind == 4 || kind == 7) {
			// ---- M-10: the streets by town. p = (across, along) in metres, aligned with the street;
			// the aprons round the buildings use world xz
			vec2 p = kind == 7 ? wpos.xz : vec2(across, along);
			float aa = length(fwidth(p)) * 0.7;
			float detail = 1.0 - smoothstep(0.03, 0.09, aa);     // joints fade before they alias
			float lo_f = texture(noise_tex, wpos.xz / 57.0 + 0.13).r;  // broad patches of older / newer stone
			float W = width * 0.5;
			// pavements either side of the carriageway on the wider streets (not in the medina)
			float pave = 0.0;
			if (kind == 3 || (kind == 4 && width >= 6.4)) {
				pave = style == 1.0 ? 1.9 : (style == 0.0 ? 1.6 : (style == 2.0 ? 1.1 : 0.0));
				if (kind == 4) pave *= 0.75;
			}
			bool on_pave = kind != 7 && pave > 0.0 && abs(across) > W - pave;
			float kerb = pave > 0.0 && kind != 7 ? line(abs(across), W - pave + 0.13, 0.26) : 0.0;
			vec3 j; vec3 stone; vec3 joint_c;
			if (style == 1.0) {
				// Puerto Alto: grey basalt setts on the carriageway, white limestone calcada with black
				// waves on the pavements and round the houses
				if (on_pave || kind == 7) {
					j = fj(bond(p * vec2(1.0, 1.0) + vec2(0.37, 0.0), vec2(0.075, 0.075), aa), detail);
					stone = vec3(0.86, 0.84, 0.79) * (0.9 + 0.2 * j.y);
					float wv = sin((kind == 7 ? p.x + p.y : p.y) * 0.9 + sin(abs(across) * 1.7) * 1.4);
					float band = (1.0 - smoothstep(0.16, 0.2, abs(wv))) * (kind == 7 ? 0.0 : 1.0);
					stone = mix(stone, vec3(0.1, 0.1, 0.11) * (0.8 + 0.4 * j.y), band);
					joint_c = vec3(0.55, 0.53, 0.5);
				} else {
					j = fj(bond(p, vec2(0.14, 0.12), aa), detail);
					stone = vec3(0.36, 0.36, 0.37) * (0.8 + 0.4 * j.y) * (0.9 + 0.2 * lo_f);
					joint_c = vec3(0.2, 0.2, 0.19);
				}
			} else if (style == 0.0) {
				// Campo Real: red brick basket weave between honey sandstone slabs
				if (on_pave || kind == 7) {
					j = fj(bond(p, vec2(0.6, 0.42), aa), detail);
					stone = vec3(0.78, 0.66, 0.48) * (0.88 + 0.22 * j.y);
					joint_c = vec3(0.45, 0.4, 0.33);
				} else {
					j = fj(basket(p, 0.44, aa), detail);
					stone = vec3(0.62, 0.33, 0.24) * (0.82 + 0.3 * j.y) * (0.9 + 0.2 * lo_f);
					joint_c = vec3(0.6, 0.55, 0.47);
				}
			} else if (style == 2.0) {
				// Valdoro: granite setts in fans, granite slabs by the houses
				if (on_pave || kind == 7) {
					j = fj(bond(p, vec2(0.9, 0.55), aa), detail);
					stone = vec3(0.47, 0.47, 0.46) * (0.85 + 0.25 * j.y);
				} else {
					j = fj(fans(p, aa), detail);
					stone = vec3(0.4, 0.4, 0.41) * (0.78 + 0.35 * j.y) * (0.9 + 0.2 * lo_f);
				}
				joint_c = vec3(0.26, 0.26, 0.25);
			} else if (style == 3.0) {
				// Sarmada: beaten earth with stones pressed into it, a stone gutter down the middle
				vec3 earth = texture(dirt_tex, wpos.xz / 3.1).rgb * vec3(1.18, 0.98, 0.74);
				earth *= 0.88 + 0.24 * lo_f;
				j = fj(bond(p + vec2(0.3, 0.0), vec2(0.34, 0.28), aa), detail);
				float pebble = step(0.72, j.y) * (1.0 - j.x) * step(0.05, j.z);
				stone = mix(earth, vec3(0.74, 0.64, 0.5) * (0.85 + 0.3 * j.y), pebble * 0.8);
				float gutter = kind == 7 ? 0.0 : 1.0 - smoothstep(0.32, 0.36, abs(across));
				vec3 g = fj(bond(p, vec2(0.36, 0.5), aa), detail);
				stone = mix(stone, vec3(0.66, 0.6, 0.52) * (0.8 + 0.3 * g.y) * (1.0 - 0.35 * g.x) * (1.0 - 0.25 * line(abs(across), 0.0, 0.14)), gutter);
				j = vec3(0.0, j.y, 1.0);
				joint_c = stone;
			} else {
				// Isola: stone flags with whitewashed joints, whitewashed edges; steps on steep lanes
				j = fj(bond(p, vec2(0.7, 0.5), aa), detail);
				stone = vec3(0.55, 0.53, 0.5) * (0.84 + 0.26 * j.y) * (0.9 + 0.2 * lo_f);
				joint_c = vec3(0.93, 0.92, 0.9);
				float edge_ww = kind == 7 ? 0.0 : smoothstep(W - 0.42, W - 0.36, abs(across));
				stone = mix(stone, vec3(0.94, 0.93, 0.91), edge_ww);
				vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
				float steep = smoothstep(0.1, 0.16, sqrt(max(1.0 - wn.y * wn.y, 0.0)));
				float ph = fract(along / 1.15);
				float riser = (1.0 - smoothstep(0.02, 0.06 + aa, min(ph, 1.0 - ph) * 1.15)) * steep * (kind == 7 ? 0.0 : 1.0);
				stone = mix(stone, vec3(0.93, 0.92, 0.9), riser * 0.8);
			}
			col = mix(stone, joint_c, j.x * detail);
			col = mix(col, vec3(0.74, 0.72, 0.68) * (0.9 + 0.2 * n1), kerb * detail);
			// wear: a darker, polished band down the carriageway, grime at the edges
			float wear = kind == 7 ? 0.0 : (1.0 - smoothstep(0.0, W * 0.55, abs(across))) * (on_pave ? 0.0 : 1.0);
			col *= 1.0 - 0.07 * wear;
			col *= 1.0 - 0.12 * smoothstep(W - 0.5, W, abs(across)) * (kind == 7 ? 0.0 : 1.0);
			// dry stone: rough and dull (at the rider's grazing angles a smoother surface mirrors the
			// sky and the paving turns white)
			rough = mix(0.9, 0.82, wear * 0.6) + 0.05 * j.x;
			spec = 0.3;
			nm = mix(vec3(0.0, 0.0, 1.0), nm, 0.35);
		} else if (style == 1.0 && kind == 5) {
			// Lisbon calcada: small white limestone cubes (the sett texture's grain only) with black
			// basalt waves laid through them, crisp-edged
			float lum = dot(texture(sett_tex, wpos.xz / 1.6).rgb, vec3(0.33));
			col = vec3(0.84, 0.82, 0.77) * (0.8 + 0.34 * lum) * (0.94 + 0.12 * n1);
			float wave = sin(along * 0.42 + sin(across * 0.21) * 2.2);
			float band = 1.0 - smoothstep(0.2, 0.26, abs(wave));
			col = mix(col, vec3(0.11, 0.11, 0.12) * (0.8 + 0.5 * lum), band);
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
			// inlaid darker stone (basalt in the port, red porphyry inland), not paint
			vec3 inlay = style == 1.0 ? vec3(0.16, 0.16, 0.17) : vec3(0.42, 0.3, 0.26);
			col = mix(col, inlay * (0.8 + 0.4 * n2), clamp(rose, 0.0, 1.0) * step(r, 6.3) * 0.65);
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
	SPECULAR = spec;
	float dn = 1.0 - smoothstep(40.0, 250.0, dist);
	NORMAL_MAP = normalize(vec3(nm.xy * dn, 1.0)) * 0.5 + 0.5;
}
