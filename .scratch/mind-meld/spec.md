# Spec: Mind-Meld — the playable slice, first milestone couch night

Status: `ready-for-agent`
Written: 2026-09-02
Sources: `docs/design-brief.md`, `CONTEXT.md`, ADRs 0001–0007, `docs/research/*`, branches `prototype/stage0-page-machines` and `prototype/keeper` (`prototype/keeper/REPORT.md`).

## Problem Statement

Jacob and Melissa have a vacant couple-game slot. It has been vacant since they finished Tick Tock: A Tale for Two. Melissa's solo slots are saturated by daily phone word games, so the missing thing is specifically a **together** game: two people on one couch, two phones, one evening, words.

Nothing on the market fills it. The games she loves most — So Clover, Codenames, Taboo, Monikers, Telestrations — are all crowd games that break at two, because at two there is nobody to hold the seat that has to understand free language. No digital-native two-player couch word game exists at all.

Right now the design exists only on paper and in two throwaway prototypes. Jacob cannot find out whether the game is fun, because Melissa cannot play it. The Stage 0 prototype was clicked through solo on a laptop by one player who is not the target player, and its Assayer was a toy heuristic. Every remaining design question — where the meld threshold sits, whether the ladder bands read as funny or mean, whether the reveal beat wants to be shorter on a harsh grade — is a question the couch answers and no amount of further design work can.

## Solution

A hosted web game at stephens.page. Melissa opens a URL on her Pixel, types her name, and is in the Room. Jacob does the same. A laptop opens the same Room as the stage.

A **Page** takes ten to fifteen minutes. The stage shows two **Anchors**. On each phone, privately, each player writes the **Bridge** — the one word whose meaning spans both Anchors. Neither sees the other's Bridge. The instant the last player commits, the **Assayer** grades, and 2.5 seconds later the stage performs the reveal: both Bridges side by side, a closeness number from 0 to 100, a ladder band, the Assayer's reasoning, and a quip naming what they actually wrote.

Land at or above the meld threshold and it is a **Meld** — one mind, two heads. Miss and the failed Bridges become the next attempt's Anchors, so a missed Page converges instead of ending. Five attempts, then the Page closes either way and is written into the **Chronicle**.

If a grade is wrong, they overrule it together, and the overrule becomes house law: the next time those words meet, the game rules the way the couple ruled. The Chronicle keeps every Page, every grade, every overrule, and it is theirs to read and correct.

The **Author** writes Pages ahead of play, so nothing waits on a model mid-game. It plants a **Bait** — the obvious Bridge that both players will reach for — which is what makes converging feel earned rather than automatic. Whether the Bait actually improves the evening is the first thing the A/B harness measures.

## User Stories

### Getting into a Room

1. As Melissa, I want to open a short URL on my phone and see a name field, so that I can start playing without an account, an install, or a password.
2. As Melissa, I want to type only my name to join, so that nothing stands between me and the game.
3. As Jacob, I want to open the stage view on the laptop, so that the reveal has a shared screen to perform on.
4. As a player, I want the Room to show who else has joined and who is still typing their name, so that we know when to start.
5. As a player, I want to reopen the same URL after closing the tab and land back in my own Seat, so that I never lose my place or my history.
6. As a player, I want my phone locking mid-Page to be harmless, so that the game survives the ordinary behaviour of a phone on a couch.
7. As a player, I want the game to reconnect and resync automatically when I unlock, so that I never have to reload to catch up.
8. As a player, I want the stage to keep the laptop screen awake during a Page, so that the reveal is not performed to a black screen.
9. As Jacob, I want a Room to hold more than two Seats even though we will use two, so that Jackbox-shaped group play needs no rewrite.
10. As a player, I want my Seat to persist across evenings, so that my Chronicle history accumulates against me and not against a fresh stranger.

### Playing a Page

11. As a player, I want to see both Anchors on my phone and on the stage at the same moment, so that the Page starts fairly.
12. As a player, I want a single text field for my Bridge, so that the interaction is as light as the thought is heavy.
13. As a player, I want my Bridge to stay private until both players have committed, so that neither of us can follow the other.
14. As a player, I want to see that the other player has committed without seeing what they wrote, so that I feel the clock without being led.
15. As a player, I want to edit my Bridge until I commit it, so that a typo is not a ruling.
16. As a player, I want the game to reject an illegal Bridge before I commit it, so that a rule I broke by accident does not cost the attempt.
17. As a player, I want a fixed short beat between the last commit and the reveal, so that the reveal is theatre rather than a loading screen.
18. As a player, I want both Bridges revealed side by side, so that the comparison lands before the number does.
19. As a player, I want a closeness number from 0 to 100, so that the outcome is graded rather than pass or fail.
20. As a player, I want a named ladder band alongside the number, so that the score has a voice.
21. As a player, I want the Assayer's reasoning shown, so that I can argue with it.
22. As a player, I want a quip that names what we actually wrote, so that the reveal is funny about us and not funny in general.
23. As a player, I want a miss to be the joke rather than the sting, so that failing together is the fun part.
24. As a player, I want our failed Bridges to become the next attempt's Anchors, so that a missed Page converges instead of collapsing.
25. As a player, I want a fixed number of attempts per Page, so that the evening has a shape and a Page can end unmelded.
26. As a player, I want a Meld to be visibly the end of the Page, so that landing it feels like landing it.
27. As a player, I want "one more?" to be a single tap, so that the evening chains.
28. As a player, I want a Page to take ten to fifteen minutes, so that we can play one on a weeknight.

### The grade, and arguing with it

29. As a player, I want to know that the same two Bridges will always be graded the same way, so that I never catch the game contradicting itself.
30. As a couple, I want to overrule a grade when we both agree it is wrong, so that we hold final authority over our own game.
31. As a couple, I want an overrule to require both of us, so that neither of us can quietly rewrite the rules.
32. As a couple, I want our overrule to be what the game rules next time those words meet, so that our house law accretes.
33. As a player, I want every overrule recorded in the Chronicle with what the machine said and what we said, so that the argument becomes lore.
34. As a player, I want the game to admit when it has no verdict, so that a failure hands us the call rather than inventing one.
35. As a player, I want to mark a grade as fair, too kind, or too harsh in one tap, so that our sense of the scale gets recorded without interrupting play.
36. As Jacob, I want those taps to accumulate into a labelled set, so that the Assayer can be calibrated against how we actually judge closeness.

### Chapters and Gives

37. As a player, I want to play a themed run of Pages, so that an evening can be a journey through one meaning-space.
38. As a player, I want to name a setting on the spot and have the game move there, so that the improv give works at Page scale.
39. As a player, I want the game to keep playing while a Give is being written, so that naming a theme never stalls the evening.
40. As a player, I want the stage to tell me when Pages for my Give have arrived, so that I know the game heard me.
41. As Jacob, I want Pages authored ahead of play, so that no model call ever sits between the couple and their next Page.

### The Chronicle

42. As a player, I want every Page written into the Chronicle, so that nothing we played is lost.
43. As a player, I want to read our Chronicle as a book, so that our history is a thing we can look at.
44. As a player, I want to correct the Chronicle, so that the record is ours and not the machine's.
45. As Jacob, I want the Chronicle exportable as Markdown on demand, so that I and a coding agent can read it without a database client.
46. As Jacob, I want the Chronicle to be an append-only log of events, so that the version history is the log rather than a separate mechanism.

### Experiments

47. As Jacob, I want each Page randomly assigned to an experiment arm, so that I can measure a design change instead of guessing at it.
48. As Jacob, I want the arm labels blinded on the stage and on the phones, so that neither of us plays the label.
49. As Jacob, I want assignment stratified by Chapter, so that one arm does not get all the easy meaning-spaces.
50. As Jacob, I want the first experiment to be Bait-scored Pages against plain ones, so that the misdirection decision is tested rather than assumed.
51. As Jacob, I want every assignment and outcome in the Chronicle, so that the ledger is the same artifact the players read.
52. As Jacob, I want a qualitative readout rather than a p-value, so that the analysis matches a sample size of two people.

### Operating it

53. As Jacob, I want the game running on stephens.page from the first evening, so that every session measures the real round-trips the reveal beat has to absorb.
54. As Jacob, I want the identical Docker image to run on my Mac and on the server, so that the deploy loop is exercised long before couch night.
55. As Jacob, I want per-role model and effort configurable without a code change, so that swapping the Assayer is a setting rather than a refactor.
56. As Jacob, I want every model response schema-validated before it reaches the game, so that a malformed response is never a crash mid-Page.
57. As Jacob, I want cost, latency, model, and prompt version recorded on every verdict and every Page, so that the model policy stays measured.
58. As Jacob, I want a working two-phone Room with rejoin inside three evenings, so that ADR-0002's kill criterion gets a fair test.

## Implementation Decisions

### Seams

**One adapter seam: the Steward.** Everything the game says to a language model crosses it, and exactly two adapters satisfy it — the live one that talks to providers, and a deterministic fake used by every test that is not a hand-run smoke test. Two adapters is what makes it a real seam rather than a hypothetical one. Model choice, per-role effort, hedging, both-orderings grading, the verdict cache and precedent, A/B assignment, schema validation, and the clue-legality filter all live behind it. Nothing else in the codebase knows a provider exists.

**Three test surfaces, no other seams.** The Game is a pure module; the Room is a process with a small interface; the LiveViews are exercised end to end. Persistence is not behind a seam — tests run against real Postgres with the Ecto sandbox, and no repository abstraction is introduced.

### The Game is pure

The rules module is a pure reducer with three functions, carried over from the Stage 0 prototype: build initial state, apply an event, project a view for a given Seat. It performs no I/O, starts no timers, and calls no models. Verdicts arrive as events applied to it, never as calls it makes — that is what keeps the Assayer's asynchrony out of the rules and lets a whole Page be driven in a test as a list of events.

This shape came from `prototype/stage0-page-machines`:

```
init(page, seats)            -> state
apply(state, event)          -> {state, effects}
view(state, seat_id)         -> what that Seat may see
```

Events: `seat_joined`, `bridge_committed`, `verdict_received`, `verdict_unavailable`, `overrule_proposed`, `overrule_agreed`, `attempt_advanced`, `page_closed`. Effects are descriptions, not actions — the Room performs them.

The whole rules surface should stay small enough to read in one sitting, per the code shape principle.

### The Room owns time and processes

A Room is a supervised process holding Game state for N Seats, two by default. It is the only thing that starts the reveal beat, fires the Steward, and pushes updates to connected views. Its interface is join, commit a Bridge, propose and agree an overrule, record a fairness tap, request a full snapshot, and start the next Page. A full snapshot on demand is the reconnect mechanism, so a phone waking from lock needs no special path.

Seats are a list, never a pair. Every rule that could be written for two players is written for a list, including the reveal, the scoring, and the stage layout.

### Grading

The Assayer fires the instant the last Seat commits, in parallel with the beat. Both orderings of each pair are graded in parallel and both are stored; the pair collapses to one cache key. The reveal is a fixed 2.5 s beat for every grade in v1 — design law 10's rule about shortening harsh grades is deliberately deferred until Melissa has played, because Stage 0 suggested the harsh grade is the punchline.

Escalation when the verdict is slow: visible Assayer activity through 4 s, a provisional band from the Author's pre-graded `likely_bridges` table at 8 s, and at 10 s the game says it has no verdict and hands the call to the players. A failure is a joint-authority moment, not an invented number.

**Scoring at N seats is a pairwise meld map.** Every unordered pair of Seats gets a closeness; the Page's headline number is the mean across pairs; the stage shows who melded with whom. At two Seats this is exactly one pair, so the two-player rule is the general rule with nothing special-cased. A group centroid can be added later as an additional display without touching the model. Live grading is capped at six Seats for v1, since pairs grow quadratically.

Named configuration, not design constants: meld threshold 75, attempt cap 5 tries per Page, the 0–100 scale, and five ladder bands (miss, adjacent, near, meld, deep meld). Band boundaries move with calibration; band wording is Assayer or Author output. Carry-forward follows Medium's rule — the two failed Bridges become the next attempt's Anchors.

### Precedent

The verdict cache is keyed by model, prompt version, and normalized inputs, with both orderings mapping to one key. The grade the players saw is what the cache stores and returns, forever (ADR-0006). A second opinion is a Chronicle annotation and never rewrites the cache. The only thing that rewrites a cache entry is a joint overrule, which writes the couple's ruling into the same key and records the event.

An overrule requires every Seat in the Room to agree, and both the machine's ruling and the couple's stand in the Chronicle.

### The Author runs ahead of play

Pages are pre-generated into a pool and never authored mid-Page — the Author takes 43 to 87 seconds per Page at max effort. A Chapter is authored ahead of the evening. A Give typed at the couch queues a background Author run against the named meaning-space; the Room keeps playing from the existing pool meanwhile, and the stage announces the new Pages when they land. No Oban in this spec; a supervised task is enough at this scale.

Each authored Page carries Anchors, the Bait, at least two deep Bridges, `likely_bridges` with `why_these` as the pre-graded table, and `meta` recording author model, prompt version, attempts, and cost. Contract shapes come from `prototype/keeper/REPORT.md`.

The live joke belongs to the Assayer, which quips on the players' actual Bridges. Author-prewritten band scripts stay as the fallback and as a future A/B arm.

### Models

Author is Fable 5.1 at max effort; live Assayer is Gemini 3.8 Flash at low effort (ADR-0005), calibrated by the couple's labelled set. Per-role model and effort are configuration behind the Steward. Hedging is two identical requests to one model, fast tier only. The Anthropic refusal-fallback header stays on the Author, logged, never depended on. All access is by API key. Every verdict records forward, reverse, reverse reasoning, model, prompt version, timings, and cost.

### Guardrails

Every model response is schema-validated with `jsv` before it enters the game, and a validation failure is a retry, never a crash. Author output passes an Elixir clue-legality filter — stem and inflection root check against ENABLE/SCOWL, plus a profanity list — with reject and regenerate. Player Bridges pass the same legality check client-side and again on commit. No Vale gate in this spec, because the Scribe is out of scope.

### Identity and storage

Joining takes a name. The Seat holds a stable id and a device token kept in the browser; reopening the URL restores the Seat. Seats never expire. Accounts are out of scope here; the one obligation is seat ids that an account can claim later (ADR-0007).

Postgres via Ecto (ADR-0003): append-only event tables for Pages, verdicts, overrules, fairness taps, experiment assignments, and player edits; the Page document as JSONB. Views are computed, never stored — the LiveView book page, a Steward-composed digest for models, and an on-demand Markdown render for humans and coding agents. Chronicle rows reference Seats, never Accounts.

### Experiments

Assignment happens at Page start, randomized and stratified by Chapter, with blinded arm labels. The first experiment is Bait-scored Pages against plain ones (ADR-0004). Assignment and outcome are Chronicle events, so the ledger and the artifact the players read are the same thing.

### Deployment

Phoenix / Elixir / LiveView, Docker release, behind the existing Apache vhost with websocket upgrade and certbot TLS, running on stephens.page from the first evening. Elixir via mise on the Mac; docker-compose for local Postgres.

## Testing Decisions

A good test here crosses one of the three surfaces and asserts on what a player or an operator could observe. It never reaches past an interface to inspect internal state, never asserts on prompt text, and never calls a provider.

**The Game, tested as a pure function.** Drive a whole Page as a list of events and assert on the projected view. This is the highest and cheapest surface, and it should carry the bulk of the rules coverage: privacy of an uncommitted Bridge, reveal only after every Seat commits, meld at threshold, band selection, carry-forward of failed Bridges into the next Anchors, the attempt cap closing a Page unmelded, overrule requiring unanimity, three Seats behaving as three pairs, and the view differing correctly between Seats. Prior art is the `init`/`apply`/`view` harness on `prototype/stage0-page-machines`.

**The Room, tested through its interface with the fake Steward.** Deterministic verdicts and controllable delays let these tests cover what the pure module cannot: the beat fires and the reveal lands, a slow verdict escalates to provisional and then to no-verdict, a dropped connection followed by a snapshot request restores exactly the view the Seat had, rejoining with a device token lands in the same Seat, and a second Page starts cleanly.

**The Steward, tested against recorded responses.** Schema validation rejects malformed output and retries, both orderings collapse to one cache key, a cached verdict returns the grade that was shown, an overrule rewrites that key, hedging fires two identical requests and takes the first, and the clue-legality filter rejects and regenerates. One live smoke test per role exists but is tagged and excluded from the default run, because the suite must never spend money or depend on a provider. Prior art is the Elixir harness on `prototype/keeper`, including its hand-rolled SSE parser and `jsv` usage.

**The LiveViews, tested end to end.** Two connected phone views plus a stage through `Phoenix.LiveViewTest`, with the fake Steward: join by name, commit both Bridges, see the reveal on all three, tap an overrule to agreement, start the next Page. This is the couch-night path, and it is the test that says the thing works.

**Persistence, tested for real.** Ecto sandbox against real Postgres. Assert that a played Page produces the expected event rows and that the Markdown export renders them. No mock repository.

## Out of Scope

- Accounts, magic-link email, and Google sign-in. Only claimable Seat ids are in scope.
- The Scribe and its Vale gate. The Chronicle records events; narrative recaps come later.
- Oban, pgvector, embeddings, and Bumblebee. All post-couch-night.
- Chronicle Clover, which stays parked on `prototype/stage0-page-machines`.
- Solo mode, competitive modes, and the LLM understudying a Seat, which ADR-0001 rules out for now.
- Outward sharing and result cards, deprioritized because couch play removes the need.
- Naming the game, which has its own session.
- Group play beyond making the model N-seat. The UI builds two phones and a stage.
- Second-opinion annotation runs, which ADR-0006 keeps offline.
- Analysis tooling for the A/B harness beyond logging and a readable ledger.

## Further Notes

**The kill criterion is live.** ADR-0002 gives Phoenix three evenings to reach a working two-phone Room with rejoin. If it does not, the stack becomes TypeScript and Socket.IO. Build in the order that tests this first: Room, Seats, join by name, two phones, rejoin — before Pages, before the Author, before the Chronicle. A fake Steward returning canned verdicts is enough to reach that milestone, and it is the same fake the tests use.

**The reveal is the product.** Stage 0's finding was that a 24 out of 100 from a stub Assayer with a toy heuristic drew a laugh. The graded number is the comedy delivery mechanism, so the ladder flavour and the reasoning line are load-bearing rather than chrome. Budget real effort there and treat it as the thing most worth polishing.

**Melissa's first contact is the working game.** She does not see a stub. The first thing she plays is two phones, a stage, and a real Assayer.

**Open and deliberately unresolved:** the meld threshold, the band boundaries, and whether the beat should shorten on a harsh grade. All three are calibration questions the couch answers, which is why the fairness tap exists and why every one of them is named configuration.

**Still pending from the Steward prototype:** Kimi K3 at max effort via Together, once the key is available. Commands are in `prototype/keeper/README.md`. It cannot block this build.
