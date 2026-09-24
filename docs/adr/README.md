# Architecture decisions

One file per decision that a future reader might otherwise undo by accident. They are written in
the `codebase-design` vocabulary — **module**, **interface**, **depth**, **seam**, **adapter**,
**leverage**, **locality** — and in the domain language of `CONTEXT.md`.

An ADR is not a rule. It records what was decided, what it cost, and what would make it worth
reopening. If the friction it names has changed, reopen it.

| # | Decision |
|---|---|
| [0001](0001-ground-drive.md) | One GroundDrive behind every wheeled vehicle |
| [0002](0002-control-scheme.md) | The controlled thing owns what the keys mean |
| [0003](0003-rider-questions.md) | The Rider answers questions; Mode is not the interface |
| [0004](0004-panel-stack.md) | One modal protocol, in one place |
| [0005](0005-resident-type.md) | The Resident is a type, and owns its own persistence |
| [0006](0006-view-pool.md) | A pool owns whether a view exists; the EntityManager owns how much it runs |
| [0007](0007-recipe-extent.md) | A Recipe declares how far its geometry reaches |
| [0008](0008-hub-surfaces.md) | A Hub declares its surfaces; the geometry is derived from them |
| [0009](0009-ground-and-map-contract.md) | Two named ground queries, and a checked map contract |
| [0010](0010-outer-world.md) | The outer world is generated offline and answered by one lattice |
