"""Project the supplied facial detail onto the matching sculpt.
Bake original front detail with a soft skin transition around cheeks and chin.
"""
reference=bpy.data.images.load('/Users/mun/Documents/Projects/DesertDelivery/assets/source/courier_turnaround.png',check_existing=True)
reference.pack()
face_material=material('Skin reference facial paint',(1,1,1),.85)
shader=next(n for n in face_material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
tex=next((n for n in face_material.node_tree.nodes if n.type=='TEX_IMAGE'),None) or face_material.node_tree.nodes.new('ShaderNodeTexImage')
tex.image=reference
face_material.node_tree.links.new(tex.outputs['Color'],shader.inputs['Base Color'])
face.data.materials.clear(); face.data.materials.append(face_material)
uv=face.data.uv_layers.get('ReferenceProjection') or face.data.uv_layers.new(name='ReferenceProjection')
bpy.context.view_layer.update()
# Front reference bounds: hair y58, sole y869; 1.88m total height.
scale=811/1.88; width,height=reference.size
for poly in face.data.polygons:
    centre=sum((C.inverted()@face.data.vertices[i].co for i in poly.vertices),Vector())/len(poly.vertices)
    front=centre.z < -.025 and abs(centre.x)<.081
    for loop_index in poly.loop_indices:
        local=face.data.vertices[face.data.loops[loop_index].vertex_index].co
        p=C.inverted()@(face.matrix_world@local)
        if front: px=281-p.x*scale
        elif centre.x>0: px=677+p.z*scale
        else: px=1476-p.z*scale
        py=869-p.y*scale
        uv.data[loop_index].uv=(px/width,1-py/height)
# Facial features are now painted from the user's exact design, with sculpted nose/cheeks.
for obj in list(head.children):
    if obj==face: continue
    if obj.name.startswith(('Almond','Hazel','Pupil','Catchlight','Upper eyelid','Lower eyelid','Eyebrow','Mouth','Lower lip','Nostril')):
        bpy.data.objects.remove(obj,do_unlink=True)
# Blend projections across the cheek, then bake to a conventional game texture.
# Abrupt per-polygon front/profile choices would leave a staircase down the jaw.
front_uv=face.data.uv_layers.new(name='FrontPhoto')
side_uv=face.data.uv_layers.new(name='SidePhoto')
blend=face.data.color_attributes.new(name='ProjectionBlend',type='FLOAT_COLOR',domain='CORNER')
for poly in face.data.polygons:
    for li in poly.loop_indices:
        local=face.data.vertices[face.data.loops[li].vertex_index].co
        p=C.inverted()@(face.matrix_world@local)
        q=C.inverted()@local
        front_uv.data[li].uv=((281-p.x*scale)/width,1-(869-p.y*scale)/height)
        px=677+p.z*scale if q.x>0 else 1476-p.z*scale
        side_uv.data[li].uv=(px/width,1-(869-p.y*scale)/height)
        t=max(0,min(1,(abs(q.x)-.055)/.027)); t=t*t*(3-2*t)
        t=max(t,max(0,min(1,(-.085-q.y)/.025)))
        if q.z>-.015: t=1
        blend.data[li].color=(t,t,t,1)
nodes=face_material.node_tree.nodes; links=face_material.node_tree.links
front_tex=nodes.new('ShaderNodeTexImage'); front_tex.image=reference
side_tex=nodes.new('ShaderNodeTexImage'); side_tex.image=reference
for texture,uv_name in [(front_tex,'FrontPhoto'),(side_tex,'SidePhoto')]:
    uv_node=nodes.new('ShaderNodeUVMap'); uv_node.uv_map=uv_name; links.new(uv_node.outputs['UV'],texture.inputs['Vector'])
color_node=nodes.new('ShaderNodeVertexColor'); color_node.layer_name='ProjectionBlend'
mix=nodes.new('ShaderNodeMixRGB'); links.new(color_node.outputs['Color'],mix.inputs[0]); links.new(front_tex.outputs['Color'],mix.inputs[1]); mix.inputs[2].default_value=(.70,.47,.28,1)
emission=nodes.new('ShaderNodeEmission'); links.new(mix.outputs[0],emission.inputs['Color'])
output=next(n for n in nodes if n.type=='OUTPUT_MATERIAL'); links.new(emission.outputs[0],output.inputs['Surface'])
bpy.ops.object.select_all(action='DESELECT'); face.select_set(True); bpy.context.view_layer.objects.active=face
bake_uv=face.data.uv_layers.new(name='FaceAtlas'); face.data.uv_layers.active=bake_uv; bake_uv.active_render=True
for poly in face.data.polygons:
    coords=[]
    for li in poly.loop_indices:
        q=C.inverted()@face.data.vertices[face.data.loops[li].vertex_index].co
        coords.append((li,.5+math.atan2(q.x,-q.z)/math.tau,(q.y+.158*.82)/(.318*.82)))
    seam=max(t[1] for t in coords)-min(t[1] for t in coords)>.5
    for li,u,vv in coords:
        if seam and u<.5: u+=1
        bake_uv.data[li].uv=(.02+.96*u,.02+.96*vv)
baked=bpy.data.images.new('CourierFaceAlbedo',width=1024,height=1024,alpha=False)
baked.generated_color=(.70,.47,.28,1)
target=nodes.new('ShaderNodeTexImage'); target.image=baked; nodes.active=target
scene=bpy.context.scene; previous_engine=scene.render.engine
try:
    scene.render.engine='CYCLES'; scene.cycles.samples=1
    bpy.ops.object.bake(type='EMIT',margin=16,use_clear=False)
finally:
    scene.render.engine=previous_engine
baked.pack()
for node in list(nodes):
    if node not in [shader,output,target]: nodes.remove(node)
links.new(target.outputs['Color'],shader.inputs['Base Color']); links.new(shader.outputs[0],output.inputs['Surface'])
for layer in list(face.data.uv_layers):
    if layer.name!='FaceAtlas': face.data.uv_layers.remove(layer)
face.data.color_attributes.remove(blend)

atlas_node=nodes.new('ShaderNodeUVMap'); atlas_node.uv_map='FaceAtlas'; links.new(atlas_node.outputs['UV'],target.inputs['Vector'])
