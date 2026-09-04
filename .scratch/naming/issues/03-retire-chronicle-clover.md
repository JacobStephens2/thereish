# 03: Retire Chronicle Clover from the docs

**What to build:** The repository stops describing the clover as a live option. It was retired during prototyping and Melissa never played it, so the docs should say retired rather than parked — the two words mean different things and only one of them is true.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

This is load-bearing for the naming decision rather than tidying: the clover being dead is why the game and the product are one object, and why the name being chosen is the game's name. A reader who finds the docs saying "parked… revivable" will re-derive the wrong tree.

Note `docs/design-brief.md` currently reads *"Chronicle Clover stays parked on `prototype/stage0-page-machines`, revivable if Melissa misses it."* The branch and its prototype stay where they are as a primary source; it is the **status** that changes, not the history.

- [ ] `docs/design-brief.md` records the clover retired, unplayed, with the date
- [ ] The A/B framing that assumed two Page machines is corrected wherever it survives in the brief
- [ ] `.scratch/mind-meld/spec.md` and ADR-0004's cross-references no longer imply a live second game
- [ ] `lib/meaning_game/steward/fake.ex` no longer refers to the clover as current
- [ ] Research notes are left alone — they are dated primary sources, not statements about today
