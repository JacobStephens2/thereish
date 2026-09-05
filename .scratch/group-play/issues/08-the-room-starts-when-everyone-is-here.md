# 08: The Room starts when everyone is here

**What to build:** A Room that takes whoever arrives instead of a player count chosen at creation. The Page starts when the Seats present declare themselves complete, and the count of Seats at that moment is the count the Page is played with.

**Blocked by:** tickets 01–05 of `.scratch/group-play/spec.md`, which keeps the player count chosen on the New Room page.

**Status:** needs-triage

Filed 2026-09-04 during the group-play grilling as a follow-up, not part of the first slice. The chosen-count model is what the code has and what the first evening with friends needs; this is the fix for the evening where a fourth person cancels and a Room of four is stuck waiting.

**What it changes in the model.** Phase is derived from the state, and today "waiting" means "fewer Seats than the count". Since ADR-0011 the start gesture already exists — a Page begins when the last Give lands — so the count-free Room needs "the Gives in hand are everyone's" to be sayable (a tap after the last Give, or a Give from a Seat that declares itself last), a rule for a Seat that joins after the start (give and bridge this Attempt, or wait for the next Page), and an answer for a Seat that leaves mid-Page and never commits — which is the same problem the two-Seat Room has when a phone goes in a pocket, and is not solved by this ticket alone.

- [ ] The New Room page needs no player count
- [ ] A Page starts when the Seats present say their Gives are all in, rather than on the Room filling
- [ ] A late Seat has a defined place in the current Attempt
- [ ] A Seat that never commits has a defined effect on the Attempt
