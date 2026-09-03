# Prototype branch — throwaway, never merged

`stage0-page-machines.PROTOTYPE.html` — Stage 0 of the couch-night prototype.
Open it by double-clicking; no server, no install, no build.

**The question it answers:** do the rules of the two candidates hold up when pushed
through real cases, before any phones, servers or real models exist?

Inside: a pure `Game` module (`init` / `apply(state, event)` / `view(state, seat)`,
plus the deterministic clue-legality gate) that is meant to lift into Elixir as
`Game.apply/2` and `Game.view/2`, and a fake `Keeper` (Author + Assayer stubs) that
keeps the real contracts — pre-generated Pages, schema-shaped verdicts, a fixed 2.5 s
reveal beat, both orderings graded, every verdict cached, reasoning always shown,
joint overrule recorded. Everything below the "THROWAWAY PAGE SHELL" banner is
disposable DOM code.

Six guided walkthroughs: clover happy path · the authored decoy bites · illegal clue
then joint overrule · Mind-Meld converging over three attempts · the same ruling twice
(cache) · moves that should be illegal.

Verdicts from couch night go back into `docs/design-brief.md` on `master`.

## Verdict (Jacob, 2026-09-02 — Stage 0, laptop, solo click-through)

**Mind-Meld beat Chronicle Clover, and the graded number is why.** Jacob got "a pang of
smirk" at a 24/100 closeness rating — the Assayer's score landed as a *punchline*, not as
a referee's ruling. That is the clever-aha the whole project is aimed at, produced by a
stub Assayer with a toy heuristic.

**Chronicle Clover left him wanting the physical cards.** So Clover's pleasure is spatial:
you shuffle cards around and *see* the relationships resolve. Four dropdowns in a list
kill it. Simulable in UI (drag, rotate, a real clover layout) — but that is significant
work, and it means the candidate cannot be fairly judged until it is built.

Caveat: this is Jacob's read, not my wife's, and she is the So Clover lover and the
actual bar.
