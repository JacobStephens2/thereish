# 07: The couple overrules a grade, and their ruling becomes house law

**What to build:** The Assayer says 41. They both think it was a Meld. One of them proposes an overrule, the other agrees, and the grade becomes theirs. The next time those words meet, the game rules the way the couple ruled. The Chronicle keeps both what the machine said and what they said.

Design law 3: humans hold final authority, and an overrule is a story rather than a correction.

**Blocked by:** 06.

**Status:** ready-for-agent

- [ ] Any Seat can propose an overrule from the reveal
- [ ] An overrule takes effect only when every Seat in the Room agrees. Neither player can rewrite a grade alone
- [ ] Rules events extend to `overrule_proposed` and `overrule_agreed`; the rules module stays pure
- [ ] An agreed overrule writes the couple's ruling into the same cache key, so it is what future identical inputs inherit
- [ ] A joint overrule is the only thing in the system that rewrites precedent
- [ ] The Chronicle records the overrule with the machine's original ruling, the couple's ruling, and who proposed it
- [ ] The proposal is visible on both phones and on the stage while it is pending, and expires cleanly if the Page moves on
- [ ] Rules tests cover unanimity required, a declined proposal leaving the grade untouched, and a three-Seat Room needing all three
- [ ] A Keeper test confirms the overruled key returns the couple's ruling afterwards
