# Design brief — the meaning game

Status: grilling complete 2026-09-01; next phase is the couch-night prototype (handoff written to the OS temp dir; see the design session). Last updated 2026-09-01.

## Vision

A game that plays with meaning. The bar, above everything else: **fun** — operationalized as **"a game Melissa likes."**

## Players

- **Melissa** — the target player. Loves So Clover and NYT Connections (savors the red-herring misdirection and narrates the clever traps afterward), Boggle (family history), crosswords. Likes Codenames, Taboo, Telestrations, Monikers, Tick Tock: A Tale for Two (finished recently, played with Jacob), probably Scrabble; Wordle to a lesser extent. Plays a word/meaning game roughly daily on her phone (Pixel 10 Pro XL, Android). Doesn't play humorous games alone — wit belongs in the content; clever-aha is the primary fun.
- **Jacob** — builder, and co-player if the two-player direction wins.

## The confirmed pattern

Her favorite games are all *one word's meaning stretched to cover several things at once*, spiced with **fair misdirection**. And the most-loved tier — So Clover, Codenames, Taboo, Monikers, Telestrations, Tick Tock — is entirely **communication games**: meaning passed between minds. The solo puzzles (Connections, crosswords, Boggle) are her alone-games; the loved-most tier is the together-tier.

## Settled decisions

- **Fun target**: clever-aha first; wit woven into the content, not slapstick gameplay.
- **Platform**: mobile-first web app, judged purely on fun grounds — maximum mechanic-experiments per hour, and a URL opens instantly on Melissa's Pixel. A game engine (Godot/Bevy/etc.) gets adopted only if the chosen mechanic demands physical juice; unfamiliarity will not count against it.
- **Tech selection principle**: choices are judged only by the fun of the result and speed of iterating toward it — never by what Jacob already knows.
- **LLM / agents at runtime**: allowed and actively interesting — the affordances of non-deterministic language technology in games are under-explored — but **optional, not a mandate**. An LLM must earn its place by enabling something otherwise impossible.
- **Scope**: a household toy until fun is proven; maybe a public thing (b) or product (c) after.
- **Two-player** (decided 2026-08-31): designed for Jacob and Melissa playing *together* — same couch, synchronous, evenings. No workday async; Jacob protects daytime focus. Her solo slots are saturated; the couple slot has been vacant since they finished Tick Tock. A solo mode can come later (the LLM understudies Jacob's seat).
- **Design thesis for the machine** (revised 2026-08-31 — see ADR-0001): **the machine holds no player seat.** If a human could do a role better, the role stays human, or the design waits for more humans. The machine takes only superhuman jobs: nightly author of boards for an audience of two, keeper of the Chronicle, instant and consistent meter of meaning-distance — the couple's live-in game designer, scribe, and instrument. (This supersedes the earlier "third seat makes group games two-player" framing; the research's six crowd jobs remain a map of what *not* to automate when a person would relish the job.)
- **Table hardware**: two phones as private screens; a laptop as an optional shared public screen is open creative space (reveal theater, Chronicle recaps) — private/public information display is a design axis to exploit.
- **Stance**: cooperative versus the game with graded score ladders. Melissa also enjoys competitive Boggle, so a light competitive garnish may return in later modes.
- **Legacy**: light memory in the prototype, architected so campaign structure is reachable; the artifact is the **Chronicle** (see CONTEXT.md), visible and player-editable per design law 5.
- **Session atom**: a **Page** (decided 2026-09-01) — one self-contained unit of play that ends cleanly in ~10–15 minutes and chains ("one more?" is a single tap); every Page is written into the Chronicle. The vocabulary is Page → Chapter → Chronicle (see CONTEXT.md). No streaks, no obligation mechanics.
- **Chronicle storage** (decided 2026-09-01, ADR-0003): Postgres via Ecto — append-only event tables (Pages, rulings, overrules, player edits; versions are the log itself, no in-game git), the Page document as JSONB; already running on the server and reachable from Docker containers, docker-compose locally. Views are computed, never stored: the LiveView book page for players, a Keeper-composed digest for in-game models, and an on-demand Markdown render (`mix chronicle.export` or `GET /chronicle.md`) for humans and coding agents. pgvector recall over past Pages is a post-couch-night feature.
- **Referee posture** (closed 2026-09-01): grades not gavels; reasoning always shown; the couple can jointly overrule anything, and overrules are recorded in the Chronicle as precedent.
- **Stack** (decided 2026-09-01, ADR-0002): Phoenix / Elixir / LiveView, hosted on stephens.page. Chosen for rooms, server-authoritative state, the private/public split, and less client code — and because Jacob wants to learn Elixir. Kill criterion: three evenings to a working two-phone room with rejoin, else TypeScript + Socket.IO.
- **Model policy, v1** (fun regardless of cost): Author `claude-fable-5-1` at max effort; Scribe `claude-fable-5-1` at max effort; the Assayer on **GLM 5.3-Flash via Baseten** (0.65 s P50 to first token, index 57), contingent on a benchmark from the VPS showing P95 inside the 2.5 s beat; a second candidate (Kimi K3, or GLM 5.3 at a lower effort row) interleaved once the harness exists; GPT-5.6 Sol (max) as an A/B arm for Author and Scribe if cheap to add. All via API keys (consumer subscriptions don't license app use). Per-role model + effort config behind one adapter module; verdict cache keyed by model + prompt version + inputs.
- **A/B testing is a v1 feature in its own right** — Jacob wants the practice for professional work: Page-level randomized assignment, blinded variant labels, stratification by Chapter, every outcome logged to the Chronicle, a qualitative readout (n is two people, so streaks and preferences, not p-values).
- **Code shape principle**: few deep modules and boring data. The game's rules should fit in one readable file — Karpathy-style minimalism reached *through* deep-module design, not against it; framework scaffolding stays generated and thin.
- **Keeper** (named 2026-09-01): the one module through which the game talks to language models — see CONTEXT.md. Vale's AiTells package is adopted for the Scribe gate.
- **Git conventions** (2026-09-01): design docs commit directly to `master`; `master` stays deployable (the Docker release builds from it); the prototype lives on `prototype/<name>` and is never merged; later feature work on short-lived branches with `/code-review` before merge, GitHub PRs optional.
- **Assayer** (named 2026-09-01): the grading role — measures closeness and clue legality at the reveal, shows its reasoning, never rules; a nod to Melissa's daily lab assays. See CONTEXT.md.
- **Deployment** (decided 2026-09-01): Docker release (`mix phx.gen.release --docker`) so the identical image runs on the Mac and on the server; behind an Apache 2.4.58 vhost (`ProxyPass "/" "http://127.0.0.1:<port>/" upgrade=websocket`, certbot for TLS) matching Jacob's existing pattern of localhost-proxied apps. Elixir/Erlang via mise on the Mac for development.
- **Legacy direction** (interest declared; depth undecided): sessions write persistent files that shape future games — Pandemic Legacy energy. The game remembers the couple's history and plays it back.

## Design laws (from research)

Distilled from `docs/research/llm-in-word-games.md` (prior art on LLM judges/referees/game-masters in word games; each law cites primary sources there):

1. **Consistency beats accuracy.** Players forgive wrong rulings, never self-contradicting ones. Same inputs → same ruling, forever; cache every verdict.
2. **Grade, don't gavel.** Comparative/graded feedback (rank, closeness) defuses resentment; binary verdicts survive only at joke stakes.
3. **Humans hold final authority.** Appeals are shipped precedent; a joint player overrule is legitimate and becomes Chronicle lore.
4. **Pre-generate and rank, don't live-generate.** Boards/decoys made ahead and ranked — turns generation problems into ranking problems and kills mid-play latency.
5. **Memory is a visible, player-editable artifact.** Silent forgetting and opaque rulings are named trust-killers; the Chronicle should be readable and correctable by the players.

From `docs/research/two-player-communication-mechanics.md` (why group word games fail at two, per official rules and designers' own words):

6. **The crowd does six nameable jobs**: opponent-as-judge, independent co-writers, vote market, chain length, eavesdropper, rival-team race. "Third seat" = staffing whichever of these the chosen mechanic needs.
7. **The boundary is free language.** Publishers successfully staff *mechanical* seats with dummies and bots (The Crew's JARVIS, Letter Jam's stands, Automa); every seat that must *understand free language* was left broken at two or given a hard 3-player floor. That unstaffable seat is precisely the LLM's claim.
8. **At two, go co-op with a graded score ladder.** Every official 2P conversion did (Wavelength co-op, Medium, Codenames' scoring table, Monikers' fallback); Codenames Duet's mission map is a ready-made legacy hook.
9. **Misdirection survives without a rival team** two proven ways: symmetric clue-givers with overlapping keys (Codenames Duet — designed by Scot Eaton to play with his wife), or blind decoys (So Clover). Both fit a couple.

From `docs/research/model-selection-for-play.md` (leaderboard methodology, HCI latency evidence, judge-quality literature):

10. **The reveal is a fixed beat, not a wait.** Fire the Meter the instant the second player commits; a fixed ~2.5 s reveal beat absorbs the p50 verdict (Shneiderman licenses slowing fast responses to keep variability under ±50%); p95 ≤ 4 s with visible activity; provisional result at 8 s; never past 10 s. Shorten the beat for harsh grades (the labor illusion backfires on bad news).
11. **Nothing is deterministic at any tier** — 1,000 temperature-0 calls yielded 80 unique completions. The verdict cache is the consistency mechanism; hedged requests must be *identical* requests to *one* model, never different models.
12. **Grade both orderings in parallel** (position bias is the tier-linked judge failure) and read the leaderboard at the effort row you'd actually run: its Latency column already includes thinking time. Meter rule of thumb: `Latency + 60 ÷ Speed ≤ 2.5 s`. The Intelligence Index contains no semantic-judgment, word-association, or puzzle-construction evals — it is a shortlist, never a decision.
13. **Authors must be frontier-tier** — small models fail on rule/format-following (invalid clues), while frontier similarity ratings match or beat human inter-annotator agreement. Where the answer space allows, the Author pre-grades so the live Meter is a lookup.

From `docs/research/deterministic-guardrails.md` (Vale, Elixir stemming/wordlists, provider schema guarantees):

14. **Never send a model to do a linter's job.** Every role's output passes a deterministic gate: a schema validator has the last word (providers guarantee shape unevenly — Gemini says "always validate"); Author clues pass Elixir legality filters (regex, ENABLE/SCOWL wordlists, stem + inflection-table root check, profanity list) with reject-and-regenerate; Scribe prose passes a Vale gate (custom Scribe style + write-good + proselint + AiTells) with one model repair pass. Shell out only for Vale; everything else lives in Elixir.

Validated gap, both files agreeing: no prior art combines LLM referee + two-player meaning game + legacy memory — and no digital-native two-player couch word game exists at all (two-device voice-linked co-op is proven by Tick Tock / The Past Within, but never crossed with words).

## Open questions

- **Prototype pair adopted (2026-09-01)**: an A/B couch night of the clover candidate (working label "Chronicle Clover" — deliberately *not* a real name; too close to So Clover) and **Mind-Meld**. The clover kill criterion stands: if the couch verdict is "So Clover with extra steps," cardboard wins. Adaptive Taboo stays benched.
- **Chapters and gives** (adopted as a direction, 2026-09-01): on-request exploration of a meaning-space, at two commitment levels — a deliberate themed journey (e.g. words of suburban family life, of Children's Hospital of Philadelphia, of the world St. Thérèse grew up in, of Newman's vein) or an improv-style instant give (Whose Line energy: name a setting, and tonight's play is suddenly set there). Works across both candidates. This is the Author's signature power: no publisher can print a deck for a meaning-space you name at 9pm.
- **House-rules as precedent** (Nomic-inspired, bounded): joint overrules and standing preferences accrete in the Chronicle as the couple's house-law, so their copy of the game slowly becomes *theirs*. Full Nomic (rule-amendment as the game) deliberately waits for three-plus humans; 1000-Blank-White-Cards-style player authorship is the direction — absorbed by the machine, not simulated by it.
- **Naming, parked until after couch night**: both games' real names; the umbrella term for the machine's roles ("Keeper" proposed, on hold). The session atom is settled as Page.
- **Clue-legality library**: build in Elixir (stem + prefix + inflection-table root check, ENABLE/SCOWL wordlists, profanity list; the grading model as cached fallback for the long tail). The need is small and not a reason to revisit ADR-0002; a candidate to extract as an open-source hex package once the prototype proves it.
- **Deterministic guardrails**: research landed (design law 14; per-role pipelines in docs/research/deterministic-guardrails.md). Adopt for the prototype in the cheapest form — schema validation everywhere, the clue-legality filter for the Author — and add the Vale gate (Scribe style + AiTells) once the Scribe exists. Research landed: docs/research/couch-sync-stack.md (Socket.IO strongest fit, Phoenix genuine runner-up; "reconnect + full snapshot" is the normal path on phones) and docs/research/oss-couch-games.md (read-first prior art: cjquines/just-one, horsepaste, opencraft's server, outofcontext; boardgame.io = concepts yes, dependency no; AGPL/unlicensed repos study-only). Recommended shape: Node/TypeScript + Socket.IO monolith, in-memory rooms snapshotted to disk, seat-rebinding rejoin, laptop as spectator client, deterministic keyed verdict cache doubling as Chronicle precedent, one seat interface so a bot could understudy later.
- **Post-couch-night Postgres roadmap** (deliberately out of the prototype): **Oban** (Postgres-native job queue, signals workers via LISTEN/NOTIFY) for overnight Author pre-generation, post-play Scribe runs, and Assayer benchmarks; **pgvector** for personal-best closeness ladders ("third-closest you've ever landed") and thematic callbacks when a Give is semantically near past Pages; embedding cosine as a deterministic closeness instrument to interleave against the Assayer; embeddings via Voyage/OpenAI/Google or locally with Bumblebee. JSONB for the Page document is used from the prototype onward.
- Deprioritized: outward sharing/result cards — couch play removes the original need; revisit only if the game goes public.

## Parked (not this game)

- **RTS with LLM-driven units** — Jacob's someday-experiment: AoE/StarCraft-style play where individual visible units are LLM/agent-powered.
- Contexto/Semantle-likes — reference points for daily semantic-puzzle stickiness, but embeddings-based and off-thesis here.
