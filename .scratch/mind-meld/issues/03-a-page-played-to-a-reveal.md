# 03: A hardcoded Page played to a reveal, graded by the fake Keeper

**What to build:** The stage shows two Anchors. On each phone, privately, each player types a Bridge and commits it. Neither sees the other's until both have committed. The instant the last Seat commits, a fixed 2.5 second beat runs, and then the stage reveals both Bridges side by side with a closeness number, a ladder band, and the Assayer's reasoning. Above the meld threshold it is a Meld.

The Page content is hardcoded and the verdict comes from the fake Keeper. No provider is called. This ticket proves the rules and the theatre before any model exists.

**Blocked by:** 02.

**Status:** resolved

- [x] The rules live in a pure module that performs no I/O, starts no timers, and calls no models. Verdicts arrive as events applied to it, never as calls it makes

  Shape carried over from `prototype/stage0-page-machines`:

  ```
  init(page, seats)    -> state
  apply(state, event)  -> {state, effects}
  view(state, seat_id) -> what that Seat may see
  ```

  Events for this ticket: `seat_joined`, `bridge_committed`, `verdict_received`, `verdict_unavailable`. Effects are descriptions the Room performs, not actions the rules take.

- [x] An uncommitted Bridge is invisible to every other Seat, and the projected view differs correctly per Seat
- [x] A Seat can edit its Bridge freely until it commits, and not after
- [x] Every Seat sees that another Seat has committed without seeing what it wrote
- [x] The reveal fires only once every Seat has committed
- [x] The beat is a fixed 2.5 seconds for every grade. No shortening on a harsh grade in v1
- [x] Scoring is a pairwise meld map: every unordered pair of Seats gets a closeness, the headline number is the mean across pairs, and the stage shows who melded with whom. Two Seats is one pair, with nothing special-cased
- [x] Meld threshold, the 0 to 100 scale, and the five ladder bands (miss, adjacent, near, meld, deep meld) are named configuration, not constants scattered through the rules
- [x] The fake Keeper returns deterministic verdicts with controllable delay, and is the same fake every later test uses
- [x] Rules tests drive a whole Page as a list of events and assert on the projected view, including a three-Seat Page producing three pairs and a correct mean
- [x] A LiveView test drives two phones and a stage from Anchors to reveal
- [x] The whole rules surface is small enough to read in one sitting

## Comments

**2026-09-03 — built.** `MeaningGame.Game` still has three functions, and now
answers `{:ok, state, effects}`. The effects channel arrived with its first
effects: `:beat`, and one `{:assay, pair, request}` per unordered pair of Seats.

Four calls worth naming:

**Phase is derived, not stored.** A Room that is not full is `:waiting`, a full
Room with a Page is `:bridging`, every Bridge in is `:assaying`, every pair
graded is `:reveal`. No transition to forget, and no way for the reveal to fire
early: it is a question about the state, asked fresh every time.

**The draft never leaves the phone.** The ticket asks that a Seat can edit its
Bridge freely until it commits — so only the commit is an event, and the word
being typed lives in the text field. It is also why the field carries no
server-set value: the other phone committing re-renders this one, and a
re-render must not rewrite what someone is in the middle of typing. Checked by
hand in a browser, because no test would have noticed.

**The beat holds the verdict, and the rules do not know how long it is.** The
Room starts a timer and fires the Assayer in a task at the same moment, and a
verdict that lands early waits out the beat. `:beat` carries no duration,
because a description that carried one would put the clock's configuration
inside the pure module.

**The Anchors are nil until the Room is full.** Not in the ticket, but the Page
"starts fairly" only if nobody reads the words while someone else is still
typing their name.

Named configuration: `reveal_beat_ms: 2500`, and a `ladder` of `scale: 0..100`
with `bands: [miss: 0, adjacent: 30, near: 55, meld: 75, deep_meld: 90]`. The
meld threshold is the floor of the `meld` band rather than a second number that
could drift away from it. `MeaningGame.Keeper` is the seam with one adapter
behind it; the fake grades on letters shared from the front, which is not a
similarity measure but a dial a test can turn — "cairn"/"cairo" is 80, and
"cairn"/"beacon" is 0 — with `delay_ms` and `mode: :unavailable | :raise`.

Verified by hand as well as by the suite: two phones and a stage, a Bridge typed
while the other player commits, the beat visible mid-flight, and the reveal
landing on all three.

**What the review caught.** The stage computed which pairs melded and never drew
it, which is a checkbox on this ticket; there is a per-pair meld marker now and
a three-Seat LiveView test for it. A Keeper adapter that *raised* rather than
returning an error left the Page stuck in `:assaying` forever — the Room now
turns a raise or an exit into the same `verdict_unavailable` the rules already
knew about, and the fake has a `:raise` mode to prove it. The nil-handling
around bands was written twice; `Ladder.read/1` is the one answer. The assaying
line was written twice in two wordings, and is one component now. Also: a Room
that restarted could reshuffle its roster, because Seats were ordered by a
second-resolution timestamp with a random UUID as the tie-break — that is a
migration to `utc_datetime_usec`, and the generator default follows it.

**Known, and deliberately not fixed here.** A Room that crashes mid-Page comes
back at the Anchors with both Bridges gone: they live in the process and nowhere
else until the Chronicle writes Page events down (ticket 08). There is a test
that pins that behaviour so it is a decision rather than a surprise. An Assayer
that never answers at all still hangs the Page — the 4s / 8s / 10s escalation is
ticket 05's, and this ticket only handles a grader that fails out loud.
