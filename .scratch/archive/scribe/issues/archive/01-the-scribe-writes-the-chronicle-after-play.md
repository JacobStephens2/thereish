# 01: The Scribe writes the Chronicle after play

**What to build:** The third of the Steward's roles (CONTEXT.md: "the machine role that writes the Chronicle after play — records, recaps, callbacks"). Today the Chronicle is an event log with a book view and a Markdown export, and the Steward composes a plain digest of it for the Author; nobody writes prose. The Scribe writes a recap of each evening's Pages into the Chronicle, in the players' own words back to them, and plants callbacks — the line next month that remembers tonight's candy cane.

**Blocked by:** nothing. The group-play slice builds the Scribe's first, smallest job (naming a new Room from the creator's Chronicle) and the role's seat in the Steward's configuration; this ticket is the role proper.

**Status:** resolved

Filed 2026-09-04 during the group-play grilling, when Jacob asked whether the Scribe existed yet. It does not; the Mind-Meld spec put it out of scope ("the Chronicle records events; narrative recaps come later").

**What the design brief already settled about it.** The model is `claude-fable-5-1`, measured in the Steward prototype as writing valid but long recaps, which is why the deterministic gate is part of the role rather than an afterthought: Scribe prose passes a Vale gate (a Scribe style, write-good, proselint, and Vale's AiTells package, adopted per ADR-0009) with one model repair pass (design law 14). Shell out only for Vale. Recaps are player-visible and player-editable like everything else in the Chronicle (design law 5), and a recap never rewrites a grade (ADR-0006).

**Open questions, answered 2026-09-04 when this was built**
- *When it runs*: **at Page close** (Jacob's call). A supervised task under `MeaningGame.Scribe.Tasks`, its own supervisor rather than the Steward's, because an assay lives inside a reveal beat and a recap is a model writing a paragraph after everyone has stood up. Oban stays on the post-couch-night roadmap.
- *What a callback may touch*: **the Chronicle only** (Jacob's call). A callback is prose the players read in the book. The Scribe reads `Chronicle.scribe_digest/2`, which is the ordinary digest with the recaps folded in; the Author still reads `Chronicle.digest/1`, which has none. Tonight's candy cane can turn up in next month's recap and cannot quietly become next month's Anchors.
- *Whether the digest becomes the Scribe's output*: **no.** Views are computed from the log and never stored (design law 5, ADR-0003). Recaps are rows the digest reads, not a replacement for it.
- *Which model*: **a model per job.** `Steward.role/2` merges a role's settings with one job's, so `scribe` holds the key and the retry count and `jobs: [recap: ...]` holds `claude-fable-5-1`. Ticket 04's naming job adds its own Gemini entry beside it and inherits the rest.

- [x] A `scribe` role in the Steward's configuration, with the fake adapter answering it in tests — `config/config.exs`, `MeaningGame.Steward.Fake.recap/2` with `recap_mode`, `recap_delay_ms`, `recap`, `recap_callback` dials
- [x] A recap written for a closed Page and stored as a Chronicle event — `chronicle_recaps`, `MeaningGame.Chronicle.Recap`, written by `MeaningGame.Scribe` once the Page is safely in the log; the Room's part is one line
- [x] The Vale gate with one repair pass, and a recap that fails it is not shown — `MeaningGame.Steward.Vale` over `priv/vale/.vale.ini`, run as the Gate's own `check` so the repair pass is the retry the seam already had, at `retries: 1`. A Scribe that fails twice leaves the Page with no recap and says so in the book.
- [x] Recaps appear in the book view and the Markdown export, editable like the rest — `data-role=recap` in `ChronicleLive`, a `> ` blockquote in the Markdown that round-trips, and `target: "recap"` on the correction form
- [x] One callback woven into a later Page, visible to the players — the `callback` field, shown in italic under the recap; the live smoke test wrote *"Last time it was hook, both of them, no explanation; tonight it was watch, both of them, and still no explanation."*

## Comments

**2026-09-04, built.** Vale 3.19.0 is pinned in `mise.toml` and installed into the release image, so the gate exists everywhere rather than on one laptop; the packages are vendored under `priv/vale/styles` (`mix scribe.sync` refreshes them) so it works offline. Two rules had to be tuned out after being watched on real prose: `write-good.Passive`, which fires on the job rather than on a fault, and `write-good.TooWordy`, which spends a repair pass on "it was".

The interesting measurement: `claude-fable-5-1` failed the gate on nearly every first answer, and on the same two rules both times — a sentence opening with "So", and the word count. Naming them in the prompt (`recap-2`) turned four-of-four live runs into first-attempt passes at ~6 s and $0.019, half the time and half the cost. The gate's value is not only refusing bad prose; it is telling you which rules are worth writing into the question.

**Reviewed the same day**, and five things came back worth fixing. The seam handed the whole Page view to the adapter, closeness and all, so the number the Scribe is forbidden to have crossed it and only the prompt's care kept it out of the question — `Steward.Recap.readable/1` now narrows the Page at the seam, where the rule belongs (ADR-0006). The Vale length cap counted the recap and the callback together, so remembering something made the recap shorter; they are linted separately now. The Markdown round trip dropped every line of a recap after the first. `MeaningGame.Scribe` was extracted out of `Rooms.Server`, where it had been six calls to other modules about nothing the Room holds — the supervisor was already named for a module that did not exist. And `Vale.installed?/0`, which nothing called, is now on `/check`: a deployment missing the binary serves every page perfectly and quietly writes no recaps, which is the exact failure that page exists to catch.

Not built here, and deliberately: an evening-level recap (there is no notion of an evening yet), and the ADR the model-per-job idea might eventually deserve — one role with two jobs is not yet a pattern.
