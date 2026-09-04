# 04: Rename the `near` band to `close`

**What to build:** The ladder's five bands read **miss / adjacent / close / meld / deep meld**, so that no game title can collide with the name of a rung on its own ladder. Play is unchanged: same floors, same thresholds, same grades.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

The standing rule from the naming session is that the title may never reuse a word the glossary owns. With `Nearabouts` on the slate, a band called `near` would put the title inside the ladder, which is the ambiguity the rule exists to prevent. The band names are the cheapest words in the system — the brief calls them "placeholders kept as named config, not design" — so the glossary yields and the title wins.

`config/config.exs` currently reads `bands: [miss: 0, adjacent: 30, near: 55, meld: 75, deep_meld: 90]`. Floors do not move.

**`passable` is not a band.** It stays the Assayer's wording, per `lib/meaning_game/ladder.ex`'s own line that band wording lives with the Assayer and not in the ladder. The atoms are a distance scale; `passable` is a quality judgement, and as a permanent rung name it would deliver a standing verdict on the player every time they land there instead of being a joke told once. Add it to the seeded band scripts for `close` as fallback flavour.

- [ ] `config/config.exs` names the band `close`, with floors unchanged
- [ ] The Author's JSON schema and its `required` list use `close`, and the prompt version is bumped
- [ ] Seeded band scripts in `lib/meaning_game/pages.ex` and `lib/meaning_game/keeper/fake.ex` are keyed on `close`
- [ ] The presentation clause in `lib/meaning_game_web/components/room_components.ex` matches `:close`
- [ ] `passable` appears as fallback flavour for the `close` band, not as a band atom
- [ ] `mix test` is green; no pre-generated Page is served against the old schema
