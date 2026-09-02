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
