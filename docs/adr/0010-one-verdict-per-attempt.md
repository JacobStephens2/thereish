---
status: accepted
---

# One Verdict per Attempt: the Assayer grades every Bridge as a set

ADR-0007 made Rooms N-seat and sketched group play as a pairwise map: every unordered pair of Seats graded, the headline the mean across pairs, the stage showing who melded with whom. The build followed that sketch. When the first evening with another couple came up (2026-09-04), Jacob chose the other branch the design brief had left open: **one Verdict per Attempt**, grading all N Bridges together as one reading of how far the table is from one mind. A four-way Bridge, not six two-way ones. Why: the reveal at four should be what it is at two — every word, one number, one quip — and six numbers, six quips and six reasonings on a phone is a report, not a punchline. It also makes grading one request per Attempt instead of N choose 2, so the seat cap stops being about cost. The two furthest-apart Bridges, which the carry-forward rule needs, are named by the Assayer inside the same Verdict rather than found by grading pairs. At two Seats every part of this is the rule the game already had, so the couch's game and its calibration do not change.

## Considered options

- **Pairwise meld map** (ADR-0007's sketch, built): richer texture — cross-couple melds are visible — at the price of N choose 2 requests and a reveal with N choose 2 of everything. Rejected for the reveal, kept as an idea for a stage that exists (`.scratch/group-play/issues/07`).
- **Couple versus couple**: two pairs on shared Anchors, compared. A different game with a team concept; filed, not chosen (`.scratch/group-play/issues/06`).

## Consequences

The Closeness of a set is defined as convergence — how far the set is from being one mind, so three tight words and one stray read as close rather than as a miss — and the Assayer's prompt says so; at two words that is the old definition. The Verdict schema gains the two furthest-apart Bridges. The prompt version bumps, which orphans the cached precedents (three verdicts and no overrules in production on the day). This supersedes the pairwise sentence in ADR-0007; the rest of ADR-0007 stands.
