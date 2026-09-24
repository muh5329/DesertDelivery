// Architecture kit surface (BuildingKit / ArchMaterials). One shader for every wall, roof, trim and
// module of every town, so a group of buildings is one surface and one draw call.
//   UV     metres (walls: u along the wall, v = -height; roofs: u along the eave, v = -up the slope)
//   UV2.x  layer index + weathering in the fraction (layer 3.4 = ashlar, 40 % weathered)
//   merged meshes (instanced = false):
//     COLOR.rgb tint, COLOR.a = metres below the eave / 32 (eave shadow), UV2.y = metres above the ground
//   module meshes (instanced = true, MultiMesh with colours and custom data):
//     CUSTOM0.rgb part colour, UV2.y = 0 fixed / 1 x INSTANCE_CUSTOM.rgb (paint) /
//     2 x the instance colour, layer = its alpha (the host wall: reveals, chimneys, merlons) /
//     3 x frame_palette[INSTANCE_CUSTOM.a] (window frames)
// Textures (assets/buildings, world/mapgen/facades.py): alb_tex RGB albedo + A tint mask,
// nrm_tex RG normal (GL) + B cavity AO + A roughness. No tangents: the frame comes from derivatives.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2DArray alb_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform bool instanced = false;
// window-frame paints (module flag 3, indexed by INSTANCE_CUSTOM.a): ArchMaterials.FRAMES
uniform vec3 frame_palette[8];
uniform float normal_strength = 1.0;
uniform float grime = 1.0;
// hemisphere sky fill (as the rock shader does): keeps shaded walls from going muddy
uniform vec3 sky_fill_color : source_color = vec3(0.70, 0.74, 0.82);
uniform float sky_fill = 0.10;
// floating props (OuterProps boats): a slow heave, pitch and roll phased by the instance position
uniform float bob = 0.0;

// metres per texture tile, per layer (facades.py LAYERS)
const float TILE[17] = float[](3.0, 3.0, 3.0, 3.0, 1.8, 3.0, 1.12, 2.0, 2.4, 2.0, 1.0, 1.0, 1.0, 2.0, 2.4, 2.0, 3.0);
const int L_PLASTER = 0;
const int L_WHITEWASH = 1;
const int L_AZULEJO = 6;
const int L_ROOF = 7;
const int L_SLATE = 8;
const int L_GLASS = 11;
const int L_IRON = 12;
const int L_TERRACE = 16;

// DayNight (M-12): the sky fill follows the hour; by night a share of the window panes is lit from
// inside (per window: the module instance's position, or a 2 x 3 m cell for baked glass) and the lamp
// glass (lanterns, plaza lamps: the warm-tinted glass) glows while the street lamps are on
global uniform vec3 dn_fill;
global uniform float dn_night;
global uniform float dn_lamps;
global uniform float dn_windows;

varying flat float v_layer;
varying flat float v_lit;
varying vec3 v_wpos;
varying flat float v_weather;
varying float v_h;
varying float v_eave;
varying vec3 v_tint;
varying vec3 v_wnormal;

float arch_hash(vec3 p) {
	uvec3 q = uvec3(ivec3(floor(p)) + ivec3(1048576));
	uint h = q.x * 374761393u + q.y * 668265263u + q.z * 2246822519u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 0xffffu) / 65535.0;
}

void vertex() {
	float l = UV2.x;
	v_layer = floor(l + 0.0005);
	v_weather = clamp(fract(l + 0.0005) * 1.25, 0.0, 1.0);
	v_tint = COLOR.rgb;
	if (instanced) {
		// modules: CUSTOM0 = the part's colour; COLOR = the instance colour (host wall tint, layer
		// in alpha: the vertex colour is white); INSTANCE_CUSTOM = paint rgb + window-frame index
		v_h = 20.0;
		v_eave = 32.0;
		vec3 part = CUSTOM0.rgb;
		if (UV2.y > 2.5) {
			v_tint = part * frame_palette[clamp(int(INSTANCE_CUSTOM.a + 0.5), 0, 7)];
		} else if (UV2.y > 1.5) {
			v_tint = part * COLOR.rgb;
			v_layer = floor(COLOR.a + 0.0005);
			v_weather = clamp(fract(COLOR.a + 0.0005) * 1.25, 0.0, 1.0);
		} else if (UV2.y > 0.5) {
			v_tint = part * INSTANCE_CUSTOM.rgb;
		} else {
			v_tint = part;
		}
	} else {
		v_h = UV2.y;
		v_eave = COLOR.a * 32.0;
	}
	if (bob > 0.0) {
		vec3 o = MODEL_MATRIX[3].xyz;
		float ph = o.x * 0.37 + o.z * 0.21;
		float roll = sin(TIME * 0.83 + ph) * 0.045 * bob;
		float pitch = sin(TIME * 0.61 + ph * 1.7) * 0.02 * bob;
		VERTEX.y += VERTEX.x * roll + VERTEX.z * pitch + sin(TIME * 0.95 + ph * 0.5) * 0.07 * bob;
	}
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// one draw per window module: its instance origin (x 4 so neighbours differ) keys the window
	v_lit = instanced ? arch_hash(MODEL_MATRIX[3].xyz * 4.0) : -1.0;
}

void fragment() {
	int L = int(v_layer + 0.5);
	float tile = TILE[clamp(L, 0, 16)];
	vec2 uv = UV / tile;
	// the UV's screen derivatives, taken in uniform control flow for the samples in branches below
	// (implicit derivatives are undefined there: wrong mips on a real GPU, m-16)
	vec2 uvdx = dFdx(UV); vec2 uvdy = dFdy(UV);
	vec4 a = texture(alb_tex, vec3(uv, float(L)));
	vec4 n = texture(nrm_tex, vec3(uv, float(L)));
	vec3 alb = a.rgb * mix(vec3(1.0), v_tint, a.a);
	bool roof = (L == L_ROOF || L == L_SLATE || L == L_TERRACE) && v_wnormal.y > 0.3;
	bool wall = abs(v_wnormal.y) < 0.6 && L != L_GLASS && L != L_IRON;
	// macro variation: large blotches (never twice the same across a town: UV carries a per-building offset)
	vec4 nz = texture(noise_tex, UV * 0.045);
	vec4 nz2 = texture(noise_tex, UV * 0.011 + vec2(0.37, 0.61));
	float w = v_weather;
	alb *= 0.95 + 0.10 * nz.r;
	alb *= 0.98 + 0.04 * nz2.b;
	// weathered plaster falls away near the ground and shows the rubble it was laid on
	if (wall && L == L_PLASTER) {
		float worn = (1.0 - smoothstep(0.1, 0.9 + 1.1 * nz.b, v_h)) * smoothstep(0.55, 0.7, nz2.r * 0.8 + 0.45 * w + 0.1 * nz.a);
		if (worn > 0.01) {
			vec3 suv = vec3(UV / 3.0, 2.0);
			alb = mix(alb, textureGrad(alb_tex, suv, uvdx / 3.0, uvdy / 3.0).rgb * vec3(0.95, 0.93, 0.9), worn);
			n = mix(n, textureGrad(nrm_tex, suv, uvdx / 3.0, uvdy / 3.0), worn);
		}
	}
	if (wall) {
		// rain streaks: long vertical noise, stronger on weathered buildings and near the eaves
		float streak = textureGrad(noise_tex, vec2(UV.x * 0.31, UV.y * 0.018), uvdx * vec2(0.31, 0.018), uvdy * vec2(0.31, 0.018)).g;
		float s = smoothstep(0.52, 0.86, streak) * (0.35 + 0.65 * w);
		alb *= 1.0 - 0.22 * s * (0.5 + 0.5 * (1.0 - smoothstep(0.0, 9.0, v_eave)));
		// rising damp and splash grime at the foot
		float g = 1.0 - smoothstep(0.0, 0.5 + 1.3 * nz.b + 0.6 * w, v_h);
		alb = mix(alb, alb * vec3(0.66, 0.62, 0.55), g * (0.45 + 0.4 * w) * grime);
		// shadow and soot under the eaves
		float e = 1.0 - smoothstep(0.0, 0.7 + 0.9 * nz.g, v_eave);
		alb *= 1.0 - 0.28 * e * grime;
		// sun-bleached / faded paint on weathered plaster
		if (L == L_PLASTER || L == L_WHITEWASH) {
			alb = mix(alb, vec3(dot(alb, vec3(0.3, 0.55, 0.15))) * 1.05, 0.18 * w * nz2.r);
		}
	}
	if (roof) {
		// moss and dirt in the lower courses, sun-bleached ridges
		alb *= 0.92 + 0.12 * nz.a;
		alb = mix(alb, alb * vec3(0.78, 0.8, 0.72), smoothstep(0.55, 0.9, nz2.g) * 0.5 * w);
	}
	ALBEDO = alb;
	float rough = n.a;
	if (L == L_GLASS) {
		METALLIC = 0.0;
		SPECULAR = 0.9;
		rough = n.a;
	} else if (L == L_IRON) {
		METALLIC = 0.55;
	} else {
		METALLIC = 0.0;
		SPECULAR = (L == L_AZULEJO) ? 0.7 : 0.35;
	}
	ROUGHNESS = rough;
	AO = n.b;
	AO_LIGHT_AFFECT = 0.25;
	// normal from the cotangent frame (no mesh tangents needed)
	vec3 dp1 = dFdx(VERTEX);
	vec3 dp2 = dFdy(VERTEX);
	vec2 duv1 = dFdx(UV);
	vec2 duv2 = dFdy(UV);
	vec3 N = normalize(NORMAL);
	vec3 dp2perp = cross(dp2, N);
	vec3 dp1perp = cross(N, dp1);
	vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
	float invmax = inversesqrt(max(max(dot(T, T), dot(B, B)), 1e-20));
	T *= invmax;
	B *= invmax;
	vec2 nxy = (n.rg * 2.0 - 1.0) * normal_strength;
	float nzz = sqrt(max(0.0, 1.0 - dot(nxy, nxy)));
	// GL normal map: +y is image up, which is -v in these UVs
	NORMAL = normalize(T * nxy.x - B * nxy.y + N * nzz);
	// soft sky fill on up-facing surfaces
	float up = clamp(v_wnormal.y * 0.5 + 0.5, 0.0, 1.0);
	EMISSION = alb * sky_fill_color * sky_fill * up * n.b * dn_fill;
	if (L == L_GLASS && dn_lamps + dn_windows > 0.001) {
		vec3 t = v_tint;
		if (t.r > 0.97 && t.g > 0.8 && t.b < 0.75) {
			// lamp glass: a warm bulb behind it
			EMISSION += vec3(1.0, 0.7, 0.36) * 7.0 * dn_lamps;
		} else if (min(t.r, min(t.g, t.b)) > 0.95) {
			float h = v_lit >= 0.0 ? v_lit : arch_hash(floor(v_wpos / vec3(2.2, 3.1, 2.2)) + vec3(0.0, 0.0, 91.0));
			float on = step(h, dn_windows);
			// rooms: warm lamplight in most, a paler kitchen or two, the odd cold blue
			float k = fract(h * 7.13);
			vec3 room = mix(vec3(1.0, 0.56, 0.24), vec3(1.0, 0.76, 0.46), k);
			room = mix(room, vec3(0.5, 0.66, 1.0), step(0.94, fract(h * 13.7)) * 0.8);
			// the pane is not uniformly bright: brighter low (the lamp), a curtain-soft falloff up
			float glow_v = 0.75 + 0.5 * smoothstep(0.2, 0.8, a.r);
			EMISSION += room * on * dn_night * 1.7 * (0.6 + 0.8 * fract(h * 3.7)) * glow_v;
			ALBEDO = mix(ALBEDO, ALBEDO * 0.4, on * dn_night);
		}
	}
}
