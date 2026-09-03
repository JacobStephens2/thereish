# 09: Real Pages, written ahead of play by the Author

**What to build:** The Room stops playing hardcoded Anchors and pulls from a pool of Pages written by the Author against a Chapter. Each Page has a Bait planted in it, the obvious Bridge both players will reach for. Nothing waits on a model mid-game, because the Author takes 43 to 87 seconds per Page.

Design law 4: pre-generate and rank, never live-generate.

**Blocked by:** 05.

**Status:** ready-for-agent

- [ ] The Author role sits behind the Keeper, using Fable 5.1 at max effort, per the measured model policy
- [ ] Authoring runs ahead of play against a named Chapter and fills a pool. No Author call ever sits between the couple and their next Page
- [ ] Each authored Page carries Anchors, the Bait, at least two deep Bridges, `likely_bridges` with `why_these` as the pre-graded table, and `meta` recording author model, prompt version, attempts, and cost. Contract shapes come from `prototype/keeper/REPORT.md`
- [ ] Author output passes an Elixir clue-legality filter before it enters the pool: stem and inflection root check against ENABLE or SCOWL wordlists, plus a profanity list. Illegal output is rejected and regenerated, never repaired by hand
- [ ] Player Bridges pass the same legality check, on the phone before commit and again on commit, so an accidental rule break never costs an attempt
- [ ] A token-cap overrun is terminal for that Page and is never retried
- [ ] The 8 second provisional band in the reveal now reads from `likely_bridges`
- [ ] The Room draws the next Page from the pool and marks it played, so no Page repeats within an evening
- [ ] Author-prewritten band scripts are stored as the quip fallback, unused while the live Assayer is healthy
- [ ] Tests: legality rejection and regeneration against recorded responses, schema validation on Author output, the pool draining and refusing to repeat a Page
- [ ] At least one Chapter authored and read by Jacob for quality before couch night
