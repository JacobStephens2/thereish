# 05: The Keeper seam, and a real Assayer grading the reveal

**What to build:** The reveal is graded by Gemini 3.8 Flash instead of by the fake, and the quip on the stage names what the players actually wrote. When the verdict is slow the reveal escalates gracefully, and when it never arrives the game says so and hands the call to the players rather than inventing a number.

This ticket builds the one seam through which the game talks to language models. Two adapters satisfy it: the live one, and the fake from ticket 03. Nothing outside the Keeper knows a provider exists.

**Blocked by:** 03.

**Status:** resolved

- [x] A single Keeper interface covering the Assayer role, with the live adapter and the existing fake as its two implementations
- [x] Per-role model and effort are configuration, so swapping the Assayer is a setting and not a refactor. Live Assayer is Gemini 3.8 Flash at low effort, per ADR-0005
- [x] Both orderings of every pair are graded in parallel and both stored, with forward, reverse, reverse reasoning, model, prompt version, timings, and cost on the verdict
- [x] Every response is schema-validated with `jsv` before it reaches the game. A validation failure retries; it never crashes a Page
- [x] Hedging is two identical requests to one model, fast tier only, first response wins
- [x] Grading fires the instant the last Seat commits, in parallel with the 2.5 second beat
- [x] Escalation: visible Assayer activity through 4 seconds, a provisional band at 8 seconds, and at 10 seconds the game states it has no verdict and hands the ruling to the players. Until the Author exists the 8 second step shows the waiting state
- [x] The Assayer quips live on the players' actual Bridges. It grades and never rules
- [x] N Seats grade as N choose 2 pairs, capped at six Seats for v1
- [x] Keeper tests run against recorded responses: schema rejection and retry, both orderings, hedging taking the first response. One live smoke test per role, tagged and excluded from the default run, so the suite never spends money
- [x] Round-trip latency measured from the VPS against the p95 target of 4 seconds

  Measured 2026-09-04 from the droplet, inside the release image, with
  `MeaningGame.Keeper.Latency.measure()` — twenty real grades through the
  shipped path, both orderings and hedging included. **p50 1,464 ms, p95
  2,444 ms against the 4,000 ms target: met.** No grade failed, and twenty of
  them cost $0.018, so an evening of five Pages is about two cents.

  | | ms |
  |---|---|
  | p50 | 1,464 |
  | p95 | 2,444 |
  | max | 5,684 |

  Two things the run says beyond the target. **The p50 is inside the 2.5 s
  beat**, which is the reveal working as designed: the verdict is normally
  already held when the theatre ends, and the beat is the pause rather than the
  wait. And **the max is not**: one grade in twenty took 5.7 s, past the
  ladder's first rung, so "the Assayer is still reading" is a line the couple
  will genuinely see now and then rather than a defensive branch. It is still
  far inside the 9 s deadline and the 10 s give-up.

  Repeatability held up, which is the whole reason ADR-0005 chose this model:
  tide/moon graded 74, 72, 74, 74 across four runs and cut/history 27, 24, 23,
  23 — ranges of 2 and 4, against the 30-to-35 the prototype measured on GLM.
  Ordering disagreement was 0 to 4 points on every pair except tide/moon's
  first run.

## Comments

**The seam, and what is behind it.** `MeaningGame.Keeper` is unchanged as an
interface — `assay/1`, one pair of Bridges at a time — and now has two adapters
answering it rather than one. `Keeper.Live` is the whole of what a live grade
costs: both orderings in parallel, hedging inside each, and the reconciliation
that makes one verdict out of two answers. Under it, `Keeper.Assay` holds the
question (system prompt, JSON schema, prompt version, and the check a schema
cannot express), `Keeper.Gate` holds design law 14 (validate, reject, ask again
with the rejection quoted back), and `Keeper.Gemini` is the only module in the
codebase that names a company. Everything about the role — provider, model,
effort, hedged requests, retries, timeouts, prices, the API key — is
`config/config.exs`, so swapping the Assayer is a commit and never a refactor.

**Not streamed, deliberately.** The Keeper prototype streamed in order to
measure time-to-first-token. The game cannot show half a verdict, so what it
waits for is the whole answer either way; asking for it in one response costs the
same wall clock, saves the SSE parser, and is why a recorded response in a test
is a JSON file rather than a transcript.

**Two budgets, not one.** `timeout_ms` (4 s) is one request; `deadline_ms` (9 s)
is the whole grading, retries included, and sits under the ten seconds at which
the game stops waiting. The first review draft had a single 9 s timeout, which
left the two retries design law 14 asks for with nowhere to happen.

**The escalation ladder lives in the Room, because it is made of time.** The
rules stay clockless: the Room arms the ladder when it asks the Assayer, stands
it down when the Assayer answers, and at the last rung applies
`verdict_unavailable` for every pair still outstanding — an event the rules
already had. The step is the one thing a snapshot says that `Game.view/2` did
not (`view.assayer_step`), and the Room merges it in. The ladder is armed by the
asking and disarmed by the answering rather than by the reveal appearing,
because those differ by the beat and an Assayer that answered in 200 ms is not
slow. The 8 s rung shows the waiting state, as the ticket says, until the
Author's `likely_bridges` exist to make it provisional.

**The quip is a first-class field, not chrome.** It rides on the Verdict beside
the reasoning, through the pure rules, into the view and into the Chronicle
(`quip`, alongside `forward`, `reverse` and `reasoning_reverse` in a migration).
The fake writes one too, naming the same two Bridges, so every screen the quip
is drawn on is exercised by a suite that never calls anybody. "Quip" is now in
CONTEXT.md.

**What the reviews caught.** The Assayer was being asked about the two Bridges
in *pair-key* order — two sorted Seat ids — so the sentence and the joke named
the words in an order that had nothing to do with the order the reveal shows
them in, and about half the time read backwards. The request now carries them in
roster order; the key stays sorted, because a key is a key. `Assay.check/1` had
no catch-all clause, so loosening the schema would have turned a malformed
answer into a `FunctionClauseError` inside a grading — precisely the crash the
Gate exists to prevent. `Keeper.Live`'s moduledoc claimed the hedged loser's
tokens were counted; they are not, and cannot be without waiting for the request
whose answer is being thrown away, so the claim is now the truth. "grader",
"ruling" and "judge" had crept into new prose, all three on CONTEXT.md's
`_Avoid_` lists. The test that was supposed to prove a late verdict cannot move
a number was vacuous — the fake was told to take five seconds and the test ended
in one — and the fixtures pulled the two orderings apart with a regex against
the prompt's exact sentence, which the spec's testing rule forbids and the
couple's calibration would have broken.

**Raised and deliberately kept.** The escalation rungs are named in three places
— the timings in config, the ordering in the Room, the wording in the components
— and a fourth rung would edit all three; that is three small jobs rather than
one abstraction, and there will not be a fourth rung. A stale escalation message
left in the mailbox by a timer that fired as the verdict landed is harmless
rather than defended against, because the mailbox's own ordering guarantees it
is read before anything could arm a new ladder for it to be mistaken for; the
reasoning is written down where the code is. The keeper tests move application
configuration and are therefore not async, which is true of every test that
touches a Room here anyway.

**Also here, and not asked for:** a six-Seat Room is tested end to end and
produces the fifteen graded pairs the cap is about; `bin/deploy` warns when the
server's `.env` has no `GEMINI_API_KEY`, because an evening where every Page
reads "No verdict" would be a missing line in a file rather than a design.

**Played on the deployed site.** Two Seats joined a `smoke` Room at
meld.stephens.page and committed "lighthouse" and "cargo" between lantern and
harbour. Gemini graded it 39, adjacent — "Both relate to maritime harbour
settings, but a lighthouse is a coastal navigational structure while cargo
refers to transported goods" — and quipped "One was dutifully watching from the
lighthouse while the other was busy unloading all the cargo." The stage drew the
Bridges, then the number, then the joke, then the argument, then the
carry-forward line, which is the reveal as designed. Two phones in one browser
profile share a session cookie and so share a Seat, so the two Bridges were
committed through `Rooms.commit_bridge/3` on the running node while the stage
was watched in the browser. The Bridges were chosen to miss, so the Page stayed
open and nothing went into the Chronicle; the `smoke` Room and its two Seats are
still in Postgres, harmless and ignorable.
