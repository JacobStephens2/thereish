# 05: A Precedent hit gets a fresh quip

**What to build:** When the same Bookends and Bridges come round again, the players get the grade they got before — and a joke about tonight. A Precedent hit inherits closeness, reasoning and the furthest pair (ADR-0006) and asks the Assayer's model for one new quip, with the same history, inside the beat; if that request fails, the cached quip is used. The verdict's provenance says it was a hit. Spec section: The Steward (A Precedent hit writes a fresh quip).

**Blocked by:** 04 (Almost, meld at 90, and any Bridge you like).

**Status:** resolved

- [x] On a Precedent hit the Steward returns the cached closeness, reasoning and furthest pair and a quip written now, from a one-field `quip` request to the Assayer's model carrying the same Bookends, Bridges, names, history and Gives
- [x] A failed or slow quip request falls back to the cached quip; the reveal's timing is unchanged either way
- [x] The verdict's meta records `precedent_hit` and the quip request's cost and latency
- [x] Steward tests with the Fake cover the hit with a fresh quip, the fallback, and that a miss still grades and caches as before; the Precedent tests are otherwise unchanged

## Answer

1. **Fresh quip on Precedent hit**:
   - In `MeaningGame.Steward.Assay`, implemented `quip_prompt/2`, `quip_schema/0`, `check_quip/1`, and `quip/1`.
   - `quip_prompt` carries the Bookends, Bridges with players' names, earlier Attempts with Bookends and Bridges, and Gives with names, with a one-field schema (`{"quip": string}`).
   - Shared user content formatting between `prompt/2` and `quip_prompt/2` via `format_user_content/3`.
   - In `MeaningGame.Steward.Live.assay/1`, when `Precedent.get/3` returns `{:ok, cached}`, a one-field `quip` request is made to the Assayer's model via `Gate.answer/3` inside a supervised task (`MeaningGame.Steward.Tasks`).
   - On success, the cached closeness, reasoning, and furthest pair are inherited, while `quip` is replaced with the newly generated quip.
   - `meta` records `precedent_hit: true`, along with the quip request's `cost_usd` and `latency_ms`.

2. **Fallback on error or timeout**:
   - If the fresh quip request fails or times out (bounded by the configured `timeout_ms`), `fresh_quip_or_fallback/3` safely falls back to `cached.quip`.
   - `meta` still records `precedent_hit: true`, `cost_usd: 0.0`, and the elapsed `latency_ms`.
   - The reveal timing in `Rooms.Server` is unaffected because verdicts arrive within the existing beat.

3. **Testing**:
   - Updated `MeaningGame.StewardTest` to cover:
     - Precedent hit inheriting grade and writing a fresh quip with recorded cost, latency, and `precedent_hit: true`.
     - Fallback to cached quip when quip request fails (e.g. 500 error).
     - Fallback to cached quip when quip request times out (slow).
     - Proper payload structure in `quip_prompt/2` (Bookends, Bridges, earlier Attempts, Gives).
     - Validation in `check_quip/1`.
     - Cache miss still grading both orderings and caching in Precedent as before.
   - `MeaningGame.Steward.PrecedentTest` passes unchanged.
