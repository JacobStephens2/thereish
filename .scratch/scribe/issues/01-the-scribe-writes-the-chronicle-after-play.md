# 01: The Scribe writes the Chronicle after play

**What to build:** The third of the Steward's roles (CONTEXT.md: "the machine role that writes the Chronicle after play — records, recaps, callbacks"). Today the Chronicle is an event log with a book view and a Markdown export, and the Steward composes a plain digest of it for the Author; nobody writes prose. The Scribe writes a recap of each evening's Pages into the Chronicle, in the players' own words back to them, and plants callbacks — the line next month that remembers tonight's candy cane.

**Blocked by:** nothing. The group-play slice builds the Scribe's first, smallest job (naming a new Room from the creator's Chronicle) and the role's seat in the Steward's configuration; this ticket is the role proper.

**Status:** needs-triage

Filed 2026-09-04 during the group-play grilling, when Jacob asked whether the Scribe existed yet. It does not; the Mind-Meld spec put it out of scope ("the Chronicle records events; narrative recaps come later").

**What the design brief already settled about it.** The model is `claude-fable-5-1`, measured in the Steward prototype as writing valid but long recaps, which is why the deterministic gate is part of the role rather than an afterthought: Scribe prose passes a Vale gate (a Scribe style, write-good, proselint, and Vale's AiTells package, adopted per ADR-0009) with one model repair pass (design law 14). Shell out only for Vale. Recaps are player-visible and player-editable like everything else in the Chronicle (design law 5), and a recap never rewrites a grade (ADR-0006).

**Open questions**
- When it runs: at Page close, at the end of an evening, or overnight. The brief's post-couch-night roadmap has Oban for overnight runs; a supervised task is enough before that.
- What a callback is allowed to touch: the Author's next Pages, the Assayer's quip, the book only.
- Whether the digest the Author reads becomes the Scribe's output rather than a computed view.
- Which model writes recaps. The brief measured `claude-fable-5-1` for them, but the role's first job (naming a Room) runs on Gemini 3.8 Flash at low effort because nobody waits at a table for a Code. If recaps want Fable, the role's configuration needs a model per job rather than per role.

- [ ] A `scribe` role in the Steward's configuration, with the fake adapter answering it in tests
- [ ] A recap written for a closed Page and stored as a Chronicle event
- [ ] The Vale gate with one repair pass, and a recap that fails it is not shown
- [ ] Recaps appear in the book view and the Markdown export, editable like the rest
- [ ] One callback woven into a later Page, visible to the players
