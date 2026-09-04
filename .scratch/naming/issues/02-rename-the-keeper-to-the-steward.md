# 02: Rename the Keeper to the Steward

**What to build:** The one seam through which the game talks to language models is called the **Steward** everywhere — in the code, in the config, in the tests, and in the documents that describe it. Nothing about its behaviour changes; this is the name landing while it is still cheap to land.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

Decided in ADR-0009. The roles are people with jobs, so their umbrella is a person with a job rather than a name for the seam itself; and `Steward` is one letter from `Stewart`, leaving a host persona somewhere to grow if the stage view ever gets one.

**Blast radius, measured 2026-09-04:** 179 occurrences. 16 modules under `lib/meaning_game/keeper/` plus `keeper.ex`; references in `game.ex`, `pages.ex`, `experiments.ex`, `application.ex`, `rooms/room.ex`, `rooms/server.ex` and `meaning_game_web/live/room_live.ex`; 10 test files including `test/support/keeper_fixtures.ex`; `config/config.exs`, `config/test.exs`, `config/runtime.exs`; `docs/design-brief.md`, `docs/deploy.md`, `docs/research/llm-in-word-games.md`, ADR-0005 and ADR-0006; and several issues under `.scratch/mind-meld/`.

Do it as **one atomic change**, not expand–contract. The blast radius is wide but the app has no external consumers, so a directory move plus a mechanical rename lands green in a single commit; a staged migration would cost more than it buys.

- [ ] `lib/meaning_game/keeper/` and `keeper.ex` are moved to `steward/` and `steward.ex`, and every module is renamed to match
- [ ] Config keys, application children and fixtures use the new name
- [ ] `mix test` is green and `mix compile --warnings-as-errors` is clean
- [ ] `docs/design-brief.md`, `docs/deploy.md`, `docs/research/llm-in-word-games.md`, ADR-0005 and ADR-0006 say Steward
- [ ] Issues under `.scratch/mind-meld/` that name the Keeper are updated
- [ ] No occurrence of "Keeper" survives outside `CONTEXT.md`'s `_Avoid_` line and ADR-0009's own account of the decision
