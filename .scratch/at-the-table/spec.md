# Spec: At the table — Pages written from the Seats' Gives

Status: `ready-for-agent`
Written: 2026-09-05
Sources: `docs/design-brief.md` (Settled decisions dated 2026-09-05), `CONTEXT.md`, ADR-0011 (this feature's ruling; supersedes ADR-0004), ADR-0005, ADR-0006, ADR-0008 (the name), ADR-0010, the grilling of 2026-09-05 after the couch night of 2026-09-04 (Room DUST's Chronicle), and the group-play spec at `.scratch/group-play/spec.md`, whose Room, Code and one-Verdict rules this builds on.

## Problem Statement

Jacob and Melissa sat down on 2026-09-04 and the game handed them a Page it had written the night before — two Anchors from a shared meaning-space with the setting printed above them. They both wrote *lighthouse*, were graded 75, and tapped "too harsh". Seven Pages later, six had melded, three on the first try. Melissa typed a Give — "give me two very unrelated words" — and had to play a Page she did not ask for before hers arrived. The Assayer's reasoning card pushed the quip off the phone. Jacob wanted to write "Gold Rush" and Melissa "Viking beaches", and the dictionary said no. Nobody could find the laptop's stage, because nothing links to it. And the couple's own words for the game — *clues*, *setting* — were not the game's.

The game was too easy, too eager, too wordy, and too strict, in that order.

## Solution

A Page does not exist until the players have made it. When the Room fills, every Seat types a Give — a setting, in their own words, private to them — and when the last one lands the Author writes two **Bookends** from two different Gives, chosen to stand far apart, in the seconds the beat meter's dots take to pulse. The players bridge them with anything they like, as long as it is not a word the Page has already used. The reveal is the Bridges, the number climbing into its band, and the quip — and nothing else; the Assayer's reasoning goes into the Chronicle, where arguments belong. A Meld is 90 now, the same word is 100, and 75 is *almost*. When a laptop is the stage, the phones go quiet and every eye goes up. "One more?" asks for Gives again, prefilled with the last ones. And the game is called **Thereish**.

Everything the Author used to pre-write — Bait, deep bridges, the pre-graded table, band scripts, the pool — is gone. Which model writes the Bookends is the first experiment on the A/B harness after Bait: Gemini 3.8 Flash against GPT-6 Astra, read from the arcs and one tap at each Page's close. Every model call's cost is visible on a spend page.

## User Stories

1. As a player, I want the Room to ask me for a setting before there is any Page, so that the first thing we play is ours.
2. As a player, I want my Give to be private to me until the first reveal, so that the other players do not know which world one of the Bookends came from.
3. As a player, I want to see that the others have given without seeing what, so that I know the Page is about to be written.
4. As a player, I want the Author to write the Bookends within a few seconds of the last Give, with visible activity while it does, so that the opening feels like the game answering rather than loading.
5. As a player, I want the two Bookends to come from two different Gives and stand far apart in meaning, so that melding takes real convergence rather than one obvious word.
6. As a player, I want a Bookend to be allowed to be a two-word phrase when the Give suggests one, so that "Gold Rush" can be a Bookend as well as a Bridge.
7. As a player, I want a Bookend never to be a word from a Give, so that my Give is not printed on the screen by another name.
8. As a player, I want to type any word or short phrase as my Bridge, so that "Viking beaches" is a legal answer.
9. As a player, I want the game to refuse a Bridge that is a Bookend or that this Page has already used, root and all, so that "lava rock" after "lava" is not a cheap 95.
10. As a player, I want the refusal to say which word it collided with, so that I can pick another without guessing.
11. As a player, I want the reveal to show every Bridge, then the number climbing into its band, then the quip, so that the punchline lands with nothing in front of it.
12. As a player, I want the Assayer's reasoning kept out of the reveal, so that the screen is a joke and not a report.
13. As a player, I want to read the Assayer's reasoning in the Chronicle when I want to argue with a grade, so that overrules are still informed.
14. As a player, I want a Meld to mean 90 or more and the same word to mean 100, so that a lucky neighbouring word is *almost* rather than a win.
15. As a player, I want the band between close and meld named *almost*, so that the ladder reads as the story it is.
16. As a player, I want an unmelded Page to end as an ending, so that five Attempts of converging is the game working and not a failure screen.
17. As a player, I want the quip to be allowed to reference every Bridge of this Page and, from the first reveal on, our Gives, so that the closing quip can pull the arc together.
18. As a player, I want the quip written fresh even when the grade is a Precedent, so that a cached grade never comes with someone else's joke.
19. As a player, I want the Again button to name the two words that carry, so that the "furthest apart" line is not needed.
20. As a player, I want the Room's Code visible on my phone throughout, so that I can show a friend how to join without leaving the Page.
21. As a player, I want the game's name, the Chronicle link and "You are Jacob" below the fold on the reveal, so that the Bridges, the number and the quip fit a Pixel without scrolling.
22. As a player with a laptop nearby, I want a button on my phone that makes this device the stage, so that I never type a URL to play.
23. As a player at a table with a stage, I want my phone to show the Bridges and the controls but not the number, band or quip, so that everyone looks up at the same screen for the reveal.
24. As a player, I want the controls — Again, One more, Overrule, the fairness taps — on my phone even when the stage has the reveal, so that the phone stays the remote.
25. As a player, I want "One more?" to ask everyone for a Give again, prefilled with my last one, so that keeping my setting is one tap and changing it is easy.
26. As a player, I want a joint overrule to write a Meld at 90, not 100, so that "we call this a Meld" is not "we wrote the same word".
27. As a player, I want one tap at the Page's close saying whether the Bookends were flat, fine or great, so that the game learns which Author writes better Pages.
28. As a player, I want the Author's failure to be said plainly — "The Author couldn't write from these" — with a way to try again or give again, so that a slow model never strands the table.
29. As a player, I want the game to call itself Thereish on every screen, so that the working title is gone.
30. As the giver, I want my Give recorded in the Chronicle with my name, so that the book remembers whose world each Page came from.
31. As a Chronicle reader, I want each Page to show its Gives, its Bookends, and who gave what, so that the arc can be read from its beginning.
32. As a Chronicle reader, I want the Assayer's reasoning on every Verdict in the book and the export, so that a grade can be argued with a month later.
33. As a Chronicle reader, I want the Markdown export to say Bookends and to list Gives, so that the export reads in the game's own words.
34. As a friend joining a Room, I want to type a Give like everyone else, so that I have as much authorship as the couple.
35. As a Room of four, I want the Author to draw the two Bookends from two of our four Gives and keep the other Gives for later Pages, so that no one's setting is wasted.
36. As Jacob, I want each Page assigned blind to Flash or Astra as its Author, stratified so neither arm gets a run of easy Rooms, so that the experiment reads fairly.
37. As Jacob, I want the experiment's outcome recorded per Page — Attempts to meld, unmelded or not, the Bookends taps — so that the readout is streaks and preferences rather than a guess.
38. As Jacob, I want an operator page totalling model spend across every Room by role and model, so that I can see whether Fable 5.1 is overkill anywhere.
39. As Jacob, I want each Room's Chronicle to end with what that Room has cost, so that the number sits next to the play it paid for.
40. As Jacob, I want the Scribe's recaps written at the highest effort, so that the paragraph the couple reads next month was written carefully — nobody is waiting for it.
41. As Jacob, I want no Page drawn or burned when a Room process starts or restarts, so that a deploy never eats content.
42. As a developer, I want the rules to answer the last Give with one Author effect and the Author's answer to arrive as an event, so that a whole Page — Gives to close — can be driven in a test as a list of events with no clock.
43. As a developer, I want the Fake Author to answer configured Bookends, or nothing, or slowly, so that every path is a test rather than a smoke test.
44. As a developer, I want the OpenAI provider tested against recorded responses like the Gemini and Anthropic providers, so that Astra is one config line away.
45. As a developer, I want every two-Seat test that does not assert on Bait or a pre-written Page to pass unchanged, so that the couch's game is proven the same where it should be.

## Implementation Decisions

### Seams

Four existing surfaces, as agreed on 2026-09-05: the rules (`MeaningGame.Game` — `init`, `apply`, `view`), the Steward behaviour with its Fake, the Room through `MeaningGame.Rooms`, and the LiveViews with real Postgres. One new mechanism, Presence, is tested through the LiveView seam and never through its own.

### The Game

**State.** The Page is no longer given to `init`; a Room starts with none. The state gains `gives` (Seat id → Give text), a `page` that is either absent or `%{bookends, gives, meta}` where `meta` is the Author's provenance (model, arm, prompt version, cost, latency), `bookends` in place of `anchors` everywhere, an `author_failure` (nil or a reason), and `bookends_taps` (Seat id → label) beside `fairness_taps`.

**Phase, still derived.** Read top to bottom: not full → `:waiting`; full and fewer Gives than Seats → `:giving`; every Give in and no Page → `:writing`; a Page and fewer Bridges than Seats → `:bridging`; Bridges in and no Verdict → `:assaying`; a Verdict and the Page over → `:closed`; otherwise `:reveal`. Nothing stores it.

**Events.**
- `give_committed` (Seat, text): legal in `:giving`, once per Seat per Page; a blank Give is `:give_required`, one over the cap (about 120 characters) `:give_too_long`. The last one in owes one effect, `{:author, request}`, where the request carries every Give in roster order with the Seat's name.
- `page_written` (Bookends, meta): legal in `:writing`; sets the Page; the Attempt is 1. Ignored if a Page already exists, so a late duplicate from a retried task changes nothing.
- `author_failed` (reason): legal in `:writing`; records the failure. Phase stays `:writing`; the view says so and offers two things.
- `author_retried` (Seat): legal in `:writing` after a failure; clears the failure and owes `{:author, request}` again.
- `gives_reset` (Seat): legal in `:writing` after a failure; clears every Give, back to `:giving`.
- `bridge_committed`: as today, with legality reading the Page's **barred words** — the Bookends of every Attempt so far (carried Bridges become Bookends and stay barred) and every Bridge committed in this Page.
- `attempt_advanced`, `verdict_received`, `verdict_unavailable`, the overrule trio, `fairness_tapped`: as today. The overrule's default closeness is the meld floor from the Ladder, not 100.
- `bookends_tapped` (Seat, label ∈ flat / fine / great): legal in `:closed`, one per Seat, replaceable; owes `{:bookends_tap, data}` carrying the Page's Bookends, Gives, author meta and arm.
- `next_page` (Seat): legal in `:closed`; clears the Page, Gives, Bridges, Verdict, taps and the arc; the Room is back in `:giving`. Replaces `page_started`, which took a drawn Page.

**Legality.** A Bridge is trimmed, whitespace-collapsed and downcased; it must be non-empty, at most 40 characters, and letters, digits, spaces, hyphens and apostrophes only. It is illegal if any of its words equals or shares a root with any word of any barred word or phrase — the existing stem, prefix and inflection checks, applied word by word on both sides, with the existing three-letter floor on prefix overlap. The dictionary check, the single-word check and the profanity list are removed from player Bridges. The refusal names the word it collided with. The same module still gates the Author's Bookends (below) and still owns the dictionary, because a Room's Code is drawn from it.

**The view.** `bookends` replaces `anchors`; `your_give`, `gives_in` (count) and `your_last_give` (for the prefill) are added; a Give appears in no view but its giver's until the first reveal, after which the reveal view lists them with names. The reveal view carries no `reasoning`; the Chronicle entry does. `next_bookends` replaces `next_anchors`. `author_failure` is exposed with its reason. The `provisional` step and everything that read the pre-graded table are gone.

**The Ladder.** Bands become miss 0 / adjacent 30 / close 55 / almost 75 / meld 90 / deep_meld 100 — configuration, as today. `melded?` is still "at or above the floor of the meld band". The overrule reads the same floor.

### The Steward

**The Author's contract changes.** `author(request, opts)` takes the Gives (with names, roster order) and answers `{:ok, %{bookends: [a, b], why: sentence, meta}}` or an error. The prompt (`author-3`) asks for exactly two Bookends, each a common English word or two-word phrase, each drawn from a *different* Give when there are two or more, chosen to stand as far apart in meaning as the Gives allow while each still belongs to its Give's world, and one sentence of why. The deterministic gate (design law 14): exactly two; each one or two words of letters, hyphens or apostrophes, at most 20 characters; distinct roots between the two; no word of either sharing a root with any word of any Give; a rejected answer is asked for again once with the reason, then the Steward gives up and the Room raises `author_failed`. A digest of the Room's Chronicle rides along as today, so the Author can avoid repeating last week's Bookends.

**The Author's model is an experiment.** The `author` role is configured per job like the Scribe: `flash` (Gemini 3.8 Flash, low, one request, a 5 s timeout and an 8 s deadline) and `astra` (GPT-6 Astra, low, same budgets). The Steward's arm assignment becomes the `author_model` experiment — arms `flash` and `astra`, assigned per Page, stratified per Room so a Room alternates rather than streaks — recorded in the Chronicle's experiment tables as today, blinded from players. The `bait_against_plain` experiment is closed: its assignment code and the Bait scoring are removed; its rows stay readable.

**A third provider.** An OpenAI provider implements the existing provider behaviour: JSON-schema structured output, reasoning effort, the key from the environment through runtime configuration, cost from the price table. Prices for `gpt-6-astra` join the table.

**The Assayer moves to `assay-3`.** The request carries the Bookends, every Bridge with its player's name in roster order, the Page's earlier Attempts (Bookends and Bridges), and the Gives with names. The rubric: 100 the same word or a plain inflection; 90–99 one idea however worded; 75–89 the same neighbourhood, distinct framing; 55–74 related ideas; 30–54 adjacent; 0–29 different roads. Bridges may be phrases; the quip may name players and draw on anything in the request; the reasoning and furthest-pair rules stand. The version bump orphans the `assay-2` precedents, none overruled.

**A Precedent hit writes a fresh quip.** The Precedent key stays model + prompt version + normalized Bookends + normalized Bridges (both orderings one key). On a hit, closeness, reasoning and the furthest pair are inherited; the quip is asked for anew with a small `quip` request (same model, same history, a one-field schema) inside the beat, and on its failure the cached quip is used. The verdict's meta says `precedent_hit`.

**Escalation** loses its provisional rung: activity through 4 s, no Verdict at 10 s. The Author's wait has its own two rungs: "still writing" at 5 s, failure at the deadline.

**The Scribe's** recap job moves to `xhigh` effort. No other change.

### Rooms and the Room process

The Room boots with no Page and draws nothing, ever; the pool, its schema, its mix task, its seeds and the hand-written fallback Pages are deleted. `Rooms.give/3` now applies `give_committed` to the rules instead of starting a background Author run; the rules' `{:author, request}` effect is performed as a supervised task calling the Steward with the Page's assigned arm, answered by `page_written` or `author_failed` as messages, with the two-rung timer above. `Rooms.retry_author/2`, `Rooms.reset_gives/2` and `Rooms.tap_bookends/3` are added; `Rooms.next_page/2` applies `next_page`. The Give status, announcement and failure fields of the old flow are removed. A Room that crashes mid-Page loses its Gives along with its Bridges, as today.

The snapshot gains nothing about stages: the Room does not know one is connected. **Presence** does — a Presence module on the Room's topic tracks every LiveView as `stage` or `phone`; the phone LiveViews read it on mount and on every diff and render quietly when a stage is present.

### The Chronicle

A Page gains its **Gives**, one row each with the Seat and the text, and an `author_meta` document (model, arm, prompt version, cost, latency, the Author's *why*). `anchors` is renamed `bookends` across the Chronicle tables and the Precedent table. Verdict rows keep `reasoning`. The experiment tables record `author_model` assignments and outcomes; an outcome carries the arc (Attempts, melded, closing band) and the Bookends taps. The book view shows Gives with names, Bookends, and reasoning on each Verdict; the Markdown export writes `Give (Jacob): …` lines and `Bookends:`, and its reader accepts old `Anchors:` lines so earlier exports still round-trip.

**Spend.** The Chronicle answers `spend` for one Room and for all: total dollars, by role (Author, Assayer, Scribe; Foley later) and by model, with the call count — computed from the cost every Verdict, Page and Recap already carries, never stored as a total. An operator page at `/spend` renders the all-Rooms answer, noindex like everything else; each Room's Chronicle ends with its own line.

### The web

- **The Room page** always shows the Code card. In `:giving` it shows a "Your setting" form (player-facing copy keeps *setting*), prefilled with this Seat's last Give; after committing, "Your setting: … — waiting for N more" and nothing about anyone else's. In `:writing` the beat meter's dots and "The Author is reading your settings", then "still writing" at five seconds, then on failure the reason with **Try again** and **New settings**. Bookends render where Anchors did, with no setting line above them. The reveal is Bridges → number and band → quip; the flavour line, the reasoning card and the furthest line are gone; the fairness taps stay; at `:closed` the ending, the arc, the Bookends tap (flat / fine / great) and One more. Under a stage the reveal renders **quiet**: Bridges and controls, no number, band or quip. The header (name, Chronicle link) and "You are …" move to a footer. A **Make this device the Stage** button navigates to the stage route; it shows whether or not this device holds a Seat.
- **The stage** tracks itself in Presence, shows "Waiting for settings: 1 of 2" with no text while Gives come in, the writing animation, the Bookends, the full reveal without reasoning, the roster and the join URL. Its title is Thereish.
- **Every page title and heading** says Thereish, and **the rename lands here in full** (naming issue 06, carried by this spec): the two prose mentions of the working title in the Steward's Author and Assayer modules go with the prompt rewrites; the design brief, ADRs 0004 / 0005 / 0007, `docs/deploy.md` and the two research notes that mention the mechanic by its working title read Thereish; `.scratch/resolved/mind-meld/` is moved to `.scratch/resolved/thereish/` with its internal references; the README introduces the game by name; the four naming research notes and round four stay untouched, being dated records about the names themselves. `meld.stephens.page` is not touched — that is naming issue 07.

### Schema

Migrations: drop the pool table; add the Gives table (page, seat, text, inserted order) and the `author_meta` document on Pages; rename `anchors` → `bookends` on attempts, verdicts, fairness taps and precedents; nothing else changes shape. Rows still reference Seats, never Accounts (ADR-0007).

### Build order

1. The rules: Gives, the Author effect and events, phases, the barred-words legality, the Ladder, the Bookends tap, the quiet-free view — with the two-Seat suite as the guard.
2. The Steward: the Author contract and gate, the `flash` and `astra` jobs, the OpenAI provider against recorded responses, `assay-3`, the fresh quip on a Precedent hit, the trimmed escalation.
3. The Room and the Chronicle: no Page at boot, the Author task and its rungs, the experiment, Gives and `author_meta` rows, the rename migration, spend.
4. The web: the Room page's phases and layout, Presence and the quiet reveal, the stage button and the stage's giving view, the spend page.
5. The name: Thereish on every screen, and the documentation and tracker sweep of naming issue 06, in one commit so the rename is one diff.
6. Deploy, then measure from the VPS: the Author's time from last Give to Bookends for two and for four Gives, and `assay-3`'s whole-verdict p95, recorded on the integration ticket (`.scratch/group-play/issues/05`).

## Testing Decisions

A good test crosses one of the four surfaces and asserts on what a player or an operator could observe. It never reads the reducer's state directly, never asserts on prompt text, and never calls a provider. Every two-Seat test that does not assert on Bait or on a pre-written Page is the regression guard and passes with its assertions unchanged; the ones that do are deleted with the feature, not rewritten around it.

**The Game, as a pure function.** A full Room with no Page is `:giving`; a Give is in its giver's view and in no other; the second Give owes exactly one Author effect carrying both Gives in roster order with names; `page_written` turns the Room to `:bridging` with the Bookends in every view; a duplicate `page_written` changes nothing; `author_failed` keeps `:writing` and exposes the reason, `author_retried` owes the effect again, `gives_reset` returns to `:giving`; "Viking beaches" commits and "lava rock" after "lava" is refused naming *lava*; a carried Bridge is barred as a Bookend on the next Attempt; 74 reads close, 75 almost, 89 almost, 90 meld and closes the Page, 100 deep meld; an overrule writes 90; the reveal view has no reasoning and the Chronicle entry does; a Bookends tap lands once per Seat and owes its effect; `next_page` empties the Page and asks for Gives with the last ones remembered. Prior art is the existing rules test's event-list harness.

**The Steward, against recorded responses and the Fake.** The Fake Author answers configured Bookends, or an error, or after a delay; the gate rejects one Bookend, three, a Bookend sharing a root with a Give word, two Bookends sharing a root, a phrase over 20 characters, and asks once more with the reason; the OpenAI provider parses a recorded structured answer and a recorded refusal; `assay-3` carries names, phrases, history and Gives and rejects a furthest pair that is not two Bridges; a Precedent hit returns the cached grade with a fresh quip and falls back to the cached quip when the quip request fails; arm assignment alternates within a Room. One tagged live smoke test per provider stays excluded. Prior art is the Steward, Precedent, legality and author tests.

**The Room, through its interface with the Fake.** A Room boots with no Page and burns nothing; two Gives produce Bookends inside the configured wait and the snapshot for each Seat shows only its own Give; a slow Fake Author reaches "still writing" and then the failure, and a retry recovers; the assigned arm is recorded per Page and the outcome per close; spend for the Room equals the sum of what its rows carry. Prior art is the Rooms test and the Room fixtures.

**The LiveViews, end to end, against real Postgres.** Two phones join, each types a setting and sees only its own, both see the Bookends, both commit, both see Bridges, number, band and quip and no reasoning, Again names the carried words, One more asks for settings prefilled; a third view mounts as the stage and both phones' reveals go quiet while the stage shows the full reveal; the stage button on a phone leads to the stage route; the Code card is present in every phase; the Bookends tap records; the spend page and the Chronicle foot line show the Room's cost; every heading says Thereish. Persistence: Gives with Seats, `author_meta`, reasoning on verdicts, the renamed columns, the Markdown export with `Bookends:` and `Give (…)` lines, and an old export with `Anchors:` still parsing. Prior art is the Room LiveView test and the Chronicle tests.

## Out of Scope

- Foley — stings, music, the spoken quip, the speaker (`.scratch/foley/spec.md`).
- A mechanism for Chapters; they stay a glossary direction.
- Count-free Rooms and the start gesture (`.scratch/group-play/issues/08`); couple-versus-couple and the meld map (06, 07).
- Accounts, magic links, per-person insights.
- Moving the deployment to `thereish.app` (`.scratch/naming/issues/07`).
- The Scribe's silence in production (`.scratch/scribe/issues/02`) — a bug, fixed on its own.
- Re-calibrating the Ladder's boundaries from fairness taps; the new floors are the couch's guess and the taps keep collecting.
- Reading the Bookends aloud, solo play, the trap-beating mode Jacob said a solo design might bring back.

## Further Notes

- **Two bugs dissolve rather than get fixed.** Drawing a Page at Room start burned one pool Page per Room per process start — five in one second on 2026-09-05 — and printing the Give above the Anchors told the table the world; neither has anywhere to live once there is no pool and no printed Give.
- **The Give's secrecy is one Attempt long.** After the first reveal the Bookends have already changed to the players' own Bridges, so a quip that names a Give is no longer a hint, and the Chronicle records every Give with its Seat from the moment it is given.
- **Calibration continues.** The labelled set (ADR-0005) keeps collecting fairness taps; the ladder shift changes what "fair" is judged against, so taps from before and after 2026-09-05 should be read as two sets when the boundaries are next moved.
- **The integration ticket** for four phones is `.scratch/group-play/issues/05`, already rewritten for this opening; it runs after this spec's tickets.
- **Measured facts to beat**: the Assayer's whole-verdict p95 was about a second from the VPS under `assay-2`; a Give's three Pages arrived within a Page's play on 2026-09-04 from Fable 5.1 at low. The Author now has five seconds and two words.
