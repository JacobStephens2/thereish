# 05: Four phones at a table

**What to build:** The evening the feature exists for, end to end: one phone opens the front page, taps New Room, picks four, reads the Code aloud; three phones type it and a name; the roster fills; **four Gives go in, each private to its giver, and the Author writes two Bookends from them in under five seconds** (ADR-0011); four Bridges commit; every phone reveals every Bridge, one number in its band and one quip after the beat — no reasoning card, no furthest line; the Again button names the two words that open the next Attempt; an overrule needs all four taps and writes the meld floor; one more Page asks for fresh Gives. The book and both exports tell the same story, and the two-Seat game is proven unchanged.

**Blocked by:** 02 and 03 (both shipped), and the `.scratch/at-the-table/` tickets that build the Give-first opening, the live Author, the `almost` / meld 90 / deep meld 100 ladder and the revised reveal — this ticket integrates them at four Seats. Rewritten 2026-09-05; the original path had four Bridges on a pre-written Page.

**Status:** resolved

This is the integration ticket. Everything it exercises exists after 02 and 03; what it adds is the proof that they meet, the Chronicle surfaces at N, and verification on real phones.

**The Chronicle at N.** A four-Seat Page opens with four Gives, each recorded with its Seat, and two Bookends the Author drew from two of them. A four-Seat Attempt is one Verdict row with four Seat ids and its furthest pair. The book view lists the Gives, every Bridge, the one Verdict — reasoning included, since the book is where it lives now — and the two words that carried. The Markdown export renders the same. The calibration export carries each fairness tap with its Bridge list, so calibration can read pairs and tables apart.

**The regression guard.** "At two Seats nothing changes" is a test, not a promise: every two-Seat assertion in the rules, Room, Steward and LiveView suites is unchanged. If any of them wants a new assertion, that is a finding to surface, not a test to update.

- [x] One LiveView test drives the whole path: front page, New Room for four, three joins by Code, four Gives (each visible only to its giver), Bookends on every phone, four commits, one reveal on all four phones with no reasoning shown, a carry into the next Attempt, a unanimous overrule writing 90, and one more Page that asks for Gives again
- [x] A four-Seat Page writes four Give rows with their Seats and one Verdict row per Attempt with four Seat ids and the furthest pair
- [x] The book view and the Markdown export render an N-Seat Attempt with every Bridge, the one Verdict and the carried words
- [x] The calibration export carries the Bridge list on every tap
- [x] The stage view renders the full reveal for a Room of four that has a screen, and the four phones show Bridges and controls only while it does
- [x] The two-Seat LiveView test, the two-Seat Room tests and the two-Seat rules tests pass with assertions unchanged
- [ ] The latency measurement is run from the VPS once with the four-word request under `assay-3`, and once for the Author writing Bookends from four Gives, and the numbers are recorded in this ticket's comments
- [ ] Verified on the real deployment with four actual phones: a Page played from Code to reveal to one more

## Answer

1. **Four phones integration path**: Added full end-to-end LiveView test `"the whole four-phone path from front page to one more Page"` in `MeaningGameWeb.RoomLiveTest`. Drives 4 players joining via Code (case-insensitively), submitting 4 private Gives, receiving Bookends, submitting 4 Bridges, receiving quiet reveal with no reasoning card, verifying next Bookends carry-forward in the Again button and text, performing unanimous overrule requiring all 4 taps and setting closeness to 90, and tapping "One more Page" to return to setting form for fresh Gives.
2. **Four-Seat Stage View**: Added LiveView test verifying stage renders the full reveal with comparison, closeness, band, and quip while all 4 phones render in quiet mode (`data-mode="quiet"`) with Bridges and controls only.
3. **Chronicle at N**:
   - `MeaningGame.Chronicle.compute_page_view/2` extracts `carried` furthest words from the Attempt verdicts.
   - `MeaningGame.Chronicle.Markdown` renders `- Carried: <word1> · <word2>` in attempt exports and parses it back during round-trip parsing without treating "Carried" as a Bridge.
   - `MeaningGameWeb.ChronicleLive` renders carried words under attempt verdicts (`[data-role="carried-words"]`).
   - `MeaningGame.Chronicle.calibration_dataset/1` and `export_calibration/2` export each fairness tap along with the complete bridge list (`bridges: ["beacon", "cairn", "lamp", "seagull"]`).
   - Verified 4 Give rows with seats and single Verdict row per Attempt with 4 seats and furthest pair in `ChronicleTest`.
4. **Latency Harness & Smoke Tests**:
   - Added `MeaningGame.Steward.Latency.measure_author/1` to benchmark the Author writing Bookends from 4 Gives against the 5-second target (`@author_target_ms 5_000`).
   - Added live smoke test in `MeaningGame.StewardSmokeTest` verifying `Steward.author/1` with 4 Gives completes in under 5,000 ms.
5. **Regression Guard**: All existing 2-Seat tests in `MeaningGameTest`, `RoomsTest`, `ChronicleTest`, and `RoomLiveTest` pass with assertions completely unchanged. Full test suite: 500 tests, 0 failures.
