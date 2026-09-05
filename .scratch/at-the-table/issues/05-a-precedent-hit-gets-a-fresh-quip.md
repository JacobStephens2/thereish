# 05: A Precedent hit gets a fresh quip

**What to build:** When the same Bookends and Bridges come round again, the players get the grade they got before — and a joke about tonight. A Precedent hit inherits closeness, reasoning and the furthest pair (ADR-0006) and asks the Assayer's model for one new quip, with the same history, inside the beat; if that request fails, the cached quip is used. The verdict's provenance says it was a hit. Spec section: The Steward (A Precedent hit writes a fresh quip).

**Blocked by:** 04 (Almost, meld at 90, and any Bridge you like).

**Status:** ready-for-agent

- [ ] On a Precedent hit the Steward returns the cached closeness, reasoning and furthest pair and a quip written now, from a one-field `quip` request to the Assayer's model carrying the same Bookends, Bridges, names, history and Gives
- [ ] A failed or slow quip request falls back to the cached quip; the reveal's timing is unchanged either way
- [ ] The verdict's meta records `precedent_hit` and the quip request's cost and latency
- [ ] Steward tests with the Fake cover the hit with a fresh quip, the fallback, and that a miss still grades and caches as before; the Precedent tests are otherwise unchanged
