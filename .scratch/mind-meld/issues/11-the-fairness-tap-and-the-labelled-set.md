# 11: One tap says whether the grade was fair

**What to build:** At the reveal, each player can tap fair, too kind, or too harsh, without interrupting play. Those taps accumulate into a labelled set that Jacob can export, which is what calibrates the Assayer and sets the meld threshold and the band boundaries against how this couple actually judges closeness.

ADR-0005 makes the labelled eval the thing that calibrates the live Assayer. This is where the labels come from, and it is the first A/B artifact.

**Blocked by:** 05.

**Status:** ready-for-agent

- [ ] Three taps at the reveal on each phone: fair, too kind, too harsh
- [ ] Tapping never blocks or delays the next attempt, and skipping it is normal
- [ ] Each tap writes a labelled row carrying the Anchors, both Bridges, the grade, the band, the model, and the prompt version
- [ ] Labels are per Seat, so the two players can disagree about the same grade
- [ ] The labelled set exports in a form a calibration run can consume
- [ ] Taps appear in the Chronicle alongside the Page they judge
- [ ] Tests: a tap writes the expected row, two Seats disagreeing both persist, and the export includes everything a calibration needs
