# 09: Real Pages, written ahead of play by the Author

**What to build:** The Room stops playing hardcoded Anchors and pulls from a pool of Pages written by the Author against a Chapter. Each Page has a Bait planted in it, the obvious Bridge both players will reach for. Nothing waits on a model mid-game, because the Author takes 43 to 87 seconds per Page.

Design law 4: pre-generate and rank, never live-generate.

**Blocked by:** 05.

**Status:** resolved

- [x] The Author role sits behind the Steward, using Fable 5.1 at max effort, per the measured model policy
- [x] Authoring runs ahead of play against a named Chapter and fills a pool. No Author call ever sits between the couple and their next Page
- [x] Each authored Page carries Anchors, the Bait, at least two deep Bridges, `likely_bridges` with `why_these` as the pre-graded table, and `meta` recording author model, prompt version, attempts, and cost. Contract shapes come from `prototype/keeper/REPORT.md`
- [x] Author output passes an Elixir clue-legality filter before it enters the pool: stem and inflection root check against ENABLE or SCOWL wordlists, plus a profanity list. Illegal output is rejected and regenerated, never repaired by hand
- [x] Player Bridges pass the same legality check, on the phone before commit and again on commit, so an accidental rule break never costs an attempt
- [x] A token-cap overrun is terminal for that Page and is never retried
- [x] The 8 second provisional band in the reveal now reads from `likely_bridges`
- [x] The Room draws the next Page from the pool and marks it played, so no Page repeats within an evening
- [x] Author-prewritten band scripts are stored as the quip fallback, unused while the live Assayer is healthy
- [x] Tests: legality rejection and regeneration against recorded responses, schema validation on Author output, the pool draining and refusing to repeat a Page
- [x] At least one Chapter authored and read by Jacob for quality before couch night

## Comments

**Author role behind the Steward.** `MeaningGame.Steward.Author` and `MeaningGame.Steward.Anthropic` configure the Author role using `claude-fable-5-1` with `effort: "max"`. Validated against JSON schema via JSV and deterministic gate checks for anchors, bait, deep bridges, likely bridges table, and band scripts.

**Legality filter & rejection loop.** `MeaningGame.Steward.Legality` implements fast root/stem matching via `:stemmer`, irregular inflection resolution (`priv/wordlists/inflections.txt`), ENABLE dictionary check (`priv/wordlists/enable1.txt`), and profanity filtering. Illegal author outputs are rejected and regenerated with feedback, never repaired by hand. Player bridges are checked live (`phx-change`) and on commit without consuming attempts.

**Pool persistence & Room lifecycle.** Authored pages are persisted in `authored_pages` (`MeaningGame.Pages.AuthoredPage`). `MeaningGame.Pages.draw/2` marks pages as played and refuses to repeat within an evening (`{:error, :pool_exhausted}`). At the 8s `:provisional` reveal beat, `Rooms.Server` reads `provisional_band` from `likely_bridges`, and `MeaningGame.Game` uses prewritten `band_scripts` as quip fallback if the live Assayer is unhealthy.

**Chapter seeded & Jacob approved.** Four quality pages for Chapter `"suburban family life"` seeded in `priv/repo/seeds.exs` and inspected/approved by Jacob.

