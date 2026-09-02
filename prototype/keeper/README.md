# PROTOTYPE — the Keeper against real model APIs

**Throwaway.** This is a prototype in the sense of `/prototype`: code that answers a question and is then
captured on a branch, never merged. It deviates from that skill's two archetypes on purpose: it is neither a
single-HTML logic demo (that already exists as Stage 0 on `prototype/stage0-page-machines`) nor a set of UI
variants. It is an Elixir mix project that talks to three real providers over raw HTTP so the questions in
`REPORT.md` (Q1–Q6) get numbers instead of guesses. Nothing here ships; only the *interface* of `Keeper`
(`author_page/1`, `assay/2`, `scribe/2`) is meant to survive.

## Run it

Toolchain is pinned in `mise.toml` (Erlang 28.5, Elixir 1.19.6). From this directory:

```sh
mise install && mix deps.get                       # once
mix keeper.author --kind clover --give "suburban family life"
mix keeper.author --kind mindmeld --give "the world St. Thérèse of Lisieux grew up in"
mix keeper.author --kind clover                    # no Give: the Author picks the meaning-space
mix keeper.author --kind clover --give "..." --author both --seed 7   # blind A/B: Author A vs Author B, key at the bottom
mix keeper.author --kind clover --give "..." --effort high             # Fable arm at a lower effort (max is ~8 min, ~$1.80 per clover Page)
mix keeper.assay                                    # 20 hand-made Mind-Meld submissions × every Assayer candidate
mix keeper.bench --n 20 --label mac                 # latency + consistency bench, cache off, streaming
mix keeper.probe                                    # Q6: structured output, a refusal, fallbacks, a rejected param
mix keeper.scribe                                   # one "Last time, …" sentence
```

`mix keeper.probe` and `mix keeper.scribe` cost cents; `mix keeper.author` at the default `effort: "max"` costs up to ~$2
and ~8 minutes per clover Page (see REPORT.md Q1). Every task also runs without keys: add `--fake` (deterministic stand-in adapter). Keys are read from
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `BASETEN_API_KEY` and never printed or written.

Every request prints one line (role, model, ttft, total, tokens, cost, stop reason) and every response its
validated JSON. Runs append to `PROTOTYPE-calls.log` (gitignored). The verdict cache is in memory;
`--persist` on `keeper.assay --cache` writes it to `PROTOTYPE-cache.json` so a second run can prove
"same ruling twice".

## From the VPS

```sh
docker build -t keeper-proto .
docker run --rm --env-file keeper.env -v "$PWD/results:/app/results" keeper-proto keeper.bench --n 20 --label vps
```

`keeper.env` holds the three keys, mode 600, deleted right after the run. Never put a key on a command line.

## Shape

- `lib/keeper.ex` — the seam. `author_page/1`, `assay/2`, `scribe/2` (+ `overrule/3`, which writes precedent into the cache).
- `lib/keeper/config.ex` — one map: which model, effort and token cap play which role; prices.
- `lib/keeper/adapter.ex` — the internal seam; `adapter/anthropic.ex` (Messages API, SSE, structured output, refusal + fallbacks), `adapter/chat_completions.ex` shared by `openai.ex` and `baseten.ex`, `adapter/fake.ex`.
- `lib/keeper/http.ex`, `sse.ex` — Req streaming with a hand-rolled SSE parser; TTFT is stamped on the first answer token.
- `lib/keeper/cache.ex`, `orderings.ex`, `hedge.ex`, `schema.ex`, `legality.ex`, `ab.ex` — the guardrails behind the seam.
- `lib/keeper/prompts.ex` — prompts, JSON schemas (ordered so reasoning precedes the number), prompt version.
- `lib/keeper/pages.ex` — Author JSON → Stage 0 Page shape; deterministic validation; clover grading (no model).
- `lib/keeper/eval_set.ex` — the 20 hand-made Mind-Meld submissions.
- `lib/mix/tasks/keeper.*.ex` — the runnable tasks above.
