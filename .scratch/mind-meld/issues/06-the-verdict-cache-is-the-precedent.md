# 06: The same two Bridges are graded the same way forever

**What to build:** The couple plays the same Anchors and writes the same Bridges a month later, and the game rules exactly as it ruled the first time. They never catch it contradicting itself. This is design law 1, and it is the mechanism that makes the whole referee posture survivable.

**Blocked by:** 05.

**Status:** resolved

- [x] A verdict cache keyed by model, prompt version, and normalized inputs, living behind the Keeper
- [x] Both orderings of a pair collapse to a single cache key
- [x] The cache stores exactly what the players were shown, and returns exactly that on a later hit, per ADR-0006
- [x] A cache hit skips the provider entirely, so a repeat is instant
- [x] Normalization is deterministic and documented, so a trailing space or a capital letter does not fork a key
- [x] A second opinion is never written into the cache. Annotations are out of scope here, and nothing silently rewrites a grade
- [x] Tests: a repeated pair returns the stored verdict without a provider call, the reverse ordering hits the same key, and a differing prompt version misses the cache

## Comments

**The verdict cache is `MeaningGame.Keeper.Precedent`.** Backed by a Postgres `precedents` table with a unique index on `key`. It lives directly behind `MeaningGame.Keeper.Live` (and `Keeper.assay`).

**Deterministic normalization and canonical keying.** Normalization applies Unicode NFC normalization, downcasing, trimming, and collapsing whitespace (`String.split/1 |> Enum.join(" ")`). Both bridges and anchors are normalized and sorted before hashing (`:crypto.hash(:sha256, Jason.encode!([model, prompt_version, sorted_anchors, sorted_bridges])) |> Base.encode16(case: :lower)`), so reversing player order, anchor order, or varying whitespace/casing never forks a key.

**No silent rewrites.** `Precedent.put` uses `on_conflict: :nothing, conflict_target: :key`, so once a verdict is stored, subsequent calls (including second opinions) cannot overwrite it. Only a joint player overrule (ticket 07) will rewrite precedent.

**Instant cache hits.** On a cache hit, `Live.assay` returns the reconstituted verdict immediately, skipping tasks, provider requests, hedging, and JSON validation entirely. Monotonic latency measured by `Keeper.assay` is instantaneous (< 50ms).

