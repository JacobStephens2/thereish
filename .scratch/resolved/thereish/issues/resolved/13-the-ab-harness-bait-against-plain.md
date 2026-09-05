# 13: Every Page is an experiment, starting with Bait against plain

**What to build:** Each Page is randomly assigned to an arm, the labels are blinded so neither player can play the label, and assignment and outcome are Chronicle events. The first experiment is Bait-scored Pages against plain ones, which is how ADR-0004's misdirection decision gets tested rather than assumed.

Jacob wants this practice for professional work, so the harness is a v1 feature in its own right and not an afterthought.

**Blocked by:** 09.

**Status:** resolved

- [x] Assignment happens at Page start, randomized and stratified by Chapter, so one arm does not collect all the easy meaning-spaces
- [x] Arm labels are blinded on the stage and on the phones. Nothing visible tells a player which arm they are in
- [x] The declared outcomes are fixed before the first Page is played, and the sample size is declared up front
- [x] The first experiment is Bait-scored Pages against plain ones
- [x] Assignment and outcome are Chronicle events, so the ledger and the artifact the players read are the same thing
- [x] The readout is qualitative, reporting streaks and preferences rather than p-values, because the sample is two people
- [x] Unblinding is a deliberate action, and the Chronicle records when it happened
- [x] Tests: assignment is stratified and roughly balanced over many Pages, labels never leak into a rendered view, and outcomes land on the right arm

## Comments

**Stratified randomized assignment by Chapter.** Implemented in `MeaningGame.Experiments` and `MeaningGame.Rooms.Server`. When a Page starts (both at Room boot and on `Rooms.next_page/2`), `MeaningGame.Experiments.assign_arm/1` inspects previous arm assignments within the Page's chapter stratum (`Chronicle.chapter_assignments/3`). If an arm is trailing in that chapter, it is selected; if balanced, it randomizes with 50/50 probability. This guarantees each Chapter is balanced within 1 page across arms and overall assignment remains balanced across multiple pages.

**Blinded during play on phones and stage.** `MeaningGame.Game.view/2` and `MeaningGame.Rooms.Server.handle_call({:snapshot, ...})` deliberately omit the assigned arm. Neither the phone views (`MeaningGameWeb.RoomLive`) nor the stage view (`MeaningGameWeb.StageLive`) render or contain attributes exposing whether the current Page is in the `:bait` or `:plain` arm.

**Fixed outcomes and sample size declared up front.** In `MeaningGame.Experiments.definition(:bait_against_plain)`, the sample size is declared up front as 20 Pages, and the declared outcomes are fixed: `:meld_rate`, `:attempts_to_meld`, `:fairness_preference`, `:overrule_rate`, and `:trap_convergence`.

**Bait-scored Pages against plain ones (ADR-0004).** In `MeaningGame.Experiments.score_verdict/4`, when a Page is assigned to the `:bait` arm, converging on the planted bait word is ruled as a Meld on the lowest rung (75 closeness) with trap narration, while converging on deep bridges is rewarded with the top rung (95+ closeness). When assigned to `:plain`, standard Assayer semantic grading is preserved.

**Append-only Chronicle events for assignments, outcomes, and unblindings.** Three append-only event tables (ADR-0003, design law 5: no `updated_at`, rows reference Rooms and Seats, never Accounts):
- `chronicle_experiment_assignments` (`MeaningGame.Chronicle.ExperimentAssignment`)
- `chronicle_experiment_outcomes` (`MeaningGame.Chronicle.ExperimentOutcome`)
- `chronicle_experiment_unblindings` (`MeaningGame.Chronicle.ExperimentUnblinding`)
Page views computed from the Chronicle link assignments and outcomes to closed Pages.

**Qualitative readout without p-values.** `MeaningGame.Experiments.qualitative_readout/1` and `MeaningGame.Chronicle.experiment_readout/2` summarize streaks, meld rates, mean attempts, fairness preference distributions, and bait trap rates, producing a descriptive qualitative narrative comparing the two arms. Statistical significance testing and p-values are strictly excluded.

**Deliberate unblinding action.** Unblinding is a deliberate human action performed via `Rooms.unblind_experiment/3` or the "Unblind Experiment" button in `MeaningGameWeb.ChronicleLive`. The unblinding event is recorded into `chronicle_experiment_unblindings` with timestamp, seat ID, and notes. Only after unblinding does `ChronicleLive` reveal arm badges and the qualitative readout. In Markdown export (`MeaningGame.Chronicle.Markdown`), pages render `- Experiment: Blinded (...)` until unblinded, at which point `- Arm: <arm>` is exported and round-tripped.

**Tests.** Extensive test coverage in `MeaningGame.ExperimentsTest`, `MeaningGame.ChronicleTest`, `MeaningGame.RoomsTest`, `MeaningGameWeb.ChronicleLiveTest`, and `MeaningGameWeb.RoomLiveTest` verifies stratified chapter assignment balancing, absence of arm label leaks in views, arm-based scoring, Chronicle event persistence, deliberate unblinding, and qualitative reporting.
