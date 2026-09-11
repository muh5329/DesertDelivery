# 0007 — A Recipe declares how far its geometry reaches

**Status:** accepted · September 2026

## Context

`WorldDatabase.add(x, z, builder)` had an unstated invariant: the geometry the closure builds lies
inside the 60 m chunk containing `(x, z)`. Much of the generator violated it. An aqueduct spanning
~160 m, a Villa hub reaching 62 m in every direction, harbour boats 24 m along their pier and a
Town courtyard promenade at least 32 m long were all filed under a single chunk, so they appeared
and vanished with a chunk two rings away — while the courier was standing on them. Nothing in the
code or the tests could detect it.

## Decision

`Recipe` carries a `radius`. A recipe with an extent is filed into every chunk it overlaps and
claimed by whichever loads first; when that chunk unloads the recipe is released and offered to
the chunks still loaded.

## Consequences

- The extent is checkable, so it is checked: the test builds every oversize recipe into a
  throwaway node and measures what it produced. It immediately caught a 70 m guess for hubs that
  Cala Blanca overran by 12 m.
- `_at(x, z, builder)` still defaults to 0 for anything that fits in its own chunk.

## Reopen if

A recipe's geometry becomes genuinely unbounded (a road network, a shoreline). Split it per chunk
the way `_scatter_records` already does, rather than declaring a huge radius.
