# 04: A missed Page converges, then closes and is written to the Chronicle

**What to build:** The players miss. Instead of the Page ending, their two failed Bridges become the next attempt's Anchors, and they try again. After five attempts the Page closes unmelded. A Meld closes it early and visibly. Either way the Page is written into the Chronicle, and "one more?" is a single tap that starts the next one.

This is Medium's carry-forward rule, and it is what turns a miss into a converging arc rather than a dead end.

**Blocked by:** 03.

**Status:** resolved

- [x] A miss carries both failed Bridges forward as the next attempt's Anchors
- [x] The attempt cap is five tries per Page, as named configuration
- [x] Reaching the cap closes the Page unmelded, and the close reads as an ending rather than a failure state
- [x] A Meld closes the Page immediately and visibly, so landing it feels like landing it
- [x] Rules events extend to `attempt_advanced` and `page_closed`; the rules module stays pure

  `page_closed` landed as a derived phase and a `{:chronicle, entry}` effect rather than as an event. See the comments below.

- [x] Every closed Page is written to the Chronicle as append-only event rows, with the Page document stored as JSONB. Rows reference Seats, never Accounts
- [x] Chronicle writes cover the Page, each attempt, and each verdict, with model, prompt version, timings, and cost carried on the verdict rows
- [x] "One more?" is one tap and starts a fresh Page in the same Room with the same Seats
- [ ] A Page fits ten to fifteen minutes at the couch, checked by playing one

  A Page was played by hand, but by one person driving two Seats, so it timed nothing. This is a couch-night measurement.

- [x] Rules tests cover carry-forward, the cap closing a Page, and a Meld closing it early
- [x] Persistence tests run against real Postgres through the Ecto sandbox. No mock repository

## Comments

**2026-09-04 — built.** A Page is now a ladder of attempts. A miss carries the
two failed Bridges forward, a Meld ends the Page where it lands, and the fifth
attempt ends it either way — after which the whole Page goes into Postgres in
one transaction and "one more?" deals the next one.

**`page_closed` is a derived phase, not an event.** The ticket asks for
`attempt_advanced` and `page_closed` as rules events. `attempt_advanced` is one:
a Seat taps "Again" and the rules work out what the next Anchors are. `page_closed`
is not, and deliberately. Closing is a question about the state — a reveal that
melded, or a reveal on the last attempt — so it is derived exactly the way
`phase` already was, and `:closed` is the fifth phase. An event would have needed
a sender, and the only candidate was the Room, which would have had to know the
closing rule to send it. Deriving means a Meld cannot fail to end a Page because
something forgot to fire. What the rules emit at that moment is the effect the
Room actually owes: `{:chronicle, entry}`, the whole Page as it was played.

**Carry-forward at N Seats is the widest pair.** At two Seats "the two failed
Bridges" is unambiguous; at three there are three pairs and only two Anchors. The
rule is the pair that missed by the most, which at two Seats is the only pair and
is therefore the design's rule with nothing special-cased. A pair the Assayer
could not grade is not the widest — an unknown is not a miss — so an ungraded
pair is taken only when nothing was graded at all.

**The Chronicle is four tables and one transaction.** `chronicle_pages` holds the
authored document as JSONB with why it ended; `chronicle_attempts` holds each
try's Anchors and the number that was shown, so reading a Page's attempts in
order is reading the arc; `chronicle_bridges` is one row per Seat per attempt,
with a real foreign key to the Seat, because "what has Melissa written across
every Page" is the question the calibration set will ask; `chronicle_verdicts`
carries the grade, the reasoning, and the provenance — model, prompt version,
latency, cost. Nothing updates or deletes a row, and every reference is
`on_delete: :restrict`.

Provenance rides on the verdict as an opaque `meta` map: the Keeper attaches it
(and times the call, because the stopwatch is the seam's business), the rules
carry it to the Chronicle and never read it. A verdict that never arrived is
still a row — `graded` false, no number, no model — because the game admitting it
had no verdict is a thing that happened.

**The write is synchronous and swallowed on failure.** It is a handful of rows to
the same Postgres the Seats came out of. A write that fails is logged, because
losing the record of a Page is bad and taking the Room down in front of the
couple — losing the Page they are looking at with it — is worse.

**Named configuration:** `attempts_per_page: 5`, alongside the beat and the
ladder. `Pages` grew from one hand-written Page to a ring of five, because "one
more?" has to be one more *Page*; the Author replaces the ring in ticket 09.

**Verified by hand as well as by the suite.** A Page played in a browser through
a miss, a carry-forward, and a Meld on attempt 2, with the stage and a phone side
by side, and the resulting rows read back out of the dev database. Two slips came
out of that and only that: at the new `:closed` phase the phone still said "you
wrote signal" and the roster still said "has written a bridge", both of which
read as a Page still in progress. Both are one predicate now.

**Known, and deliberately not fixed here.** A Room that crashes mid-Page still
loses that Page — the Chronicle is written when a Page closes, not as it is
played, so a finished Page is never at risk but the one in flight is. Nothing
defends against a carry-forward producing the same word twice; that needs an
Assayer that grades a word against itself below the meld threshold, and if one
ever does, the next attempt is a Page with one word twice rather than a crash.

**What the review caught.** The Page's clock started when the Room process
booted rather than when the Page did, so the first Page of an evening would have
counted everyone typing their names — and that timestamp is exactly what the ten
to fifteen minute question will be answered from. It is stamped now when the
Page first has a Room full enough to play it, and there is a test that keeps it
there. Bridge and verdict rows were read back in `inserted_at` order, which
inside one transaction is close to a coin toss; they carry a position now. The
Chronicle's tables had an `updated_at` the moduledoc had just finished saying
was meaningless — a table whose rows cannot be updated should not have one, so
append-only is structural rather than a promise. The view called the played
attempts `history`, which is on the Chronicle's `_Avoid_` list in CONTEXT.md;
they are `played`. `Chronicle.write` claimed an error return that `insert!` makes
unreachable, and the Room had a clause waiting for it. Smaller: `Pages.all/0` had
no caller, `gap/1` was named the opposite of what it returned, `closed_because`
and the attempt rendering were each written twice, and the carry-forward line was
written once on the stage and once on the phone.

**Raised by the review and deliberately kept.** The attempt cap is read from
configuration inside the pure module, the same way `Ladder` reads the band
boundaries — the cap and the boundaries are the same kind of number, and passing
one in while looking the other up would make the pair harder to calibrate
together. The Chronicle is four append-only entity tables rather than a stream of
event rows; nothing updates or deletes, and the corrections in ticket 08 arrive
as their own rows. A Chronicle write that fails is still logged and swallowed.
`view.played` and the arc at the close, and the "attempt N of 5" counter, are
more than the ticket asked for, and they are what makes the close read as an
ending and the cap read as a shape rather than a surprise.
