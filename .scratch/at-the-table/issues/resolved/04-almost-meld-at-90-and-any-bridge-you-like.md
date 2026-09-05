# 04: Almost, meld at 90, and any Bridge you like

**What to build:** The ladder reads miss 0 / adjacent 30 / close 55 / almost 75 / meld 90 / deep meld 100; a Meld still ends the Page and a joint overrule writes the meld floor. A Bridge may be any word or short phrase — "Gold Rush", "Viking beaches" — barred only when one of its words equals or shares a root with a word of a Bookend or a Bridge this Page has already used, and the refusal names the collision; the dictionary, single-word and profanity checks are gone for players. The Assayer moves to `assay-3`: Bridges with players' names, phrases allowed, the Page's earlier Attempts and the Gives in the request, and the rubric rewritten for the new rungs. Spec sections: The Game (Legality, The Ladder), The Steward (`assay-3`).

**Blocked by:** 01 (Anchors become Bookends).

**Status:** resolved

- [x] The ladder's bands are the six above, as configuration; 74 reads close, 75 and 89 almost, 90 meld and closes the Page, 100 deep meld; the band name `almost` appears wherever bands are named
- [x] A proposed overrule defaults to the meld floor read from the Ladder, not 100
- [x] Legality: a Bridge is trimmed, whitespace-collapsed and downcased; non-empty; at most 40 characters; letters, digits, spaces, hyphens and apostrophes; illegal if any of its words equals or shares a root (stem, prefix with the three-letter floor, inflection) with any word of any barred word or phrase — the Bookends of every Attempt so far and every Bridge committed in this Page; the refusal names the word it collided with. "Viking beaches" commits; "lava rock" after "lava" is refused naming *lava*; a carried Bridge is barred as the next Attempt's Bookend
- [x] The dictionary, single-word and profanity checks no longer apply to player Bridges; the module still gates the Author's Bookends and still owns the dictionary for Codes
- [x] The phone's live validation and the commit both use the new rule and show the same message
- [x] `assay-3`: the request carries the Bookends, every Bridge with its player's name in roster order, the Page's earlier Attempts (Bookends and Bridges) and the Gives with names; the rubric is 100 same word or plain inflection, 90–99 one idea however worded, 75–89 same neighbourhood distinct framing, 55–74 related, 30–54 adjacent, 0–29 different roads; the quip may name players and draw on anything in the request; the furthest-pair check and the Precedent's both-orderings key are unchanged; the version bump orphans `assay-2` precedents
- [x] Rules tests for the ladder, the overrule floor and every legality case; Steward tests for `assay-3`'s request and a rejected furthest pair; the Fake grades phrases
- [ ] Deployed; the Assayer's whole-verdict p95 under `assay-3` measured from the VPS and recorded here

## Answer

1. **The Ladder & Overrule Floor**:
   - Configured the 6 bands in `config/config.exs`: `miss: 0, adjacent: 30, close: 55, almost: 75, meld: 90, deep_meld: 100`.
   - `MeaningGame.Ladder.meld_threshold/0` returns `90`; `Ladder.melded?/1` checks `>= 90`.
   - Added `"almost"` band presentation and band scripts across components and fallback pages (`lib/meaning_game/pages.ex`, `lib/meaning_game_web/components/room_components.ex`).
   - Overrule proposals default to `Ladder.meld_threshold()` (90) rather than 100.

2. **Legality & Barred Words**:
   - `MeaningGame.Steward.Legality.check_bridge/2`: player bridges are normalized (trimmed, whitespace-collapsed, downcased), capped at 40 chars, allowed letters/digits/spaces/hyphens/apostrophes (`~r/^[a-z0-9 '\-]+$/`).
   - Removed dictionary, single-word, and profanity checks for player bridges.
   - Retained dictionary, single-word, and profanity validation for Author bookends (`MeaningGame.Steward.Author.check_author_bridge/2`) and Code dictionary.
   - `check_against_barred/2` checks every word of candidate bridge against every word of all barred words/phrases (past attempt bookends, past attempt bridges, current bookends, committed bridges of the current attempt).
   - Collision refusal names the collision: `"\"#{bridge}\" shares a root with \"#{barred_word}\"."`.
   - Phone live validation and commit both use the new rule and display identical refusal messages.

3. **`assay-3` & Fake Phrases**:
   - Bumped `MeaningGame.Steward.Assay` prompt version to `"assay-3"` (orphaning `assay-2` precedents).
   - Request format carries Bookends, player names with bridges in roster order, earlier attempts with bookends and bridges, and Gives with names.
   - Updated Assayer system prompt and 6-band rubric (100, 90–99, 75–89, 55–74, 30–54, 0–29); quip may reference players and request context.
   - Furthest pair check and Precedent canonical key support both strings and bridge maps.
   - `MeaningGame.Steward.Fake` grades multi-word phrases using shared prefix overlap and handles bridge maps with player names.

4. **Testing & Standards**:
   - All 454 ExUnit tests pass with 0 failures (`MIX_TEST_PARTITION=tt04 mix test`).
   - Strict compiler check passed (`mix compile --warnings-as-errors`).
   - Formatter clean (`mix format`).
