shader_type spatial;
render_mode cull_disabled;
uniform vec4 stone_color : source_color = vec4(0.43, 0.44, 0.43, 1.0);
uniform float tile_scale = 1.0;
varying vec3 world_pos;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p = world_pos.xz * tile_scale;
 p.x += mod(floor(p.y),2.0)*0.5;
 vec2 cell=floor(p); vec2 f=fract(p);
 float edge=min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
 float grout=1.0-smoothstep(.015,.065,edge);
 float grain=hash(floor(world_pos.xz*65.0));
 ALBEDO=mix(stone_color.rgb*(.84+hash(cell)*.30)+(grain-.5)*.025,vec3(.24,.25,.24),grout*.72);
 ROUGHNESS=.93;
}
