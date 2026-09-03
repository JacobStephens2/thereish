# 03: A hardcoded Page played to a reveal, graded by the fake Keeper

**What to build:** The stage shows two Anchors. On each phone, privately, each player types a Bridge and commits it. Neither sees the other's until both have committed. The instant the last Seat commits, a fixed 2.5 second beat runs, and then the stage reveals both Bridges side by side with a closeness number, a ladder band, and the Assayer's reasoning. Above the meld threshold it is a Meld.

The Page content is hardcoded and the verdict comes from the fake Keeper. No provider is called. This ticket proves the rules and the theatre before any model exists.

**Blocked by:** 02.

**Status:** ready-for-agent

- [ ] The rules live in a pure module that performs no I/O, starts no timers, and calls no models. Verdicts arrive as events applied to it, never as calls it makes

  Shape carried over from `prototype/stage0-page-machines`:

  ```
  init(page, seats)    -> state
  apply(state, event)  -> {state, effects}
  view(state, seat_id) -> what that Seat may see
  ```

  Events for this ticket: `seat_joined`, `bridge_committed`, `verdict_received`, `verdict_unavailable`. Effects are descriptions the Room performs, not actions the rules take.

- [ ] An uncommitted Bridge is invisible to every other Seat, and the projected view differs correctly per Seat
- [ ] A Seat can edit its Bridge freely until it commits, and not after
- [ ] Every Seat sees that another Seat has committed without seeing what it wrote
- [ ] The reveal fires only once every Seat has committed
- [ ] The beat is a fixed 2.5 seconds for every grade. No shortening on a harsh grade in v1
- [ ] Scoring is a pairwise meld map: every unordered pair of Seats gets a closeness, the headline number is the mean across pairs, and the stage shows who melded with whom. Two Seats is one pair, with nothing special-cased
- [ ] Meld threshold, the 0 to 100 scale, and the five ladder bands (miss, adjacent, near, meld, deep meld) are named configuration, not constants scattered through the rules
- [ ] The fake Keeper returns deterministic verdicts with controllable delay, and is the same fake every later test uses
- [ ] Rules tests drive a whole Page as a list of events and assert on the projected view, including a three-Seat Page producing three pairs and a correct mean
- [ ] A LiveView test drives two phones and a stage from Anchors to reveal
- [ ] The whole rules surface is small enough to read in one sitting
