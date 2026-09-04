# 11: One tap says whether the grade was fair

**What to build:** At the reveal, each player can tap fair, too kind, or too harsh, without interrupting play. Those taps accumulate into a labelled set that Jacob can export, which is what calibrates the Assayer and sets the meld threshold and the band boundaries against how this couple actually judges closeness.

ADR-0005 makes the labelled eval the thing that calibrates the live Assayer. This is where the labels come from, and it is the first A/B artifact.

**Blocked by:** 05.

**Status:** resolved

- [x] Three taps at the reveal on each phone: fair, too kind, too harsh
- [x] Tapping never blocks or delays the next attempt, and skipping it is normal
- [x] Each tap writes a labelled row carrying the Anchors, both Bridges, the grade, the band, the model, and the prompt version
- [x] Labels are per Seat, so the two players can disagree about the same grade
- [x] The labelled set exports in a form a calibration run can consume
- [x] Taps appear in the Chronicle alongside the Page they judge
- [x] Tests: a tap writes the expected row, two Seats disagreeing both persist, and the export includes everything a calibration needs

## Comments

**Three taps at the reveal on each phone.** In `MeaningGameWeb.RoomComponents`, when a revealed verdict with closeness is shown on phone screens, a `data-role="fairness-controls"` card invites each seated player to rate the ruling with three taps: `fair` ("Fair"), `too_kind` ("Too kind"), and `too_harsh` ("Too harsh"). Tapping provides immediate visual feedback (`data-role="your-tap"` and `data-role="seat-tap"`) highlighting the chosen judgment.

**Non-blocking and independent.** Tapping never blocks, pauses, or delays advancing to the next attempt or next page. Skipping it is completely normal. Labels are captured per Seat (`seat_id`), allowing the two players to disagree on the same verdict (e.g., my wife rates fair while Jacob rates too harsh) and both judgments persist independently.

**Full evaluation row with model metadata.** Each tap writes an immutable, append-only row to `chronicle_fairness_taps` (`MeaningGame.Chronicle.FairnessTap`). Per ADR-0003 and design law 5, rows have no `updated_at`. Every row captures the Anchors, both Bridges, the closeness/grade, the band, the model, prompt version, seat ID, attempt number, room ID, optional page ID, and label.

**Chronicle visibility and Markdown round-tripping.** In `MeaningGame.Chronicle`, computed page views load associated fairness taps for each attempt. `MeaningGameWeb.ChronicleLive` displays them alongside the Page and attempt they judge. `MeaningGame.Chronicle.Markdown` serializes taps as `- Fairness: <Seat>: <label>` and accurately round-trips them without mistaking `"Fairness"` for player bridges.

**Calibration set export.** Available in JSON and JSONL formats across CLI and HTTP:
- CLI: `mix calibration.export [--room <slug>] [--format json|jsonl] [--output <path>]` (`Mix.Tasks.Calibration.Export`).
- HTTP: `GET /calibration.json` and `GET /r/:slug/calibration.json` (`MeaningGameWeb.ChronicleController`).
- Chronicle UI: direct header link to export the calibration dataset.
The exported items include every field required for downstream Assayer calibration runs.
