# Meaning Game

I want to make a game which plays with meaning. Maybe it could even use an LLM
somehow. I want it more than anything else to be fun.

A two-player couch word game for Jacob and Melissa, with a machine author-scribe.
The game is still unnamed; **Mind-Meld** is the Page type being built first.

- `docs/design-brief.md` — the design, and how it got here
- `CONTEXT.md` — the glossary. Room, Seat, Page, Keeper, Bridge, Meld
- `docs/adr/` — the decisions that are settled
- `.scratch/mind-meld/spec.md` and `.scratch/mind-meld/issues/` — the build

## Running it

Elixir and Erlang come from `mise` (`mise.toml` pins them), and Postgres from
docker-compose:

```sh
mise install
docker compose up -d
mix setup
mix phx.server
```

Then http://localhost:4000, which serves `MeaningGameWeb.CheckLive` — the
deployment's proof of life, and nothing game-shaped yet.

```sh
mix test          # the whole suite, including one that boots the endpoint
mix precommit     # compile with warnings as errors, format, test
```

## Deploying

It runs at **https://meld.stephens.page** from the first evening, so every
session measures the real VPS round-trips. From a clean, pushed `master`:

```sh
bin/deploy
```

See `docs/deploy.md`.
