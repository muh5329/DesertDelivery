# 0001 — The mission is authorship, not architecture

**Date:** 2026-09-07
**Status:** current

## What happened

I opened this workspace offering "deep module design" as the topic, and asked what the win was —
with four options, all of them framed as *learning a discipline*: do the next refactor, judge code
you didn't write, design it right first time, talk about it precisely.

He answered none of them. He wrote:

> "Learn about this code so i can expand upon it. Do manual coding because all of it is AI written
> shit."

## What I now believe

The subject is **Desert Delivery**, not software design. Design vocabulary is a *lens* for reading
his own repo, and it earns its place only when it makes a specific file easier to understand or a
specific change easier to place. A lesson that teaches a principle without landing on a real file
path is off-mission.

Underneath the request is a problem of **ownership**. He has ~11,000 lines that run, are tested,
and are not his. That is not a knowledge gap — it is an authorship gap, and it closes by typing,
not by reading. Hence the standing rule now in `NOTES.md`: **he writes the code; I give the shape.**

The frustration is also information, not noise. "AI written shit" says the current state is not
acceptable to him even though the tests pass. Passing tests were never the goal.

## What I got wrong first

Two things, and the second is worse.

1. I offered a topic list drawn from what *I* had just spent a session doing. The vocabulary was
   fresh in my context, so I assumed it was the thing worth learning. It was my frame, not his.
2. I built the options around *becoming better at architecture* — a discipline to acquire. He
   wants a **codebase to own**. Those produce completely different lessons: one starts with the
   deletion test, the other starts with "here is where a keypress enters your game".

The tell I should have caught: all four of my options were abstractions, and none of them named a
file.

## What this unlocks

- Lesson 01 could be scoped correctly: one real path through the real repo, ending in a feature he
  writes himself.
- The vocabulary budget in `NOTES.md` — at most two terms per lesson, only when a lesson needs
  them. Lesson 01 spent *interface* and *seam* and nothing else.
- A test for every future lesson: **does it name a file he will open?** If not, rewrite it.

## Open questions

- He has not said whether he wants a community. `RESOURCES.md` asks once and then drops it.

## Addendum, 2026-09-07 — fluency answered, and it moves the ceiling

I had written "his GDScript fluency is unknown; watch which step snags". He answered directly:
**proficient in GDScript.**

That collapses one of the two things a lesson could be teaching. The gap is not the language and
never was — it is (a) this repo, which an agent wrote, and (b) the design vocabulary for talking
about its shape. So difficulty has to come from **judgement**, not from typing.

Lesson 01's hand task was retuned the moment he said it. It had been six steps of "write this one
line", which for him is a five-minute formality. It is now:

- **Part A**, the horn — unchanged in substance, explicitly framed as a warm-up, hints stripped to
  the one silent failure mode (`ACTIONS`).
- **Part B** — put the horn in the three *wrong* places on purpose, predict the behavioural
  difference for each first, then verify. Deliberate error as the teaching device.
- **Part C** — two predictions with no typing at all. One has a genuinely pleasing answer
  (`TruckScheme` never reaches `super.map()` in cargo mode, so the horn is silent while packing
  without anyone implementing that). The other asks him to decide *which module owns a rule* —
  Foot, Rider or Player — which is a design call with no syntactic component.

**The general correction:** for this learner, "make it harder" must never mean "write more code".
It means remove the scaffolding from the *decision*. A task he can complete by knowing GDScript is
a task that teaches him nothing.
