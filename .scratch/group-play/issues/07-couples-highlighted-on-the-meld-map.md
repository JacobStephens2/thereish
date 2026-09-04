# 07: Couples highlighted on the meld map

**What to build:** A meld map for a Room that has a stage: every pair of Seats graded alongside the one Verdict, drawn as who melded with whom, with the reveal knowing which Seats are a couple. Each couple's own pair is shown as the score they care about, and a cross-couple Meld ("Jacob and Esme think alike") is presented as the surprise it is. The Page's Verdict, Meld, carry-forward and Precedent stay ADR-0010's; the pair grades are a display, not a ruling.

**Blocked by:** tickets 01–05 of `.scratch/group-play/spec.md`, which builds the N-Seat reveal this decorates — and a stage to draw the map on, since it is a report on a phone (ADR-0010).

**Status:** needs-triage

Filed 2026-09-04 during the group-play grilling as an idea for later. It is the cheaper cousin of 06: it keeps the one set of rules and adds a reading of it, so it can be tried before committing to a team mode. It brings back N choose 2 grading requests per Attempt, for display only, which is the cost ADR-0010 declined to pay for a phone.

**What it changes in the model.** Something has to say which Seats belong together. The smallest version is a pairing declared at join ("I'm with Mara"), kept on the Seat and shown in the roster. Whether that is a glossary term or just a display fact depends on whether any rule ever reads it; as filed, none does.

- [ ] A Seat can be marked as paired with another Seat in the Room
- [ ] The reveal puts each player's own couple-pair first and marks cross-couple Melds
- [ ] The roster shows the couples
