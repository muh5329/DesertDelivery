// The outer world's ground: CDLOD patches (outer_terrain_view.gd) displaced on the GPU from the
// 12.5 m heightfield, and a layered material.
//
// Geometry: every vertex evaluates the same surface as OuterGround.height_at (triangles on the
// 6.25 m lattice; lattice point = bilinear data + micro relief x (1 - flatten)), so at LOD 0 the
// rendered ground is the collided ground. Odd grid vertices morph onto their even neighbours with
// camera distance (CDLOD), which collapses a patch exactly into its parent's mesh: no cracks.
//
// Material: 13 texture layers (Texture2DArray, Terrain3D packing: albedo + height, normal +
// roughness) mixed from the splat map (rock / sand / farmland / snow), slope and altitude, the
// aux map (forest floor, flatten = road shoulders and town pads, biome, dryness), procedural field
// parcels in the farmland, a far-distance road mask, a macro tint and broad noise. Transitions are
// height-blended; every layer is sampled at two scales with rotation (anti-tiling), rock is
// triplanar, and detail fades with distance.
shader_type spatial;
render_mode world_vertex_coords, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_tex : filter_nearest;          // RF 2001^2 (exact texel reads)
uniform sampler2D height_lin : filter_linear;           // the same texture, filtered (normals)
uniform sampler2D aux_tex : filter_nearest;             // RGBA8: forest, flatten, biome, dryness
uniform sampler2D aux_lin : filter_linear;
uniform sampler2D splat_tex : filter_linear;            // RGBA8: rock, sand, farm, snow
uniform sampler2D tint_tex : source_color, filter_linear; // 1001^2 macro tint (x2)
uniform sampler2D road_tex : filter_linear_mipmap;      // 4096^2 road coverage
uniform sampler2D micro_tex : filter_nearest, repeat_enable;
uniform sampler2D micro_lin : filter_linear, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;  // tileable value noise
uniform sampler2DArray alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_arr : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float micro_amp = 0.45;
uniform vec3 lod_camera = vec3(0.0);
uniform float hole = 622.0;
uniform float detail_normal = 0.9;
uniform float far_road_start = 650.0;
uniform float far_road_end = 950.0;

const float ORIGIN = -12500.0;
const float STEP = 12.5;
const float LAT = 6.25;
const int N = 2001;
const float SIZE = 25012.5;   // N * STEP

// layer ids (outer_terrain_view.gd LAYERS)
const int MEADOW = 0; const int DRYGRASS = 1; const int ALPINE = 2; const int SCRUB = 3; const int DIRT = 4;
const int SOIL = 5; const int SAND = 6; const int LIMESTONE = 7; const int GRANITE = 8; const int GRAVEL = 9;
const int SNOW = 10; const int CLAY = 11; const int PEBBLES = 12;
const int NL = 13;

varying vec3 wpos;
varying float morph_v;

float hdat(ivec2 p) { return texelFetch(height_tex, clamp(p, ivec2(0), ivec2(N - 1)), 0).r; }
float fdat(ivec2 p) { return texelFetch(aux_tex, clamp(p, ivec2(0), ivec2(N - 1)), 0).g; }

float lattice(ivec2 L) {
	L = clamp(L, ivec2(0), ivec2(4000));
	ivec2 i0 = L >> ivec2(1);
	ivec2 o = L & ivec2(1);
	float h = hdat(i0); float f = fdat(i0);
	if (o.x == 1 && o.y == 0) {
		h = (h + hdat(i0 + ivec2(1, 0))) * 0.5; f = (f + fdat(i0 + ivec2(1, 0))) * 0.5;
	} else if (o.x == 0 && o.y == 1) {
		h = (h + hdat(i0 + ivec2(0, 1))) * 0.5; f = (f + fdat(i0 + ivec2(0, 1))) * 0.5;
	} else if (o.x == 1 && o.y == 1) {
		h = (h + hdat(i0 + ivec2(1, 0)) + hdat(i0 + ivec2(0, 1)) + hdat(i0 + ivec2(1, 1))) * 0.25;
		f = (f + fdat(i0 + ivec2(1, 0)) + fdat(i0 + ivec2(0, 1)) + fdat(i0 + ivec2(1, 1))) * 0.25;
	}
	ivec2 mp = ((L * ivec2(25) - ivec2(50000)) % ivec2(256) + ivec2(256)) % ivec2(256);
	float m = texelFetch(micro_tex, mp, 0).r * 255.0;
	return h + (m - 128.0) / 127.0 * micro_amp * (1.0 - f);
}

float surface(vec2 w) {
	vec2 g = (w - ORIGIN) / LAT;
	ivec2 I = ivec2(floor(g));
	vec2 f = g - vec2(I);
	float b = lattice(I + ivec2(1, 0));
	float c = lattice(I + ivec2(0, 1));
	if (f.x + f.y <= 1.0) {
		float a = lattice(I);
		return a + (b - a) * f.x + (c - a) * f.y;
	}
	float d = lattice(I + ivec2(1, 1));
	return d + (c - d) * (1.0 - f.x) + (b - d) * (1.0 - f.y);
}

void vertex() {
	float cell = INSTANCE_CUSTOM.x;
	vec2 origin = MODEL_MATRIX[3].xz;
	vec2 gp = round((VERTEX.xz - origin) / cell);
	vec2 wp = origin + gp * cell;
	ivec2 L = ivec2(round((wp - ORIGIN) / LAT));
	float h0 = lattice(L);
	float d = distance(lod_camera, vec3(wp.x, h0, wp.y));
	float morph = clamp((d - INSTANCE_CUSTOM.y) / max(INSTANCE_CUSTOM.z - INSTANCE_CUSTOM.y, 1.0), 0.0, 1.0);
	vec2 odd = mod(gp, 2.0);
	vec2 mp = wp - odd * cell * morph;
	float h = (morph <= 0.0 || (odd.x + odd.y) < 0.5) ? lattice(ivec2(round((mp - ORIGIN) / LAT))) : surface(mp);
	if (max(abs(mp.x), abs(mp.y)) < hole) { h = -25.0; }
	VERTEX = vec3(mp.x, h, mp.y);
	NORMAL = vec3(0.0, 1.0, 0.0);
	wpos = VERTEX;
	morph_v = morph;
}

// ---------------------------------------------------------------- helpers
float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(100000));
	uint h = q.x * 374761393u + q.y * 668265263u;
	h = (h ^ (h >> 13u)) * 1274126177u;
	return float((h ^ (h >> 16u)) & 0xffffu) / 65535.0;
}

vec2 map_uv(vec2 w) { return (w - ORIGIN + 0.5 * STEP) / SIZE; }

vec2 rot(vec2 p, float a) { float c = cos(a); float s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }

// one layer at one uv: albedo+height, normal (tangent xy)+roughness
void layer_sample(int id, vec2 uv, out vec4 ah, out vec4 nr) {
	ah = texture(alb_arr, vec3(uv, float(id)));
	nr = texture(nrm_arr, vec3(uv, float(id)));
}

// two scales, rotated and blended by a noise mask, faded to the large scale with distance
void layer_mix(int id, vec2 w, float dist, float nmask, float scale, out vec4 ah, out vec4 nr) {
	vec2 uv1 = w / scale;
	vec2 uv2 = rot(w, 0.73 + float(id) * 0.41) / (scale * 3.7) + vec2(0.37 * float(id), 0.11);
	vec4 a1; vec4 n1; vec4 a2; vec4 n2;
	layer_sample(id, uv2, a2, n2);
	float near_w = (1.0 - smoothstep(70.0, 220.0, dist)) * (0.45 + 0.45 * nmask);
	if (near_w > 0.01) {
		layer_sample(id, uv1, a1, n1);
		ah = mix(a2, a1, near_w); nr = mix(n2, n1, near_w);
	} else {
		ah = a2; nr = n2;
	}
}

// triplanar for rock faces (xz projection on flats, the dominant side projection on cliffs)
void layer_tri(int id, vec3 w, vec3 n, float dist, float scale, out vec4 ah, out vec4 nr) {
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 ax; vec4 nx; vec4 ay; vec4 ny; vec4 az; vec4 nzv;
	layer_sample(id, w.zy / scale, ax, nx);
	layer_sample(id, w.xz / scale, ay, ny);
	layer_sample(id, w.xy / scale, az, nzv);
	ah = ax * bw.x + ay * bw.y + az * bw.z;
	nr = nx * bw.x + ny * bw.y + nzv * bw.z;
	if (dist > 250.0) {
		vec4 a2; vec4 n2;
		layer_sample(id, rot(w.xz, 1.1) / (scale * 4.1), a2, n2);
		float t = smoothstep(250.0, 700.0, dist) * bw.y;
		ah = mix(ah, a2, t); nr = mix(nr, n2, t);
	}
}

// field parcels in the farmland: crop id 0..5 and furrow stripes; the same pattern outer_flora.gd
// uses for the hedges
vec4 fields(vec2 w) {
	vec2 p = rot(w, 0.35) + vec2(sin(w.y * 0.0021) * 40.0, sin(w.x * 0.0017) * 35.0);
	vec2 cell = vec2(190.0, 115.0);
	float row = floor(p.y / cell.y);
	p.x += hash21(vec2(row, 17.0)) * cell.x;
	vec2 id = floor(p / cell);
	vec2 f = fract(p / cell);
	float crop = floor(hash21(id) * 6.0);
	vec2 e = min(f, 1.0 - f) * cell;
	float edge = min(e.x, e.y);
	float furrow = 0.5 + 0.5 * sin(p.y * 6.2831 / (hash21(id + 3.0) > 0.5 ? 1.6 : 2.4) + p.x * 0.004);
	return vec4(crop, edge, furrow, hash21(id + 7.0));
}

void fragment() {
	vec3 w = wpos;
	float dist = length(w - CAMERA_POSITION_WORLD);
	vec2 uv = map_uv(w.xz);
	// ---- macro normal from the data (filtered) + micro relief
	float e = STEP;
	float hl = texture(height_lin, map_uv(w.xz - vec2(e, 0.0))).r;
	float hr = texture(height_lin, map_uv(w.xz + vec2(e, 0.0))).r;
	float hd = texture(height_lin, map_uv(w.xz - vec2(0.0, e))).r;
	float hu = texture(height_lin, map_uv(w.xz + vec2(0.0, e))).r;
	vec4 aux = texture(aux_lin, uv);
	float flat_m = aux.g;
	vec2 muv = w.xz / 64.0;
	float mm = 0.25;
	float ml = texture(micro_lin, muv - vec2(mm / 64.0, 0.0)).r; float mr = texture(micro_lin, muv + vec2(mm / 64.0, 0.0)).r;
	float md = texture(micro_lin, muv - vec2(0.0, mm / 64.0)).r; float mu = texture(micro_lin, muv + vec2(0.0, mm / 64.0)).r;
	float mscale = micro_amp * (1.0 - flat_m) * 255.0 / 127.0;
	vec3 n = normalize(vec3((hl - hr) / (2.0 * e) + (ml - mr) * mscale / (2.0 * mm) * 0.35,
		1.0, (hd - hu) / (2.0 * e) + (md - mu) * mscale / (2.0 * mm) * 0.35));
	float slope = 1.0 - n.y;
	// ---- inputs
	vec4 sp = texture(splat_tex, uv);
	vec3 tint = texture(tint_tex, uv).rgb * 2.0;
	float n1 = texture(noise_tex, w.xz / 173.0).r;
	float n2 = texture(noise_tex, w.xz / 37.0 + 0.3).r;
	float n3 = texture(noise_tex, w.xz / 911.0 + 0.7).r;
	float biome = floor(texture(aux_tex, uv).b * 255.0 + 0.5);
	float forest = aux.r;
	float dry = aux.a;
	// ---- layer weights
	float w_[NL];
	for (int i = 0; i < NL; i++) { w_[i] = 0.0; }
	float rock = max(sp.r, smoothstep(0.42, 0.75, slope + (n2 - 0.5) * 0.12));
	float snow = sp.a * smoothstep(0.75, 0.45, slope);
	snow = max(snow, smoothstep(930.0, 1010.0, w.y + (n1 - 0.5) * 90.0) * smoothstep(0.6, 0.35, slope));
	float sand = sp.g;
	float farm = sp.b;
	float grass = max(1.0 - rock - snow - sand - farm, 0.0);
	bool arid = biome == 4.0 || biome == 8.0;
	bool alpine_zone = w.y > 380.0 && !arid;
	// grass family
	float lush = clamp(1.0 - dry * 1.3 + (n1 - 0.5) * 0.6, 0.0, 1.0);
	float scrubby = smoothstep(0.45, 0.75, n2 * 0.6 + n1 * 0.4) * 0.6;
	if (alpine_zone) {
		float a = smoothstep(380.0, 650.0, w.y);
		w_[ALPINE] += grass * a * (1.0 - scrubby * 0.4);
		w_[MEADOW] += grass * (1.0 - a) * lush;
		w_[DRYGRASS] += grass * (1.0 - a) * (1.0 - lush);
		w_[SCRUB] += grass * a * scrubby * 0.4;
	} else if (arid) {
		w_[DRYGRASS] += grass * (0.55 - scrubby * 0.2);
		w_[SCRUB] += grass * (0.22 + scrubby * 0.35);
		w_[SAND] += grass * 0.14;
		w_[CLAY] += grass * 0.10 * smoothstep(0.08, 0.3, slope);
	} else {
		w_[MEADOW] += grass * lush * (1.0 - scrubby);
		w_[DRYGRASS] += grass * (1.0 - lush) * (1.0 - scrubby);
		w_[SCRUB] += grass * scrubby;
	}
	// forest floor: needles and dirt under the canopy
	float ff = smoothstep(0.35, 0.8, forest) * 0.55;
	w_[DIRT] += ff * (w_[MEADOW] + w_[DRYGRASS] + w_[ALPINE]) ;
	w_[MEADOW] *= 1.0 - ff; w_[DRYGRASS] *= 1.0 - ff; w_[ALPINE] *= 1.0 - ff;
	// rock: granite in the range, limestone elsewhere, red clay faces in the badlands
	if (arid) { w_[LIMESTONE] += rock * 0.72; w_[CLAY] += rock * 0.28; }
	else if (w.y > 300.0 && biome != 6.0) { w_[GRANITE] += rock * smoothstep(300.0, 600.0, w.y); w_[LIMESTONE] += rock * (1.0 - smoothstep(300.0, 600.0, w.y)); }
	else { w_[LIMESTONE] += rock; }
	w_[GRAVEL] += rock * smoothstep(0.55, 0.35, slope) * 0.35;   // scree at the foot of the faces
	w_[SNOW] += snow;
	// sand: beaches (pebbles on the rocky coasts), the seabed
	float rocky_coast = smoothstep(0.35, 0.65, n2) * (1.0 - smoothstep(-20.0, -1.0, -w.y + 0.0) * 0.0);
	w_[SAND] += sand * (arid ? 1.0 : 1.0 - rocky_coast * 0.5);
	w_[PEBBLES] += sand * (arid ? 0.0 : rocky_coast * 0.5);
	// farmland: the parcels
	vec4 fp = fields(w.xz);
	fp.z = mix(0.5, fp.z, 1.0 - smoothstep(60.0, 220.0, dist));   // furrows only close up (no moire)
	vec3 field_tint = vec3(1.0);
	if (farm > 0.01) {
		float crop = fp.x;
		float hedge = 1.0 - smoothstep(1.5, 4.0, fp.y);
		float fw = farm * (1.0 - hedge);
		if (crop < 1.0) { w_[DRYGRASS] += fw; field_tint = vec3(1.32, 1.08, 0.56); }                    // ripe wheat
		else if (crop < 2.0) { w_[MEADOW] += fw; field_tint = vec3(0.86, 1.16, 0.74); }                 // green crop
		else if (crop < 3.0) { w_[SOIL] += fw * (0.6 + 0.4 * fp.z); w_[DIRT] += fw * 0.4 * (1.0 - fp.z); field_tint = vec3(0.92, 0.84, 0.76); }   // ploughed
		else if (crop < 4.0) { w_[SOIL] += fw * (1.0 - fp.z * 0.8); w_[MEADOW] += fw * fp.z * 0.8; }   // vines / rows
		else if (crop < 5.0) { w_[DRYGRASS] += fw * 0.6; w_[SCRUB] += fw * 0.4; field_tint = vec3(1.1, 1.0, 0.8); }     // fallow
		else { w_[MEADOW] += fw * 0.5; w_[DRYGRASS] += fw * 0.5; field_tint = vec3(1.06, 1.08, 0.7); }     // hay
		w_[SCRUB] += farm * hedge;
		field_tint = mix(vec3(1.0), field_tint * (0.92 + 0.16 * fp.w), farm * (1.0 - hedge));
	}
	// road shoulders and town pads: packed gravel and dirt
	float shoulder = smoothstep(0.35, 0.9, flat_m) * (1.0 - snow);
	if (shoulder > 0.0) {
		for (int i = 0; i < NL; i++) { w_[i] *= 1.0 - shoulder * 0.7; }
		w_[GRAVEL] += shoulder * 0.45 * (0.4 + 0.6 * n2);
		w_[DIRT] += shoulder * 0.25;
	}
	// ---- sample and height-blend the active layers
	float nmask = n2;
	vec3 col = vec3(0.0); vec3 tn = vec3(0.0); float rough = 0.0; float wsum = 0.0;
	float hmax = -10.0;
	vec4 AH[NL]; vec4 NR[NL];
	for (int i = 0; i < NL; i++) {
		if (w_[i] < 0.02) { continue; }
		float scale = (i == GRAVEL || i == PEBBLES) ? 3.0 : ((i == SOIL || i == SAND || i == SNOW || i == CLAY) ? 7.0 : 5.0);
		if (i == LIMESTONE || i == GRANITE) {
			layer_tri(i, w, n, dist, 9.0, AH[i], NR[i]);
		} else {
			layer_mix(i, w.xz, dist, nmask, scale, AH[i], NR[i]);
		}
		hmax = max(hmax, AH[i].a + w_[i]);
	}
	for (int i = 0; i < NL; i++) {
		if (w_[i] < 0.02) { continue; }
		float bw = max(AH[i].a + w_[i] - hmax + 0.28, 0.0);
		col += AH[i].rgb * bw; tn += (NR[i].rgb * 2.0 - 1.0) * bw; rough += NR[i].a * bw; wsum += bw;
	}
	col /= max(wsum, 1e-4); tn /= max(wsum, 1e-4); rough /= max(wsum, 1e-4);
	// ---- colour: macro tint, broad variation, field crops
	col *= mix(vec3(1.0), tint, 0.85);
	col *= 0.86 + 0.28 * n3;
	col *= mix(1.0, 0.9 + 0.2 * n1, 0.6);
	col *= field_tint;
	// forest from afar: the canopy's dark green where trees are no longer instanced
	float canopy = smoothstep(0.3, 0.75, forest) * smoothstep(700.0, 1300.0, dist);
	col = mix(col, vec3(0.10, 0.16, 0.08) * (0.8 + 0.4 * n2), canopy * 0.75);
	// roads beyond the ribbon meshes
	float road = texture(road_tex, uv).r * smoothstep(far_road_start, far_road_end, dist);
	col = mix(col, vec3(0.30, 0.29, 0.28), road * 0.9);
	// the seabed darkens with depth under the water
	col *= mix(1.0, 0.55, smoothstep(0.0, -12.0, w.y));
	// ---- normal: macro normal perturbed by the layer normals (fading with distance)
	float dn = detail_normal * (1.0 - smoothstep(60.0, 400.0, dist));
	vec3 t = normalize(vec3(1.0, -n.x / max(n.y, 0.2), 0.0));
	vec3 bt = normalize(cross(t, n));
	vec3 nw = normalize(n + (t * tn.x - bt * tn.y) * dn);
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.35, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
