# Rock library: exact geometry, deferred performance conclusion

The streamed recipe profiler previously reported a 50.487 ms indivisible recipe.
RockGen generated unique procedural meshes synchronously on first request. This
change moves known world mesh generation to an authoring bake and lazily loads
individual compressed resources at runtime. It does not change geometry, LOD,
material selection, transforms, collision hulls or concave collision faces.

Schema 2 contains 180 pieces totalling 23,040,663 bytes (21.97 MiB). Its forced
bake performed 5,068.838 ms of procedural mesh generation over the full world.
That aggregate is authoring cost, not a measured frame-time improvement.

`rock-library-tests.log` records eight passing checks, including bytewise parity
of every mesh attribute in both LODs and all hulls for all 180 pieces regenerated
from stored exact parameters. It also verifies lazy disk loading, memory reuse,
unknown-parameter fallback, effective defaults, distinct close floating-point
keys, and transformed convex/concave collision equality.

The bake requires `--rebuild-rock-library`, which bypasses preexisting disk
resources before world generation. Canonical sorted Variant bytes preserve
parameter precision, and a schema version invalidates changed algorithms.
Invalid/missing resources fall back to generation. The baker removes obsolete
hashed resource files only in its owned output directory after successful saves.

Runtime attribution separately records procedural mesh bake, resource load and
collider construction time inside the slowest atomic streamed recipe. The
parent's actual traversal determines whether this removes the measured stall;
no result is inferred from aggregate bake timings. Individual loads/colliders
and other recipe builders remain indivisible under the soft streaming budget.

Export limitation: no export preset exists. Selected-resource exports must
explicitly include `assets/rocks/generated/*.res` because lookup paths are
constructed dynamically. Default all-resource exports include these files.
The directory README documents this requirement and reproducible bake/tests.

Independent adversarial review by the simulation agent accepted this change with
no source blocker after auditing the keys, fallback types, forced bake, parity
test logic and actual 180-piece/8-pass log, and export documentation. Its optional
malformed on-disk metadata probe was deferred during the parent's timed traversal
to avoid contaminating performance measurements.
