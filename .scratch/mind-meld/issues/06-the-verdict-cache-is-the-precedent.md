# 06: The same two Bridges are graded the same way forever

**What to build:** The couple plays the same Anchors and writes the same Bridges a month later, and the game rules exactly as it ruled the first time. They never catch it contradicting itself. This is design law 1, and it is the mechanism that makes the whole referee posture survivable.

**Blocked by:** 05.

**Status:** ready-for-agent

- [ ] A verdict cache keyed by model, prompt version, and normalized inputs, living behind the Keeper
- [ ] Both orderings of a pair collapse to a single cache key
- [ ] The cache stores exactly what the players were shown, and returns exactly that on a later hit, per ADR-0006
- [ ] A cache hit skips the provider entirely, so a repeat is instant
- [ ] Normalization is deterministic and documented, so a trailing space or a capital letter does not fork a key
- [ ] A second opinion is never written into the cache. Annotations are out of scope here, and nothing silently rewrites a grade
- [ ] Tests: a repeated pair returns the stored verdict without a provider call, the reverse ordering hits the same key, and a differing prompt version misses the cache
