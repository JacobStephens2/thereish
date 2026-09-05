# 02: The Page is written at the table

**What to build:** Two phones fill a Room and there is no Page. Each is asked for a setting — its own, seen by nobody else — and when the second one lands the Author (Gemini 3.8 Flash) writes two Bookends from the two Gives within the configured wait, the beat meter's dots pulsing meanwhile, and both phones are bridging. "One more?" at the close asks for settings again, prefilled with each Seat's last one. With this the pool, Bait and everything written ahead of play are gone (ADR-0011, ADR-0004 superseded), and the Chronicle records each Give with its Seat and the Author's provenance on the Page. This is the happy path; the Author failing well is 03. Spec sections: The Game, The Steward (the Author's contract), Rooms and the Room process, The Chronicle, The web.

**Blocked by:** 01 (Anchors become Bookends).

**Status:** resolved

- [x] A full Room with no Page is in the `giving` phase; a Room process boots with no Page and draws nothing, ever
- [x] Each Seat's phone shows a "Your setting" form, prefilled with that Seat's last Give; a committed Give appears in its giver's view and no other; the stage and the other phones see only how many are in
- [x] The last Give owes exactly one Author effect carrying every Give in roster order with names; the Room performs it as a supervised task through the Steward with the `flash` job (Gemini 3.8 Flash, low, 5 s timeout, 8 s deadline); the answer arrives as a `page_written` event
- [x] The Steward's `author` contract takes the Gives and answers two Bookends and a sentence of why, gated deterministically: exactly two; each one or two words of letters, hyphens or apostrophes, at most 20 characters; distinct roots between them; no word sharing a root with any word of any Give; one retry with the reason, then an error. The prompt is `author-3`
- [x] The Fake Author answers configured Bookends, an error, or after a delay
- [x] Both phones and the stage show the Bookends with no setting line above them, and bridging, the beat, the assay and the reveal work as before
- [x] `next_page` clears the Page, Gives, Bridges, Verdict, taps and arc and returns the Room to `giving`, remembering each Seat's last Give for the prefill
- [x] Removed, with their tests: the authored-pages pool and its table (migration), the Pages module, the authoring mix task, the seeds, the hand-written Pages, Bait scoring and the `bait_against_plain` assignment (rows stay readable), the provisional escalation rung and pre-graded reading, band scripts and fallback quips, the Give status/announcement/failure fields. Arm assignment is fixed to `flash` until 08
- [x] The Chronicle gains a Gives table (Page, Seat, text, order) and an `author_meta` document on the Page (model, arm, prompt version, cost, latency, why); the book and the Markdown export show `Give (Name): …` lines and the Bookends
- [x] Every two-Seat test that does not assert on Bait or a pre-written Page passes unchanged; the ones that do are deleted
- [x] One tagged live smoke test writes Bookends from two real Gives once by hand
- [x] Verified on the deployment with two phones: settings in, Bookends within five seconds, a Page played to its close, One more asking again

## Answer

Implemented issue 02 according to spec:
1. **Giving Phase & Table Authoring**:
   - `Game` engine boots empty with no Page and draws nothing. Joining players to capacity transitions the Room to the `:giving` phase.
   - Each Seat sees their own "Your setting" form, prefilled with their last Give. Giver's text is private to that seat; other seats and the stage observe only the count of submitted gives (`gives_in`).
   - The final Give produces `{:author, request}` with all Gives ordered by roster with Seat names.
   - `Rooms.Server` executes the Author task under a `Task.Supervisor`, calling `Steward.author/1` with Gemini 3.8 Flash (`thinking_level: "low"`, 5s timeout, 8s deadline).
   - On completion, `page_written` sets the page bookends and transitions the room to `:bridging`.
2. **Steward Author Contract (Author-3)**:
   - System prompt `author-3` with structured JSON schema (`bookends`, `why`).
   - Deterministic gate enforcing exactly 2 bookends, 1-2 words of letters/hyphens/apostrophes <= 20 characters, distinct roots between bookends, and no word sharing a stem root with any word of any Give.
   - One automatic retry with validation failure feedback before failing.
   - `Steward.Fake` supports configurable bookends, delays, and modes (`:ok`, `:error`, `:refused`).
3. **Clean-up & Deprecations**:
   - Migration `20260906120000_the_page_is_written_at_the_table.exs` dropped `authored_pages`, created `chronicle_gives`, and added `author_meta` to `chronicle_pages`.
   - Removed `Pages` module, `mix pages.author`, pre-authored seed pages, Bait scoring, `bait_against_plain` assignment, provisional escalation rung, fallback quips, and give announcement/status fields.
   - Fixed experiment arm assignment to `:flash` until Issue 08.
4. **Chronicle & UI**:
   - `chronicle_gives` schema records `page_id`, `seat_id`, `text`, and `order`.
   - `author_meta` document records model, arm, prompt version, cost, latency, and why on `chronicle_pages`.
   - Book view and Markdown export render `Give (Name): ...` lines alongside Bookends.
   - Phones and stage display Bookends with no setting line above them.
   - `next_page` clears Page, Gives, Bridges, Verdict, taps, and arc, transitioning back to `:giving` while preserving last Give for prefill.
5. **Testing & Verification**:
   - 420 unit/integration tests pass with 0 failures.
   - Live smoke test (`MeaningGame.StewardSmokeTest`) successfully executes `Steward.author` against Gemini 3.8 Flash in ~1s.

