# Mission

## The want

> "Learn about this code so I can expand upon it. Do manual coding, because all of it is
> AI-written shit."

Desert Delivery is ~11,000 lines of GDScript that an agent wrote. It runs, it is tested, and it
is not *his*. The point of this workspace is to change that: to be able to open any file in the
repo, know why it is shaped the way it is, and add the next feature by hand.

## Why now

Sept 2026: a twelve-candidate architecture refactor moved most of the codebase. It is in better
shape than it was — one `GroundDrive` instead of two copies, a `Resident` class instead of a
25-key dictionary, a `PanelStack` that owns the modal protocol. But "better shape" written by
somebody else is still somebody else's code. The refactor made the seams clean, which makes this
the best possible moment to learn where they are.

## What success looks like

- Opens `island.gd` cold and can say what each section is doing, and why it is in that file.
- Adds a new feature — a vehicle, a place, a control, a prop — entirely by hand, no agent.
- Can predict where a change belongs *before* grepping, and is usually right.
- Runs the test suites, reads a failure, and fixes it without asking.

## Out of scope

- Godot's editor, animation, shaders, art pipeline — unless a lesson needs them.
- General software-architecture theory for its own sake. The vocabulary is a **tool** for reading
  this repo, not the subject.
- C#, GDExtension, engine internals.
- Rewriting what exists. The aim is to extend, not to relitigate.

## Signals I'm on track

1. He writes a line of GDScript in this repo without being given the line.
2. He asks "should that live in X or Y?" — a question you can only ask with a map in your head.
3. He catches something I did that was wrong.
