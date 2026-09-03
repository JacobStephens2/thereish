# PROTOTYPE report — the Keeper against real APIs

Branch `prototype/keeper`, 2026-09-02. Throwaway code; the numbers and samples below are the deliverable.
Everything ran from `prototype/keeper/` with `mix keeper.*` (see README). Model ids were read live from
`GET /v1/models` on every provider before any call; prices from each provider's pricing page the same day
(Fable 5.1 $10/$50, Opus 5 $5/$25, Sonnet 5 $2/$10, GLM 5.3-Flash on Baseten $0.15/$0.50, GPT-5.6 Sol $4/$20,
GPT-5.6 Luna $0.20/$1.20 per MTok in/out). Costs below count every token the providers reported, thinking included.

## Verdicts in six lines

- **Q1 Author quality: YES.** All 12 Pages (3 Gives × 2 kinds × 2 Authors) were schema-valid and clue-legal on the **first** attempt once the output cap was right; Fable's decoys are excluded by the ring's double constraint and its vocabulary is *of the Give*. The catch: at `effort: "max"` a clover Page thinks for 34.5k tokens — 7.8 min and $1.78 with a 100k cap, and a hard failure (zero text, $1.61 burned) under the 32k cap it was first given. Mind-Meld at `max` costs $0.15–0.32 and 43–87 s; clover at `high` $0.25–0.38 and 65–110 s.
- **Q2 Assayer budget: GLM 5.3-Flash PASSES with room from both the Mac and the VPS** (VPS: first token P50 314 ms, whole verdict P95 961 ms). Sonnet 5 and GPT-5.6 Luna pass; Opus 5 at low effort fails the P50 rule from both (2.53 s Mac, 2.61 s VPS) though its P95 total is under 4 s. Added later: **Gemini 3.8 Flash passes from both machines** (VPS 594 ms first token, 961 ms P95 total), Gemini 3.7 passes, and DeepSeek V4 Flash 0731 fits the beat only with reasoning off (at `max` it is 7–9 s P50).
- **Q3 Consistency: no model is deterministic (law 11 confirmed); Opus is tightest, GLM loosest; Gemini 3.8 Flash comes closest to Opus (repeat ranges 0–8).** Same submission ×5 ranged up to 35 points on GLM and 6 on Opus; ordering disagreement averaged 2.5–2.8 (Opus) versus 8.8–14.5 (GLM). Hedging two identical requests cut GLM's P95 total from 1.52 s to 1.17 s.
- **Q4 Assayer quality: Opus's grades and reasoning read as the fairest, Sonnet close behind; GLM is fast but erratic on the middle of the scale.** All four agree at the extremes. Added later: Gemini 3.7/3.8 Flash are stable but 10–15 points more generous than Opus in the 40–75 band (water/steam melds under Gemini); DeepSeek V4 Flash is Opus-like when it thinks and GLM-noisy when it doesn't.
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

**What happened at `effort: "max"` with a 32,000-token cap.** Two of three clover runs (the Thérèse Give and the no-Give
run) streamed for 431 s and 421 s, produced **zero text** (no first-token time at all) and stopped with
`stop_reason: "max_tokens"`: 32,000 output tokens of thinking each, $1.61 each, and then the retry loop started the
same request again. The runs were killed; the retry-on-cap behaviour was removed (a cap overrun is now terminal) and the
Author's cap raised to 100,000. The Mind-Meld Pages at `max` used 2,600–5,900 thinking tokens; the clover schema (eight
legal clues under a stem rule, two disjoint rings, two decoys that must tempt *and* be excludable) is a different order
of problem for the model's deliberation.

**Clover at `effort: "high"` (Fable arm), Author A at `xhigh`, 100k cap — both valid on the first attempt.**

*Give: the world St. Thérèse of Lisieux grew up in.*

Author B (110 s, $0.38; 7,339 out of which 6,383 thinking) — theme "Thérèse's Normandy: a lacemaker's and watchmaker's Catholic household, orchards, convent bells":

- ring **lace → watch → rose → snow**; exemplar clues *wrist* (Zélie's lace cuffs and Louis's watches meet at the wrist), *stem* (a rose grows on one; a watch is wound by one), *shower* (her promised shower of roses; snow on her clothing day), *frost* (frost draws lace on a Norman window). Decoy **thorn**, aimed at *stem*: "Hearing stem, the guesser sees the rose at once and reaches for its thorn… Excluded: stem is a thing each keyword owns outright… a thorn sits on a stem but has none of its own, and a watch has nothing thorny anywhere; in the ring, watch is already locked to lace by wrist, so its other neighbour must carry a stem itself, and only the rose does."
- ring **veil → bell → orchard → candle**; clues *wedding*, *ring* (a bell rings; orchard trees keep their years in rings), *bees* (apple blossom, and their wax becomes altar candles), *chapel*. Decoy **steeple**, aimed at *chapel*: "…it even borrows the bell's gravity, since bells hang in steeples. Excluded: chapel here names the room two small things are brought into, a veil on the head and a candle in the hand; a steeple is the building itself, not something carried in. And it can hold no second hand in the ring…"

Author A (296 s, $0.33; 16,459 out, 15,870 reasoning) — theme "St. Thérèse's late-nineteenth-century Norman childhood: parental craft, domestic life, Catholic devotion, and rail pilgrimage":

- ring **lace → watch → garden → linen**; clues *maker* ("Zélie was a lacemaker and Louis a watchmaker"), *spring* (a watch's coiled spring; the season that wakes a garden), *table*, *needle* (needle lace, including Alençon). Decoy **king**, aimed at *maker*: "Kingmaker is a familiar compound, and Thérèse affectionately regarded her father as her king. Excluded: a kingmaker does not craft a king and names neither parental trade."
- ring **shrine → candle → letter → train**; clues *votive*, *wax* (a candle melts sealing wax), *mail*, *pilgrimage* (her rail pilgrimage to Rome). Decoy **crayon**, aimed at *wax*: "a crayon merely contains wax and plays no part in that lighting-and-sealing bridge."

*No Give.*

Author B (65 s, $0.25; 4,753 out, 3,904 thinking) — theme "A South Philly rowhouse block settling into a weeknight evening":

- ring **stoop → brick → mural → alley**; clues *front*, *wall*, *graffiti*, *back*. Decoy **door**, aimed at *front*: "Front door is the most automatic completion… Excluded: stoop and brick together are the fixed masonry you can see from the sidewalk without anything moving; the door is the one part that opens, and it would fit *back* just as well, which gives away that it is not anchored to either pair."
- ring **couch → jersey → pretzel → hoagie**; clues *game*, *soft* (jersey knit; a Philly pretzel is always the soft kind), *picnic*, *crumbs*. Decoy **cheesesteak**, aimed at *picnic*: "…the one Philly staple that cannot go on a picnic" because it comes off a hot griddle.

Author A (58 s, $0.069; 3,310 out, 2,935 reasoning) — theme "a Philadelphia weeknight culture crawl":

- ring **cup → book → screen → ticket**; clues *paper*, *adaptation*, *cinema*, *holder* ("cup holder and ticket holder are familiar compounds"). Decoy **camera**, aimed at *cinema*: "a camera belongs to production", the pair describes the audience side.
- ring **coaster → draft → round → quiz**; clues *beer*, *pick* (a draft pick, identified by its round), *trivia*, *pub*. Decoy **bottle**, aimed at *beer*: "bottled beer is packaged rather than draft."

*Give: suburban family life, Fable arm at `effort: "max"`, 100k cap.*

Author B (468 s, $1.78; 35,297 out of which **34,535 thinking**) — theme "suburban family life: the Saturday soccer shuttle and the weeknight living room" — valid on the first attempt:

- ring **minivan → carpool → cleats → mud**; clues *chauffeur* ("the parent as unpaid driver"), *practice*, *caked*, *tracked*. Decoy **piano**, aimed at *practice*: "Practice is the word shouted up the stairs every evening at the kid who has not touched the piano… Excluded: carpool and cleats together fix the sense: the practice you get driven to, on a field, in studded shoes. Piano practice happens at home in socks; nobody carpools to the living room, and piano has no other clue to lean on."
- ring **remote → couch → blanket → thermostat**; clues *lost*, *movie*, *chilly* ("somebody says it is chilly; the answer is a blanket, never the thermostat"), *dad* ("the two sacred controls Dad alone may touch"). Decoy **retainer**, aimed at *lost*: "the household's most-lost object, wrapped in a cafeteria napkin and thrown away weekly… A retainer vanishes at the lunch table, not in the sofa, and nothing about it is chilly, movie, or dad, so it cannot close a ring."

Author A (157 s, $0.18; 8,662 out, 8,194 reasoning) — theme "suburban family life":

- ring **lunchbox → dinner → portrait → diploma**; clues *kitchen*, *family*, *framed*, *school*. Decoy **bus**, aimed at *school*: "a bus is recurring transport, not the finishing milestone supplied by the diploma."
- ring **sprinkler → ball → teammate → minivan**; clues *backyard*, *soccer*, *carpool*, *hose*. Decoy **stocking**, aimed at *hose* (the hosiery sense): "minivan and sprinkler together force the water-tube sense."

Same Give, same schema: Author B's Page is the one my wife would narrate afterwards (the retainer in the napkin, the
thermostat only Dad may touch); Author A's is competent and a little institutional ("familiar household institutions").
Compared with Author B at `high` (65–110 s, $0.25–0.38), `max` bought 4–7× the thinking, 5× the cost and 4–7× the
wall time for a Page of similar legality and arguably sharper wit. Latency is irrelevant for the Author (it runs
before play), so this is a taste-versus-cost call: roughly $2 versus $0.35 per clover Page.

Reading, blind: both Authors produce legal, schema-valid clovers first time, and both understand what a decoy is for.
The difference is in *how the exclusion works*. Author B's decoys are excluded by the **ring's double constraint** (a
card must satisfy two clues at once: "watch is already locked to lace by wrist", "it would fit back just as well, which
gives away…"), which is the fair-misdirection mechanism Stage 0's ring view was built to make visible, and its
rationales are narratable afterwards in the So Clover way. Author A's decoys are excluded by a **category boundary**
(production vs audience, bottle vs draft), which is fair but flatter, and two of its clues are compound-word tricks
(*holder*, *paper*) rather than meaning bridges. Author B's vocabulary is also more *of the Give* (Zélie's lace cuffs,
a Norman orchard's bees, a soft pretzel) where Author A's is a generic Philadelphia evening. On this evidence the
Chronicle Clover bet (an authored decoy beats a blind-drawn one) has an Author that can carry it — at `high`.

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

Per-call lines only, every provider's own token counts, prices as listed at the top (Gemini and DeepSeek from the
addendum). This excludes three killed in-flight Fable clover attempts (two 32k-cap retries stopped after ~3 min each and
one first attempt stopped at ~10 min, all streamed thinking with no output), estimated at **about $3** more from their run
times, so the real total is **about $14**, under the $25 line without an ask.

| model | calls | logged $ |
|---|---|---|
| claude-fable-5-1 | 13 | 7.9869 |
| claude-opus-5 | 272 | 1.2657 |
| gpt-5.6-sol | 6 | 0.6868 |
| claude-sonnet-5 | 279 | 0.4664 |
| accounts/fireworks/models/deepseek-v4-flash-0731 | 722 | 0.2633 |
| gemini-3.7-flash | 244 | 0.1273 |
| gemini-3.8-flash | 245 | 0.0810 |
| gpt-5.6-luna | 383 | 0.0461 |
| zai-org/GLM-5.3-Flash | 446 | 0.0294 |
| **total logged** | 2918 | **10.9529** |

Mac 1762 calls $9.8783; VPS 1156 calls $1.0746

Where it went: 13 Fable calls ($8.0 logged + ~$3 killed) are three quarters of the bill, and one of them (the max-effort
clover) is $1.78 on its own; the six Sol calls cost $0.69. The entire Assayer programme (four benches on two machines, the
20-item assay on nine model/effort arms, ~2,300 verdict calls) cost about $2.10, of which the Opus arm is $1.27 and all of
Gemini and DeepSeek together about $0.45.

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

- **Author `max_tokens`**: 100k at `effort: "max"`, and treat a cap overrun as terminal, never as a retry. Decide
  per kind: `max` for Mind-Meld ($0.15–0.32, under 90 s) is cheap; `max` for clover ($1.78, 7.8 min) versus `high`
  ($0.25–0.38, under 2 min) is a taste call for the couple — generate a few of each blind and let them pick.
- **Assayer choice**: three live options now, decide after the couple labels ~100 pairs (research §5f): (a) GLM 5.3-Flash,
  fastest, noisiest; (b) **Gemini 3.8 Flash at `low`, nearly as fast, Opus-like repeatability, but generous by 10–15 points
  in the middle band, so re-tune the 75 threshold or the rubric**; (c) Sonnet 5 at low effort, fairest of the three that fit,
  at a 2 s P50. Whichever runs live, seed the Chronicle's precedent with an Opus 5 second opinion on borderline pairs
  (60–85) and on every overrule.
- **GLM cap**: 160 tokens was hit once in 40; either 200 or a firmer "under 25 words" instruction.
- Cancel hedge losers cooperatively (done here) and keep `pool_timeout` generous; watch the VPS.
- Scribe output through the Vale gate (length, em dashes, AI tells) before it reaches the Chronicle, as planned.
- Log `thinking_tokens` and `reasoning_tokens` per call into the Chronicle's call record; they are the cost.
- The Fake adapter should serve golden JSON from files so Stage 0-style walkthroughs can run against the real seam.

## Addendum — Gemini 3.7 / 3.8 Flash and DeepSeek V4 Flash 0731, added at Jacob's request

Added after the first report. `gemini-3.7-flash` and `gemini-3.8-flash` (Google, OpenAI-compatible endpoint,
`reasoning_effort: "low"`; thinking cannot be turned off and `minimal` is rejected on these two; $0.75 / $3.75 per MTok
through 2026-12-31, output priced with thoughts) and `accounts/fireworks/models/deepseek-v4-flash-0731` on Fireworks
serverless ($0.22 / $0.66 per MTok) at `reasoning_effort` **max** (Jacob's ask), **low** and **none**. Same bench, same
assay set, same evening (Mac and VPS runs about an hour after the first ones).

### Latency (Mac, n=20, item 9, cache off)

| candidate | model (effort) | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gemini37 | gemini-3.7-flash (low) | 1,264 | 2,203 | 1,408 | 2,277 | 104.3 | 921.9 | 1,329.1 | PASS | PASS | 0/20 |
| gemini38 | gemini-3.8-flash (low) | 656 | 3,051 | 760 | 3,198 | 39.9 | 324.1 | 841.1 | PASS | PASS | 0/20 |
| deepseek_max | accounts/fireworks/models/deepseek-v4-flash-0731 (max) | 7,151 | 15,241 | 7,514 | 15,413 | 685.9 | 3,222.2 | 7,169.6 | **FAIL** | **FAIL** | 1/20 |
| deepseek_low | accounts/fireworks/models/deepseek-v4-flash-0731 (low) | 2,747 | 5,647 | 3,163 | 5,828 | 289.7 | 1,009.7 | 2,806.4 | **FAIL** | **FAIL** | 0/20 |
| deepseek_none | accounts/fireworks/models/deepseek-v4-flash-0731 (none) | 315 | 1,533 | 972 | 2,200 | 36.6 | 57.8 | 1,352.6 | PASS | PASS | 0/20 |

Warm-up (discarded): gemini37 ttft=1,576 total=1,633; gemini38 ttft=2,047 total=2,115; deepseek_max ttft=9,566 total=9,774; deepseek_low ttft=8,845 total=9,037; deepseek_none ttft=1,227 total=1,913

### Latency (VPS, n=20, item 9, cache off)

| candidate | model (effort) | ttft p50 | ttft p95 | total p50 | total p95 | out tok | tok/s p50 | ttft+60/tps | p50 rule ≤2.5s | p95 rule ≤4s | failures |
|---|---|---|---|---|---|---|---|---|---|---|---|
| gemini37 | gemini-3.7-flash (low) | 1,234 | 1,674 | 1,347 | 1,845 | 131.3 | 760.2 | 1,312.9 | PASS | PASS | 0/20 |
| gemini38 | gemini-3.8-flash (low) | 594 | 804 | 718 | 959 | 39.4 | 310.3 | 787.3 | PASS | PASS | 0/20 |
| deepseek_max | accounts/fireworks/models/deepseek-v4-flash-0731 (max) | 9,288 | 27,955 | 9,508 | 28,105 | 979.4 | 3,690.9 | 9,304.3 | **FAIL** | **FAIL** | 0/20 |
| deepseek_low | accounts/fireworks/models/deepseek-v4-flash-0731 (low) | 2,849 | 4,788 | 3,041 | 4,992 | 273.4 | 1,112.9 | 2,902.9 | **FAIL** | **FAIL** | 0/20 |
| deepseek_none | accounts/fireworks/models/deepseek-v4-flash-0731 (none) | 378 | 1,125 | 1,030 | 2,515 | 36.8 | 58.8 | 1,398.0 | PASS | PASS | 0/20 |

Warm-up (discarded): gemini37 ttft=1,684 total=1,854; gemini38 ttft=919 total=1,063; deepseek_max ttft=4,290 total=4,479; deepseek_low ttft=4,171 total=4,324; deepseek_none ttft=685 total=1,259

### Hedging (Mac, 2 identical requests, first wins, n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 |
|---|---|---|---|---|---|---|
| gemini37 | 2,277 | 1,511 | 1,408 | 1,307 | 2,203 | 1,413 |
| gemini38 | 3,198 | 864 | 760 | 738 | 3,051 | 769 |
| deepseek_max | 15,413 | 19,100 | 7,514 | 6,226 | 15,241 | 18,919 |
| deepseek_low | 5,828 | 4,165 | 3,163 | 3,109 | 5,647 | 3,885 |
| deepseek_none | 2,200 | 1,515 | 972 | 1,022 | 1,533 | 1,428 |

### Hedging (VPS, 2 identical requests, first wins, n=20)

| candidate | unhedged total p95 | hedged total p95 | unhedged total p50 | hedged total p50 | unhedged ttft p95 | hedged ttft p95 |
|---|---|---|---|---|---|---|
| gemini37 | 1,845 | 1,475 | 1,347 | 1,289 | 1,674 | 1,424 |
| gemini38 | 959 | 920 | 718 | 681 | 804 | 841 |
| deepseek_max | 28,105 | 18,310 | 9,508 | 6,289 | 27,955 | 18,094 |
| deepseek_low | 4,992 | 5,257 | 3,041 | 3,001 | 4,788 | 5,089 |
| deepseek_none | 2,515 | 1,036 | 1,030 | 851 | 1,125 | 386 |

### Repeat agreement (Mac, same submission ×5, cache off)

| candidate | item 1 moon/moon | item 7 butter/spread | item 9 tide/moon | item 18 paper/scar |
|---|---|---|---|---|
| gemini37 | 100 ×5 | 85, 85, 82, 78, 82 (range 7) | 68, 68, 72, 72, 65 (range 7) | 10, 8, 12, 12, 10 (range 4) |
| gemini38 | 100 ×5 | 85, 85, 78, 85, 84 (range 7) | 72, 72, 72, 72, 72 (range 0) | 12, 12, 12, 12, 15 (range 3) |
| deepseek_max | 100 ×5 | 70, 70, 65, 70, 85 (range 20) | 60, 60, 60, 65, 55 (range 10) | 25, 30, 55, 30 (range 30) |
| deepseek_low | 100 ×5 | 65, 65, 65, 70, 65 (range 5) | 60, 80, 65, 60, 60 (range 20) | 10, 20, 25, 20, 20 (range 15) |
| deepseek_none | 100 ×5 | 80, 70, 65, 80, 65 (range 15) | 45, 55, 55, 35, 45 (range 20) | 25, 35, 35, 15, 15 (range 20) |

### Repeat agreement (VPS, same submission ×5, cache off)

| candidate | item 1 moon/moon | item 7 butter/spread | item 9 tide/moon | item 18 paper/scar |
|---|---|---|---|---|
| gemini37 | 100 ×5 | 85, 78, 85, 82, 85 (range 7) | 68, 70, 70, 65, 68 (range 5) | 10, 12, 15, 10, 12 (range 5) |
| gemini38 | 100 ×5 | 85, 82, 85, 78, 85 (range 7) | 72, 72, 68, 72, 76 (range 8) | 12, 5, 10, 12, 12 (range 7) |
| deepseek_max | 100 ×5 | 70, 80, 65, 78, 70 (range 15) | 60, 60, 65, 58, 60 (range 7) | 25, 45, 15, 30, 20 (range 30) |
| deepseek_low | 100 ×5 | 65, 65, 60, 70, 75 (range 15) | 60, 60, 60, 65, 60 (range 5) | 20, 25, 50, 20, 20 (range 30) |
| deepseek_none | 100 ×5 | 65, 70, 70, 60, 78 (range 18) | 45, 55, 45, 55, 35 (range 20) | 15, 35, 15, 35, 15 (range 20) |

### Ordering agreement (Mac, (A,B) vs (B,A), 20 items)

| candidate | mean abs diff | max abs diff | within 5 | graded pairs |
|---|---|---|---|---|
| gemini37 | 4.0 | 15 | 75.0% | 20 |
| gemini38 | 4.3 | 27 | 75.0% | 20 |
| deepseek_max | 5.7 | 20 | 65.0% | 20 |
| deepseek_low | 9.2 | 35 | 68.4% | 19 |
| deepseek_none | 7.4 | 25 | 57.9% | 19 |

### Ordering agreement (VPS, (A,B) vs (B,A), 20 items)

| candidate | mean abs diff | max abs diff | within 5 | graded pairs |
|---|---|---|---|---|
| gemini37 | 2.8 | 13 | 80.0% | 20 |
| gemini38 | 4.3 | 40 | 80.0% | 20 |
| deepseek_max | 3.1 | 10 | 88.2% | 17 |
| deepseek_low | 5.5 | 15 | 68.4% | 19 |
| deepseek_none | 8.3 | 35 | 57.9% | 19 |

### Assay (Mac, cache off, both orderings; reconciled closeness (forward/reverse))



| # | anchors | A / B | expected | gemini37 | gemini38 | deepseek_max | deepseek_low | deepseek_none |
|---|---|---|---|---|---|---|---|---|
| 1 | ocean+night | moon / moon | 100 identical | 100 (100/100) | 100 (100/100) | 100 (100/100) | 100 (100/100) | 100 (100/100) |
| 2 | ocean+night | tide / tides | ~100 inflection | 100 (100/100) | 100 (100/100) | 100 (100/100) | 100 (100/100) | 100 (100/100) |
| 3 | mirror+river | reflection / reflect | ~95 | 98 (98/98) | 99 (100/98) | 90 (90/90) | 90 (90/90) | 90 (85/95) |
| 4 | coffee+morning | cup / mug | ~90 synonyms | 93 (95/90) | 91 (90/92) | 90 (90/90) | 93 (90/95) | 83 (85/80) |
| 5 | fire+ice | melt / thaw | ~90 synonyms | 95 (95/95) | 95 (94/95) | 90 (90/90) | 85 (85/85) | 83 (75/90) |
| 6 | garden+prison | wall / fence | ~80 near | 89 (88/90) | 88 (88/88) | 74 (65/82) | 73 (60/85) | 70 (70/70) |
| 7 | bread+knife | butter / spread | ~75 borderline meld | 80 (82/78) | 79 (80/78) | 68 (65/70) | 80 (80/80) | 63 (60/65) |
| 8 | king+castle | throne / crown | ~70 related | 83 (80/85) | 84 (85/82) | 75 (80/70) | 75 (70/80) | 68 (70/65) |
| 9 | ocean+night | tide / moon | ~55 related | 70 (70/70) | 72 (72/72) | 58 (55/60) | 60 (55/65) | 45 (35/55) |
| 10 | coffee+morning | alarm / awake | ~60 related | 72 (78/65) | 69 (72/65) | 58 (60/55) | 60 (65/55) | 50 (65/35) |
| 11 | fire+ice | water / steam | ~60 related | 78 (78/78) | 76 (72/80) | ERR | ERR | 70 (65/75) |
| 12 | doctor+silence | waiting / hospital | ~45 | 49 (45/52) | 52 (58/45) | 48 (30/65) | 43 (40/45) | 40 (35/45) |
| 13 | doctor+silence | oath / secret | ~50 | 72 (72/72) | 68 (72/64) | 58 (55/60) | 59 (50/68) | 50 (45/55) |
| 14 | letter+wound | open / seal | ~35 antonym-ish | 52 (48/55) | 58 (70/45) | 50 (50/50) | 58 (60/55) | 25 (20/30) |
| 15 | train+dream | journey / sleep | ~30 | 20 (25/15) | 23 (25/20) | ERR | 15 (15/15) | 23 (20/25) |
| 16 | king+castle | moat / queen | ~30 | 23 (25/20) | 23 (25/20) | 23 (30/15) | 20 (30/10) | 23 (20/25) |
| 17 | train+dream | track / drift | ~25 | 21 (24/18) | 19 (15/22) | ERR | 45 (45/45) | 40 (35/45) |
| 18 | letter+wound | paper / scar | ~15 miss | 8 (10/5) | 14 (12/15) | 20 (20/20) | 13 (20/5) | 30 (45/15) |
| 19 | garden+prison | weed / cell | ~15 miss | 10 (15/5) | 10 (10/10) | 18 (20/15) | 15 (15/15) | 15 (20/10) |
| 20 | mirror+river | glass / bank | ~10 miss | 10 (10/10) | 8 (5/10) | 13 (15/10) | 13 (10/15) | 25 (15/35) |



| candidate | mean | max | within 5 | melded (≥75) | errors |
|---|---|---|---|---|---|
| gemini37 | 4.0 | 13 | 70.0% | 9 | 0 |
| gemini38 | 4.8 | 25 | 70.0% | 9 | 0 |
| deepseek_max | 6.3 | 35 | 76.5% | 6 | 3 |
| deepseek_low | 6.7 | 25 | 63.2% | 7 | 1 |
| deepseek_none | 10.5 | 30 | 40.0% | 5 | 0 |



Reasoning samples (forward ordering):



- **7 bread + knife: butter / spread**
  - gemini37: Butter is the archetypal spread applied to bread with a knife, linking them closely in the same functional context.
  - gemini38: Butter is the quintessential spread applied to bread with a knife, making them closely linked as a noun and its direct category or action.
  - deepseek_max: Butter is a specific kind of spread; both share the bread-and-knife context, but 'spread' is broader.
  - deepseek_low: Both refer to something put on bread with a knife; butter is a type of spread, so they share the same core idea.
  - deepseek_none: Butter is a specific spread, so they're related but not the same idea.
- **9 ocean + night: tide / moon**
  - gemini37: The moon directly governs the tide, making these closely related physical phenomena that both naturally connect the ocean to the night.
  - gemini38: Tide and moon are intimately connected concepts through lunar gravity, representing closely related associations to the night ocean.
  - deepseek_max: Tide is an ocean effect caused by the moon; the moon is a night sky body. Connected, yet distinct ideas.
  - deepseek_low: Both evoke ocean and night, but moon is the cause, tide the effect, making them related yet distinct ideas.
  - deepseek_none: Tide and moon are distinct natural phenomena linked to ocean and night, but only conceptually related, not the same idea.
- **14 letter + wound: open / seal**
  - gemini37: The players targeted the exact same conceptual axis relating to letters and wounds, but chose direct antonyms for their bridge.
  - gemini38: Open and seal are direct antonyms acting on the exact same domain, representing opposite states of the anchors.
  - deepseek_max: Open and seal are opposite actions, yet each naturally applies to both a letter and a wound; related but not melded.
  - deepseek_low: Both are common actions performed on letters and wounds, but they are opposites, making them related yet distinct.
  - deepseek_none: Open and seal are opposites (as verbs for wounds/letters), but not the same idea in bridging meaning.
- **18 letter + wound: paper / scar**
  - gemini37: Paper and scar represent completely different concepts with essentially no shared meaning.
  - gemini38: Paper and scar represent completely different concepts, sharing little meaning aside from tangential associations to the anchors.
  - deepseek_max: Paper relates to letter as material, scar to wound as remnant; they share no common idea.
  - deepseek_low: Paper and scar are both associated with cuts, but they are otherwise distinct objects with little semantic overlap.
  - deepseek_none: Both relate to physical marks, but paper suggests a cut while scar implies healed tissue, distinct ideas.
- **20 mirror + river: glass / bank**
  - gemini37: Glass and bank connect to the anchors in completely different ways (material/surface versus landscape feature) and share little meaning.
  - gemini38: Glass refers to the reflective material of a mirror, while bank refers to the physical edge of a river, representing completely distinct concepts.
  - deepseek_max: Glass leans toward mirror, bank toward river; they occupy different semantic paths with little overlap.
  - deepseek_low: Glass and bank share little beyond vague physical associations with the anchors; they are different ideas.
  - deepseek_none: Glass reflects like a mirror; bank is a river's edge. They share no direct conceptual overlap.

Addendum spend: Mac bench gemini37 $0.0522; gemini38 $0.0331; deepseek_max $0.0695; deepseek_low $0.0233; deepseek_none $0.0092; VPS bench gemini37 $0.0537; gemini38 $0.0333; deepseek_max $0.0666; deepseek_low $0.0227; deepseek_none $0.0092.

### Reading

- **Gemini 3.8 Flash at `low` is the new front-runner for the live Assayer.** From the VPS its first answer token lands at
  594 ms P50 and the whole verdict at 961 ms P95 (Mac: 656 ms / 3.2 s, one tail event), second only to GLM on speed, and it
  is the most repeatable non-Anthropic grader measured tonight: five identical grades on tide/moon on the Mac, repeat
  ranges 0–8 everywhere else, ordering disagreement 4.3 mean on both machines with one outlier each (27 and 40). Cost per
  verdict was about $0.0003 (thinking billed).
- **Gemini 3.7 Flash** passes both rules too, with equally tight repeat (4–7) and ordering (2.8–4.0), but its first token
  takes twice as long (1.2–1.3 s P50), so 3.8 dominates it. Note that for both Gemini arms the `out tok` and `tok/s`
  columns include thinking tokens (the OpenAI-compatible endpoint reports `total − prompt`), so tok/s is inflated; the
  pass rule is carried by TTFT anyway.
- **DeepSeek V4 Flash 0731 at `max`** (Jacob's ask) is out of the question for the beat: 7–9 s P50, 15–28 s P95, and
  3 of 20 ordering pairs overran a 4,000-token cap on thinking alone. At `low` it still fails both rules (2.7–2.8 s P50,
  5–5.8 s P95). At `none` it fits (315–378 ms first token, P95 total 2.2–2.5 s) but grades as noisily as GLM (repeat
  ranges 15–20, ordering 7–8 mean). Fireworks also served two 504 gateway timeouts and several 20 s queue waits during
  the assay, and hedging rescued its tail (VPS `none` P95 2.5 s → 1.0 s), which says the tail is the queue, not the model.
- **Assay quality.** Both Gemini arms agree with everyone at the extremes (items 1–6, 15–20) and are *stable* in the
  middle, but they grade the middle **10–15 points more generously than Opus and Sonnet**: tide/moon 70–72 (Opus 55),
  throne/crown 83–84 (Opus 64), oath/secret 68–72 (Opus 53), open/seal 52–58 (Opus 42), and water/steam 76–78, which
  makes it a *meld* under Gemini and not under any Anthropic grader (9 melds out of 20 versus 7). That is a calibration
  offset, not noise: the same pairs land in the same order, just higher. If Gemini becomes the Assayer, the 75 threshold
  or the rubric in the prompt needs re-tuning against the couple's labels. Its reasoning reads plainly and fairly (see
  samples above). DeepSeek at `max` and `low` grade close to Opus where they completed (wall/fence 73–74, tide/moon
  58–60) but with 4 errors in 40; at `none` it is loose and noisy (paper/scar 45 in one ordering, 15 in the other).

## Blind key

Throughout this report, **Author A = `gpt-5.6-sol` (`reasoning_effort: "xhigh"`)** and **Author B = `claude-fable-5-1`**
(`effort: "max"` for Mind-Meld and the suburban clover; `effort: "high"` for the other two clovers). The per-run labels
printed by `mix keeper.author --author both` were randomised by seed (`Keeper.AB.assign/2`) and re-normalised here.
