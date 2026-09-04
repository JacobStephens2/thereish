# 01: The Assayer reads every Bridge together and names the two furthest apart

**What to build:** The Steward grades a list of N Bridges as one set and answers with one Verdict: a Closeness for how far the set is from one mind, one sentence of reasoning, one quip naming what the players wrote, and the two Bridges that landed furthest apart. At two Bridges it is the Verdict the couch already gets, and the two furthest apart are the two. Nothing a player sees changes in this ticket; what changes is that the game can now ask about four words and get one answer it can carry forward.

**Blocked by:** None (can start immediately).

**Status:** resolved

The request stays the Anchors plus Bridges; the Bridges are a list of any length in roster order. The prompt is rewritten for N players and states what the number means (ADR-0010, CONTEXT.md "Closeness"): the same idea in different words melds; three tight words and one stray read as close, not as a miss; at two words it is the closeness of the two. The prompt version bumps, because the grades either side of the change are not comparable; production holds three cached Verdicts and no overrules, so nothing of value is orphaned.

Position bias is handled as at two: the live adapter asks in two orderings, roster order and its reverse, hedged as the role is configured, and reconciles as today — the mean of the two Closenesses, the forward ordering's reasoning, quip and furthest pair, the reverse ordering's Closeness and reasoning kept in meta. Twenty-four orderings of four words are not graded.

The deterministic check grows (design law 14): the furthest pair must be exactly two entries and both must be Bridges from the request, compared after the same normalisation the Precedent uses. An answer that fails is a retry, never a Verdict.

The fake grades N words so that tests keep choosing their own numbers: the Closeness is the mean of its shared-prefix grade over every pair, the furthest pair is the pair with the lowest such grade, ties broken by roster order. At two words its grade is exactly what it is today, which is what keeps every existing test's assertions unchanged. Its dials — delay, unavailable, raise — do not change.

The furthest pair travels with the Verdict everywhere a Verdict is kept: a Precedent row carries it so a cache hit can be carried forward, and a Chronicle Verdict row carries it so the book can say which words became the next Anchors. Two additive migrations, no data migration. The Bait experiment reads "every Bridge" instead of "both": the trap is sprung when every Bridge is the Bait, deep convergence when every Bridge is among the deep Bridges. The latency measurement gains a four-word request.

- [x] A grading request carries a list of N Bridges, and the Verdict carries `furthest`: two of those Bridges, verbatim
- [x] The live prompt addresses N players, states the convergence definition, and asks for the furthest pair; the prompt version is bumped
- [x] Both orderings are asked and reconciled as before; the furthest pair comes from the forward ordering
- [x] An answer whose furthest pair is not exactly two of the request's Bridges is rejected and retried
- [x] The fake grades N words as the mean of pairwise shared-prefix grades with the lowest pair as furthest, and its two-word grade is unchanged
- [x] Precedent rows and Chronicle Verdict rows store the furthest pair; both migrations are additive
- [x] A cached Verdict returned from Precedent carries its furthest pair
- [x] The Bait arm springs the trap only when every Bridge is the Bait, and marks deep convergence only when every Bridge is a deep Bridge
- [x] The latency measurement includes a four-word request
- [x] Steward, Precedent and Chronicle tests cover the above against recorded responses; the tagged smoke test grades four real words once by hand
- [x] Every existing test passes with its assertions unchanged

**Resolved 2026-09-04.** One thing was left for ticket 02, which owns the rules
module: the reducer does not yet put a `furthest` key on the Verdict it records,
because that is the same change that replaces the pairwise Verdict map with one
Verdict per Attempt. The column, the changeset and the projection are in place
and tested through `Chronicle.write/3`, so the Chronicle carries the pair the
moment the rules hand it one.
