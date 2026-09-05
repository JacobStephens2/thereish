# 06: Couple versus couple

**What to build:** Two couples at one table play the same Bookends as two teams. Jacob and Melissa meld their own pair, Bryan and Evelyn meld theirs, and the reveal compares the two Closenesses — a rival-team race, which is the competitive garnish the design brief keeps for later modes (Melissa enjoys competitive Boggle; research law 6 names the rival-team race as one of the crowd's jobs).

**Blocked by:** tickets 01–05 of `.scratch/group-play/spec.md`, which builds group play with one Verdict per Attempt (ADR-0010).

**Status:** needs-triage

Filed 2026-09-04 during the group-play grilling as an idea for later, not a ticket for the first slice. Jacob chose one Verdict on every Bridge together for the first evening with another couple (ADR-0010); this is the alternative shape he wants kept.

**What it changes in the model.** The rules gain a grouping of Seats — a team — and grade only within-team pairs, so at two couples that is two Verdicts rather than one. The headline is no longer one mean but two numbers side by side. Meld, carry-forward, overrule and the fairness tap all need a per-team reading. Whether a team is a new glossary term, and what it is called ("pair" is taken by the Assayer's pair of Bridges), is a domain-modeling question for the spec.

**Open questions**
- How teams are declared: at join, by the opener, or by the players pairing themselves on their phones.
- Whether the losing couple's Bridges carry forward for them alone, or whether both couples share one converging arc.
- Whether a team race wants a competitive Ladder reading ("who was closer") or stays co-op with two ladders.

- [ ] A spec section or ADR settles the team concept and its name
- [ ] The rules grade within-team pairs only and expose two headlines
- [ ] The phone reveal shows both couples' numbers side by side
- [ ] Played once with two couples
