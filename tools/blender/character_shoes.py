"""Tailored ankle shoes; executed by character.py before merge/export.

Uses common.py's Godot-coordinate mesh helpers and the current character asset.
The upper is one connected surface from toe to ankle, not intersecting primitives.
Keep this before character_skin.py (which may merge or bind pivot children).
"""

shoe_leather = material('Shoe leather chestnut', (.205, .108, .057), .76)
shoe_edge = material('Shoe burnished edges', (.128, .064, .032), .82)
shoe_rubber = material('Shoe dark outsole', (.049, .036, .027), .94)
shoe_welt = material('Shoe leather welt', (.255, .149, .076), .88)
shoe_thread = material('Shoe waxed flax laces', (.48, .345, .205), .92)
shoe_eyelet = material('Shoe aged bronze eyelets', (.22, .15, .073), .50, .35)


def shoe_ring_points(cx, y, z, rx, rz, count=40):
    # Broad toe with a softly flattened plan profile, narrower at the heel.
    result = []
    for j in range(count):
        a = math.tau*j/count
        c, s = math.cos(a), math.sin(a)
        width = rx * (1.0 - .10*max(0, s))
        result.append((cx + width*math.copysign(abs(c)**.90, c), y,
                       z + rz*math.copysign(abs(s)**.90, s)))
    return result


def shoe_shell(name, cx, rings, mat, parent, cap_top=True, smooth_level=0):
    count = 40
    vertices = []
    for y, z, rx, rz in rings:
        vertices.extend(shoe_ring_points(cx, y, z, rx, rz, count))
    faces = []
    for row in range(len(rings)-1):
        for j in range(count):
            a, b = row*count+j, row*count+(j+1)%count
            faces.append((a, a+count, b+count, b))
    if name == 'Shoe layered outsole':
        # Matching left/right perimeter stations make a real recessed underside,
        # rather than an n-gon triangulated through the arch cavity.
        for j in range(count//2):
            indices = [(3*count//4+j)%count, (3*count//4+j+1)%count,
                       (3*count//4-j-1)%count, (3*count//4-j)%count]
            faces.append(tuple(dict.fromkeys(indices)))
        shaped = []
        for x, y, z in vertices:
            arch = 0.0
            if -.033 < z < .043:
                t = (z+.033)/.076
                arch = .012 * math.sin(math.pi*t)**.65
            toe = .007 * max(0.0, min(1.0, (-z-.130)/.047))**1.5
            influence = max(0.0, min(1.0, (-.368-y)/.017))
            shaped.append((x, y+(arch+toe)*influence, z))
        vertices = shaped
    else:
        faces.append(tuple(range(count)))
    if cap_top:
        faces.append(tuple((len(rings)-1)*count+j for j in reversed(range(count))))
    obj = mesh(name, vertices, faces, mat, parent)
    if smooth_level:
        bpy.context.view_layer.objects.active = obj
        modifier = obj.modifiers.new('Smooth continuous shoe last', 'SUBSURF')
        modifier.levels = smooth_level
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


for side, leg_name in [(-1, 'LegL'), (1, 'LegR')]:
    leg_pivot = next((o for o in asset.children_recursive
                      if o.type == 'EMPTY' and o.name == leg_name), None)
    if leg_pivot is None:
        raise RuntimeError('Shoe authoring requires explicit '+leg_name+' pivot')
    knee_pivot = next((o for o in leg_pivot.children
                       if o.type == 'EMPTY' and o.name.startswith('Knee')), None)
    if knee_pivot is None:
        raise RuntimeError('Shoe authoring requires Knee under '+leg_name)
    for old in list(knee_pivot.children):
        if old.type == 'MESH' and old.name.startswith(
                ('Boot sole', 'Laced shoe', 'Boot ankle', 'Boot lace', 'Shoe ')):
            bpy.data.objects.remove(old, do_unlink=True)
    cx = side*.05
    shoe_shell('Shoe layered outsole', cx, [
        (-.385, -.043, .072, .128), (-.382, -.043, .077, .134),
        (-.371, -.043, .077, .134), (-.368, -.043, .075, .132)],
        shoe_rubber, knee_pivot)
    shoe_shell('Shoe welt', cx, [
        (-.368, -.043, .075, .132), (-.365, -.043, .078, .133),
        (-.357, -.043, .077, .132), (-.354, -.043, .072, .127)],
        shoe_welt, knee_pivot)
    shoe_shell('Shoe continuous leather upper', cx, [
        (-.357, -.043, .070, .124), (-.350, -.043, .071, .124),
        (-.337, -.042, .071, .120), (-.326, -.042, .070, .116),
        (-.321, -.040, .067, .113), (-.314, -.025, .064, .091),
        (-.307, -.008, .060, .082), (-.297, .001, .055, .076),
        (-.280, .002, .053, .069), (-.260, .010, .050, .058),
        (-.239, .010, .051, .054), (-.232, .010, .052, .054),
        (-.231, .010, .048, .050), (-.241, .010, .047, .049)],
        shoe_leather, knee_pivot, cap_top=False, smooth_level=1)
    # Padded open collar wraps the sock; the interior stays dark rather than capped.
    collar = shoe_ring_points(cx, -.234, .010, .051, .053, 40)
    tube('Shoe collar piping', collar+[collar[0]], .0033, shoe_edge, knee_pivot, 6)
    # A narrow raised tongue follows the sloping instep and protrudes at the ankle.
    tongue_levels = [(-.320, -.151, .019), (-.308, -.097, .026),
                     (-.289, -.080, .028), (-.271, -.063, .027),
                     (-.249, -.052, .026), (-.229, -.052, .023)]
    tongue_verts = []
    for y, z, width in tongue_levels:
        tongue_verts.extend([(cx-width, y, z+.003), (cx, y+.002, z-.002),
                            (cx+width, y, z+.003)])
    tongue_faces = []
    for row in range(len(tongue_levels)-1):
        for col in range(2):
            a = row*3+col
            tongue_faces.append((a, a+3, a+4, a+1))
    tongue = mesh('Shoe raised tongue', tongue_verts, tongue_faces, shoe_edge, knee_pivot)
    bpy.context.view_layer.objects.active = tongue
    mod = tongue.modifiers.new('Leather tongue thickness', 'SOLIDIFY'); mod.thickness = .003
    bpy.ops.object.modifier_apply(modifier=mod.name)
    # Four crossed rows stand proud of the tongue and remain visible from front.
    lace_rows = [(-.308, -.103), (-.288, -.085), (-.269, -.068), (-.248, -.057)]
    for row, (y, z) in enumerate(lace_rows):
        for direction in [-1, 1]:
            torus('Shoe eyelet', (cx+direction*.024, y, z), .0037, .0011,
                  shoe_eyelet, knee_pivot, 'z', 10, 5)
        if row == len(lace_rows)-1:
            continue
        next_y, next_z = lace_rows[row+1]
        for direction in [-1, 1]:
            tube('Shoe crossed lace', [(cx+direction*.024, y, z-.002),
                 (cx, (y+next_y)/2+.002, (z+next_z)/2-.006),
                 (cx-direction*.024, next_y, next_z-.003)], .0022,
                 shoe_thread, knee_pivot, 6)
    tube('Shoe lace knot', [(cx-.016, -.248, -.062), (cx, -.245, -.067),
                           (cx+.016, -.248, -.062)], .003, shoe_thread, knee_pivot, 6)
    for direction in [-1, 1]:
        tube('Shoe tied lace end', [(cx, -.245, -.067),
             (cx+direction*.018, -.251, -.072), (cx+direction*.009, -.266, -.078)],
             .002, shoe_thread, knee_pivot, 6)
    # Fine individual stitches define the vamp and welt without oversized ropes.
    outline = shoe_ring_points(cx, -.356, -.043, .074, .129, 56)
    for j in range(0, len(outline), 2):
        tube('Shoe welt stitch', [outline[j], outline[(j+1)%len(outline)]],
             .0009, shoe_thread, knee_pivot, 4)
    for direction in [-1, 1]:
        seam_points = [(cx+direction*.033, -.309, -.088),
                       (cx+direction*.044, -.320, -.120),
                       (cx+direction*.053, -.330, -.136)]
        tube('Shoe stitched vamp', seam_points, .0012, shoe_welt, knee_pivot, 5)

    # A curved quarter seam defines the ankle facing and meets the welt behind
    # the ball of the foot, echoing a stitched leather panel rather than a cone.
    for direction in [-1, 1]:
        tube('Shoe ankle quarter seam', [
            (cx+direction*.037, -.246, -.029),
            (cx+direction*.045, -.268, -.026),
            (cx+direction*.050, -.292, -.011),
            (cx+direction*.057, -.320, .002),
            (cx+direction*.061, -.350, .010)],
            .0015, shoe_welt, knee_pivot, 5)
