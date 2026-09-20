# Simulation overhaul and adversarial review

Implemented explicit resident states for resting, travelling, working, yielding, unloading and blocked routes. Failed routes retry without inventing deliveries or work. Persistence now carries destination/state, validates route cursors, supports empty routines and normalizes weekly schedule lookup. Resident traffic uses spatial neighbor buckets; autopilot shares the grade-aware AStar road network rather than building a quadratic graph and running quadratic Dijkstra.

Delivery handoffs reject reentrant transitions and keep a bounded receipt history with the wallet. Loading restores cargo without generating collection/payment transactions and publishes state only after restoration.

Independent critics:
- World agent reviewed resident persistence, neighbor buckets and AStar changes. No blocking defect; unused legacy graph fields removed. Static navigation is built once; dynamically adding roads after autopilot setup would require rebuilding/replanning.
- Controls agent found an intermediate payout snapshot bug: a wallet listener could save completed job index with DONE stage. Corrected by committing next job before publishing payment, guarding restoration, and adding wallet-listener snapshot regression.

Validation: life_tests passed (0 failures); delivery_tests passed (0 failures), including final callback publication cleanup; journey_tests passed after fresh editor import. Regression tests exercise failed-route nonpayment, destination/state roundtrip, empty schedules, recursive delivery listeners, wallet callback saves and one receipt per completed handoff.

Limitations: these are simulation and correctness upgrades; they do not establish AAA quality or new narrative content. One pre-existing ObjectDB shutdown leak warning remains in delivery/journey test exits.
