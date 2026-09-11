# Resources

Curated. Format: [RESOURCES-FORMAT.md](./RESOURCES-FORMAT.md).

## The engine

### GDScript reference — Godot Engine docs
- **Link:** https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_basics.html
- **Type:** reference
- **Trust:** primary
- **Use it for:** syntax you are about to type — typed variables, `:=`, signals, inner classes,
  properties with `get:`/`set:`. The repo uses static typing everywhere; this is the spec for it.
- **Read:** not yet

### Using InputEvent — Godot Engine docs
- **Link:** https://docs.godotengine.org/en/stable/tutorials/inputs/inputevent.html
- **Type:** reference
- **Trust:** primary
- **Use it for:** how an action in the InputMap becomes something `Input.is_action_pressed()` can
  answer. This is the layer directly beneath `Controls.Keyboard`.
- **Read:** not yet

### Input class reference — Godot Engine docs
- **Link:** https://docs.godotengine.org/en/stable/classes/class_input.html
- **Type:** reference
- **Trust:** primary
- **Use it for:** the exact difference between `is_action_pressed` (held) and
  `is_action_just_pressed` (this frame only). The repo depends on that difference.
- **Read:** not yet

### Godot Docs, 4.7 branch — landing page
- **Link:** https://docs.godotengine.org/en/stable/index.html
- **Type:** reference
- **Trust:** primary
- **Use it for:** everything else. 4.7 is the current stable branch and the version this project
  targets, so `stable` links are correct for us — worth knowing, because most tutorials online
  are for 4.2/4.3 and some APIs moved.
- **Read:** not yet

## The design vocabulary

### A Philosophy of Software Design — John Ousterhout
- **Link:** https://web.stanford.edu/~ouster/cgi-bin/book.php
- **Type:** book
- **Trust:** primary
- **Use it for:** where "deep module" and "shallow module" come from. Short (~190pp) and readable.
- **Caveat:** this workspace **rejects one of its definitions.** Ousterhout measures depth as the
  ratio of implementation size to interface size, which rewards padding the implementation. We
  measure depth as *leverage*: how much behaviour a caller gets per unit of interface they have to
  learn. Same word, better definition. Do not import the ratio.
- **Read:** not yet

### CS 190: Software Design Studio — Ousterhout, Stanford
- **Link:** https://web.stanford.edu/~ouster/cs190-winter23/
- **Type:** course
- **Trust:** primary
- **Use it for:** the lecture notes are free and are the book's material with worked examples.
- **Read:** not yet

## This repo (local, and as trustworthy as anything above)

### CONTEXT.md — the domain glossary
- **Link:** `../CONTEXT.md`
- **Type:** reference
- **Trust:** primary
- **Use it for:** what a word means *here*. Rider, Mode, Hub, Place, Ring, Recipe, Station,
  Resident, Panel, GroundDrive. If a lesson uses a domain noun, this is where it is defined.
- **Read:** skimmed

### ARCHITECTURE.md — the shape of the thing
- **Link:** `../ARCHITECTURE.md`
- **Type:** reference
- **Trust:** primary
- **Use it for:** the folder map, the runtime tree, the generation flow, and the list of
  invariants the tests hold.
- **Read:** skimmed

### docs/adr/ — nine architecture decision records
- **Link:** `../docs/adr/`
- **Type:** reference
- **Trust:** primary
- **Use it for:** *why* something is shaped the way it is, what it cost, and what would make it
  worth reopening. When a lesson says "this used to be two copies", the ADR is the receipt.
- **Read:** not yet

## Communities — not yet chosen

Wisdom comes from people, not documents, and nothing here is a substitute. Candidates to look at
when there is something real to ask (deliberately not committed to yet):

- The official Godot community hub — https://godotengine.org/community/
- r/godot — high volume, mixed quality, good for "is this normal?"

**Open question for the learner:** do you want to be pointed at a community at all, or is this a
solo project you would rather keep to yourself? Say so and I will stop suggesting it.
