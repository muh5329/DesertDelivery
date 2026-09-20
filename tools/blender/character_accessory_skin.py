"""Bind tailoring details after character_skin.py, before final normal/export pass.

Works in evaluated authored world space, then bakes into rig-local space. Does not
reparent a local mesh without converting its vertices, or alter clothing weights.
"""
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

bpy.context.view_layer.update()
_accessory_cinv = C.inverted()


def _accessory_surface(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    tree = BVHTree.FromBMesh(bm)
    bm.free()
    return obj, tree


def _accessory_front_depth(surface, point):
    obj, tree = surface
    inverse = obj.matrix_world.inverted()
    origin = inverse @ v((point.x, point.y, -2))
    direction = (inverse.to_3x3() @ v((0, 0, 1))).normalized()
    hit, _normal, _index, _distance = tree.ray_cast(origin, direction)
    if hit is None:
        raise RuntimeError('Tailoring projection missed '+obj.name+' at '+str(point))
    return (_accessory_cinv @ (obj.matrix_world @ hit)).z


def _accessory_closest_path(point, path):
    best, distance = None, float('inf')
    for a, b in zip(path, path[1:]):
        span = b-a
        t = max(0., min(1., (point-a).dot(span)/span.length_squared))
        candidate = a + span*t
        d = (candidate-point).length_squared
        if d < distance:
            best, distance = candidate, d
    return best


def _accessory_bind(parts, label, kind):
    if not parts:
        raise RuntimeError('Missing authored tailoring parts for '+label)
    vertices, faces, materials, face_materials = [], [], [], []
    inverse_rig = rig.matrix_world.inverted()
    for obj in parts:
        base = len(vertices)
        vertices.extend(inverse_rig @ obj.matrix_world @ vert.co for vert in obj.data.vertices)
        material_map = {}
        for i, mat in enumerate(obj.data.materials):
            if mat not in materials:
                materials.append(mat)
            material_map[i] = materials.index(mat)
        for poly in obj.data.polygons:
            faces.append(tuple(base+i for i in poly.vertices))
            face_materials.append(material_map[poly.material_index])
    data = bpy.data.meshes.new(label)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(label, data)
    COLL.objects.link(obj)
    obj.parent = rig
    obj.matrix_parent_inverse = Matrix.Identity(4)
    obj.matrix_basis = Matrix.Identity(4)
    for mat in materials:
        data.materials.append(mat)
    for poly, index in zip(data.polygons, face_materials):
        poly.material_index = index
        poly.use_smooth = True
    groups = {key: obj.vertex_groups.new(name='Skin_'+key) for key in pivots}
    for vertex in data.vertices:
        q = _accessory_cinv @ (rig.matrix_world @ vertex.co)
        if kind == 'shirt':
            pelvis = 1-smoothstep(1.155, 1.32, q.y)
            # Suspenders remain inside the central torso, away from sleeve weights.
            weights = {'Root': pelvis, 'Torso': 1-pelvis}
        else:
            pelvis = smoothstep(.86, 1.04, q.y)
            right = smoothstep(-.026, .026, q.x)
            knee = 1-smoothstep(.32, .51, q.y)
            weights = {'Root': pelvis, 'LegL': (1-pelvis)*(1-right)*(1-knee),
                       'KneeL': (1-pelvis)*(1-right)*knee,
                       'LegR': (1-pelvis)*right*(1-knee), 'KneeR': (1-pelvis)*right*knee}
        for key, weight in weights.items():
            if weight > 1e-6:
                groups[key].add([vertex.index], weight, 'REPLACE')
    modifier = obj.modifiers.new('Tailoring follows continuous garments', 'ARMATURE')
    modifier.object = rig
    for part in parts:
        bpy.data.objects.remove(part, do_unlink=True)
    return obj


_shirt_surface = _accessory_surface(blouse)
_pants_surface = _accessory_surface(trousers)
_strap_parts = [o for o in asset.children_recursive if o.type == 'MESH'
               and o.name.startswith(('Front suspender', 'Y suspender', 'Shoulder suspender', 'Suspender clip', 'Button placket', 'Shirt button'))]
for _obj in _strap_parts:
    if _obj.name.startswith('Button placket'):
        bm=bmesh.new(); bm.from_mesh(_obj.data)
        bmesh.ops.subdivide_edges(bm,edges=[e for e in bm.edges if e.calc_length()>.012],cuts=10,use_grid_fill=True)
        bm.to_mesh(_obj.data); bm.free()
        path=[_accessory_cinv@(torso.matrix_world@v(p)) for p in [(0,.24,-.106),(0,.40,-.110),(0,.56,-.095)]]
        inverse=_obj.matrix_world.inverted()
        for vertex in _obj.data.vertices:
            point=_accessory_cinv@(_obj.matrix_world@vertex.co)
            center=_accessory_closest_path(point,path)
            point.z+=_accessory_front_depth(_shirt_surface,center)-.0045-center.z
            vertex.co=inverse@v(point)
        continue
    if not _obj.name.startswith(('Suspender clip','Shirt button')):
        continue  # Straps were already projected by character_skin.py.
    _center = _accessory_cinv @ _obj.matrix_world.translation
    _shift = _accessory_front_depth(_shirt_surface, _center) - .007 - _center.z
    _inverse = _obj.matrix_world.inverted()
    for _vertex in _obj.data.vertices:
        _point = _accessory_cinv @ (_obj.matrix_world @ _vertex.co)
        _point.z += _shift  # Translate the complete clip; retain its thickness.
        _vertex.co = _inverse @ v(_point)
_accessory_bind(_strap_parts, 'SkinnedSuspenders', 'shirt')

_pocket_parts = [o for o in asset.children_recursive if o.type == 'MESH'
                and o.name.startswith(('Pocket welt', 'Fly stitching'))]
for _obj in _pocket_parts:
    # The source tubes have only three path rings. Add samples before assigning
    # nonlinear pelvis weights so their long edges follow the same cloth bend.
    _bm = bmesh.new()
    _bm.from_mesh(_obj.data)
    _long_edges = [edge for edge in _bm.edges if edge.calc_length() > .012]
    bmesh.ops.subdivide_edges(_bm, edges=_long_edges, cuts=7, use_grid_fill=True)
    _bm.to_mesh(_obj.data)
    _bm.free()
    _side = -1 if (_accessory_cinv @ (_obj.matrix_world @ _obj.data.vertices[0].co)).x < 0 else 1
    if _obj.name.startswith('Pocket welt'):
        _path = [(_side*.141, .285, -.054), (_side*.128, .238, -.081), (_side*.095, .183, -.099)]
        _clearance = .0023
    else:
        _path = [(0, .278, -.104), (0, .195, -.115), (0, .10, -.117)]
        _clearance = .0019
    _path = [_accessory_cinv @ (root.matrix_world @ v(p)) for p in _path]
    _inverse = _obj.matrix_world.inverted()
    for _vertex in _obj.data.vertices:
        _point = _accessory_cinv @ (_obj.matrix_world @ _vertex.co)
        _center = _accessory_closest_path(_point, _path)
        _point.z += _accessory_front_depth(_pants_surface, _center) - _clearance - _center.z
        _vertex.co = _inverse @ v(_point)
_accessory_bind(_pocket_parts, 'SkinnedTrouserStitching', 'pants')
print('TAILORING SKIN: suspenders, clips, pocket welts and fly attached to cloth rig')
