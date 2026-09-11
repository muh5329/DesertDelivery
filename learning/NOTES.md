# Notes

Working notes and stated preferences. Read before designing a lesson.

## Preferences

- **He types the code, not me.** The whole reason for this workspace is that the codebase was
  written by an agent. A lesson that hands over finished code defeats it. Lessons give the
  *shape* — which file, which function, what it must do — and he writes the lines.
  Exception: showing existing repo code so he can read it. That is reading, not writing.
- Blunt is fine. He described his own codebase as "AI-written shit". No need to soften findings
  or be reassuring about the state of things.
- **Proficient in GDScript** (stated 7 Sep 2026). Do not teach syntax, do not walk him through a
  line, do not explain what a signal is. His gap is *this codebase* and the design vocabulary —
  not the language. Practically: hints point at a design question, never at how to write the code,
  and hand tasks are judged on placement decisions rather than on whether they compile.
- One project only: Desert Delivery. Every example comes from the real repo, real file paths,
  real function names. No invented `Foo`/`Bar`.

## Working notes

- Godot **4.7**, Forward Plus. GDScript, static typing used throughout the repo.
- Terrain3D is a GDExtension with no arm64 Linux build — the `--facet` flag is the fallback path.
  He runs on a Mac, so he gets the real Terrain3D path.
- Test suites he can run himself:
  `godot --headless --path . -- --test=architecture_tests` (also feature, edge, life, journey,
  truck, delivery, riding_feel). All eight pass as of 7 Sep 2026.
- The repo's own `CONTEXT.md`, `ARCHITECTURE.md` and `docs/adr/` are high-trust local sources
  and should be cited like any other primary source.

## Vocabulary budget

He is new to the design vocabulary. Introduce **at most two new terms per lesson**, and only
terms a lesson actually needs to make its point. Terms introduced so far:

- Lesson 0001: **interface**, **seam**.

Still unspent: module, depth, adapter, leverage, locality, the deletion test.

## Workspace mechanics

- Lessons live at `learning/lessons/`, open from disk with their assets alongside. I cannot open
  them for him: my shell is a headless Linux VM that can reach his files but not his browser. Give
  him the command instead — from the repo root:
  `open learning/lessons/<file>.html`
- `learning/` sits inside the game repo (his choice), so it shows up in `git status`. If that ever
  annoys him, it moves out or gets ignored — ask before doing either.
