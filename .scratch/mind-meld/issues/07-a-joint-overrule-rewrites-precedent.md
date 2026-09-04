# 07: The couple overrules a grade, and their ruling becomes house law

**What to build:** The Assayer says 41. They both think it was a Meld. One of them proposes an overrule, the other agrees, and the grade becomes theirs. The next time those words meet, the game rules the way the couple ruled. The Chronicle keeps both what the machine said and what they said.

Design law 3: humans hold final authority, and an overrule is a story rather than a correction.

**Blocked by:** 06.

**Status:** resolved

- [x] Any Seat can propose an overrule from the reveal
- [x] An overrule takes effect only when every Seat in the Room agrees. Neither player can rewrite a grade alone
- [x] Rules events extend to `overrule_proposed` and `overrule_agreed`; the rules module stays pure
- [x] An agreed overrule writes the couple's ruling into the same cache key, so it is what future identical inputs inherit
- [x] A joint overrule is the only thing in the system that rewrites precedent
- [x] The Chronicle records the overrule with the machine's original ruling, the couple's ruling, and who proposed it
- [x] The proposal is visible on both phones and on the stage while it is pending, and expires cleanly if the Page moves on
- [x] Rules tests cover unanimity required, a declined proposal leaving the grade untouched, and a three-Seat Room needing all three
- [x] A Steward test confirms the overruled key returns the couple's ruling afterwards

## Comments

**Joint overrules rewrite precedent.** `MeaningGame.Steward.Precedent.overrule/5` and `MeaningGame.Steward.overrule/3` rewrite the precedent row for that key using `on_conflict: {:replace, [:closeness, :reasoning, :quip, :updated_at]}`, making future identical pairs inherit the couple's house law directly from the cache without calling the model provider.

**Pure Game rules and unanimity.** `MeaningGame.Game` handles `{:overrule_proposed, ...}`, `{:overrule_agreed, ...}`, and `{:overrule_declined, ...}` purely with zero I/O. An overrule requires unanimous agreement across all Seats in the Room. When agreed, it transitions the verdict to closeness 100 (`deep meld`), emits `{:overrule, overrule_data}`, and if the Page melds and closes, emits `{:chronicle, ...}` without duplicate writes if already closed. If declined, or when an attempt advances or new page starts, any pending overrule proposal expires cleanly.

**Chronicle records both rulings.** The `chronicle_overrules` table (`MeaningGame.Chronicle.Overrule`) records the anchors, bridges, machine's original closeness/reasoning/quip, the couple's closeness/reasoning/quip, and the proposing seat ID.

**Room broadcast and LiveView visibility.** `MeaningGame.Rooms` provides `propose_overrule/3`, `agree_overrule/2`, and `decline_overrule/2`. The `overrule_banner` component renders the pending status and voting actions in real-time across both phones and the stage.
