# 06: Apply the chosen name

**What to build:** The game has its name, in every document that describes it and in the tracker directory that carries it. ADR-0008 stops being a proposal.

**Blocked by:** 05 (Put the slate to my wife).

**Status:** ready-for-agent

**Scope, measured 2026-09-04:** 150 occurrences of "Mind-Meld". `docs/design-brief.md` (9), `.scratch/naming/issues/01-the-games-real-name.md` (10), ADRs 0004 / 0005 / 0007 / 0008, `docs/deploy.md`, `docs/research/two-player-communication-mechanics.md`, `docs/research/model-selection-for-play.md`, `lib/meaning_game/steward/author.ex` and `assay.ex` (one each, in prose), and `.scratch/mind-meld/` — a spec plus 10 issues, which is a `git mv` and not only a `sed`.

**The four naming research notes keep saying "Mind-Meld".** `name-mind-meld-availability.md` alone holds 61 of the 150, and all four are dated primary sources *about* that name. Renaming them would falsify the record that justified the decision.

- [ ] The design brief, the spec, ADRs 0004 / 0005 / 0007 and the deploy doc carry the chosen name
- [ ] `.scratch/mind-meld/` is renamed, and its ticket paths and internal references follow
- [ ] The prose mentions in `lib/` are updated
- [ ] `CONTEXT.md` is checked for any surviving working-title reference
- [ ] The design brief's two "Naming" bullets move from Open questions to Settled decisions, including the umbrella term now settled by ADR-0009
- [ ] ADR-0008's status goes `proposed` → `accepted`, and it records which name won and how she read the others
- [ ] The four naming research notes are left untouched
