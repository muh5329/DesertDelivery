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
uniform sampler2D height_lin : filter_linear;           // the same heights, filtered (normals): R32F at boot, then an
uniform float height_lin_scale = 1.0;                   // R16 copy (m-16: R32F linear filtering is optional on
uniform float height_lin_offset = 0.0;                  // some GPUs); metres = r * scale + offset
uniform sampler2D aux_tex : filter_nearest;             // RGBA8: forest, flatten, biome, dryness
uniform sampler2D aux_lin : filter_linear;
uniform sampler2D splat_tex : filter_linear;            // RGBA8: rock, sand, farm, snow
uniform sampler2D tint_tex : source_color, filter_linear; // 1001^2 macro tint (x2)
uniform sampler2D feat_tex : filter_linear_mipmap;       // RGBA8 2001^2: wadi bed, irrigation, erg, cavity (0.5 = none)
uniform sampler2D road_tex : filter_linear_mipmap;      // 4096^2 road coverage
uniform sampler2D micro_tex : filter_nearest, repeat_enable;
uniform sampler2D micro_lin : filter_linear, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;  // tileable value noise
uniform sampler2DArray alb_arr : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrm_arr : filter_linear_mipmap_anisotropic, repeat_enable;

uniform float micro_amp = 0.45;
uniform int layer_count = 13;                           // = NL; a uniform so the layer loops stay loops
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

// DayNight: the forest floor's green-gold bounce is an emission term; it follows the hour
global uniform vec3 dn_fill;

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
	// (L*25 - 50000) mod 256 without a negative operand: % of a negative int is undefined in GLSL
	// and differs between drivers (m-16); 102400 = 400 x 256
	ivec2 mp = (L * ivec2(25) + ivec2(52400)) % ivec2(256);
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
	vec3 dv = lod_camera - vec3(wp.x, h0, wp.y);
	float d = length(vec3(dv.x, dv.y * 0.5, dv.z));      // OuterTerrainView.VERT_WEIGHT
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

// one layer at one uv: albedo+height, normal (tangent xy)+roughness. Every layer sample sits in
// per-pixel branches (the active layers differ from pixel to pixel), where implicit derivatives are
// undefined: a real GPU picks a wrong mip along every layer boundary and the ground sparkles there
// (m-16; the software rasteriser hides it). So the gradients are explicit: `gx`, `gy` are the
// screen derivatives of the uv, computed from the world position's derivatives outside any branch.
void layer_sample(int id, vec2 uv, vec2 gx, vec2 gy, out vec4 ah, out vec4 nr) {
	ah = textureGrad(alb_arr, vec3(uv, float(id)), gx, gy);
	nr = textureGrad(nrm_arr, vec3(uv, float(id)), gx, gy);
}

// two scales, rotated and blended by a noise mask, faded to the large scale with distance
void layer_mix(int id, vec2 w, vec2 wdx, vec2 wdy, float dist, float nmask, float scale, out vec4 ah, out vec4 nr) {
	vec2 uv1 = w / scale;
	float ang = 0.73 + float(id) * 0.41;
	float k2 = 1.0 / (scale * 3.7);
	vec2 uv2 = rot(w, ang) * k2 + vec2(0.37 * float(id), 0.11);
	vec4 a1; vec4 n1; vec4 a2; vec4 n2;
	layer_sample(id, uv2, rot(wdx, ang) * k2, rot(wdy, ang) * k2, a2, n2);
	float near_w = (1.0 - smoothstep(70.0, 220.0, dist)) * (0.45 + 0.45 * nmask);
	if (near_w > 0.01) {
		layer_sample(id, uv1, wdx / scale, wdy / scale, a1, n1);
		ah = mix(a2, a1, near_w); nr = mix(n2, n1, near_w);
	} else {
		ah = a2; nr = n2;
	}
}

// triplanar for rock faces (xz projection on flats, the dominant side projection on cliffs)
void layer_tri(int id, vec3 w, vec3 wdx, vec3 wdy, vec3 n, float dist, float scale, out vec4 ah, out vec4 nr) {
	vec3 bw = pow(abs(n), vec3(4.0));
	bw /= (bw.x + bw.y + bw.z);
	vec4 ax; vec4 nx; vec4 ay; vec4 ny; vec4 az; vec4 nzv;
	layer_sample(id, w.zy / scale, wdx.zy / scale, wdy.zy / scale, ax, nx);
	layer_sample(id, w.xz / scale, wdx.xz / scale, wdy.xz / scale, ay, ny);
	layer_sample(id, w.xy / scale, wdx.xy / scale, wdy.xy / scale, az, nzv);
	ah = ax * bw.x + ay * bw.y + az * bw.z;
	nr = nx * bw.x + ny * bw.y + nzv * bw.z;
	if (dist > 250.0) {
		vec4 a2; vec4 n2;
		float k4 = 1.0 / (scale * 4.1);
		layer_sample(id, rot(w.xz, 1.1) * k4, rot(wdx.xz, 1.1) * k4, rot(wdy.xz, 1.1) * k4, a2, n2);
		float t = smoothstep(250.0, 700.0, dist) * bw.y;
		ah = mix(ah, a2, t); nr = mix(nr, n2, t);
	}
}

// P-2: the parcels are laid out per farming district (~1.3 km, wobbly borders), each with its own
// furrow direction and row depth, and every row its own parcel length - one global 190 x 115 m
// lattice read as a checkerboard quilt from the air. OuterFlora.parcel_frame is the same function
// (hedges, walls, vines and hay follow the painted edges): keep them in step.
vec2 parcel_frame(vec2 w, out vec2 cell, out float ang) {
	vec2 dq = w / 1300.0 + vec2(sin(w.y * 0.0009), sin(w.x * 0.0011)) * 0.3;
	vec2 did = floor(dq);
	ang = 0.35 + (hash21(did * 13.0 + 5.0) - 0.5) * 1.4;
	vec2 p = rot(w, ang) + vec2(sin(w.y * 0.0021) * 40.0, sin(w.x * 0.0017) * 35.0);
	float rh = mix(80.0, 150.0, hash21(did * 13.0 + 9.0));
	float row = floor(p.y / rh);
	float len = mix(110.0, 280.0, hash21(vec2(row, did.x * 31.0 + did.y * 7.0 + 3.0)));
	p.x += hash21(vec2(row, 17.0)) * len;
	cell = vec2(len, rh);
	return p;
}

// field parcels in the farmland: crop id 0..5 and furrow stripes
vec4 fields(vec2 w) {
	vec2 cell; float ang;
	vec2 p = parcel_frame(w, cell, ang);
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
	// screen derivatives of the world position, taken here in uniform control flow (see layer_sample)
	vec3 wdx = dFdx(w);
	vec3 wdy = dFdy(w);
	float dist = length(w - CAMERA_POSITION_WORLD);
	vec2 uv = map_uv(w.xz);
	// ---- macro normal from the data (filtered) + micro relief
	float e = STEP;
	float hl = texture(height_lin, map_uv(w.xz - vec2(e, 0.0))).r * height_lin_scale;
	float hr = texture(height_lin, map_uv(w.xz + vec2(e, 0.0))).r * height_lin_scale;
	float hd = texture(height_lin, map_uv(w.xz - vec2(0.0, e))).r * height_lin_scale;
	float hu = texture(height_lin, map_uv(w.xz + vec2(0.0, e))).r * height_lin_scale;
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
	vec4 ft = texture(feat_tex, uv);
	float wadi = ft.r; float irr = ft.g; float erg = ft.b;
	float occl = (ft.a - 0.5) * 2.0;          // + valleys and gullies, - crests
	// ---- layer weights
	float w_[NL];
	for (int i = 0; i < NL; i++) { w_[i] = 0.0; }
	float rock = max(sp.r, smoothstep(0.42, 0.75, slope + (n2 - 0.5) * 0.12));
	// snow: the painted snowfields, plus a line that runs lower on the shaded north faces and in the
	// gullies, higher on the sunny south faces and crests, torn by rock ribs
	float aspect = clamp(-n.z / max(length(n.xz), 1e-3), -1.0, 1.0) * smoothstep(0.05, 0.3, slope);   // + faces north
	float line_y = 960.0 - aspect * 70.0 - max(occl, 0.0) * 60.0 + (n1 - 0.5) * 110.0 + (n2 - 0.5) * 30.0;
	float snow = sp.a * smoothstep(0.75, 0.45, slope);
	snow = max(snow, smoothstep(line_y - 40.0, line_y + 40.0, w.y) * smoothstep(0.62, 0.36, slope + (n2 - 0.5) * 0.15));
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
		// the plateau between the sand: desert pavement (reg) on the flats, dry grass and scrub in
		// the hollows, clay on the slopes
		float reg = smoothstep(0.05, 0.015, slope) * smoothstep(0.35, 0.65, n1 * 0.7 + n3 * 0.5) * (1.0 - irr);
		w_[DRYGRASS] += grass * (0.5 - scrubby * 0.2) * (1.0 - reg);
		w_[SCRUB] += grass * (0.2 + scrubby * 0.3) * (1.0 - reg);
		w_[GRAVEL] += grass * reg * 0.65;
		w_[PEBBLES] += grass * reg * 0.35;
		w_[SAND] += grass * 0.12;
		w_[CLAY] += grass * 0.14 * smoothstep(0.06, 0.25, slope);
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
	// sand: beaches (pebbles on the rocky coasts), the seabed, the erg, the wadi floors (sand with
	// braided gravel bars)
	float rocky_coast = smoothstep(0.35, 0.65, n2) * (1.0 - smoothstep(-20.0, -1.0, -w.y + 0.0) * 0.0);
	float braid = smoothstep(0.42, 0.62, texture(noise_tex, rot(w.xz, 0.6) / vec2(61.0, 17.0)).r);
	float in_wadi = wadi * (1.0 - erg);
	w_[SAND] += sand * (arid ? 1.0 - in_wadi * braid * 0.6 : 1.0 - rocky_coast * 0.5);
	w_[PEBBLES] += sand * (arid ? in_wadi * braid * 0.6 : rocky_coast * 0.5);
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
	// road shoulders and town pads: packed gravel and dirt; beyond them, along the country roads, a
	// damp ditch line: lusher, darker grass at the outer edge of the flattened corridor
	float ditch = smoothstep(0.12, 0.32, flat_m) * (1.0 - smoothstep(0.4, 0.62, flat_m)) * (biome == 5.0 ? 0.0 : 1.0) * (1.0 - snow);
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
	for (int i = 0; i < NL; i++) { AH[i] = vec4(0.0); NR[i] = vec4(0.5, 0.5, 1.0, 1.0); }
	// (the bound is a uniform: a constant 13 lets a shader compiler unroll the loop with every
	// sample inlined 13 times - a software rasteriser's compiler ran out of memory on it)
	for (int i = 0; i < layer_count; i++) {
		if (w_[i] < 0.02) { continue; }
		float scale = (i == GRAVEL || i == PEBBLES) ? 3.0 : ((i == SOIL || i == SAND || i == SNOW || i == CLAY) ? 7.0 : 5.0);
		if (i == LIMESTONE || i == GRANITE) {
			layer_tri(i, w, wdx, wdy, n, dist, 9.0, AH[i], NR[i]);
		} else {
			layer_mix(i, w.xz, wdx.xz, wdy.xz, dist, nmask, scale, AH[i], NR[i]);
		}
		hmax = max(hmax, AH[i].a + w_[i]);
	}
	for (int i = 0; i < layer_count; i++) {
		if (w_[i] < 0.02) { continue; }
		float bw = max(AH[i].a + w_[i] - hmax + 0.28, 0.0);
		col += AH[i].rgb * bw; tn += (NR[i].rgb * 2.0 - 1.0) * bw; rough += NR[i].a * bw; wsum += bw;
	}
	col /= max(wsum, 1e-4); tn /= max(wsum, 1e-4); rough /= max(wsum, 1e-4);
	// sandstone strata on the arid cliffs and mesa rims: formations 5-20 m thick (cream, ochre, red,
	// a mauve shale), thin beds inside them, a pale cap rock, dark desert-varnish streaks down the faces
	if (arid) {
		float yy = w.y + (n3 - 0.5) * 14.0;
		float form = floor(yy / 11.0);
		float fr = hash21(vec2(form, 3.0));
		vec3 fcol = fr < 0.25 ? vec3(1.24, 1.08, 0.86) : (fr < 0.55 ? vec3(1.16, 0.86, 0.62) : (fr < 0.82 ? vec3(1.04, 0.66, 0.50) : vec3(0.86, 0.72, 0.70)));
		float beds = sin(yy * 2.7 + n1 * 3.0) * 0.5 + 0.5;
		vec3 strata = fcol * mix(0.9, 1.07, beds);
		vec2 vk = vec2(1.0 / 9.0, 0.08 / 3.0);
		float varnish = smoothstep(0.55, 0.8, textureGrad(noise_tex, vec2(w.x + w.z, w.y * 0.08) / vec2(9.0, 3.0),
			vec2(wdx.x + wdx.z, wdx.y) * vk, vec2(wdy.x + wdy.z, wdy.y) * vk).r) * smoothstep(0.55, 0.8, slope);
		strata *= 1.0 - varnish * 0.35;
		col = mix(col, col * strata, smoothstep(0.3, 0.85, rock) * 0.9);
	} else if (w.y > 300.0) {
		// lichen and weathering on the granite
		col = mix(col, col * vec3(0.92, 0.96, 0.90) * (0.85 + 0.3 * n2), rock * 0.5);
	}
	// ---- colour: macro tint, broad variation, field crops
	col *= mix(vec3(1.0), tint, 0.85);
	col *= 0.86 + 0.28 * n3;
	col *= mix(1.0, 0.9 + 0.2 * n1, 0.6);
	col *= field_tint;
	col = mix(col, col * (arid ? vec3(0.86, 0.84, 0.8) : vec3(0.72, 0.84, 0.62)), ditch * 0.7);
	// the forest floor: brown needles and leaf litter, a little moss, darker under the canopy
	float litter = smoothstep(0.22, 0.7, forest) * (1.0 - snow) * (arid ? 0.3 : 1.0);
	col = mix(col, col * vec3(1.02, 0.84, 0.62) * (0.82 + 0.25 * n2), litter * 0.75);
	// irrigated plots: lush green even in the desert
	col = mix(col, col * vec3(0.72, 1.08, 0.62), irr * farm * 0.6);
	// the erg: pale sand, darker in the dune troughs, wind ripples close up
	if (erg > 0.05) {
		float ripple = sin(dot(w.xz, vec2(-0.62, 0.78)) * 3.1 + n2 * 6.0) * 0.5 + 0.5;
		col *= mix(1.0, 0.94 + 0.08 * ripple, erg * (1.0 - smoothstep(30.0, 120.0, dist)));
	}
	// wet sand along the waterline (and the lake and river shores are darker too)
	float wetline = (1.0 - smoothstep(0.35, 1.4, w.y)) * step(-0.5, w.y) * max(sand, wadi * 0.0);
	col *= 1.0 - wetline * 0.32;
	// cavity: gullies, valleys and the feet of slopes darker, crests a touch lighter (the far view's
	// ambient occlusion)
	col *= 1.0 - 0.34 * max(occl, 0.0) + 0.07 * max(-occl, 0.0);
	// forest from afar: the canopy where trees are no longer instanced - dark conifer masses in the
	// range, olive-green broadleaf lower down, grey-green maquis and scrub; mottled at crown scale
	// and lit by the slope (the canopy's own relief) so a forest reads as a mass, not a stain
	float canopy = smoothstep(0.3, 0.75, forest) * smoothstep(700.0, 1300.0, dist);
	if (canopy > 0.001) {
		vec3 cc = w.y > 300.0 && !arid ? vec3(0.055, 0.10, 0.065) : (arid ? vec3(0.20, 0.21, 0.12) : vec3(0.09, 0.14, 0.06));
		float crowns = textureGrad(noise_tex, w.xz / 23.0, wdx.xz / 23.0, wdy.xz / 23.0).r;
		cc *= 0.72 + 0.56 * crowns;
		cc *= 0.8 + 0.5 * clamp(dot(n, normalize(vec3(-0.45, 0.8, 0.4))), 0.0, 1.0);
		col = mix(col, cc, canopy * 0.82);
	}
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
	// under the canopy the ground sees mostly the blue sky ambient and went slate-grey: the light
	// that reaches a forest floor is green-gold, bounced off the leaves and the litter
	EMISSION = col * vec3(0.16, 0.13, 0.07) * litter * (1.0 - smoothstep(150.0, 600.0, dist)) * dn_fill;
	ROUGHNESS = clamp(rough, 0.35, 1.0);
	SPECULAR = 0.3;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
}
