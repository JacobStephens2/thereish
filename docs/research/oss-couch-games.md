# OSS couch games — implementation prior art

Surveyed 2026-09-01, all metadata (stars, last push, license) read from the repos that day.
Scope: what these codebases teach about **building** a two-phones-private + laptop-public,
room-code, one-household word game. Mechanic inspiration lives in
`llm-in-word-games.md` and `two-player-communication-mechanics.md`; transport/framework
*comparison* is `couch-sync-stack.md`'s job — here each repo's transport choice is noted
only as a one-line data point.

---

## 1. The framework: boardgame.io

**[boardgameio/boardgame.io](https://github.com/boardgameio/boardgame.io)** — MIT, 12.4k stars, TypeScript.

- **What it is**: the OSS turn-based-game framework: game = plain object of `moves` over
  immutable state `G` + framework context `ctx`.
- **What it gives free** (all verified in `docs/documentation/`):
  - **Phases / turns / stages** — [stages](https://github.com/boardgameio/boardgame.io/blob/main/docs/documentation/stages.md)
    let *multiple players act inside one turn, each in their own stage*: the exact shape of
    "both players privately submit, then reveal." This is the hardest part of a
    simultaneous-play word game and it's a solved, documented primitive here.
  - **Secret state** — [`playerView`](https://github.com/boardgameio/boardgame.io/blob/main/docs/documentation/secret-state.md)
    redacts `G` per player *server-side before sending*; bundled `PlayerView.STRIP_SECRETS`
    convention: a `G.secret` key plus `G.players[id]` private pockets, stripped to the viewer's own.
  - **Lobby** — REST API (create/join/leave/list) issuing **per-seat credential tokens**;
    the server refuses moves without the right token. Rejoin = present the same credentials.
  - **Storage adapters** — in-memory, `FlatFile`, community `bgio-postgres` / `bgio-firebase`.
- **Maintenance status (2026)**: two-sided. The repo is *active* — a new maintainer
  (Ivett Ördög) spent Jul–Aug 2026 modernizing CI/build (ESLint 9, pnpm, dependency
  refresh) with occasional fixes from others — but the **last npm release is 0.50.2,
  2022-11-10**; nothing has shipped in ~4 years. Treat it as usable-but-frozen: sound
  concepts, uncertain release future.
- **Transport (data point)**: bundled socket.io client/server master, plus a local
  (no-network) transport used for prototyping and bots.
- **Read for**: the *concepts* (playerView, stages, seat credentials) port to any stack even
  if the dependency is skipped. For a fixed two-seat household game, its generic lobby is
  overkill.

---

## 2. The Jackbox shape — phones as controllers, shared screen

### rocketcrab — the join-friction specialist
**[tannerkrewson/rocketcrab](https://github.com/tannerkrewson/rocketcrab)** — MIT, 268 stars, pushed 2026-08, TypeScript/Next.js.

- **What it is**: a meta-lobby ("party games for phones") that launches other web games
  into iframes so a group enters *one* code all evening.
- **Worth stealing**:
  - Room codes are **4 lowercase letters**, uniqueness-checked, `ffff` reserved as a dev
    room that auto-joins (`localhost:3000/dev`) — a tiny feature that speeds every test loop.
  - **Rejoin**: client stashes party state (uuid + its numeric player id); on reconnect the
    server honors `previousId` if unused, so the seat survives a refresh. Host is a flag
    recomputed from an `idealHostId`, re-assigned if the host leaves.
  - Its integration contract is a clean statement of the minimum lobby API any game needs:
    *an endpoint that creates a room and returns its code, plus join-by-URL*
    (`yourgame.com/abcd`); it passes each player's `name` and `ishost` as query params.
  - Empty parties are destroyed immediately (except the dev room) — no cleanup cron.
- **Transport (data point)**: socket.io.

### Massive Decks — the "central screen optional" pattern
**[Lattyware/massivedecks](https://github.com/Lattyware/massivedecks)** — **AGPL-3.0**, 500 stars, pushed 2023-11, Elm client + TypeScript server.

- **What it is**: Cards Against Humanity-like with first-class couch support: "You can set
  up a central screen, but you don't need to" — Chromecast + spectator views built in.
- **Worth stealing**: the shared screen is *just another client* in a spectator role, not a
  special server mode — exactly our laptop. Games private by default, optional password.
  Server dependencies reveal the sync design: `express-ws` (WebSockets), `rfc6902` +
  `fast-json-patch` (**JSON Patch diffs** of server state to clients), `jsonwebtoken`
  (**a JWT per seat** = rejoin token), `hashids` (short codes from internal ids), `pg`.
- **Transport (data point)**: WebSockets pushing JSON-Patch deltas over a server-authoritative document.
- **License caution**: AGPL — read the architecture, don't lift code.

### Drawphone — seats that survive people
**[tannerkrewson/drawphone](https://github.com/tannerkrewson/drawphone)** — MIT, 293 stars, pushed 2024-10, Node/jQuery.

- **What it is**: Telestrations on phones (the author's admitted "first project" spaghetti — read selectively).
- **Worth stealing**: **`PlayerAI`** (`server/app/player-ai.js`): a bot is a subclass of
  `Player` whose `socket` is a duck-typed fake (`{once, emit, disconnect}`). When a seat
  must not go empty (chains break otherwise), the bot fills it through the *same interface*
  as a human — no special-case branches in game logic. Directly relevant to our "machine
  understudies a seat later" note: design the seat interface now, not the bot.
- **Transport (data point)**: socket.io; 4-letter room codes; a game ends when *all* players disconnect, not one.

### Out of Context — the modern (2026) reference build
**[Meshiest/outofcontext](https://github.com/Meshiest/outofcontext)** — **GPL-3.0**, 35 stars, pushed 2026-08-31 (very active), TypeScript.

- **What it is**: a six-game telephone-style party suite (write/draw/tamper chains), 4-char
  lobby codes, self-hosted single Express instance.
- **Worth stealing** (its README is an unusually crisp architecture statement):
  game logic isolated in `core/`, server/client share a types package; **lobby state
  persists to disk (JSON + pako)** as the crash/restart substrate; server sends **error
  codes, never prose**, client renders them via i18n — a discipline that keeps rulings
  machine-readable (relevant to Chronicle-as-precedent).
- **Transport (data point)**: typed tRPC — mutations over plain HTTP, server push via **SSE** subscriptions. (A live example of the HTTP+SSE column in the transport study.)
- **License caution**: GPL — patterns yes, code no.

### scribble.rs — self-hosting hygiene
**[scribble-rs/scribble.rs](https://github.com/scribble-rs/scribble.rs)** — BSD-3-Clause, 657 stars, pushed 2026-05, Go.

- **What it is**: the maintained skribbl.io clone; several community instances run it.
- **Worth stealing**: lobby lifecycle is two env vars (`LOBBY_CLEANUP_INTERVAL`,
  `LOBBY_CLEANUP_PLAYER_INACTIVITY_THRESHOLD`) — idle rooms garbage-collect themselves;
  whole server configured by env, Docker-first, one binary. The right amount of ops for a
  household server on stephens.page.
- **Transport (data point)**: WebSockets (`lxzan/gws`), uuid lobby ids.

### Also on this shelf (one-liners)
- **[ajanata/PretendYoureXyzzy](https://github.com/ajanata/PretendYoureXyzzy)** — BSD-2, 1.3k stars, dormant (2023). Proof the shape predates WebSockets: Java servlets + **AJAX long-poll** (`cah.longpoll.js`) ran huge public games.
- **[InvoxiPlayGames/johnbox](https://github.com/InvoxiPlayGames/johnbox)** (AGPL, private-server reimplementation of actual Jackbox protocols) and **[tomalama/hackbox](https://github.com/tomalama/hackbox)** (MIT, stale 2023 framework) — exist; neither worth depth.

---

## 3. Word games — hidden info, reveals, phone text input

### horsepaste (jbowens' Codenames) — the minimal-server masterclass
**[jbowens/horsepaste](https://github.com/jbowens/horsepaste)** — **NO LICENSE** (all rights reserved — study only), 654 stars, pushed 2026-01, Go. Runs horsepaste.com.

- **What it is**: the widely-played web Codenames (repo renamed from `codenames`).
- **Worth stealing (as ideas)**:
  - **Room = any string; `getGame` creates on first access.** No create/join distinction, no
    lobby at all: the URL *is* the room. For one household: a standing room name is a bookmark.
  - **Long-poll on a version token**: client sends its `state_id`
    (= `UpdatedAt.UnixNano()`); the handler parks on a channel until state changes, then
    returns full JSON. Four endpoints total (`/game-state`, `/guess`, `/end-turn`,
    `/next-game`). Sync without a socket layer.
  - **Persistence per mutation**: every accepted move saves the game via a tiny
    `Store` interface (disk-backed); restart-safe by construction.
  - **Deterministic boards**: state carries `seed` + `perm_index`; the same seed replays the
    same board series — shareable and reproducible (echoes design law 1's determinism).
  - **The trust-based view split**: the full secret `layout` ships to *every* client; the
    spymaster view is a client-side toggle. Fine among friends; our private clues should
    instead be redacted at send time (boardgame.io's `playerView`, just-one below) — but it
    shows how far "same state, two renderings" goes for public-screen vs phone-screen.
- **Transport (data point)**: HTTP long-polling keyed by state version; in-memory game map + store saves.

### cjquines/just-one — the closest shape to our game
**[cjquines/just-one](https://github.com/cjquines/just-one)** — MIT, 25 stars, pushed 2024-08, Node + Express. (The clone rocketcrab links as "Just One".)

- **What it is**: Just One online — everyone *simultaneously and privately* writes a
  one-word clue; duplicates cancel; the guesser sees survivors. Structurally the nearest
  OSS relative of a simultaneous-private-clue couch word game.
- **Worth stealing**:
  - **Phase machine** in one `Room` class: `wait → clue → eliminate → guess → judge → end`.
    Clues live as `{player → {clue, visible}}`.
  - **Rejoin = same name.** Players are keyed by display name, not socket id; a returning
    socket is re-bound and the server **re-sends exactly the state that name may see for
    the current phase** (the guesser reconnecting mid-`clue` still sees nothing). Per-phase,
    per-role redaction computed at send time — the whole privacy model in ~350 lines.
  - **Duplicate-cancel without an LLM**: `nlp(s1).text("root") === nlp(s2).text("root")`
    using the `compromise` NLP library — lemmatize both clues, compare roots. A reminder
    that the *cheapest adequate judge* for a ruling is sometimes a deterministic library,
    reserving the LLM for judgments only it can make (design law: LLM must earn its place).
  - **Judgment by majority**: the `judge` phase collects player votes and takes the mode —
    humans-as-referee expressed in code, our design law 3.
- **Transport (data point)**: socket.io, rooms by name in URL.

### Longwave (Wavelength) — private dial, shared board
**[cynicaloptimist/longwave](https://github.com/cynicaloptimist/longwave)** — MIT, 100 stars, pushed 2025-03, React + Firebase.

- **What it is**: web Wavelength; room = URL path, join by sharing the link.
- **Worth stealing**: cleanest example of *clue-giver private view vs everyone-else view*
  over one shared state document; i18n of the card deck (`spectrum-cards` as locale files)
  shows content-as-data, translated/swappable — a shape our nightly-authored boards will want.
- **Transport (data point)**: Firebase Realtime Database as both transport and store (client-only app, no own server).

### Wordle family — input UX and a legal lesson
- **[cwackerfuss/react-wordle → "Reactle"] — deleted.** The canonical MIT Wordle clone
  (thousands of stars, ~1,900 forks) was removed after the NYT's March 2024 DMCA campaign
  against Wordle clones ([404 Media](https://www.404media.co/nytimes-files-copyright-takedowns-against-hundreds-of-wordle-clones/),
  [Gizmodo](https://gizmodo.com/nyt-dmca-takedown-request-wordle-clones-reactle-1851320538)).
  Lesson recorded under Licenses below.
- **[lynn/hello](https://github.com/lynn/hello)** ("hello wordl") — MIT, 370 stars, alive.
  The surviving reference for **phone word-entry UX**: a custom on-screen keyboard rendered
  by the game (buttons dispatching to game state) plus hardware-key handling — sidestepping
  mobile-browser focus/autocorrect/viewport-jump misery of a real `<input>`. Melissa's
  phone is the primary controller; this is the pattern to copy for letter-level input.
  (For free-text clues, just-one uses a plain form field — fine for whole words.)
- **[betaveros/castlefall](https://github.com/betaveros/castlefall)** — MIT, TS, minimal
  phones-in-a-circle word game: worth a skim for how small a room server can be.

---

## 4. Semantic / LLM word games — where the model sits, what gets cached

### Semantle — precompute everything, serve lookups
**[gitlab.com/novalis_dt/semantle](https://gitlab.com/novalis_dt/semantle)** (David Turner) — **GPL-3.0**, Flask.
(GitHub mirror of the source: [lawley/semantle](https://github.com/lawley/semantle) fork.)

- **Architecture**: no model runs at request time. Offline scripts (`dump-vecs.py`,
  `dump-hints.py` — README: "wait a very long time") bake word2vec vectors and per-puzzle
  hint rankings into **SQLite**; vectors stored truncated (bfloat16-style halves,
  re-expanded on read) to shrink the DB; the Flask app just does keyed lookups
  (`/model/<word>`). Similarity is thus *identical for every player forever* — consistency
  by construction, our design law 1 achieved with zero inference cost (law 4's
  pre-generate-and-rank, in the embeddings register).
- **Transport (data point)**: plain HTTP request/response; the game is solo, no sync needed.
- **Live descendant**: [ishefi/semantle-he](https://github.com/ishefi/semantle-he)
  (GPL-3.0, pushed 2026-07) — same idea grown into a maintained service: Python API server,
  SQL migrations (alembic), Docker; proof the pattern operates long-term.

### Blabrecs — the judge ships to the browser
**[mkremins/blabrecs](https://github.com/mkremins/blabrecs)** (Max Kreminski & Isaac Karth) — **NO LICENSE** (study only), ClojureScript.

- **Architecture**: the "is this plausibly an English word?" classifier is a small CNN
  **checked into the repo** (`model.json` + weight shard) and run **entirely in-browser via
  TensorFlow.js**; training happens offline in `train_cnn.py`. No server, no API, no cost,
  no latency, perfectly consistent rulings. The existence proof that a *meaning-ish judge
  can be a static asset* when the judgment is narrow enough.
- **Transport (data point)**: none — static page.

### OpenCraft — the cache-first LLM judge, in ~200 lines
**[bufferhead-code/opencraft](https://github.com/bufferhead-code/opencraft)** — **NO LICENSE** (study only), 107 stars, Vue + Fastify.

- **What it is**: an Infinite Craft clone with the LLM self-hosted (Neal's original is closed).
- **Architecture** (`server/index.js` — read it, it's tiny): every combination request
  checks a **SQLite `word_cache` table first, trying the pair in both orders** (symmetric
  canonicalization); only on miss does it invoke **node-llama-cpp running local
  Mistral-7B**, with **`seed: 0`** (deterministic decode) and a **JSON-schema grammar**
  constraining output shape; result inserted into the cache. Cache-first → fixed seed →
  schema-constrained output → persist verdict: our design law 1 as literal running code,
  with the model on the game server (couch-friendly: no per-ruling API bill, no network
  dependency — at the price of local model quality).
- **Transport (data point)**: plain HTTP JSON API; game itself is solo/local.

---

## 5. Licenses at a glance

| Repo | License | Borrow code? |
|---|---|---|
| boardgame.io | MIT | Yes |
| rocketcrab, drawphone | MIT | Yes |
| cjquines/just-one | MIT | Yes |
| longwave, lynn/hello, castlefall | MIT | Yes |
| scribble.rs | BSD-3 | Yes |
| PretendYoureXyzzy | BSD-2 | Yes (dated code) |
| massivedecks, johnbox | **AGPL-3.0** | No — patterns only |
| semantle, semantle-he, outofcontext | **GPL-3.0** | Only if we'd accept GPL for the whole game; treat as patterns-only |
| horsepaste, opencraft, blabrecs | **No license** | **No — all rights reserved; study only** |

Two legal notes beyond SPDX tags: (1) three of the most instructive repos here (horsepaste,
opencraft, blabrecs) have *no license file*, so nothing may be copied from them — re-derive,
don't paste. (2) The NYT DMCA'd ~1,900 Wordle-clone repos in 2024 including the canonical
MIT one — cloning a *trademarked/live commercial game's* look-and-feel is exposure even
under MIT. Our game is original and household-scoped, so this is only a naming/skinning
caution (already consistent with the brief's "Chronicle Clover is not a real name" instinct).

---

## Signals for our design (inference)

Everything below is inference from the survey, not fact from any single repo.

1. **Collapse the lobby to a URL.** The genre's lobby machinery (codes, uniqueness, create
   vs join) exists for strangers at scale. horsepaste shows the degenerate case we actually
   are: *the room is a URL path, created on first access*. One household → a standing room
   (`stephens.page/game/couch`), phones keep it bookmarked; "room code UX" disappears
   entirely. Keep a 4-char-code path only if guests ever visit.
2. **Identity = seat name + server-held state; rejoin is re-binding, not re-joining.**
   The convergent pattern across just-one (same name re-binds), rocketcrab (`previousId`),
   massivedecks (JWT per seat), boardgame.io (seat credentials): all state lives
   server-side; a reconnecting device presents a stable identity and is *re-sent exactly
   what that seat may currently see*. With two fixed seats (Jacob / Melissa) this shrinks
   to two hardcoded seats — a phone refresh mid-round must cost nothing. Design this on day
   one; it is the whole disconnect-recovery story.
3. **One authoritative state doc + phase machine + per-seat redaction at send time.**
   just-one's `Room` (350 lines) and boardgame.io's `playerView`+stages are the same
   architecture at two sizes: phases gate which moves are legal, a send-time filter decides
   what each seat and the spectator view receive, and the **simultaneous-reveal moment is
   just a phase transition** (server flips `clue → reveal`, broadcasts, done). The laptop
   public screen is massivedecks' "optional central screen": *a third client with the
   spectator filter*, zero extra server concepts — and the private/public display axis from
   the brief falls out of the same filter function.
4. **The referee is a cache with a model behind it.** opencraft (SQLite verdict cache,
   both orders, seed 0, grammar-constrained JSON), semantle (offline precompute, serve
   lookups), blabrecs (judge as static in-browser asset) form a spectrum of the same
   commitment: **judgments are keyed, canonicalized, persisted, and deterministic; the
   model only ever fills cache misses** — ideally pre-filled at board-authoring time (law
   4), leaving play-time misses rare. And just-one's `compromise`-root equality is the
   reminder to grade with the *cheapest adequate judge* per ruling tier: string/lemma
   match → embeddings → LLM, escalating only when needed. The verdict cache and the
   Chronicle can be the same table: a cached ruling with its reasoning *is* precedent.
5. **Give every seat one interface so anything can sit in it.** drawphone's `PlayerAI`
   (bot = player with a duck-typed socket) is the cheap trick that keeps our "solo mode
   later, machine understudies Jacob" option open without designing for it now.

**Read in depth before building** (in order): **cjquines/just-one** (MIT, an afternoon —
nearest shape: simultaneous private submissions, phase machine, name-based rejoin);
**horsepaste** `server.go`+`game.go` (long-poll versioned state, save-per-mutation, room-as-URL —
ideas only, no license); **opencraft** `server/index.js` (the cache-first local-LLM judge);
**outofcontext**'s README + `core/` (what a well-factored 2026 self-hosted party server
looks like). boardgame.io's docs on stages/playerView are worth an hour even if the
dependency is never installed.
