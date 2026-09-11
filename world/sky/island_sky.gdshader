shader_type sky;
uniform vec3 zenith : source_color = vec3(0.22, 0.47, 0.68);
uniform vec3 horizon : source_color = vec3(0.76, 0.83, 0.83);
uniform float daylight = 1.0;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
float fbm(vec2 p) { return noise(p)*.55+noise(p*2.03)*.27+noise(p*4.11)*.12+noise(p*8.21)*.06; }
void sky() {
	float h=max(EYEDIR.y,0.0);
	vec3 base=mix(horizon,zenith,pow(h,.45));
	vec2 p=EYEDIR.xz/max(.12,EYEDIR.y+.12)*2.2+vec2(TIME*.007,TIME*.002);
	float f=fbm(p);
	float cloud=smoothstep(.50,.70,f)*smoothstep(.01,.18,h);
	vec3 cloud_col=mix(vec3(.66,.72,.75),vec3(1.0,.96,.87),smoothstep(.53,.78,f));
	base=mix(base,cloud_col,cloud*.94);
	float sun=pow(max(dot(EYEDIR,LIGHT0_DIRECTION),0.0),350.0);
	base+=vec3(1.0,.74,.39)*sun*.6;
	COLOR=mix(vec3(.012,.023,.055),base,daylight);
}
