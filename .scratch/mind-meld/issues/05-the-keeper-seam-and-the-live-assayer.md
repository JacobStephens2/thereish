# 05: The Keeper seam, and a real Assayer grading the reveal

**What to build:** The reveal is graded by Gemini 3.8 Flash instead of by the fake, and the quip on the stage names what the players actually wrote. When the verdict is slow the reveal escalates gracefully, and when it never arrives the game says so and hands the call to the players rather than inventing a number.

This ticket builds the one seam through which the game talks to language models. Two adapters satisfy it: the live one, and the fake from ticket 03. Nothing outside the Keeper knows a provider exists.

**Blocked by:** 03.

**Status:** ready-for-agent

- [ ] A single Keeper interface covering the Assayer role, with the live adapter and the existing fake as its two implementations
- [ ] Per-role model and effort are configuration, so swapping the Assayer is a setting and not a refactor. Live Assayer is Gemini 3.8 Flash at low effort, per ADR-0005
- [ ] Both orderings of every pair are graded in parallel and both stored, with forward, reverse, reverse reasoning, model, prompt version, timings, and cost on the verdict
- [ ] Every response is schema-validated with `jsv` before it reaches the game. A validation failure retries; it never crashes a Page
- [ ] Hedging is two identical requests to one model, fast tier only, first response wins
- [ ] Grading fires the instant the last Seat commits, in parallel with the 2.5 second beat
- [ ] Escalation: visible Assayer activity through 4 seconds, a provisional band at 8 seconds, and at 10 seconds the game states it has no verdict and hands the ruling to the players. Until the Author exists the 8 second step shows the waiting state
- [ ] The Assayer quips live on the players' actual Bridges. It grades and never rules
- [ ] N Seats grade as N choose 2 pairs, capped at six Seats for v1
- [ ] Keeper tests run against recorded responses: schema rejection and retry, both orderings, hedging taking the first response. One live smoke test per role, tagged and excluded from the default run, so the suite never spends money
- [ ] Round-trip latency measured from the VPS against the p95 target of 4 seconds
