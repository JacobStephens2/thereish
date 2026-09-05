# 10: Thereish, on every screen and in every document

**What to build:** The game is called Thereish (ADR-0008) and nothing calls it anything else. This ticket carries naming issue 06 in full, in one commit so the rename is one diff: every page title and heading; the prose in the Author and Assayer prompt modules; the design brief, ADRs 0004 / 0005 / 0007, the deploy doc and the two research notes that name the mechanic by its working title; the README; and the resolved tracker directory (`.scratch/resolved/mind-meld/`) moved to a Thereish name with its internal references. The four naming research notes and round four stay untouched, being dated records about the names. `meld.stephens.page` is not touched — that is naming issue 07. Checklist: `.scratch/naming/issues/06-apply-the-chosen-name.md`.

**Blocked by:** 02 (The Page is written at the table), 04 (Almost, meld at 90, and any Bridge you like).

**Status:** resolved

- [x] Every rendered title and heading says Thereish; the root layout's default title too
- [x] No "Mind-Meld" / "Mind Meld" remains in `lib/`, the design brief, ADRs 0004 / 0005 / 0007, the deploy doc, the README, or the two non-naming research notes, except where a sentence records history ("the working title was …")
- [x] `.scratch/resolved/mind-meld/` is moved to `.scratch/resolved/thereish/` and its internal references follow
- [x] `CONTEXT.md` has no surviving working-title reference
- [x] The four naming research notes and round four are unchanged
- [x] Naming issue 06's boxes are ticked and it is moved to `issues/resolved/`; the design brief's status line and settled decisions read correctly after the sweep
- [x] One commit; the suite green; deployed

## Comments

Applied in full:
1. Every rendered title and heading says Thereish, and the root layout's default title is Thereish (`root.html.heex`, `front_live.ex`, `room_live.ex`, `stage_live.ex`, `check_live.ex`).
2. Scribe prompt prose in `recap.ex` and `naming.ex` updated to Thereish.
3. Design brief, ADRs 0004 / 0005 / 0007, deploy doc, README, NOTICE, CONTEXT.md, and the two non-naming research notes updated to Thereish (retaining historical working title references where appropriate).
4. Moved `.scratch/resolved/mind-meld/` to `.scratch/resolved/thereish/` with internal references and cross-references updated.
5. The four naming clearance notes and round four remained completely untouched.
6. Naming issue 06 checked and moved to `.scratch/naming/issues/resolved/06-apply-the-chosen-name.md`.
7. Tests added/updated, test suite green.
