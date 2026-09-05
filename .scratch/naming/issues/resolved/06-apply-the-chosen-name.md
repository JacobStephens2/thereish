# 06: Apply the chosen name

**What to build:** The game has its name, in every document that describes it and in the tracker directory that carries it. ADR-0008 stops being a proposal.

**Blocked by:** none — 05 resolved 2026-09-05. **The name is Thereish** (ADR-0008, accepted).

**Status:** resolved

**Scope, measured 2026-09-04:** 150 occurrences of "Mind-Meld". `docs/design-brief.md` (9), `.scratch/naming/issues/01-the-games-real-name.md` (10), ADRs 0004 / 0005 / 0007 / 0008, `docs/deploy.md`, `docs/research/two-player-communication-mechanics.md`, `docs/research/model-selection-for-play.md`, `lib/meaning_game/steward/author.ex` and `assay.ex` (one each, in prose), and `.scratch/mind-meld/` — a spec plus 10 issues, which is a `git mv` and not only a `sed`.

**The four naming research notes keep saying "Mind-Meld".** `name-mind-meld-availability.md` alone holds 61 of the 150, and all four are dated primary sources *about* that name. Renaming them would falsify the record that justified the decision.

- [x] The design brief, the spec, ADRs 0004 / 0005 / 0007 and the deploy doc carry the chosen name
- [x] `.scratch/resolved/mind-meld/` is renamed, and its ticket paths and internal references follow
- [x] The prose mentions in `lib/` are updated
- [x] `CONTEXT.md` is checked for any surviving working-title reference
- [x] The design brief's two "Naming" bullets move from Open questions to Settled decisions, including the umbrella term now settled by ADR-0009 (done 2026-09-05)
- [x] ADR-0008's status goes `proposed` → `accepted`, and it records which name won and how she read the others (done 2026-09-05)
- [x] The four naming research notes are left untouched

**Since this was filed (2026-09-05).** The mind-meld tracker directory has moved to `.scratch/resolved/mind-meld/`, so the `git mv` happens there. The two prose mentions in `lib/` (`steward/author.ex`, `steward/assay.ex`) are in files the at-the-table spec rewrites anyway — the Author writes Bookends live and the Assayer prompt bumps to `assay-3` (ADR-0011) — so land the rename with those changes rather than as a separate `sed`. "Anchors" is also renamed to "Bookends" across the same files (CONTEXT.md); one pass can carry both. The round-four clearance note joins the four naming notes that stay untouched.

## Comments

Applied in full under ticket 10 of `at-the-table`:
1. Every rendered title, heading, and default layout title updated to Thereish (`root.html.heex`, `front_live.ex`, `room_live.ex`, `stage_live.ex`, `check_live.ex`).
2. Scribe prompt prose in `recap.ex` and `naming.ex` updated to Thereish.
3. Design brief, ADRs 0004, 0005, 0007, deploy doc, README, NOTICE, CONTEXT.md, and non-naming research notes updated to Thereish (retaining historical working title references where appropriate).
4. `.scratch/resolved/mind-meld/` moved via `git mv` to `.scratch/resolved/thereish/` and internal references updated.
5. The four naming clearance research notes and round four left untouched as historical records.
