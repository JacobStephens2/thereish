# 05: Four phones at a table

**What to build:** The evening the feature exists for, end to end: one phone opens the front page, taps New Room, picks four, reads the Code aloud; three phones type it and a name; the roster fills; four Bridges commit; every phone reveals one number, one quip and the two furthest words after the beat; those two words open the next Attempt; an overrule needs all four taps; one more Page starts. The book and both exports tell the same story, and the two-Seat game is proven unchanged.

**Blocked by:** 02 (One Verdict per Attempt) and 03 (Rooms are created by Code).

**Status:** ready-for-agent

This is the integration ticket. Everything it exercises exists after 02 and 03; what it adds is the proof that they meet, the Chronicle surfaces at N, and verification on real phones.

**The Chronicle at N.** A four-Seat Attempt is one Verdict row with four Seat ids and its furthest pair. The book view lists every Bridge, the one Verdict, and the two words that carried. The Markdown export renders the same. The calibration export carries each fairness tap with its Bridge list, so calibration can read pairs and tables apart.

**The regression guard.** "At two Seats nothing changes" is a test, not a promise: every two-Seat assertion in the rules, Room, Steward and LiveView suites is unchanged. If any of them wants a new assertion, that is a finding to surface, not a test to update.

- [ ] One LiveView test drives the whole path: front page, New Room for four, three joins by Code, four commits, one reveal on all four phones, a carry into the next Attempt, a unanimous overrule, and one more Page
- [ ] A four-Seat Page writes one Verdict row per Attempt with four Seat ids and the furthest pair
- [ ] The book view and the Markdown export render an N-Seat Attempt with every Bridge, the one Verdict and the carried words
- [ ] The calibration export carries the Bridge list on every tap
- [ ] The stage view renders the same reveal for a Room of four that has a screen
- [ ] The two-Seat LiveView test, the two-Seat Room tests and the two-Seat rules tests pass with assertions unchanged
- [ ] The latency measurement is run from the VPS once with the four-word request and the numbers are recorded in this ticket's comments
- [ ] Verified on the real deployment with four actual phones: a Page played from Code to reveal to one more
