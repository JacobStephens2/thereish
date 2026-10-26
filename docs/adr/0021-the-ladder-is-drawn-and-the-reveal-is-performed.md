---
status: accepted
---

# The Ladder is drawn as a Rail, and the reveal is performed inside the hold

The Ladder's bands have been configuration since the first week and were drawn nowhere: the reveal showed a number, a band word and the Bridges, all at once, so "seven short of a Meld" — the thing the table actually feels — was never said. Stage 0 already found that the graded number is the comedy delivery mechanism, and a punchline delivered as a table of fields is a punchline read off a spreadsheet. Decision (2026-10-23): the Ladder gets drawn. A **Rail** is one scale with its bands in order, the line where a Meld starts, the Attempt's Closeness as a marker on it, each Seat's Call as a pin, and the gap said in words. The reveal becomes a sequence: the Bridge cards flip one at a time, each **word landing before its author's name**, then the closeness card, then the marker climbing the Rail with the number counting on the same clock.

The word before the name is the whole joke's grammar. "Lighthouse — and that was Bram" is funny in a way "Bram wrote lighthouse" is not, because the table gets to react to the word before it knows who to blame. The Rail's bands read from the same configuration the grade is read against, so a recalibrated Ladder redraws itself and nothing can drift between what a band means and where it is drawn.

The hard constraint: **the sequence is absorbed by `reveal_hold_ms`, never added to it.** Design law 10 licenses slowing a fast response to keep the theatre even, and stops at a ten-second ceiling; a staged reveal that ran on top of the hold would walk straight through it at six Seats. So Pacing arms the hold at `max(hold, sequence_ms)`, and the flip run is capped, so eight Seats stagger faster rather than stretching the reveal. A table that reads nothing into a reveal still waits exactly as long as it did before.

## Considered options

- **A number that counts up and nothing else.** Rejected: that is the old reveal with an animation on it. The Rail exists so the number has somewhere to be.
- **One card per Seat, flipped by a tap.** Rejected: a reveal the Stage performs is for the whole table at once; a tapped reveal belongs to whoever holds the phone.
- **Adding the sequence's seconds to the hold.** Rejected under design law 10 — see above. The sequence is theatre inside the beat, not a second beat.
- **A sound per flip.** Rejected for now: the stings already mark the reveal, and a flip chime per Seat is noise. The buzz in the hand carries the per-Seat rhythm instead (ADR-0023).

## Consequences

- Six band colour tokens join the theme, cool below the Meld line and warm at and above it, so a band is recognisable before it is read. They are tokens, not literals, and they survive the theme plugin in both light and dark.
- `prefers-reduced-motion` is the sequence's **first** branch: it draws the final state and stops. This is also where the old reduced-motion/audio coupling is fixed — the reveal's sound is gated on the Speaker alone, so a player who turns motion off no longer silences the Room.
- The Rail is one component drawn in three modes (phone, Stage, the quiet phone that says "Look up."), and it carries a slot for ghost marks, which is where a Split reading's two numbers are pinned (ADR-0024).
- The Chronicle draws no Rail: the book is read, not performed, and its Attempts stay a dense list with no motion.
