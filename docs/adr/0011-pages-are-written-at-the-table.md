---
status: accepted
---

# Pages are written at the table from the Seats' Gives

Until 2026-09-05 a Room opened on a Page the Author had written the night before: design law 4 said pre-generate and rank, never live-generate, because the Author of 2026-09-01 took 43–87 s per Page. The second playtest (2026-09-04, Room DUST) found three things wrong with that at once. The game was too easy — seven Pages, six melded, three on the first Attempt — because the Author wrote Anchors that shared a meaning-space and printed the Give above them as a setting. The pre-written Page stood between the couple and the Give they had just typed. And Melissa's Give, "give me two very unrelated words", asked the Author for the rule the game should have had. Decision: **no Page exists until every Seat has given a Give**, each private to its giver until the Page's first reveal; the **Author writes the Page live** in the seconds after the last Give lands — two **Bookends**, words or two-word phrases, each drawn from a different Give and chosen to stand far apart; and "One more?" asks for fresh Gives. Live generation was measured fun that night (the quips, the Pages from a Give), so law 4 is rewritten to "generate live when the wait fits the theatre."

## Considered options

- **Keep the pool, draw by Give**: the Give's Pages arrive in the background while the couple play something else first. Rejected — it is the thing the couple objected to, and the pool burned a Page per Room on every process start.
- **One Give from anyone, the Author picks the far word**: works at two Seats, leaves everyone else without authorship at four. Rejected for "every Seat gives one", which mirrors the commit rhythm the game already has.
- **A slow, frontier Author with theatre for the wait**: rejected for a fast one — the opening should read as the game answering, and the job is two words.

## Consequences

- **ADR-0004 is superseded.** Bait, deep bridges, `likely_bridges`, band scripts, the `authored_pages` pool, `Pages.first` at Room start, the 8-second provisional reading and the fallback quips are removed. The only trap that fired on 2026-09-04 (lighthouse/lighthouse, graded 75) drew "too harsh" from both players; misdirection now comes from the distance between the Bookends and the privacy of the Gives.
- The Author's model becomes the A/B harness's first experiment after Bait: Gemini 3.8 Flash against GPT-6 Astra at low, read from the arc and one tap on the Bookends at the close.
- Chapter stays in the glossary as a direction with no mechanism.
- A Give is recorded in the Chronicle with the Seat that gave it, and becomes material for the quip from the first reveal on.
