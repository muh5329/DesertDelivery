class_name LighthouseBeam
extends MeshInstance3D
## The turning beams of a lighthouse at night (M-12): two long soft cones from the lantern,
## rotated on the GPU (TIME), drawn additively and only while it is dark (`dn_night`). No script
## runs per frame; the lantern itself is lamp glass (arch.gdshader / NightLights.bulb_material).

const LENGTH := 260.0
const RADIUS := 16.0
static var _mesh: ArrayMesh
static var _mat: ShaderMaterial


## A beam pair at `pos` (the lantern's centre, in `parent`'s space).
static func attach(parent: Node3D, pos: Vector3, phase := 0.0) -> LighthouseBeam:
	var b := LighthouseBeam.new()
	b.name = "LighthouseBeam"
	b.mesh = _beam_mesh()
	b.material_override = _material()
	b.position = pos
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.custom_aabb = AABB(Vector3(-LENGTH, -RADIUS, -LENGTH), Vector3(LENGTH * 2.0, RADIUS * 2.0, LENGTH * 2.0))
	b.set_instance_shader_parameter("phase", phase)
	parent.add_child(b)
	return b


static func _beam_mesh() -> ArrayMesh:
	if _mesh: return _mesh
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 12
	for side: float in [-1.0, 1.0]:
		for i in range(seg):
			var a0 := TAU * i / seg; var a1 := TAU * (i + 1) / seg
			var p0 := Vector3(0.0, cos(a0), sin(a0)); var p1 := Vector3(0.0, cos(a1), sin(a1))
			var tip := Vector3(side * 0.6, 0, 0)
			var e0 := Vector3(side * LENGTH, 0, 0) + p0 * RADIUS
			var e1 := Vector3(side * LENGTH, 0, 0) + p1 * RADIUS
			# UV.x = 0 at the lantern .. 1 at the far end; UV.y = the angle round the cone (edge softness)
			for v in [[tip + p0 * 0.35, Vector2(0, 0), p0], [e0, Vector2(1, 0), p0], [e1, Vector2(1, 1), p1],
					[tip + p0 * 0.35, Vector2(0, 0), p0], [e1, Vector2(1, 1), p1], [tip + p1 * 0.35, Vector2(0, 1), p1]]:
				st.set_normal(v[2]); st.set_uv(v[1]); st.add_vertex(v[0])
	_mesh = st.commit()
	return _mesh


static func _material() -> ShaderMaterial:
	if _mat: return _mat
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
global uniform float dn_night;
instance uniform float phase = 0.0;
uniform vec3 beam : source_color = vec3(1.0, 0.9, 0.68);
uniform float strength = 0.22;
uniform float period = 11.0;
varying float along;
void vertex() {
	float a = TIME * TAU / period + phase;
	float c = cos(a); float s = sin(a);
	VERTEX = vec3(VERTEX.x * c - VERTEX.z * s, VERTEX.y, VERTEX.x * s + VERTEX.z * c);
	NORMAL = vec3(NORMAL.x * c - NORMAL.z * s, NORMAL.y, NORMAL.x * s + NORMAL.z * c);
	along = UV.x;
}
void fragment() {
	// soft edges (the cone's rim seen side-on fades out), brightest near the lantern
	float rim = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fall = pow(1.0 - along, 1.6) * smoothstep(0.0, 0.03, along);
	ALBEDO = beam * strength * dn_night * fall * rim * rim;
}
"""
	_mat = ShaderMaterial.new(); _mat.shader = sh
	return _mat
