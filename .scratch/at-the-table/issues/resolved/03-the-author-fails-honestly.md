# 03: The Author fails honestly

**What to build:** A slow or broken Author never strands the table. Five seconds after the last Give every screen says the Author is still writing; at the deadline the phones say it could not write from these settings and why, and offer **Try again** (asks the Author once more with the same Gives) and **New settings** (clears every Give and returns to giving). The stage, which sees no Give text, shows "Waiting for settings: 1 of 2" while Gives come in and the same writing and failure states after. A duplicate answer from a retried task changes nothing. Spec sections: The Game (events), The Steward (escalation), The web.

**Blocked by:** 02 (The Page is written at the table).

**Status:** resolved

- [x] At five seconds in `writing` every screen says the Author is still writing; the Author's rungs are configuration beside the Assayer's
- [x] At the deadline, or when the Author task raises, exits, or answers an error, the Room applies `author_failed` with a reason; the phase stays `writing` and every phone shows the reason with Try again and New settings
- [x] Try again (`author_retried`) clears the failure and owes the Author effect again; New settings (`gives_reset`) clears every Give and returns the Room to `giving`; either Seat may tap either
- [x] A second `page_written` for a Page that already exists is ignored
- [x] The stage shows "Waiting for settings: N of M" with no Give text, then the writing animation, then the failure state
- [x] Rules tests cover each event; a Room test with a slow Fake Author reaches still-writing and then failure and recovers on retry; a LiveView test sees both buttons and their effects on two phones

## Answer

Implemented ticket 03:
1. **Author Escalation & Timers**:
   - Added `author_escalation_ms: [still_writing: 5_000, deadline: 8_000]` configuration in `config/config.exs` beside `assayer_escalation_ms`, with test timings in `config/test.exs` and `author_escalation/1` helper in `RoomFixtures`.
   - `Rooms.Server` tracks author wait with timer, transitions to `:still_writing` at 5 seconds, and escalates to deadline failure ("timed out") if no response is received.
   - `Rooms.Server` generates a unique task `ref` to distinguish superseded or late task completions from active retries.
2. **Failure Handling & Recovery**:
   - On deadline, task error, raise, or exit, `Rooms.Server` applies `{:author_failed, %{reason: reason}}`. Phase remains in `:writing`.
   - Phones display the failure reason ("The Author couldn't write from these settings: <reason>") and offer **Try again** (`phx-click="retry_author"`) and **New settings** (`phx-click="reset_gives"`).
   - Either Seat may tap either button.
   - **Try again** (`author_retried`) clears the failure notice and re-triggers the `{:author, request}` effect.
   - **New settings** (`gives_reset`) clears all submitted gives, cancels any pending author timers, and returns the room to `:giving`, preserving each player's last give for input prefill.
   - Duplicate `page_written` events on an existing Page are safely ignored.
3. **Stage & Component Display**:
   - In `:giving`, stage shows "Waiting for settings: N of M" without exposing Give text.
   - On the final Give, stage shows the writing animation with beat meter.
   - At 5 seconds (`:still_writing`), every screen (stage and phones) updates to "The Author is still writing...".
   - Upon failure, stage renders the failure state with the reason, hiding the writing animation.
4. **Verification**:
   - Rules tests in `GameTest` cover `author_failed`, `author_retried`, `gives_reset`, duplicate `page_written`, error states, and multi-seat invocation.
   - Room process tests in `RoomsTest` verify slow fake author escalation to `still_writing`, deadline timeout failure, task raise/exit handling, and successful recovery on retry.
   - LiveView tests in `RoomLiveTest` and component tests in `RoomComponentsTest` verify stage count/animation/failure progression and phone recovery options across both seats.
   - Full test suite passes: 497 tests, 0 failures.
