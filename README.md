# Thereish

I want to make a game which plays with meaning. Maybe it could even use an LLM
somehow. I want it more than anything else to be fun.

That note became **Thereish**: a couch word game for two phones and a laptop —
two to six phones, when friends come round — with a machine author-scribe. It
runs at **https://thereish.app**. Success is measured one way: My wife likes it.

## How a Page goes

1. Someone opens a Room at `/new` and reads its **Code** aloud — a four-letter
   word the Scribe picks. Everyone else types the word and a name. No accounts.
2. Every Seat gives a **Give**: a setting, in a phrase. "Viking beaches." "The
   world St. Thérèse grew up in." A Give stays private until the first reveal.
3. The **Author** writes two **Bookends** at the table, in seconds — a word or
   phrase drawn from one Give, another from a second, chosen to stand far apart.
4. Everyone writes a **Bridge**: the word or phrase whose meaning spans both.
   Anything goes except a Bookend, or a Bridge this Page has already seen.
5. After a fixed **Beat**, the reveal: every Bridge, one number, its band on the
   **Ladder** — miss, adjacent, close, almost, meld, deep meld — and the
   **Assayer**'s quip about what was actually written. The reasoning is
   recorded, not read aloud.
6. A **Meld** ends the Page. A miss carries the two Bridges that landed furthest
   apart forward as the next **Attempt**'s Bookends, so a Page converges rather
   than repeats; after five Attempts it closes unmelded. "One more?" asks for
   fresh Gives.

Everything played goes into the Room's **Chronicle**: an append-only,
player-readable record of every Page, every Verdict, every joint overrule
(which becomes precedent), and the **Recap** the Scribe writes after everyone
has gone to bed. The Assayer grades; it never rules. Same inputs, same grade,
forever.

Any device can make itself the **Stage**: the reveal is performed on the laptop
for the whole table while the phones go quiet. **Foley** scores each Page with
an instrumental written from its Gives, speaks the quip, and plays the stings.

`CONTEXT.md` defines every capitalised word above.

## The machine's roles

The game talks to models through one seam, the **Steward** (ADR-0009). The
machine holds no player seat (ADR-0001): it takes only the jobs nobody at the
table could do better. Each role is a few lines of `config/config.exs`.

| Role | Job | Today |
|---|---|---|
| Author | writes the Bookends at the table | Gemini 3.8 Flash, A/B-tested per Page against GPT-6 Astra |
| Assayer | grades an Attempt's Bridges and writes the quip | Gemini 3.8 Flash at low effort, hedged, every Verdict cached as precedent |
| Scribe | names Rooms, titles Tracks, writes Recaps | Gemini 3.8 Flash for the fast jobs; Claude Fable 5.1 for Recaps, behind a Vale prose gate |
| Foley | music, effects, voice | Mureka for the Tracks, ElevenLabs for the forged stings, Hume Octave for the voice |

No model's word is final. A schema validator has the last say on every answer,
Elixir stemming keeps a Bridge from echoing a Bookend's root, and Vale reads the
Scribe's prose before the couple do (design law 14).

## Reading the design

- `docs/design-brief.md` — the design and how it got here: the target player,
  the settled decisions, the fourteen design laws, three playtests
- `CONTEXT.md` — the glossary: Room, Code, Seat, Page, Give, Bookends, Bridge,
  Attempt, Verdict, Meld, Chronicle, and the words each one avoids
- `docs/adr/` — the twelve settled decisions, and what each one replaced
- `docs/research/` — the reading behind the laws: LLM referees in word games,
  why group word games fail at two, model selection for a 2.5-second beat,
  name clearance
- GitHub issues — the tracker: specs are parent issues and tickets are
  sub-issues (`docs/agents/issue-tracker.md`); historical features remain in
  `.scratch/`

## The code

Few deep modules and boring data. The rules fit in one file.

- `lib/thereish/game.ex` — the rules as a pure reducer: build state, apply an
  event, project what one Seat may see. No timers, no sockets, no models.
- `lib/thereish/rooms/` — a Room is a process; join by name, reconnect by
  snapshot
- `lib/thereish/ladder.ex` — the bands, as configuration the couch calibrates
- `lib/thereish/steward/` — the seam and its adapters (Gemini, Anthropic,
  OpenAI, Mureka, ElevenLabs, Hume), plus `Fake`, which every test grades against
- `lib/thereish/chronicle/` — the record's Ecto schemas; the log is the version
  history
- `lib/thereish/experiments.ex` — the A/B harness: per-Page assignment, blinded
  labels, outcomes written to the Chronicle, a qualitative readout
- `lib/thereish/scribe.ex`, `foley/`, `notice.ex`, `umami.ex` — after-play
  writing, sound, the operator's email, page views
- `lib/thereish_web/live/` — the door (`/`), `/new`, the Room (`/r/CODE`), its
  Stage (`/stage`), its Chronicle (`/chronicle`, or `/chronicle.md` for a
  human or an agent), and the operator's `/spend`

## Running it

Elixir, Erlang and Vale come from `mise` (`mise.toml` pins them); Postgres from
docker-compose:

```sh
mise install
docker compose up -d
mix setup
mix phx.server
```

Then http://localhost:4000. With no keys the app boots and Rooms open, but the
Author writes nothing and the Assayer grades nothing; `GEMINI_API_KEY` alone
makes it playable. Keys go in the shell, or in `.env.local` for the release
image:

| Key | What it turns on |
|---|---|
| `GEMINI_API_KEY` | the Assayer, the Author, Room naming, Foley's ear |
| `ANTHROPIC_API_KEY` | the Scribe's Recaps |
| `OPENAI_API_KEY` | the Author's Astra arm |
| `MUREKA_API_KEY` | a Track for every Page |
| `HUME_API_KEY`, `HUME_SECRET_KEY` | the Assayer's voice |
| `ELEVENLABS_API_KEY` | the alternative voice, and the forge's effects |

```sh
mix test          # the whole suite, against Steward.Fake — it never spends a cent
mix precommit     # compile with warnings as errors, format, test
```

## Deploying

Every push to `master` deploys to **https://thereish.app** through GitHub
Actions (`.github/workflows/deploy.yml`). `bin/deploy` is the manual route from
a clean, pushed `master`, and `bin/keys-to-server` carries the keys over. Spend
is visible at `/spend` and at the foot of each Room's Chronicle. See
`docs/deploy.md`.

The ENABLE word list in `priv/wordlists/` is public domain; see `NOTICE`.
