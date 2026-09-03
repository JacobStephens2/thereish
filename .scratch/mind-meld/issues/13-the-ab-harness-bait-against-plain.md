# 13: Every Page is an experiment, starting with Bait against plain

**What to build:** Each Page is randomly assigned to an arm, the labels are blinded so neither player can play the label, and assignment and outcome are Chronicle events. The first experiment is Bait-scored Pages against plain ones, which is how ADR-0004's misdirection decision gets tested rather than assumed.

Jacob wants this practice for professional work, so the harness is a v1 feature in its own right and not an afterthought.

**Blocked by:** 09.

**Status:** ready-for-agent

- [ ] Assignment happens at Page start, randomized and stratified by Chapter, so one arm does not collect all the easy meaning-spaces
- [ ] Arm labels are blinded on the stage and on the phones. Nothing visible tells a player which arm they are in
- [ ] The declared outcomes are fixed before the first Page is played, and the sample size is declared up front
- [ ] The first experiment is Bait-scored Pages against plain ones
- [ ] Assignment and outcome are Chronicle events, so the ledger and the artifact the players read are the same thing
- [ ] The readout is qualitative, reporting streaks and preferences rather than p-values, because the sample is two people
- [ ] Unblinding is a deliberate action, and the Chronicle records when it happened
- [ ] Tests: assignment is stratified and roughly balanced over many Pages, labels never leak into a rendered view, and outcomes land on the right arm
