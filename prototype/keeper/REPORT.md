# PROTOTYPE report — the Keeper against real APIs

Branch `prototype/keeper`, 2026-09-02. Throwaway code; the numbers and samples below are the deliverable.
Everything ran from `prototype/keeper/` with `mix keeper.*` (see README). Model ids were read live from
`GET /v1/models` on every provider before any call; prices from each provider's pricing page the same day
(Fable 5.1 $10/$50, Opus 5 $5/$25, Sonnet 5 $2/$10, GLM 5.3-Flash on Baseten $0.15/$0.50, GPT-5.6 Sol $4/$20,
GPT-5.6 Luna $0.20/$1.20 per MTok in/out). Costs below count every token the providers reported, thinking included.

## Verdicts in six lines

- **Q1 Author quality: YES for Mind-Meld, QUALIFIED for clover.** Every Mind-Meld Page was schema-valid and clue-legal on the first try and read as genuinely authored for the Give. Clover at `effort: "max"` overran a 32k output cap twice on thinking alone; it needs a 100k cap (see Q1 for what a capped run produced). <!-- Q1-VERDICT -->
- **Q2 Assayer budget: GLM 5.3-Flash PASSES with room from both the Mac and the VPS** (VPS: first token P50 314 ms, whole verdict P95 961 ms). Sonnet 5 and GPT-5.6 Luna pass; Opus 5 at low effort fails the P50 rule from both (2.53 s Mac, 2.61 s VPS) though its P95 total is under 4 s.
- **Q3 Consistency: no model is deterministic (law 11 confirmed); Opus is tightest, GLM loosest.** Same submission ×5 ranged up to 35 points on GLM and 6 on Opus; ordering disagreement averaged 2.5–2.8 (Opus) versus 8.8–14.5 (GLM). Hedging two identical requests cut GLM's P95 total from 1.52 s to 1.17 s.
- **Q4 Assayer quality: Opus's grades and reasoning read as the fairest, Sonnet close behind; GLM is fast but erratic on the middle of the scale.** All four agree at the extremes.
- **Q5 Elixir friction: LOW.** Raw HTTP + SSE to three providers is ~250 lines including the parser; `jsv` installed and validated cleanly; nothing here worries ADR-0002.
- **Q6 Fable 5.1 features from raw HTTP: structured output works exactly as documented; a refusal is HTTP 200 with `stop_reason: "refusal"` and a `stop_details` category; `fallbacks: "default"` was accepted but did not rescue a `reasoning_extraction` refusal.**

## Q1 — Author quality

Setup: `claude-fable-5-1`, no `thinking` param, `output_config: {effort, format: {type: json_schema, schema}}`,
`fallbacks: "default"`, streaming, versus `gpt-5.6-sol` at `reasoning_effort: "xhigh"` (its top; `max` is rejected),
`response_format: json_schema` strict. Same prompts, same schemas (ordered so the bridge/why precede the word/grade).
Both Authors are shown under blind labels; the key is the last line of this report. Every Page below passed the
schema validator and the deterministic gate (`Keeper.Pages.validate/2`: counts, single words, disjoint clovers, decoy
distinct, every exemplar clue legal under Stage 0's rule) — the validator, not the model, has the last word (law 14).

### Mind-Meld Pages (three Gives, both Authors, all valid on the first attempt)

| Give | Author A | Author B |
|---|---|---|
| suburban family life | **backyard / weekend**. Bridges foreseen: barbecue, chores, play, garden, party, family. "The place-and-time pairing opens several recognizable suburban routes without dictating one answer." 12.7 s, $0.016 (753 out, 631 reasoning) | **barbecue / carpool**. Bridges: neighbors, weekend, minivan, soccer, driveway, dad. "…barbecue is weekend, backyard, leisure, smoke and adults with beers; carpool is weekday, road, logistics, schedules and kids in the back… two bridges that start apart, say neighbors and minivan, become a fresh pair with obvious next steps toward each other." 87 s, $0.32 (6,281 out, 5,907 thinking) |
| the world St. Thérèse of Lisieux grew up in | **lace / rosary**. Bridges: thread, beads, pattern, hands, repetition, devotion. "Lace recalls the Martin family's Alençon trade, while the rosary evokes the Catholic devotions that structured Thérèse's home and schooling." 84 s, $0.074 (3,630 out, 3,465 reasoning) | **lace / clock**. Bridges: craft, hands, patience, delicate, heirloom, needle. "…her mother Zélie ran a point d'Alençon lace business and her father Louis was a watchmaker-jeweller, so 'lace' and 'clock' literally reconstruct the parlour and workshop of her childhood without naming a single saint… the French even call clock hands 'aiguilles', needles… the darker mourning: black lace and a stopped clock after Zélie's death when Thérèse was four." 56 s, $0.21 (3,968 out, 3,503 thinking) |
| no Give | theme "Museum-and-dinner date night": **art / dinner**. Bridges: taste, course, plate, composition, gallery, date. 23 s, $0.020 | theme "Rainy Weeknight In": **kettle / window**. Bridges: steam, fog, tea, glass, rain, whistle. "…the kettle's steam becomes fog on the pane… a kettle whistles; wind whistles at the window." 43 s, $0.15 (2,929 out, 2,625 thinking) |

Reading, blind: Author B's pairs are the ones with the double life the game wants (lace/clock is the Martin household
*and* time-versus-stillness; kettle/window is a physical chain and a ritual). Author A's pairs are sound but thinner:
backyard/weekend has one obvious answer (barbecue), art/dinner is a menu of puns. Both Authors' "likely bridges" are
usable as a pre-graded table (law 13). Neither needed a retry.

### Clover Pages

<!-- CLOVER -->

## Q2 — Assayer budget

Bench: `mix keeper.bench --n 20`, cache off, streaming, retries off, one fixed submission (item 9, tide/moon between
ocean/night), 20 sequential calls per candidate after one discarded warm-up; candidates run concurrently. TTFT is the
first *answer* token (first non-empty text delta; thinking deltas don't count). tok/s is output tokens over
(total − ttft). Pass rules: `ttft_p50 + 60 ÷ tps_p50 ≤ 2.5 s` and `total_p95 ≤ 4 s`.

### From the Mac (Philadelphia, residential fibre), 2026-09-02 evening

| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| glm | zai-org/GLM-5.3-Flash (`reasoning_effort: low`) | 352 ms | 950 ms | 613 ms | 1,520 ms | 56.6 | 175.1 | 695 ms | PASS | PASS | 0/20 |
| luna | gpt-5.6-luna (`reasoning_effort: low`) | 1,129 | 2,085 | 1,524 | 2,448 | 59.1 | 108.6 | 1,681 | PASS | PASS | 0/20 |
| opus | claude-opus-5 (`effort: low`) | 1,892 | 2,183 | 2,691 | 3,167 | 75.0 | 94.7 | 2,525 | **FAIL** (by 25 ms) | PASS | 0/20 |
| sonnet | claude-sonnet-5 (`effort: low`) | 1,505 | 2,285 | 2,064 | 2,855 | 55.8 | 98.3 | 2,116 | PASS | PASS | 0/20 |

Warm-up (first call, connection + schema compile): glm 747 ms, luna 2,666 ms, opus 2,676 ms, sonnet 2,664 ms total.

### From the VPS (stephens.page, x86_64, Docker `hexpm/elixir` image)

Same bench, same evening, run inside the Docker image on the VPS (`results/bench-vps.md`; a first attempt crashed
during the hedge phase, see Q5, and was rerun after the fix):

| candidate | model | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| glm | zai-org/GLM-5.3-Flash | **314 ms** | 645 ms | 627 ms | **961 ms** | 59.5 | 196.0 | 620 ms | PASS | PASS | 0/20 |
| luna | gpt-5.6-luna | 689 | 1,359 | 1,029 | 1,777 | 56.8 | 124.2 | 1,172 | PASS | PASS | 0/20 |
| opus | claude-opus-5 | 1,932 | 2,445 | 2,817 | 3,132 | 72.9 | 88.3 | 2,611 | **FAIL** (by 111 ms) | PASS | 0/20 |
| sonnet | claude-sonnet-5 | 1,468 | 1,610 | 2,077 | 2,259 | 56.1 | 95.7 | 2,095 | PASS | PASS | 0/20 |

Warm-up: glm 1,084 ms, luna 1,013 ms, opus 3,297 ms, sonnet 3,494 ms total. The VPS is *closer* than the Mac to
every provider (GLM P95 total 0.96 s vs 1.52 s; Luna 1.78 s vs 2.45 s); the Anthropic numbers barely move because
their time is generation, not network.

VPS consistency, for the record (details in `results/bench-vps.md`): repeat ranges glm 20/15/15, luna 12/23/13,
opus 4/3/12, sonnet 5/0/5 on items 7/9/18; ordering mean abs diff glm 10.3, luna 5.6, opus 3.5, sonnet 4.7; hedging
cut GLM's P95 total 961→839 ms and Luna's 1,777→1,260 ms, Opus and Sonnet unchanged.

Reading: GLM 5.3-Flash lands the *whole* verdict inside the 2.5 s beat at P50 with almost 2 s to spare, and its P95
total is under the beat too. Sonnet 5 at low effort fits (P95 2.9 s). Opus 5 at low effort is right on the line and its
first answer token alone is ~1.9 s. Note the Anthropic candidates carry a 578-token input (the system prompt) versus
242 for Baseten and 285 for OpenAI: same prompt text, different tokenizers, and the Anthropic ids also spend ~1.5 s
before the first text delta even with `thinking_tokens: 0` reported.

## Q3 — Assayer consistency and bias (cache off)

### Repeat agreement (same submission ×5, forward ordering only, cache off; Mac)

| candidate | item 1 moon/moon | item 7 butter/spread | item 9 tide/moon | item 18 paper/scar |
|---|---|---|---|---|
| glm | 100 ×5 | 88, 60, 90, 90, 78 (range 30) | 45, 55, 45, 45, 55 (range 10) | 20, 45, 45, 30, 10 (range 35) |
| luna | 100 ×5 | 78, 82, 82, 78, 82 (range 4) | 45, 45, 55, 55, 45 (range 10) | 20, 35, 10, 20, 28 (range 25) |
| opus | 100 ×5 | 76, 82, 82, 80, 80 (range 6) | 55, 60, 55, 55, 58 (range 5) | 5, 8, 8, 8, 8 (range 3) |
| sonnet | 100 ×5 | 80, 80, 60, 85, 85 (range 25) | 45, 40, 45, 45, 45 (range 5) | 15, 10, 15, 15, 10 (range 5) |

Only the trivial case (identical words) is deterministic for anyone. "Within ±5" holds for Opus on 4/4 items, Sonnet
3/4, Luna 2/4, GLM 1/4. Law 11 stands: the cache is the consistency mechanism, and the *first* ruling on a pair is a
draw from a distribution whose width is model-dependent. Item 7 (butter/spread, the borderline meld) crosses the
75 threshold on repeat for GLM and Sonnet — exactly the case where "grades not gavels" and the joint overrule matter.

### Ordering agreement ((A,B) vs (B,A), 20 items, both bench and assay runs; Mac)

| candidate | mean abs diff (bench / assay) | max abs diff | within 5 (bench / assay) |
|---|---|---|---|
| glm | 8.8 / 14.5 | 25 / **85** | 40% / 45% |
| luna | 5.5 / 6.2 | 25 / 28 | 70% / 70% |
| opus | 2.5 / 2.8 | 9 / 10 | 90% / 85% |
| sonnet | 7.0 / 4.0 | 30 / 15 | 65% / 80% |

GLM's 85-point swing was item 18 (paper/scar): 85 when Jacob's word came first ("both landed on the same wounding
idea via 'paper cut'"), 0 when my wife's did. Averaging both orderings (law 12) is doing real work for GLM; for Opus
it is insurance. Position bias tracks tier, as the research predicted.

### Hedging (two identical requests to one model, first wins; Mac, n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 |
|---|---|---|---|---|---|---|
| glm | 1,520 | **1,172** | 613 | 637 | 950 | 577 |
| luna | 2,448 | **1,673** | 1,524 | 1,224 | 2,085 | 1,326 |
| opus | 3,167 | 2,982 | 2,691 | 2,689 | 2,183 | 2,195 |
| sonnet | 2,855 | **2,353** | 2,064 | 2,120 | 2,285 | 1,718 |

Hedging shortens the tail where the tail is network/queue jitter (GLM, Luna, Sonnet) and does nothing for Opus,
whose tail is generation. Cost: the loser is billed for whatever it streamed before cancellation; at GLM prices that
is noise, at Opus prices it doubles a $0.005 call.

## Q4 — Assayer quality on the 20-item Mind-Meld set

`mix keeper.assay`, cache off, both orderings, reconciled closeness (forward/reverse). "expected" is the author of this
prototype's prior, not ground truth; the couple's own labels are the real eval (research §5f).

| # | anchors | A / B | expected | glm | luna | opus | sonnet |
|---|---|---|---|---|---|---|---|
| 1 | ocean+night | moon / moon | 100 identical | 100 (100/100) | 100 (100/100) | 100 (100/100) | 100 (100/100) |
| 2 | ocean+night | tide / tides | ~100 inflection | 100 (100/100) | 100 (100/100) | 100 (100/100) | 100 (100/100) |
| 3 | mirror+river | reflection / reflect | ~95 | 98 (95/100) | 100 (100/100) | 97 (97/97) | 98 (97/98) |
| 4 | coffee+morning | cup / mug | ~90 synonyms | 94 (95/92) | 90 (90/90) | 87 (85/88) | 90 (90/90) |
| 5 | fire+ice | melt / thaw | ~90 synonyms | 82 (85/78) | 89 (90/88) | 89 (88/90) | 91 (92/90) |
| 6 | garden+prison | wall / fence | ~80 near | 82 (85/78) | 85 (85/85) | 80 (78/82) | 85 (85/85) |
| 7 | bread+knife | butter / spread | ~75 borderline meld | 87 (82/92) | 74 (82/65) | 79 (80/78) | 83 (85/80) |
| 8 | king+castle | throne / crown | ~70 related | 80 (75/85) | 66 (60/72) | 64 (65/63) | 60 (65/55) |
| 9 | ocean+night | tide / moon | ~55 related | 51 (62/40) | 47 (45/48) | 55 (55/55) | 45 (45/45) |
| 10 | coffee+morning | alarm / awake | ~60 related | 62 (78/45) | 68 (68/68) | 54 (55/52) | 55 (55/55) |
| 11 | fire+ice | water / steam | ~60 related | 62 (78/45) | 82 (82/82) | 61 (60/62) | 55 (55/55) |
| 12 | doctor+silence | waiting / hospital | ~45 | 35 (45/25) | 39 (30/48) | 49 (45/52) | 33 (30/35) |
| 13 | doctor+silence | oath / secret | ~50 | 58 (60/55) | 56 (55/56) | 53 (58/48) | 55 (55/55) |
| 14 | letter+wound | open / seal | ~35 antonym-ish | 25 (25/25) | 34 (48/20) | 42 (42/42) | 38 (45/30) |
| 15 | train+dream | journey / sleep | ~30 | 25 (30/20) | 30 (25/35) | 14 (15/12) | 28 (35/20) |
| 16 | king+castle | moat / queen | ~30 | 28 (30/25) | 20 (20/20) | 17 (15/18) | 23 (20/25) |
| 17 | train+dream | track / drift | ~25 | 28 (25/30) | 45 (35/55) | 16 (20/12) | 19 (18/20) |
| 18 | letter+wound | paper / scar | ~15 miss | 43 (85/0) | 19 (18/20) | 9 (10/8) | 13 (15/10) |
| 19 | garden+prison | weed / cell | ~15 miss | 18 (15/20) | 13 (10/15) | 10 (12/8) | 15 (20/10) |
| 20 | mirror+river | glass / bank | ~10 miss | 33 (20/45) | 23 (25/20) | 12 (12/12) | 18 (20/15) |

Melded (≥ 75) count: glm 8, luna 7, opus 7, sonnet 7. Errors: 0 for all (one GLM call in an earlier run hit the
160-token cap and was regenerated by the validator).

Reasoning samples (forward ordering):

- **7 butter / spread** — opus: "Butter is a type of spread; near-synonymous in this context, though one is specific and the other general." sonnet: "Both refer to buttering/spreading bread with a knife, essentially the same idea." glm: "'Spread' strongly evokes butter…; same functional idea, near-meld."
- **9 tide / moon** — opus: "Closely linked concepts—moon drives tides—but they name different things, one celestial, one aquatic." glm: "…the moon pulls the ocean's tides and rules the night. Causally linked, though tide names the water's motion while moon names the celestial cause." (two sentences for a one-sentence brief)
- **14 open / seal** — opus: "Both target the letter's closure/wound-state axis but from opposite ends; antonyms sharing a domain, not the same idea." glm: "Open and seal are near-antonyms…, so the bridges point in contrary directions."
- **18 paper / scar** — glm (forward, 85): "Paper (via letter/paper cut) and scar (from wound) both evoke injury — 'paper cut' and 'wound/scar' — so both players landed on the same wounding idea from different sides." opus (9): "Paper relates to letters as material; scar relates to wounds as aftermath — different domains with little overlap."
- **20 glass / bank** — sonnet: "Glass evokes reflective surface, bank evokes riverside edge—different aspects, little semantic overlap."

Reading: the four agree at both ends of the scale (items 1–6, 19–20). The middle is where they differ, and where a
couple would argue: Opus and Sonnet grade antonyms-on-one-axis (open/seal) in the 40s with reasoning that would
survive being read aloud; GLM's reasoning is fluent but occasionally invents a link ("paper cut") and then grades it
as a meld in one ordering and a miss in the other. Luna is the most generous in the 60–85 band (water/steam 82).
If the couple's taste is "fair misdirection, narratable afterward", Opus's *reasoning* is the model of the genre; its
*latency* is the problem (Q2). GLM's speed buys a lot, and both-orderings averaging plus the cache hides most of its
noise after the first ruling, but the first ruling on a borderline pair is a coin flip on GLM.

## Q5 — Elixir friction

Total: three real adapters, SSE parser, cache, orderings, hedge, schema gate, legality gate, four mix tasks in
~1,100 lines; toolchain via `mise` took 6 minutes (precompiled Erlang 28.5, Elixir 1.19.6).

- **SSE with Req**: `Req.post(url, into: fn {:data, chunk}, {req, resp} -> … end)` plus a 30-line parser
  (`Keeper.SSE`) that splits on blank lines and carries the partial event across chunk boundaries. Events do split
  across chunks routinely; the parser handled it first time. Non-200 bodies arrive through the same callback, so the
  adapter accumulates raw bytes when `resp.status != 200` and prints the provider's JSON error. TTFT is stamped inside
  the callback on the first non-empty text delta (`Keeper.HTTP.stamp_ttft/1`). Per-request state rides in
  `Req.Response.put_private/3`.
- **Three wire shapes, two parsers**: Anthropic's named events (`message_start`, `content_block_delta` with
  `text_delta` / `thinking_delta`, `message_delta` with `stop_reason` + usage) and the OpenAI-shaped `data: {...}`
  chunks (`choices[0].delta.content`, `[DONE]`, usage in the final chunk with `stream_options.include_usage`). Baseten
  is OpenAI-shaped but takes `max_tokens` where OpenAI's reasoning models want `max_completion_tokens`; GLM's
  reasoning arrives in `delta.reasoning_content` (empty at `low`).
- **JSON**: Elixir 1.19's built-in `JSON` has no pretty printer and maps are unordered, and property order in a JSON
  schema *matters* for constrained decoding (reasoning must precede the number). `Jason.OrderedObject` solved both;
  the validator gets a plain-map copy (`Keeper.Prompts.to_map/1`).
- **Schema validation**: `jsv` 0.22.0 installed cleanly (`JSV.build!/1`, `JSV.validate/2`, `JSV.normalize_error/1`),
  handled `$defs`/`$ref`, and rejected nothing the providers had accepted. The providers' own schema guarantees held on
  every call in this run (0 schema failures out of ~1,300 JSON responses), so the validator earned its keep only on the
  deterministic checks the schema cannot express: exactly-four, disjoint clovers, clue legality, cap overruns.
- **Every 4xx hit and its fix**: (1) Anthropic 400 `"temperature is deprecated for this model."` — omit sampling
  params entirely (probe 4). (2) OpenAI 400 `reasoning_effort does not support 'max'… Supported values are: 'none',
  'low', 'medium', 'high', and 'xhigh'` — Sol's top is `xhigh`. (3) GLM `finish_reason: "length"` at a 160-token cap
  (not a 4xx, but the same class): the validator rejected and regenerated. (4) Anthropic `stop_reason: "max_tokens"`
  with zero text on the clover Author at `effort: "max"` and a 32k cap — thinking consumed the whole budget; the fix
  is a 100k cap and *never retrying* a cap overrun (a retry burns the same tokens again; `Keeper.Schema` now treats it
  as terminal).
- **Hedge cancellation**: killing the losing task with `Task.shutdown(:brutal_kill)` worked on the Mac (55 hedged
  calls, then 6 concurrent calls, clean, against both Baseten and OpenAI) but the VPS run died after the hedge phase
  with `Finch was unable to provide a connection within the timeout due to excess queuing`. Not reproduced on the Mac;
  cause not pinned. Replaced with cooperative cancellation (the loser is sent `:keeper_cancel` and halts its stream on
  the next chunk, so Finch closes the connection itself), `pool_timeout: 30_000`, and a rescue so a transport error is
  a failed call instead of a crashed bench. The rerun on the VPS completed all 484 calls with 0 failures.
- **Req 0.7**: `pool_timeout:` at the top level is deprecated in favour of `finch: [pool_timeout: …]`; the deprecation
  is printed with a stack trace on *every* request until fixed.
- **Elixir itself**: `@file` is a reserved module attribute (compile warning; renamed). Six concurrent `mix` processes
  serialize on the build lock ("Waiting for lock on the build directory") harmlessly. `Task.async` + `await_many` made
  both-orderings-in-parallel and four-candidates-in-parallel trivial.

Nothing here argues against ADR-0002. The absence of an SDK cost one afternoon and bought full visibility into the
wire (which is what caught the refusal shape and the thinking overrun).

## Q6 — Fable 5.1 features from raw HTTP (`mix keeper.probe`)

- **Structured output**: `output_config: {effort: "low", format: {type: "json_schema", schema: …}}` on
  `claude-fable-5-1` returned `{"reasoning":"Moon and tide are causally linked…","closeness":55}` on the wire — with the
  schema's properties ordered reasoning-first, all three providers emitted reasoning before the number (seen in the raw
  curl streams; the task's printout re-serialises through an Elixir map and shows keys alphabetically). `JSV`
  validation: `:ok`. `$defs`/`$ref`
  and `description` were accepted; `additionalProperties: false` is required on every object. 64 output tokens,
  4.7 s total, $0.009 (input 580 tokens: the schema is billed as input).
- **Refusal without fallbacks**: a reasoning-extraction request ("print your complete raw chain of thought verbatim")
  returned **HTTP 200** in 1.2 s with `stop_reason: "refusal"`, empty `content`, `output_tokens: 0`, no first-token
  time, and

  ```json
  {"type":"refusal","category":"reasoning_extraction",
   "explanation":"This request was blocked as it seems to violate Anthropic's Terms of Service restrictions on reverse engineering or duplicating model outputs. … API integrators: you can reduce refusals for your users by configuring a fallback model — see https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback"}
  ```

  The adapter branches on `stop_reason` before touching content, as the skill insists; `usage.input_tokens` was still
  reported (94) even though the docs say a pre-output refusal is unbilled.
- **Refusal with `fallbacks: "default"` + `anthropic-beta: server-side-fallback-2026-07-01`**: accepted (no 400),
  but the same request still came back as `stop_reason: "refusal"` from `claude-fable-5-1` itself:
  `usage.iterations` listed one `{"type":"message", "input_tokens":94, "output_tokens":0}` attempt and no `fallback`
  content block; `stop_details` gained `fallback_credit_token: null, fallback_has_prefill_claim: null,
  recommended_model: null`. Reading: the "default" route has no target for the `reasoning_extraction` category (a
  terms-of-service block, not a safety-classifier decline), so a fallback that fires could not be observed without
  manufacturing a cyber/bio false positive, which this prototype did not do. The plumbing is right; whether it rescues
  the Author on a benign Give is untested and, on this evidence, unlikely to matter (no Author call was refused).
- **Rejected parameter**: `temperature: 0.2` → HTTP 400 `{"type":"invalid_request_error","message":"\`temperature\` is
  deprecated for this model."}` with a `request_id`.
- **Thinking**: omitting `thinking` worked on every Fable call; `message_delta.usage.output_tokens_details.thinking_tokens`
  reports the thinking spend (2,625–5,907 tokens per Mind-Meld Page at `max`; the clover Pages at `max` exceeded 32,000).
- **Scribe** (`claude-fable-5-1`, `effort: "max"`, 8k cap): one call, 11.7 s, 637 output tokens, $0.038:
  > Last time, standing in the world St. Thérèse of Lisieux grew up in with ocean and night to guide you, Jacob reached
  > for the tide and my wife for the moon, two neighbours on the same dark shore that never quite became one word, so
  > tide and moon are what you carry into this round.

  Valid and warm; too long for one breath (a Vale sentence-length rule would catch it).

## Spend

<!-- SPEND -->

## What the real Keeper should keep / change

**Keep**

- The seam: `author_page/1`, `assay/2`, `scribe/2` with everything else private. Every task in this prototype went
  through it; nothing needed to reach past it.
- The adapter behaviour with a provider-neutral request/result (`text, json, usage, timings, stop_reason`). One shared
  chat-completions parser served OpenAI and Baseten; Anthropic is its own. Three adapters plus Fake made the seam real.
- Streaming everywhere, with TTFT stamped on the first *answer* token. It is the number the reveal beat is built on and
  the SDK-less path gives it for free.
- Ordered JSON schemas with reasoning before the grade; `additionalProperties: false` everywhere; the validator as the
  last word, followed by the deterministic checks the schema cannot express.
- Both orderings averaged, disagreement logged in the verdict (`forward`, `reverse`): it is the difference between a
  usable and an unusable GLM.
- The cache key `kind::model::prompt_version::anchors::sorted(words)`; the overrule writes into the same key.
- Hedging as an option per candidate, identical requests to one model only; it pays on the fast tier.
- `Keeper.Config` as one map: swapping the Assayer was one line during this run.

**Change**

- **Author `max_tokens`**: 100k at `effort: "max"`, and treat a cap overrun as terminal, never as a retry. Consider
  `effort: "high"` for clover as the default and `max` for Mind-Meld, per the Q1 numbers. <!-- KEEP-Q1 -->
- **Assayer choice**: keep GLM 5.3-Flash as the live Assayer for the *beat*, but seed the Chronicle's precedent with a
  second opinion from Opus 5 (or Sonnet 5) on borderline pairs (60–85) and on every overrule; or run Sonnet at low
  effort as the Assayer and accept a 2 s P50. Decide after the couple labels ~100 pairs (research §5f).
- **GLM cap**: 160 tokens was hit once in 40; either 200 or a firmer "under 25 words" instruction.
- Cancel hedge losers cooperatively (done here) and keep `pool_timeout` generous; watch the VPS.
- Scribe output through the Vale gate (length, em dashes, AI tells) before it reaches the Chronicle, as planned.
- Log `thinking_tokens` and `reasoning_tokens` per call into the Chronicle's call record; they are the cost.
- The Fake adapter should serve golden JSON from files so Stage 0-style walkthroughs can run against the real seam.

## Blind key

<!-- KEY -->
