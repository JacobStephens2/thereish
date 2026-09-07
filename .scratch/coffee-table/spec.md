# Spec: Coffee table — the Stage is read, the table is heard, and the book remembers the song

Status: `ready-for-agent`
Written: 2026-09-06
Sources: `docs/design-brief.md` (Settled decisions dated 2026-09-06), `CONTEXT.md` (Stage, Speaker, Track, Foley, Scribe, Code), ADR-0007 (Accounts by magic link — the sender this spec sets up is theirs to use later), ADR-0009 (one seam to the models), ADR-0011 (Pages written at the table — the Gives a Track is titled from), the Foley spec at `.scratch/foley/spec.md` and the at-the-table spec at `.scratch/at-the-table/spec.md` (whose Room facts, pushed events, Presence and reveal this builds on), `docs/research/audio-input-models-for-naming-a-track.md`, `docs/research/email-for-the-notice-ses-or-resend.md`, and the grilling of 2026-09-06 after the third playtest (Room KALE with Cole and Sid in the morning; Room RICE, the first Page with Foley's keys in place, that night). Four tickets were filed before this spec and are referenced rather than repeated: `.scratch/at-the-table/issues/11` (the fold on the phone), `12` (the stage fits the laptop), `.scratch/foley/issues/07` (the keys — done, 2026-09-06) and `08` (the deploy warns).

## Problem Statement

On the morning of 2026-09-06 Jacob, Cole and Sid sat at a coffee table with a laptop as the Stage and their phones in hand. The reveal did not fit the laptop: the header, the join line, the Attempt, the Bookends, three Bridges and the number filled the screen and the quip was cut off, so someone reached over and scrolled — which is exactly the thing a Jackbox screen never makes you do. On a phone the Code card and the speaker bar took the fold and the Bookends were half visible. The house loop played all evening and never handed over to a Page's music; the quip was never spoken though "Voice" was ticked; "House loop only" was read backwards; there was no way to stop the music once a Page had started; the sting was quiet; one loop wore thin. Nobody knew until the next morning's logs that the server simply had no Mureka or Hume key — the deploy warns about two keys and was silent about the rest. That night, with the keys in, the first keyed Page's Track faded in and its quip was spoken, and forty cents of it stayed invisible on the spend page until the Page closed; the four silent Verdicts of the morning will stay invisible forever, because a failed voice leaves no record. A Meld ends with a sting and silence where a celebration belongs. The Chronicle cannot play back the song a Page was played to. The Bookends carry no name on screen and the input asks for "the word between them," so the table has no words for the game's parts. The Code card is a bare word where a line of the Scribe's would do. Nobody is told when someone new opens a Room. And of the eighty cents the game has ever spent, seventy-one went to the Scribe writing recaps at the highest effort, the role furthest from the table.

## Solution

The Stage is read, not touched. Everything a reveal is made of fits a laptop at once (ticket 12), and on the phone the game comes first the moment a Page exists (ticket 11). Sound is controlled from anywhere: one **music** control with three states — Off, House loop, Written for this Page — replaces the checkbox that was read backwards, and it and the voice switch live on every phone below the fold and on the Stage, since they are Room facts and one tap flips them. Levels move into configuration and are rebalanced; four house loops rotate per Page; a **Track** gets a **title** from the Scribe the moment it is asked for, so "the summer camp song" is a thing the table can say and the Chronicle can play back. A Bridge committed makes a sound: on the committing phone always, and on the Stage when there is one. A Meld is celebrated with a forged victory cue, deep meld with a brighter one. "Bookends" and "Your bridge" are printed where they belong. The Code arrives with a quip written in the same breath the Scribe names the Room. Umami counts page views, first-party and cookieless, and an email through Amazon SES tells Jacob when a Room is opened from a device that has never played — the sender that ADR-0007's magic links will need, set up now, with DKIM, a custom MAIL FROM and a DMARC record whose reports actually arrive. The spend page says how many Pages are in play and not yet counted, a failed voice is recorded on its Verdict as music's failures are on the Page, and the Scribe writes at low effort.

## User Stories

### The Stage and the phone

1. As a player at a coffee table, I want the whole reveal — Bookends, every Bridge, the number and band, the quip — on the laptop at once, so that nobody reaches for the laptop during play. (Ticket 12.)
2. As a player on a phone mid-Page, I want the Attempt, the Bookends and my Bridge input first on the screen, so that the Code and the speaker bar are not what I see when I look down. (Ticket 11.)
3. As a player, I want the words "Bookends" over the pair and "Your bridge" on the input, on phone and Stage, so that the table has the game's names for its parts.
4. As a player, I want the Stage to keep its sound controls below the fold, so that settings can be changed there once an evening without the reveal moving.

### Sound at the table

5. As a player, I want one music control with three states — Off, House loop, Written for this Page — so that "what will I hear" is one choice and not a checkbox named after the exception.
6. As a player, I want the music control and the voice switch on my phone below the fold, so that the phone is the remote for sound as it is for everything else.
7. As a player, I want a tap on any phone to change the Room's sound facts, and the Stage and every other phone to show the change, so that the controls are the Room's and not one device's.
8. As a player, I want music Off to silence the music bus and nothing else, so that the stings and the voice still land.
9. As a player, I want Written for this Page to be the default, so that a Room that never touches the control hears a Track when one arrives.
10. As a player, I want the sting and the voice clearly above the loop, so that the band is heard across a room from a laptop.
11. As a player, I want the loop under talk rather than over it, so that the music is a floor and not a guest.
12. As a player, I want a different house loop each Page, never the same one twice running, so that an evening of five Pages is not one tune five times.
13. As a player, I want a "Now playing" line below the fold on the Stage and on the Speaker's phone naming what I hear and whether it is the house loop or a Track written for this Page, so that the difference is a fact on screen and not a guess.
14. As a player, I want a sound when I commit my Bridge, so that the tap lands — heard through the Stage when there is one, and on my phone when there is no Stage (ticket 15).
15. As a player at a table with a Stage, I want the Stage to sound every commit, so that the table hears itself filling in.
16. As a player at a table with no Stage, I want each phone to sound its own commit and no phone to relay anyone else's, so that a commit is one sound from one place.
17. As a player, I want the commit sound on my phone on by default, silent under reduced-motion, with one tap to turn it off for this device, so that a sound answering my own tap is never "the game playing on the bus."
18. As a player, I want a Meld to be celebrated with a short victory cue, and a deep meld with a brighter one, so that the moment sounds like what it is.
19. As a player, I want the Page's Track to fade out beneath the victory cue rather than cut, so that the celebration is the last thing heard.
20. As a player, I want the unmelded ending to stay a settle, so that five Attempts of converging still ends as an ending.

### Tracks and the book

21. As a player, I want every Track to have a title, so that "the Viking beaches song" is something we can ask for again.
22. As a player, I want the same Gives to bring back the same Track with the same title, so that a song we remember is the song we get.
23. As a player, I want the title written from our settings and ready before the Track arrives, so that the "Now playing" line changes once, not twice.
24. As a Chronicle reader, I want each Page's entry to name its Track and play it, so that an evening's songs can be found from the record.
25. As a Chronicle reader, I want a Page with no Track to say nothing about music rather than show an empty player, so that the book stays honest.
26. As a Chronicle reader, I want the Markdown export to carry the Track's title, so that the export reads as the evening did.
27. As a player, I want the house loops to have names too, so that the "Now playing" line never says "house-loop-3.mp3".

### The Code

28. As the creator of a Room, I want the Code card to carry one line from the Scribe about the Code, so that the door has a voice.
29. As the creator, I want the quip written in the same call that names the Room, so that nobody waits twice.
30. As a player in a Room drawn at random, I want a quip written from the word alone, so that a Room with no history still has its line.
31. As a player, I want the quip to appear on the Stage's header and beneath each rejoin link on the front page, so that the Room is recognisable wherever its Code is.
32. As Jacob, I want no model call on any page load, so that a bot reading the door costs nothing.
33. As Jacob, I want Room creation rate-limited per device and per address, so that the one call creation makes cannot be made ten thousand times.

### Knowing it was played

34. As Jacob, I want Umami to count page views on every page, first-party and cookieless, so that I can see whether anyone played without asking.
35. As Jacob, I want the Umami script present only when its URL and website id are configured, so that development and tests load nothing.
36. As Jacob, I want an email when a Room is created from a device that has never played, so that a new table is news the same day.
37. As Jacob, I want that email sent through Amazon SES from an address at thereish.app, so that I learn the platform on a real sender and the game's own domain carries its own mail.
38. As Jacob, I want SPF, DKIM, a custom MAIL FROM and a DMARC record with a reporting address published for thereish.app through Porkbun's API, so that aggregate reports arrive and the records are a script rather than a memory.
39. As Jacob, I want the notice never to delay or fail a Room's creation, so that mail is a side effect and not a dependency.
40. As Jacob, I want the sender usable later for ADR-0007's magic links, so that Accounts do not start by choosing a mail vendor.
41. As Jacob, I want production access requested from SES on the day the identity is verified, so that the sandbox is behind us before Accounts need it.

### Spend and the record

42. As Jacob, I want the spend page and each Room's Chronicle foot to say how many Pages are in play and not yet counted, so that a Page I am looking at is not forty invisible cents.
43. As Jacob, I want a failed voice recorded on its Verdict — zero cost and the reason — so that the book can say a quip went unspoken.
44. As Jacob, I want the Scribe's recap written at low effort, so that the role furthest from the table is not nine dollars in ten.
45. As Jacob, I want `xhigh` kept as a one-line alternative, so that the choice is reversible without code.

### Operators and developers

46. As Jacob, I want the forge to make the new assets the way it made the first ten — several candidates, Gemini's ear ranking them, my ear choosing, a manifest, a copy under fixed names — so that the victory cues, the commit tick and four more loops cost cents once.
47. As Jacob, I want the SES setup to be a wizard I run once — IAM identity, domain identity, DNS through Porkbun, production access request, the credentials onto the server — so that it is not re-explained to an agent every time.
48. As a developer, I want the music control, the commit sounds, the victory cues and the "Now playing" line driven by pushed events a LiveView test can assert on, so that "the Stage sounds every commit and a phone sounds only its own" is a test.
49. As a developer, I want the title job behind the Steward behaviour with a Fake that answers a configured title, or nothing, or slowly, so that every path is a test.
50. As a developer, I want the mail delivered through Swoosh with its Test adapter in tests, so that "a new device's Room sends one notice and a returning device's sends none" is an assertion and not a mailbox.
51. As a developer, I want levels read from configuration and handed to the client as data, so that a level change is a config change and the by-ear ticket stays a ticket.

## Implementation Decisions

### Seams

The four existing surfaces, as in the two specs before this one: the rules (`MeaningGame.Game`), the Steward behaviour with its Fake, the Room through `MeaningGame.Rooms`, and the LiveViews with real Postgres, playback asserted as pushed events. Two things touch nothing new: mail is a side effect of `Rooms.create` and is asserted at that seam through Swoosh's Test adapter, and Umami is a string in the root layout asserted through a controller test. The mix tasks (the forge) are tested with the Fake as before. DNS and AWS are a human's wizard, verified by hand and recorded on their ticket. **The Game does not change**: nothing here is a rule.

### Room facts: the music control

`house_loop_only` becomes **`music`**, a Room fact with three values — `off`, `house`, `page` — default `page`. Migration by expand and contract in one ticket, the blast radius being a handful of call sites: add the column, write `house` where `house_loop_only` was true and `page` elsewhere, move every reader, drop the boolean. The Room's interface replaces `set_house_loop_only/2` with `set_music/2`; the snapshot answers `music` in place of `house_loop_only`; `set_voice/2` stays. The score task starts only when `music` is `page`; switching to `page` mid-Page with no Track and no task running starts one (today's behaviour on unchecking, kept). The switches component renders on **every** phone and on the Stage, not only on the Speaker's view: the facts are the Room's. On the phone it renders in the speaker bar, which ticket 11 moves below the play controls; on the Stage it stays in the header, which ticket 12 keeps to one line. Voice stays a checkbox; music is a three-way segmented control with the three words above.

### Pushed events

`foley:page` keeps its shape and gains `title` and `kind` (`house` or `track`) beside `path`; `music: off` pushes `foley:page` with a nil path, which the hook takes as "fade the music bus out and keep the buses for stings and voice". The Foley coordinator resolves the path from `music`: `off` → nil; `house` → this Page's loop; `page` → the Track when it has landed, else this Page's loop.

Two new events for commits. **`foley:commit`** is pushed to the Stage's view — and only to a Stage's view, never to a phone that holds the Speaker — whenever the count of committed Seats rises within a Page; it plays the commit tick on the stings bus. **`foley:own-commit`** is pushed to the committing phone's own view when its `commit_bridge` succeeds, **only when no Stage holds the Room** (ticket 15); when a Stage is present, the Stage sounds the commit and phones stay quiet so one commit is not two sounds from two places. With no Stage, the hook plays the tick locally, gated by the per-device switch and reduced-motion, regardless of whether this phone is the Speaker. The hook is therefore mounted on every phone with a `local sounds` mode that owns nothing but the tick; the Speaker mode is unchanged. The per-device switch is browser storage, default on, rendered as a small icon beside the speaker icon; while a Stage is present, it clarifies that commits play from the Stage while preserving the device setting for play without a Stage.

`foley:ending` gains a third kind: `deep_meld`, when the closing Verdict's band is deep meld. `meld` and `deep_meld` play their victory cue on the stings bus and fade the music bus out over about two seconds beneath it, instead of stopping the music at once; `unmelded` is unchanged. The `ending-meld.mp3` "arrival" is retired from play and left in the static directory until the cues are chosen.

### Levels

The hook's constants become configuration under the `foley` role — `levels: [music: …, stings: …, voice: …, duck: …]` — handed to the hook as data attributes on its container, so a level change is a config change and nothing is re-rendered. Starting values: the loop lower than today's 0.7, stings and voice above 1.0 (Web Audio gain permits it), the duck as it is. The exact numbers are set by ear on the deployment and recorded on `.scratch/foley/issues/06`, which stays the listening ticket. No asset is re-rendered and no mixer is built; the values are there for one if a keyed playtest asks.

### Assets made once: the forge, again

The forge's brief set gains: **four house loops** (Mureka, the same instrumental-under-conversation brief with a different mood each — the manifest gives every loop a short name, which the "Now playing" line uses), **two victory cues** (ElevenLabs sound generation, eight to twelve seconds; meld an arrival that resolves, deep meld the same idea brighter and a beat longer), and **one commit tick** (under half a second, a soft click or wood tap, nothing tonal enough to fight the loop). Candidates ranked by Gemini's ear and chosen by Jacob as before; the manifest gains the entries; fixed names in the static audio directory. A small module lists the loops with their names and paths so the Room and the hook agree on what "loop 3" is called.

### Loop rotation

The Room picks a loop when a Page is written: random among the loops other than the last one played in this Room, held in the Room's process state (not persisted — a restart may repeat once, which is fine). The choice rides on the snapshot as the Page's `loop` (name and path) so every view resolves the same file.

### The Scribe titles the Track

The Steward behaviour gains **`title_track(gives, opts)`** answering `{:ok, %{title, meta}}` or an error. The `scribe` role gains a **`title`** job — Gemini 3.8 Flash at low, a one-field schema, a short timeout and deadline in the naming job's class — asking for a title of at most five words for an instrumental written from these settings, no quotes, no "song". The deterministic gate: one to five words, letters, digits, spaces, hyphens and apostrophes, at most 40 characters; one repair, then the fallback. **The fallback is deterministic**: the Gives, trimmed, title-cased, joined with " · ", cut at 40 characters. The title task starts when the Author starts, beside the score task, so it is ready long before the Track (Mureka takes 30–90 s; the title takes a second) and the "Now playing" line changes once. The track cache gains `title`; a cache hit brings the title back with the file. The Track map (`path`, `duration`, `format`, `meta`) gains `title`, and `music_meta` on the Page gains `title` and `path` so the Chronicle can play it. A title that arrives after the Page has moved on is dropped like a late Track. The title's cost rides in `music_meta` beside the Track's.

### The Chronicle plays the Track

The book's Page entry, when `music_meta` carries a `path`, shows the title and an audio element pointing at the media route that already serves the Track; a Page without a path shows no music line; the Markdown export writes `Track: <title>` when there is one and its reader accepts the line. Old Pages have no path and change nothing.

### The Code's quip

The naming request's schema gains **`quip`**: one line of at most 90 characters about the Code, in the Assayer's register but the Scribe's voice, no player names since none exist yet. The gate: non-empty, at most 90 characters, no newline; a failing quip is dropped, never a failed creation. **A Room with no history**, which today draws a random word with no model call, makes one **`quip`-only** request with the drawn word and the same deadline, so the Room still opens in a moment and a slow model leaves the quip empty. The Room row gains `quip` (nullable). It renders beneath the Code on the Code card, in the Stage's header beside the join line, and under each rejoin link on the front page. No page load makes a model call.

**Rate limit.** Room creation is limited per device token and per remote address, in memory, a small ETS counter with a sliding hour: generous for a household (a handful per device per hour, a few dozen per address) and closed to a loop. Over the limit the door says "Give it a minute" and creates nothing. Limits are configuration.

### Umami

The root layout renders Umami's script tag — deferred, with the website id — when `UMAMI_SCRIPT_URL` and `UMAMI_WEBSITE_ID` are both configured through runtime configuration, and nothing otherwise. The instance is the one already running on the server; the website is created in its dashboard by hand (a step on the wizard's list). No session replay. No other tracking.

### The notice, through SES

**Swoosh** enters the dependencies with `Swoosh.Adapters.AmazonSES` in production (which needs `gen_smtp` for the raw message and speaks SES's v1 Query API — a fact, not a problem), `Swoosh.Adapters.Local` in development with the mailbox preview at `/dev/mailbox`, and `Swoosh.Adapters.Test` in tests. A Mailer module is created — this app was generated with `--no-mailer`, so `phx.gen.auth` will expect it later (ADR-0007). Credentials through runtime configuration: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` (us-east-1, the server's coast). The notice's addresses are configuration: `NOTICE_TO` (the operator) and `NOTICE_FROM` (an address at thereish.app). When `Rooms.create` succeeds for a device token that holds no Seat anywhere — the same check the Scribe's naming uses to decide whether there is history — a supervised task delivers one plain-text notice: the Code, the player count, the time, and a link. A returning device sends nothing. Delivery never blocks creation; a failure is logged. With no credentials configured the Mailer is not called at all and a line at boot says so, in the manner of `.scratch/foley/issues/08`.

**The human half is a wizard**, generated with `/wizard` and run once by Jacob from a `va` shell: create the IAM identity with SES send permissions and an access key; create the SES domain identity for thereish.app and read back the three Easy DKIM CNAMEs; set a custom MAIL FROM subdomain and read back its MX and TXT; publish those and `_dmarc.thereish.app` (`p=none` to start, `rua=` to an address Jacob reads — an address on another domain needs that domain's report-authorisation record, which the wizard publishes when both domains are at Porkbun) through Porkbun's DNS API with the key `va` provides; wait for the identity to verify; request production access with the use-case text; write the credentials and addresses into the server's `.env` through `bin/keys-to-server`, whose key list grows by these names. `bin/deploy` and the boot warning of `foley/08` learn the new names too.

### Spend and the record

`Chronicle.spend` is unchanged — a ledger of rows. The spend page and the Chronicle's foot line gain a count of Pages in play — Rooms whose process is running and whose Phase is bridging, assaying or reveal — and the sentence "N Pages in play, not yet counted", omitted when the count is zero. A speak task that fails records `voice_meta` for its Attempt with the provider, the voice, `cost_usd` 0.0 and a `failure` reason, attached to the Verdict at chronicle time as a success is; the spend page counts it as a Foley call at zero, as it counts a failed score. The Scribe's `recap` job moves to `low` effort with `xhigh` as a commented alternative; nothing else about the recap changes.

### Schema

Rooms: `music` (string, default `page`) added and `house_loop_only` dropped in one migration pair; `quip` (string, nullable). Track cache: `title` (string, nullable). No new tables; `music_meta` and `voice_meta` are maps and gain keys without migration.

### Build order

1. The forge: the seven new briefs, the manifest, the loop-names module; run under `va bash`; commit the chosen assets.
2. The Room: `music` in place of `house_loop_only`, `set_music`, the loop pick per Page, `title_track` on the Steward with the Fake and the Gemini job, the title task beside the score task, `title` in the cache and on the Track, the voice failure record, the quip in the naming schema and the quip-only request, the Room's `quip`, the rate limit.
3. The web: the three-way control and voice on every phone and the Stage, `foley:page` with title and kind, `foley:commit` to the Stage and `foley:own-commit` to the phone, the local-sounds hook mode and its per-device switch, `deep_meld` and the fading ending, levels from configuration, the "Now playing" line, the captions, the quip on the Code card, the Stage and the door, the Chronicle's Track player and the export line, the spend page's in-play sentence.
4. Umami and the Mailer: the layout tag from configuration, Swoosh with the three adapters, the notice from `Rooms.create`, the boot line, the deploy warnings, the wizard for SES and DNS; Jacob runs the wizard and puts the website in Umami.
5. The Scribe at `low`.
6. Deploy; play a Page with a Stage and one without; record levels and what was heard on `.scratch/foley/issues/06`; confirm the notice arrived, the Track plays from the book, and the spend page's sentence.

## Testing Decisions

A good test crosses one of the four surfaces and asserts on what a player, a Chronicle reader, the operator or the speaking browser could observe. It never calls a provider, never sends real mail, never asserts on prompt text, and never decodes audio.

**The Steward, against recorded responses and the Fake.** `title_track` with the Fake answers a configured title, an error, or after a delay; the gate rejects six words, 41 characters, a quoted title, and asks once more; the fallback builds the deterministic title from three Gives and cuts at 40; the Gemini job parses a recorded answer; the naming request's schema carries `quip` and the gate drops a 91-character quip without failing the word; the quip-only request parses. Prior art is the naming, recap and score tests.

**The Room, through its interface with the Fake.** `music` persists across a restart and migrates from the boolean; `page` starts a score task, `house` and `off` do not, and `page` set mid-Page with no Track starts one; two consecutive Pages never pick the same loop; the title lands on the Track before the Fake's delayed score answers and rides the cache on a hit; a title for a Page that moved on is dropped; a failing Fake speak records `voice_meta` with a failure and zero cost on the Attempt's Verdict at chronicle time; creating a Room from a device with no history sends exactly one notice through the Test adapter carrying the Code, and from a device with history sends none; a Fake Mailer that raises leaves creation successful; the rate limit refuses the Nth creation in an hour and admits the first after; a random-word Room asks for a quip only and opens without one when the Fake is slow. Prior art is the Rooms test, especially the speaker, voice and score sections.

**The Chronicle.** `spend` counts a zero-cost voice failure as a Foley call; the Markdown export writes and re-reads `Track:`; the in-play count is 1 for a Room in bridging and 0 after its Page closes. Prior art is the Chronicle test's spend section.

**The LiveViews.** With two phones and a Stage: the music control and voice switch render on both phones and the Stage, a tap on a non-Speaker phone changes the fact and every view re-renders it; `foley:page` carries `title` and `kind`; a commit pushes `foley:commit` to the Stage and `foley:own-commit` to the committing phone only, and nothing to the other phone; with no Stage and a phone holding the Speaker, a commit pushes `foley:own-commit` to the committer and no `foley:commit` to anyone; a deep-meld close pushes `foley:ending` with `deep_meld`; the "Now playing" line names the loop, then the title when the Track lands; "Bookends" and "Your bridge" render on phone and Stage; the quip renders on the Code card, the Stage header and the front page's rejoin link; the spend page shows the in-play sentence for a Room in play and not otherwise; the Chronicle shows a Track's title and player for a Page with a path and no music line for one without; the root layout carries the Umami tag when configured and not otherwise. Prior art is the Room LiveView test, the Chronicle LiveView test, the spend page test and the room components test.

**The tasks.** The forge with the Fake writes candidates for the seven new briefs and copies winners under the new fixed names; the loop-names module lists every loop in the manifest. Prior art is the forge task test.

**By hand, on the deployment (tickets, not tests).** Levels, the cues, the tick on a phone and on the Stage, the fade under the victory cue, the "Now playing" line — on `.scratch/foley/issues/06`. The SES wizard end to end, the DKIM and DMARC records resolving, the first notice in Jacob's inbox, the first DMARC aggregate report, production access granted — on the wizard's ticket.

## Out of Scope

- Titling a Track from its audio; filed for later on Gemini 3.8 Flash only (`docs/research/audio-input-models-for-naming-a-track.md`, and the inference rule in the design brief).
- A mixer; the levels are configuration until a keyed playtest says the fixed values are wrong.
- A second voice bake-off with Cartesia; Hume stays.
- Accounts and magic links themselves (ADR-0007) — the sender is set up here, the feature is its own spec.
- Session replay of any kind.
- The two fold tickets and the two key tickets, which are already filed and referenced.
- Personalised victory music; a cue written for the Page would arrive a minute after the moment.
- Reading the Bookends aloud; a per-Room voice; sides or the meld map.
- DMARC reporting on stephens.page — Jacob's other site; noted in the research and left to him.

## Further Notes

- **Why the Stage sounds commits and a Speaker phone does not.** The one-Speaker rule exists so two devices never play one Room sound a hundred milliseconds apart. With a Stage present, the Stage sounds every commit and phones stay quiet (ticket 15); sounding on both phone and laptop meant one commit was two sounds from two places on the couch. With no Stage, a phone sounding its own commit is a UI sound answering its own tap — one sound from one place — so it does not break the rule; a Speaker phone relaying everyone's commits would just be the rule with extra steps and a table that hears one phone click for everyone.
- **Why the title is text-first.** The title is off the critical path either way, but a title from the Gives is ready in a second and costs a fortieth of a cent, and the research found the specialists that hear music better than Gemini are hosted only where the inference rule forbids. The audio arm stays a two-day experiment on the harness.
- **Why SES, when Resend already sends for stephens.page.** Resend sends through SES — its subprocessor list names AWS as its sending provider and `send.stephens.page` publishes SES's own records. Jacob wants the platform under his hands, nobody is waiting for the notice, and ADR-0007 will need a real sender on thereish.app. The DigitalOcean SMTP-port block is irrelevant to an HTTPS adapter, so no second server. Resend's free tier would have allowed the domain (three domains); the choice is about learning, not limits.
- **Measured facts that shaped this.** The ten recaps to date cost $0.71 of the $0.80 ever spent, seven to fifteen cents each at `xhigh` against two cents before it, first-pass through the Vale gate either way. The first keyed Track (RICE, "africa" and "cuba") took 84 s to arrive and cost four cents; its quip was spoken by Hume; both were invisible on the spend page until the Page closed. Room KALE closed with no music record because its house-loop switch was left on, not because of a bug.
- **On `foley:page` with a nil path.** Music Off is not `foley:stop`: stings, the beat and the voice still play. The hook fades the music bus and keeps everything else, and a later `page` or `house` fades it back in.
- **Ticket 08 grows.** The deploy's warnings and the boot line cover the AWS credentials and the Umami pair as well as Foley's keys; `bin/keys-to-server` lists them all.
