# 0004 — One modal protocol, in one place

**Status:** accepted · September 2026

## Context

The courier Counter and the field Journal each hand-rolled the same five-part protocol: remember
the mouse mode, free the mouse, block the player's controls, pause delivery handoffs, and latch a
one-frame guard so the closing click could not fall through. `Game` re-derived "is anything modal"
by naming both panels, in two places.

Two adapters, no seam — and the copies had diverged into a live bug. Opening the Counter paused
handoffs; opening the Journal did not. `DeliverySystem` completes a stage after 0.5 s stopped
inside a Ring, and reading the Journal is exactly "stopped", so opening the journal while parked
in a pickup Ring collected the Package behind the book.

## Decision

`PanelStack` owns the protocol. Panels call `open(self)` / `close(self)`; `Game` asks
`panels.any_open()` and `panels.just_closed()`.

## Consequences

- A third panel is layout and content only.
- The bug is not expressible: pausing handoffs is a property of something being open.
- Three tests cover it, including the one that would have caught it.

## Reopen if

A panel needs to be open *without* blocking gameplay (a minimap overlay, a toast). That is not a
modal — do not open it through the stack.
