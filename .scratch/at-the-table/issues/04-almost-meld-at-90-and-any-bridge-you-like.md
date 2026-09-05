# 04: Almost, meld at 90, and any Bridge you like

**What to build:** The ladder reads miss 0 / adjacent 30 / close 55 / almost 75 / meld 90 / deep meld 100; a Meld still ends the Page and a joint overrule writes the meld floor. A Bridge may be any word or short phrase — "Gold Rush", "Viking beaches" — barred only when one of its words equals or shares a root with a word of a Bookend or a Bridge this Page has already used, and the refusal names the collision; the dictionary, single-word and profanity checks are gone for players. The Assayer moves to `assay-3`: Bridges with players' names, phrases allowed, the Page's earlier Attempts and the Gives in the request, and the rubric rewritten for the new rungs. Spec sections: The Game (Legality, The Ladder), The Steward (`assay-3`).

**Blocked by:** 01 (Anchors become Bookends).

**Status:** ready-for-agent

- [ ] The ladder's bands are the six above, as configuration; 74 reads close, 75 and 89 almost, 90 meld and closes the Page, 100 deep meld; the band name `almost` appears wherever bands are named
- [ ] A proposed overrule defaults to the meld floor read from the Ladder, not 100
- [ ] Legality: a Bridge is trimmed, whitespace-collapsed and downcased; non-empty; at most 40 characters; letters, digits, spaces, hyphens and apostrophes; illegal if any of its words equals or shares a root (stem, prefix with the three-letter floor, inflection) with any word of any barred word or phrase — the Bookends of every Attempt so far and every Bridge committed in this Page; the refusal names the word it collided with. "Viking beaches" commits; "lava rock" after "lava" is refused naming *lava*; a carried Bridge is barred as the next Attempt's Bookend
- [ ] The dictionary, single-word and profanity checks no longer apply to player Bridges; the module still gates the Author's Bookends and still owns the dictionary for Codes
- [ ] The phone's live validation and the commit both use the new rule and show the same message
- [ ] `assay-3`: the request carries the Bookends, every Bridge with its player's name in roster order, the Page's earlier Attempts (Bookends and Bridges) and the Gives with names; the rubric is 100 same word or plain inflection, 90–99 one idea however worded, 75–89 same neighbourhood distinct framing, 55–74 related, 30–54 adjacent, 0–29 different roads; the quip may name players and draw on anything in the request; the furthest-pair check and the Precedent's both-orderings key are unchanged; the version bump orphans `assay-2` precedents
- [ ] Rules tests for the ladder, the overrule floor and every legality case; Steward tests for `assay-3`'s request and a rejected furthest pair; the Fake grades phrases
- [ ] Deployed; the Assayer's whole-verdict p95 under `assay-3` measured from the VPS and recorded here
