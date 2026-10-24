---
status: accepted
---

# The Assayer's two readings may be shown when they contradict each other

Design law 12 has the Assayer grade both orderings of the same Bridges in parallel, because position bias is the judge failure that tracks with tier. It has done so from the first assay, and the recorded Verdict is the **mean** of the two. Until now the pair was averaged and thrown away: a reading of 31 and a reading of 78 reached the table as 55, with the game's reasoning held off the screen the way it always is. That is a grader with no confidence in its own grade, saying nothing about it. Decision (2026-10-23): when the two readings disagree by at least `split_decision_at`, the table is shown both — "The Assayer graded this twice — 31, and 78." — with each reading's own sentence beneath, and the Overrule becomes one tap on the generous one.

This is the one carve-out to reasoning-stays-off-the-screen, and it is narrow by construction. The screen is not being handed the Assayer's thinking; it is being told that the thing which grades disagreed with itself, which is a fact about the ruling and not an argument for it. ADR-0003 and ADR-0006 already say who settles that: the players rule, the Assayer only grades, and the only thing that rewrites a Precedent is a joint overrule. A split reading is the game saying out loud that this is one of those moments.

**The readings are shown in writing only, and never spoken.** Voice reads the Bookends, and optionally the band word and the Quip; it does not read a split. Two numbers argued aloud over a reveal would make the grader the loudest thing in the room at exactly the moment the table should be arguing, and a spoken number cannot be re-read. The Rail pins them as two ghost marks and the two sentences sit under it, legible for as long as the table wants them.

## Considered options

- **Show the two readings every time.** Rejected: rarity is the whole safety argument. A grader caught disagreeing with itself once a night is the table's best argument and the first reason anyone reaches for an Overrule; one caught at it every Page is a grader nobody believes, and the number stops being a punchline.
- **Record the wider — or the more generous — reading as the Verdict.** Rejected: the mean is what the cache stores and what the players saw, and no silent rewrite is allowed (ADR-0006, design law 1). Only the Overrule changes it, and then on the record.
- **Hide it behind an admin page.** Rejected: calibration already has the Opinions and the Spend page. This one is for the table, in the moment, or it is nothing.
- **Speaking the split through Voice.** Rejected — see above.
- **Letting one Seat accept the generous reading alone.** Rejected: an Overrule is unanimous among the Seats playing the Page, split or no split. The split makes the proposal one tap; it does not make it one Seat's.

## Consequences

- Gated twice: at `split_decision_at: 20` in configuration, and behind a Room fact (Split readings, on by default) so a table that finds it noise can turn it off from any device.
- The spread is derived, not stored: the two readings are already columns on the Verdict, so a Precedent hit reconstitutes the spread from them and the second table to write the same Bridges sees the same argument the first one did (ADR-0006).
- The Overrule gains one entry point — "Believe the generous reading (N)" — which proposes that reading as the Closeness and nothing else. Declining is recorded and named, as it is for any Overrule.
- The mean remains the recorded Verdict, in the Chronicle and in the cache, whatever the table does with the argument.
