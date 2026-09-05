# 05: Four phones at a table

**What to build:** The evening the feature exists for, end to end: one phone opens the front page, taps New Room, picks four, reads the Code aloud; three phones type it and a name; the roster fills; **four Gives go in, each private to its giver, and the Author writes two Bookends from them in under five seconds** (ADR-0011); four Bridges commit; every phone reveals every Bridge, one number in its band and one quip after the beat — no reasoning card, no furthest line; the Again button names the two words that open the next Attempt; an overrule needs all four taps and writes the meld floor; one more Page asks for fresh Gives. The book and both exports tell the same story, and the two-Seat game is proven unchanged.

**Blocked by:** 02 and 03 (both shipped), and the `.scratch/at-the-table/` tickets that build the Give-first opening, the live Author, the `almost` / meld 90 / deep meld 100 ladder and the revised reveal — this ticket integrates them at four Seats. Rewritten 2026-09-05; the original path had four Bridges on a pre-written Page.

**Status:** ready-for-agent

This is the integration ticket. Everything it exercises exists after 02 and 03; what it adds is the proof that they meet, the Chronicle surfaces at N, and verification on real phones.

**The Chronicle at N.** A four-Seat Page opens with four Gives, each recorded with its Seat, and two Bookends the Author drew from two of them. A four-Seat Attempt is one Verdict row with four Seat ids and its furthest pair. The book view lists the Gives, every Bridge, the one Verdict — reasoning included, since the book is where it lives now — and the two words that carried. The Markdown export renders the same. The calibration export carries each fairness tap with its Bridge list, so calibration can read pairs and tables apart.

**The regression guard.** "At two Seats nothing changes" is a test, not a promise: every two-Seat assertion in the rules, Room, Steward and LiveView suites is unchanged. If any of them wants a new assertion, that is a finding to surface, not a test to update.

- [ ] One LiveView test drives the whole path: front page, New Room for four, three joins by Code, four Gives (each visible only to its giver), Bookends on every phone, four commits, one reveal on all four phones with no reasoning shown, a carry into the next Attempt, a unanimous overrule writing 90, and one more Page that asks for Gives again
- [ ] A four-Seat Page writes four Give rows with their Seats and one Verdict row per Attempt with four Seat ids and the furthest pair
- [ ] The book view and the Markdown export render an N-Seat Attempt with every Bridge, the one Verdict and the carried words
- [ ] The calibration export carries the Bridge list on every tap
- [ ] The stage view renders the full reveal for a Room of four that has a screen, and the four phones show Bridges and controls only while it does
- [ ] The two-Seat LiveView test, the two-Seat Room tests and the two-Seat rules tests pass with assertions unchanged
- [ ] The latency measurement is run from the VPS once with the four-word request under `assay-3`, and once for the Author writing Bookends from four Gives, and the numbers are recorded in this ticket's comments
- [ ] Verified on the real deployment with four actual phones: a Page played from Code to reveal to one more
