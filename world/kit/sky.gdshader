// Rounded, cream-lit cloud banks over a clear blue summer gradient.
shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.61, 0.70, 0.85);
uniform vec3 sky_horizon_color : source_color = vec3(0.42, 0.55, 0.71);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.35;
// r5: the lilac in the reference is a haze BAND (~8-20 deg up), not the zenith: above it the sky goes
// back to a pale blue-grey. cliff_coast frames 0-18 deg (band = top), coast_b / arch frame up to
// 29 deg and were a pink-lilac sheet. Third stop: sky -> zenith over band_deg .. zenith_deg
uniform vec3 sky_zenith_color : source_color = vec3(0.66, 0.70, 0.78);
uniform float sky_band_deg = 16.0;
uniform float sky_zenith_deg = 40.0;
uniform float sky_energy = 1.4;
uniform float daylight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 ground_bottom_color : source_color = vec3(0.33, 0.38, 0.43);
uniform vec3 ground_horizon_color : source_color = vec3(0.42, 0.55, 0.71);
uniform float ground_curve : hint_range(0.0, 1.0) = 0.02;
uniform float ground_energy = 1.0;
uniform float sun_angle_max_deg = 35.0;
uniform float sun_curve : hint_range(0.0, 1.0) = 0.09;

uniform sampler2D sky_cover : filter_linear, repeat_enable;   // a = cover 0..1, r = lobe detail 0..1
uniform vec3 cloud_mul_edge : source_color = vec3(0.98, 0.93, 0.96);  // thin edge: barely darker, pinker
uniform vec3 cloud_mul_core : source_color = vec3(0.90, 0.85, 0.90);  // lobe cores: darker still
uniform vec3 cloud_base : source_color = vec3(0.68, 0.65, 0.74);      // flat-lit stratus colour (x sky_energy)
uniform float cloud_flat : hint_range(0.0, 1.0) = 0.7;                // 0 = pure tint of the sky, 1 = the flat colour
uniform float cloud_core_darken = 0.93;                               // lobe cores vs the smear
uniform float cloud_strength : hint_range(0.0, 1.0) = 1.0;

uniform vec3 glow_color : source_color = vec3(0.83, 0.72, 0.66);     // r4: narrow lobe PEACH (#d4b8a8; the ref's low sky toward the sun is #bdaa95 H31)
uniform vec3 glow_wide_color : source_color = vec3(0.77, 0.69, 0.73); // #c4b0bb: the wide cast stays pink-lilac (ref upper sky #a09eb5)
uniform float glow_amount = 0.35;
uniform float glow_power = 4.0;      // narrow lobe on the sun direction ...
uniform float glow_wide = 0.35;      // ... plus a wide lobe: azimuth-dependent at the horizon, uniform above ~10 deg
uniform float glow_wide_color_mul = 0.4;  // the wide lobe adds glow_color x this (a pink-lilac cast, not a second sun)


// the day/night cycle (DayNight): the sun and the moon are uniforms, not LIGHT0 - the one
// DirectionalLight is the sun by day and the moon by night. Until DayNight's first push `sun_vec`
// is zero and LIGHT0 drives the disc and the glow as it always did.
uniform vec3 sun_vec = vec3(0.0);
uniform vec3 sun_disc_color = vec3(0.0);    // linear, x energy
uniform vec3 moon_vec = vec3(0.0, -1.0, 0.0);
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float stars : hint_range(0.0, 1.0) = 0.0;
uniform mat3 star_rot = mat3(1.0);

float sky_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float sky_vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(sky_hash(i), sky_hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(sky_hash(i + vec3(0.0, 1.0, 0.0)), sky_hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(sky_hash(i + vec3(0.0, 0.0, 1.0)), sky_hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(sky_hash(i + vec3(0.0, 1.0, 1.0)), sky_hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

// stars fixed to the celestial sphere: one candidate per cell of a 3-D grid, a soft point of about
// a pixel (no twinkle: TIME would re-filter the radiance map every frame), a few bright ones, and a
// faint milky band
vec3 star_field(vec3 d) {
	vec3 s = star_rot * d;
	vec3 acc = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 150.0 : 60.0;
		vec3 p = s * scale;
		vec3 cell = floor(p);
		float h = sky_hash(cell + float(layer) * 17.0);
		float keep = layer == 0 ? 0.93 : 0.985;
		if (h > keep) {
			vec3 jit = vec3(sky_hash(cell + 3.1), sky_hash(cell + 7.7), sky_hash(cell + 11.3)) * 0.6 + 0.2;
			float r = length(fract(p) - jit);
			float b = (h - keep) / (1.0 - keep);
			float size = layer == 0 ? 0.16 : 0.12;
			float pt = 1.0 - smoothstep(0.0, size, r);
			vec3 tint = mix(vec3(1.0, 0.86, 0.72), vec3(0.75, 0.85, 1.0), sky_hash(cell + 5.0));
			acc += tint * pt * (layer == 0 ? 0.35 + 0.9 * b : 1.2 + 3.0 * b);
		}
	}
	float band = exp(-pow(dot(s, normalize(vec3(0.3, 0.2, 0.93))) / 0.2, 2.0));
	float n = sky_vnoise(s * 9.0) * 0.6 + sky_vnoise(s * 23.0) * 0.4;
	acc += vec3(0.55, 0.6, 0.8) * band * smoothstep(0.35, 0.8, n) * 0.06;
	return acc;
}

void sky() {
	float v_angle = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = (1.0 - v_angle / (PI * 0.5));
	vec3 sky = mix(sky_horizon_color, sky_top_color, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	sky = mix(sky, sky_zenith_color, smoothstep(radians(sky_band_deg), radians(sky_zenith_deg), PI * 0.5 - v_angle));
	sky *= sky_energy;

	bool cycle = dot(sun_vec, sun_vec) > 0.5;
	vec3 L_dir = cycle ? normalize(sun_vec) : LIGHT0_DIRECTION;
	vec3 L_col = cycle ? sun_disc_color : LIGHT0_COLOR * LIGHT0_ENERGY;
	float L_size = cycle ? radians(0.55) : LIGHT0_SIZE;
	vec3 glow_add = vec3(0.0);
	if (cycle || LIGHT0_ENABLED) {
		float sun_angle = acos(clamp(dot(L_dir, EYEDIR), -1.0, 1.0));
		float sun_max = radians(sun_angle_max_deg);
		// the sun sets behind the horizon (the disc is cut there, not faded)
		float above = cycle ? step(-0.004, EYEDIR.y) : 1.0;
		if (sun_angle < L_size) {
			sky = mix(sky, L_col, above);
		} else if (sun_angle < sun_max) {
			float c2 = (sun_angle - L_size) / (sun_max - L_size);
			sky = mix(sky, mix(L_col, sky, clamp(1.0 - pow(1.0 - c2, 1.0 / sun_curve), 0.0, 1.0)), above);
		}
		// warm glow: narrow lobe on the sun + a wide lobe. r3: the reference's upper sky is pink-lilac
		// on BOTH sides of the frame (#a09eb5 upper-right with the sun behind the camera), so above
		// ~10 deg the wide lobe is azimuth-independent; at the horizon it still follows the sun's
		// azimuth (sea.gdshader rebuilds exactly that horizon term, keep them in step)
		float d = max(dot(normalize(EYEDIR), L_dir), 0.0);
		vec2 az_e = normalize(EYEDIR.xz + vec2(1e-4, 0.0));
		vec2 az_s = normalize(L_dir.xz + vec2(1e-4, 0.0));
		float az = max(dot(az_e, az_s), 0.0);
		float wide = mix(pow(az, 1.5), 1.0, smoothstep(0.0, 0.17, abs(EYEDIR.y)));
		glow_add = (glow_color * pow(d, glow_power) * glow_amount + glow_wide_color * wide * glow_wide * glow_wide_color_mul) * sky_energy;
		sky += glow_add;
	}

	// clouds: darken/tint the sky under the cover, cores darker than edges
	vec4 cov = texture(sky_cover, SKY_COORDS);
	float a = cov.a * cloud_strength;
	// the reference's clouds keep one flat pinkish-grey (#a6a9be) whatever the sky behind them:
	// lighter than the horizon sky, a hair darker than the zenith. Cores darker for structure.
	vec3 mul = mix(cloud_mul_edge, cloud_mul_core, cov.r);
	vec3 cloud = mix(sky * mul, cloud_base * sky_energy, cloud_flat * smoothstep(0.0, 0.5, a));
	cloud *= mix(vec3(1.0), vec3(0.69, 0.81, 0.94), cov.r * 0.78);
	// by night the clouds are dark shapes against the stars, their rims silvered toward the moon
	vec3 mv = normalize(moon_vec);
	float up_moon = step(0.0, mv.y);
	float mrim = pow(max(dot(normalize(EYEDIR), mv), 0.0), 5.0) * night * up_moon;
	cloud += vec3(0.5, 0.56, 0.72) * mrim * (1.0 - cov.r) * 0.12;
	// the night sky behind the cover: stars, then the moon (the thin cloud edges let it through)
	if (stars > 0.001) {
		sky += star_field(EYEDIR) * stars * smoothstep(-0.02, 0.12, EYEDIR.y);
	}
	if (night > 0.001) {
		float mcos = dot(mv, EYEDIR);
		float ma = acos(clamp(mcos, -1.0, 1.0));
		float msz = radians(1.1);
		if (ma < msz * 1.2 && EYEDIR.y > -0.004) {
			float r = ma / msz;
			float mare = sky_vnoise(EYEDIR * 260.0) * 0.6 + sky_vnoise(EYEDIR * 700.0) * 0.4;
			vec3 disc = vec3(0.95, 0.96, 1.0) * (0.72 + 0.28 * smoothstep(0.3, 0.7, mare)) * (1.0 - 0.25 * r * r) * 1.8;
			sky = mix(sky, disc, (1.0 - smoothstep(0.9, 1.0, r)) * night);
		}
		float halo = pow(max(mcos, 0.0), 900.0) * 0.45 + pow(max(mcos, 0.0), 40.0) * 0.05;
		sky += vec3(0.62, 0.7, 0.95) * halo * night * up_moon;
	}
	sky = mix(sky, cloud, a);

	float cg = (v_angle - PI * 0.5) / (PI * 0.5);
	vec3 ground = mix(ground_horizon_color, ground_bottom_color, clamp(1.0 - pow(1.0 - cg, 1.0 / ground_curve), 0.0, 1.0));
	ground *= ground_energy;
	ground += glow_add;   // the last rows under the sea plane must match the sky's horizon, glow included
	COLOR = mix(ground, sky, step(0.0, EYEDIR.y)) * daylight;
}
