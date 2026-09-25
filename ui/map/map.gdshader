shader_type canvas_item;
// The world map drawn into a Control: the baked 25 km overview (data/minimap/overview.webp) and,
// where the view is close, the 1.5 m/px insets of the core and the towns (detail.webp), faded in at
// their edges. The view is a centre (world x, z), metres per pixel and a rotation (the heading, for
// a heading-up minimap). `circle` masks a round minimap with a soft edge. Nothing here is per-frame
// CPU work: the markers are drawn over it by the Control.

uniform sampler2D overview : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_disable;
uniform vec3 world = vec3(-12500.0, -12500.0, 25000.0);   // origin x, z; size
uniform vec2 center = vec2(0.0);                          // world x, z at the middle of the rect
uniform float mpp = 4.0;                                  // metres per pixel of the rect
uniform float rotation = 0.0;                             // bearing shown up (radians, 0 = north)
uniform vec2 rect_size = vec2(200.0);
uniform float detail_mix = 1.0;
uniform int inset_count = 0;
uniform vec4 inset_world[24];                             // x0, z0, w, h (m)
uniform vec4 inset_uv[24];                                // u0, v0, du, dv in the detail atlas
uniform bool circle = true;
uniform vec4 sea = vec4(0.19, 0.42, 0.54, 1.0);           // beyond the edge of the world
uniform float fade = 1.0;

vec2 to_world(vec2 px) {
	vec2 local = (px - rect_size * 0.5) * mpp;
	float c = cos(rotation), s = sin(rotation);
	// screen -> world: rotate by +rotation (the heading comes up)
	return center + vec2(local.x * c - local.y * s, local.x * s + local.y * c);
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 w = to_world(px);
	vec2 dx = dFdx(w), dy = dFdy(w);
	vec2 ouv = (w - world.xy) / world.z;
	vec4 col = sea;
	if (ouv.x >= 0.0 && ouv.y >= 0.0 && ouv.x <= 1.0 && ouv.y <= 1.0) {
		col = textureGrad(overview, ouv, dx / world.z, dy / world.z);
	}
	if (detail_mix > 0.001) {
		for (int i = 0; i < inset_count; i++) {
			vec4 r = inset_world[i];
			vec2 t = (w - r.xy) / r.zw;
			if (t.x < 0.0 || t.y < 0.0 || t.x > 1.0 || t.y > 1.0) continue;
			// fade over the inset's outer 60 m so its sharper roads meet the overview's softly
			vec2 m = min(t, 1.0 - t) * r.zw;
			float f = smoothstep(0.0, 60.0, min(m.x, m.y)) * detail_mix;
			vec4 q = inset_uv[i];
			vec4 d = textureGrad(detail, q.xy + t * q.zw, dx / r.zw * q.zw, dy / r.zw * q.zw);
			col = mix(col, d, f);
		}
	}
	col.a = fade;
	if (circle) {
		float rr = length(px - rect_size * 0.5) / (min(rect_size.x, rect_size.y) * 0.5);
		col.a *= 1.0 - smoothstep(0.985, 1.0, rr);
		// a soft darkening towards the rim, like the edge of a lens
		col.rgb *= 1.0 - 0.18 * smoothstep(0.7, 1.0, rr);
	}
	COLOR = col;
}
