"""Reference courier hair: an asymmetric swept crest and staggered leaf-like nape.

Authored in the existing lock helper's pre-transform coordinates. character.py
mirrors X, widens it by 1.10, compresses positive Y by .87, then scales by .82.
Keep the existing name prefixes so that transform and NPC hair recolouring apply.
"""
for obj in list(head.children):
    if obj.type == 'MESH' and obj.name.startswith(('Hair', 'Layered', 'Hero swept', 'Left swept', 'Right', 'Crown', 'Fine')):
        bpy.data.objects.remove(obj, do_unlink=True)

# Close the scalp beneath the crest. ell stores its centre in object.location:
# character.py compresses positive local vertices by .87, but not that centre.
# Top is therefore .090 + .102*.87 = .17874 before the shared .82 scale,
# safely above the head sculpt's .160; rear radius stays inside the layered locks.
ell('Hair crown', (0, .090, .020), (.124, .102, .108), hair, head, 32)

# Crown locks travel diagonally from the part, rather than beginning along a
# horizontal helmet rim. Their alternating heights and azimuths break up the cap.
crown_specs = [
    (.02, .024, .040, -.014),
    (.39, .010, .043, -.051),
    (.78, -.009, .045, -.028),
    (1.17, .007, .047, -.069),
    (1.57, -.014, .048, -.045),
    (1.96, .003, .045, -.078),
    (2.37, -.007, .044, -.035),
    (2.78, .016, .041, -.057),
    (3.11, .028, .035, -.010),
]
for i, (a, rise, width, tip_y) in enumerate(crown_specs):
    x = math.cos(a) * .116
    z = .020 + math.sin(a) * .112
    turn = -.12 if i < 5 else .12
    end_x = math.cos(a + turn) * .136
    end_z = .021 + math.sin(a + turn) * .126
    lock('Layered crown %02d' % i, [
        (-.030 + x * .23, .169 + rise, .013 + z * .20),
        (x * .60 - .011, .151 + rise * .55, z * .76),
        (x, .081 + rise * .3, z),
        (x * 1.08, tip_y + .044, z + .010),
        (end_x, tip_y, end_z),
    ], width, .24, a)

# Short underlayers are interleaved between crown tips. Each finishes in a
# descending, outward-pointing wedge: no identical upward-curled hemline.
nape_specs = [
    (.17, -.068, .032), (.64, -.109, .036),
    (1.07, -.080, .037), (1.53, -.132, .039),
    (1.97, -.102, .037), (2.45, -.123, .034),
    (2.93, -.079, .029),
]
for i, (a, tip_y, width) in enumerate(nape_specs):
    x = math.cos(a) * .112
    z = .027 + math.sin(a) * .108
    turn = -.17 if a < math.pi / 2 else .17
    lock('Layered nape %02d' % i, [
        (x * .83, .051 - (i % 3) * .008, z * .89),
        (x * 1.02, .002, z + .003),
        (x * 1.13, tip_y + .031, z + .016),
        (math.cos(a + turn) * .154, tip_y,
         .028 + math.sin(a + turn) * .140),
    ], width, .25, a)

# Four distinct heights make the frontal crest read as layered swept hair.
# Paths have long broad arcs and pointed terminal wedges, not a curled sausage.
lock('Crown swept crest', [
    (-.106, .162, -.004), (-.094, .217, -.025),
    (-.040, .242, -.055), (.035, .211, -.063),
    (.093, .177, -.045), (.136, .193, -.012),
], .033, .28)
lock('Hero swept upper', [
    (-.079, .179, -.055), (-.037, .186, -.090),
    (.040, .159, -.111), (.099, .138, -.083),
    (.146, .157, -.029),
], .039, .25)
lock('Hero swept forelock', [
    (-.087, .161, -.088), (-.047, .163, -.116),
    (.008, .129, -.139), (.040, .086, -.143),
    (.043, .047, -.128),
], .040, .25)
lock('Right swept wave', [
    (.008, .147, -.044), (.070, .133, -.086),
    (.115, .100, -.070), (.155, .117, -.018),
], .034, .25)
lock('Right lower wave', [
    (.061, .099, -.049), (.112, .073, -.075),
    (.143, .052, -.039), (.163, .074, -.006),
], .026, .24)
lock('Left swept temple', [
    (-.102, .150, -.044), (-.123, .116, -.078),
    (-.120, .072, -.089), (-.105, .022, -.082),
], .027, .26)

# Fine sideburns frame the ear without turning into a row of dangling strands.
for side in [-1, 1]:
    lock('Layered temple', [
        (side * .115, .063, -.039),
        (side * .129, .023, -.034),
        (side * .117, -.020, -.046),
    ], .019, .27, 0 if side > 0 else math.pi)

# The helper already interpolates smooth paths and shades faces smoothly.
# Global subdivision shortened the narrow ends into rounded lobes; retain the
# authored taper instead. Twelve vertices per section avoid a polygonal outline.

# The broad frontal waves are rounded like sculpted hair; nape tips retain their taper.
for obj in list(head.children):
    if obj.type=='MESH' and obj.name.startswith(('Crown swept','Hero swept')):
        soften(obj,1)
