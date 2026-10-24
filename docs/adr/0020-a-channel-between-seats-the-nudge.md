---
status: accepted
---

# A channel between Seats: the Nudge is one public word, spent

Every Bridge until now was written in private and read at the reveal, so a Page was two or six people doing the same crossword in the same room: parallel solitaire with a shared punchline. Design law 9 named the two proven ways misdirection survives without a rival team — symmetric clue-givers with overlapping keys, and blind decoys — and neither was ever built, because both want a rival team's secrecy and a couch has none. Decision (2026-10-23): a Seat may spend a **Nudge**, one word, on a Page. It lands in public the instant it is sent, it is **barred** for the rest of the Page like a Bookend or an earlier Bridge, and it is spent — one per Seat per Page at the shipped knob. That is the whole mechanic: the first information the Game moves between Seats while an Attempt is still open.

It is not Bait (ADR-0004, superseded by ADR-0011). Bait was a word the Author planted for the players to fall onto, which is why it died: the only trap that ever fired drew "too harsh" from both players. A Nudge is planted by nobody — the misdirection is live and player-authored, the way So Clover's decoys are the players' own. And it does not bend the grade: a table that converges on the obvious reading of a Nudge still scores high, because the Assayer reads the Bridges and has never been shown a Nudge.

The teeth are the burn, not secrecy. A word said out loud across the couch is free and always has been; a word *spent* cannot be written, so the Seat that nudges gives up its own best answer to point at it, and the table has to bridge around the direction rather than through it. That is why a Nudge makes an Attempt harder rather than easier, and why it is the first misdirection route this game can actually hold.

## Considered options

- **A private nudge to one Seat.** Rejected: a couch has no private channel worth the plumbing — they are sitting next to each other — and a secret the Chronicle keeps is a secret the book cannot read back.
- **A free nudge, unspent.** Rejected: free advice is just talking, which the table already does better. Nothing would change but a text box.
- **A nudge that is barred only for its sender.** Rejected: then it is a hint, and the other Seats race to write the word they were handed. Barring it for everyone is what turns a hint into a direction.
- **Nudges as the Assayer's input.** Rejected outright: the Nudge never enters an assay payload, so the Precedent key is unchanged and the same Bridges on the same Bookends still inherit the same grade (ADR-0006, design law 1).
- **A budget per Attempt rather than per Page.** Rejected for now: per Page makes the spend a decision about *when*, which is the interesting one. Per Attempt is a config change away if the couch disagrees.

## Consequences

- `nudges_per_page` is configuration, because what one public word does to an Attempt is a calibration question the couch answers. Zero is the off switch and a Game with it is today's game exactly: no Seat may nudge, and no word is barred by one.
- Two off switches shipped and neither is the table's: `nudges_per_page: 0` in configuration, and the blinded Arm of the channel Experiment (`:nudge_off`), which takes the budget away for one Page without naming itself anywhere (`Thereish.Experiments`). A Room fact in the shape of Full table or Split readings — a column, a toggle in the settings modal, one tap from any device — is deliberately deferred: `Game.set_nudges_per_page/2` is the seam it would turn, and until a night asks for it, a couch that wants the channel gone needs a config change and a deploy. The Arm has to be read before the toggle is worth a column.
- A Nudge is public, so the Stage shows it and the Chronicle keeps it beside the Attempt it landed on — word, nudger, spent. The Scribe may hear it, because the Scribe writes the evening; nothing that grades may.
- The barred list grows one term: `barred_words/1` now reads the Nudges as well as the Bookends and the Page's earlier Bridges, which is what makes a Nudge unwritable everywhere at once and absent from the Assayer's request.
