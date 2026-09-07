# 02: The modules say Thereish

**What to build:** `MeaningGame` and `MeaningGameWeb` become `Thereish` and `ThereishWeb`, and the OTP application `:meaning_game` becomes `:thereish`. This is the last place the working title survives: 179 files under `lib`, `test`, `config`, `priv`, `rel` and `bin` mention it, and it reaches past the code into the release binary (`rel/overlays/bin/server` execs `./meaning_game`), the asset profiles (`tailwind meaning_game`, `esbuild meaning_game` in `mix.exs`), every `config :meaning_game, ...` key in `config/runtime.exs`, and the database, which is `meaning_game` on the server and `meaning_game_dev` locally (`docs/deploy.md`).

It is a mechanical change with one genuinely careful part — the database — and it changes the running deployment, so it wants a window rather than a spare ten minutes.

**Blocked by:** None strictly, but do `01` first so this happens in a directory with the right name.

**Status:** ready-for-agent

**On the database.** The rename does not require renaming it. `:thereish` can keep talking to a database called `meaning_game` — the name is a string in `DATABASE_URL` and nothing else. Renaming it means an `ALTER DATABASE` with no connections open, a matching `pg_hba.conf` grant, and a change to the server's `.env`, all on a Chronicle that holds every evening played so far. **Do not rename the database in this ticket.** Leave it, note the mismatch in `docs/deploy.md` in one line, and let it be a separate deliberate job if it ever bothers anyone. A failed rename here loses the record of every Page ever played.

**On the mechanical part.** `git mv` the directory tree, then a single pass over module names, `:meaning_game` atoms, the release scripts and the asset profiles. The compiler and the test suite are the check: an Elixir codebase either compiles under its new namespace or it does not, and the ~755-test suite is comprehensive enough that green means green. `Thereish.Release.migrate` is the name the migrate overlay must call.

- [ ] `lib/meaning_game/` and `lib/meaning_game_web/` are `git mv`d to `lib/thereish/` and `lib/thereish_web/`, with every module renamed to match; the same for `test/`
- [ ] `mix.exs` declares `app: :thereish`, and the tailwind and esbuild profiles are renamed in both the config and the `assets.build` / `assets.deploy` aliases
- [ ] Every `config :meaning_game, ...` key in `config/config.exs`, `runtime.exs`, `dev.exs`, `test.exs` and `prod.exs` becomes `config :thereish, ...`, including the `:steward` role configuration and the Foley levels
- [ ] The four `rel/overlays/bin/` scripts exec `./thereish` and call `Thereish.Release.migrate`
- [ ] The database keeps its current name; `docs/deploy.md` says in one line that the app is `thereish` and its database is still `meaning_game`, and why
- [ ] `mix compile --warnings-as-errors` is clean and the full suite passes with no test's meaning changed — renames only, no assertions rewritten to fit
- [ ] Deployed, and the deployment checked: `/check` returns 200, a Room can be created and a Page played through to a close, and the Chronicle still shows the evenings that came before the rename
- [ ] The `MeaningGame` name survives only in the research notes and in ADRs as historical record; `grep -rn "MeaningGame" lib test config rel bin` is empty

## Comments

**2026-09-07.** Filed from Jacob's playtest notes (`.scratch/ideas/ideas.md`): "I see some code that's still meaning game which I'm wondering if It would be good to change to thereish. such as MeaningGameWeb." Scope measured the same day: 179 files mention `MeaningGame`.
