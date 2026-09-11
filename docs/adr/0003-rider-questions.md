# 0003 — The Rider answers questions; Mode is not the interface

**Status:** accepted · September 2026

## Context

`CONTEXT.md` said everyone "reads `rider.mode` or reacts to `mode_changed`", and that is exactly
what went wrong: because the enum was the interface, each caller re-derived the *policy* it
actually wanted, differently. "Can a handover happen" was spelled as a three-mode list in
`delivery_system`; "is the courier stopped" was spelled again in `journey_system` with its own
thresholds. The same question — who is the courier and where is he — was answered independently
in four places, two phrased with `is_riding()` and two with `is_on_foot()`. They agreed only
because `Mode` happened to have five members.

## Decision

The Rider keeps the transitions, which it owns well, and answers the questions callers actually
ask: `courier()`, `active_vehicle()`, `can_hand_over()`, `is_stopped()`, `is_aiming()`. `mode`
stays for the debug overlay and the save file. `last_intent` is private — a ControlIntent stops at
the Rider.

## Consequences

- Adding a Mode is a Rider-only change instead of a repo-wide grep with silent failure modes.
- Each predicate is directly assertable on a Rider with stubbed bodies.

## Reopen if

A caller needs something genuinely mode-shaped that no question covers. Add a question, not a
mode check.
