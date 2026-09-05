# Spec: Foley — what the Room hears

Status: `ready-for-agent`
Written: 2026-09-05
Sources: `docs/design-brief.md` (Foley, decided 2026-09-05), `CONTEXT.md` (Foley, Steward, Beat, Band), ADR-0005 (the quip is the Assayer's), ADR-0009 (one seam to the models), ADR-0011 (Pages written at the table — the Gives this scores), `docs/research/tts-for-the-assayers-voice.md`, the API facts gathered on 2026-09-05 for Mureka, ElevenLabs sound effects and Gemini audio input, and the grilling of 2026-09-05. Depends on `.scratch/at-the-table/spec.md` for the Gives, the Bookends, the six-band Ladder and the quiet reveal.

## Problem Statement

The reveal is a performance with no sound. The number climbs, the band arrives, the quip lands — silently, on a phone, while four people look at their own screens. The beat is a fixed 2.5 seconds because it is theatre, and theatre this quiet has no drumroll. A Page set in "a summer camp" or "the Viking beaches" sounds exactly like every other Page. And the quip — the Assayer's one line of comedy, written about the words the players actually wrote — is read silently by each player at their own pace, which is not how a punchline works.

## Solution

**Foley**, the fourth machine role behind the Steward, makes what the Room hears. Three jobs. *Effects*: a rising figure for the beat, one sting per Band — miss, adjacent, close, almost, meld, deep meld — and two endings, made once through ElevenLabs, ranked by Gemini 3.8 Flash's ear and then Jacob's, and shipped with the game as static files. *Music*: a house loop made once, and one instrumental per Page written by Mureka from the Seats' Gives — started the moment the Author starts, arriving a minute or so later, fading in over the house loop while the Page is still being played — with a switch back to the house loop for a track nobody likes. *Voice*: the band word and then the quip, spoken by one fixed voice that becomes the Assayer's, ready when the quip appears, from text the Assayer already wrote; the provider is decided by a bake-off between ElevenLabs v3 Conversational and Hume Octave 2 that Jacob and Melissa listen to.

**One speaker per Room.** The stage plays when there is one, after the single tap browsers demand; otherwise whichever phone claims the speaker icon plays, and claiming it silences whoever had it. Voice and house-loop-only are switches on the speaking screen, Room facts that survive a Page and a reload, off by default on phones. Nothing here ever delays a reveal: audio that is late plays late, and audio that never comes is a reveal exactly as it is today.

## User Stories

1. As a player, I want the beat to sound like a beat, so that the two and a half seconds before the number are a held breath and not a pause.
2. As a player, I want a different sting for each Band, so that a miss and a meld are heard before they are read.
3. As a player, I want a Meld to sound like an arrival and an unmelded ending to sound like an ending, so that the Page closes with the right note.
4. As a player, I want the quip spoken aloud after the band word, so that the punchline lands once, for everyone, in the Assayer's voice.
5. As a player, I want the Assayer to have one voice, so that it becomes a character we know rather than a text-to-speech setting.
6. As a player, I want music under the Page written from our settings, so that the Viking beaches sound like the Viking beaches.
7. As a player, I want a house loop under the Page until the Page's own music arrives, so that the first Page of the night is not silent.
8. As a player, I want the Page's music to fade in over the house loop when it lands rather than cut in, so that its arrival is a small delight and not an interruption.
9. As a player, I want a switch back to the house loop, so that a generated track we dislike is one tap away from gone.
10. As a player, I want the music to duck under the beat and the stings and the voice, so that the joke is never fighting the soundtrack.
11. As a player at a table with a stage, I want the laptop to be the thing that plays sound, so that the room shares one soundscape.
12. As a player on the stage's first visit, I want one clear "tap for sound" and nothing else standing between me and the game, so that the browser's gesture rule costs one tap and no confusion.
13. As a player at a table with no stage, I want exactly one phone to play sound, so that two phones never play the same sting a hundred milliseconds apart.
14. As a player, I want to claim the speaker by tapping an icon on my phone, and to see that I have it, so that whoever sits nearest the middle can be the speaker.
15. As a player, I want claiming the speaker to silence the phone that had it, so that there is never a chorus by accident.
16. As a player, I want my phone silent by default, so that opening the game on the bus plays nothing.
17. As a player, I want the voice switch and the house-loop switch only on the speaking screen, so that the controls live where the sound is.
18. As a player, I want those switches to survive "One more?" and a reload, so that I set them once an evening.
19. As a player, I want a spoken quip that arrives late to play late, and one that never arrives to change nothing, so that sound is never the reason a reveal waited.
20. As a player, I want the Page's music to keep playing across Attempts, so that a five-Attempt arc has one soundtrack.
21. As a player, I want a repeated set of settings to bring back the same track, so that "the summer camp song" can be a thing we remember.
22. As a player, I want the voice to say the band word and then the quip, and not the number, so that the spoken line is a beat and a punchline rather than a digit.
23. As a Chronicle reader, I want to know which model wrote a Page's music and voiced its quips and what it cost, so that the spend page tells the whole story.
24. As Jacob, I want the stings, the beat figure, the endings and the house loop generated once by a task that gives me several candidates each, ranked by Gemini's ear against the brief, so that I choose from a shortlist and the files are committed.
25. As Jacob, I want a bake-off task that renders the same handful of quips from Room DUST through ElevenLabs v3 Conversational and Hume Octave 2 into files labelled blind, so that Melissa and I choose the Assayer's voice by ear and the choice is one config line.
26. As Jacob, I want the losing voice provider kept as a configured option, so that the choice is reversible without code.
27. As Jacob, I want Mureka asked for one track per Page and not two, so that the default `n=2` does not double the bill.
28. As Jacob, I want Foley's spend on the same page as the language models', so that the evening's cost is one number.
29. As Jacob, I want no Gemini call in the path between a Give and a track, so that the music's latency is Mureka's alone.
30. As a developer, I want Foley's three jobs behind the Steward's behaviour with a Fake that answers fixture files, so that every Room and LiveView test runs without a network.
31. As a developer, I want the ElevenLabs, Hume and Mureka providers tested against recorded responses, so that a vendor's format change is a failing test and not a silent evening.
32. As a developer, I want the speaking screen's playback driven by pushed events that a LiveView test can assert on, so that "the non-speaking phone plays nothing" is a test.
33. As a developer, I want the Room to treat a Mureka job that never finishes as a Page with the house loop, so that a stuck job is never a stuck Room.

## Implementation Decisions

### Seams

Four, as agreed on 2026-09-05: the Steward behaviour with its Fake, the Room through `MeaningGame.Rooms`, the LiveViews (playback asserted as pushed events), and the two mix tasks with the Fake. Playback itself — ducking, fades, the Safari-safe format — is verified by hand on the deployment and recorded on its ticket, because no server-side test can hear.

### The Steward widens

The Steward's behaviour gains Foley's callbacks:
- `score(gives, opts)` — one instrumental for a Page from its Gives; answers a local file (path, duration, format) and meta (provider, model, cost, latency), or an error. Runs Mureka's job — start, poll until succeeded or failed or the deadline, download the chosen URL — entirely inside the Steward, so the Room sees one answer.
- `speak(line, opts)` — one spoken line as audio bytes with format and meta, from the configured voice job.
- `forge(brief, opts)` — N candidate effects for a brief, each as bytes with meta; used only by the forge task.
- `rank(candidates, brief)` — Gemini 3.8 Flash reads N clips as inline audio with the brief and answers an ordering with one sentence each; used only by the forge task. This is the Gemini provider's first audio-input request.

The `foley` role is configured per job like the Scribe: `effects` (ElevenLabs sound generation, `eleven_text_to_sound_v2`, MP3 44.1 kHz), `music` (Mureka instrumental, `n: 1`, model `auto`, a 3-minute deadline, one poll every few seconds), `voice` (provider and voice id chosen by the bake-off; both ElevenLabs and Hume providers exist and either is one config line; MP3 output; a 3 s timeout), and `ear` (Gemini 3.8 Flash, audio in, JSON out). Keys — `MUREKA_API_KEY`, `ELEVENLABS_API_KEY`, `HUME_API_KEY` and `HUME_SECRET_KEY` — come from the environment through runtime configuration like the others; locally they arrive via `va`. The price table gains Mureka's per-track price and per-character prices for the voice providers; ElevenLabs' character cost is read from its response header when present.

The Fake answers a fixture MP3 for every job, or an error, or after a delay, as the Fake Assayer does.

### Assets made once: the forge

`mix foley.forge` takes a brief set — the beat figure (2.5 s, rising, resolving on the downbeat), six stings (miss, adjacent, close, almost, meld, deep meld; each under two seconds; the meld pair brighter than the rest and deep meld the brightest), two endings (meld: an arrival; unmelded: a settle, not a sting), and the house loop (Mureka, an instrumental that sits under talk, prompted once and edited never) — and for each asks the provider for N candidates (four by default), asks the ear to rank them against the brief, prints the ranking with reasons and the file paths, and stops. Jacob listens and writes the chosen index per brief into a small manifest; a second run with the manifest copies the winners into the game's static audio directory under fixed names, which are committed. Generation costs cents; the ear costs less. Nothing at play time ever calls `forge` or `rank`.

### Music at play time

When the Room performs the Author effect it also, unless the Room's house-loop-only switch is on, starts a supervised `score` task with the same Gives. The Steward first checks the **track cache**: a table keyed by the normalized, sorted Gives holding the local file path, duration and meta; a hit is answered at once. A miss runs Mureka and, on success, downloads the track into the app's media directory on the server's volume (Mureka's URLs expire in thirty days, so the game never depends on them), writes the cache row, and answers. The Room receives `{:scored, page_ref, track}` and, if the Page is still the same one, records it in its state and broadcasts; the speaking client fades it in. A job that fails or outruns its deadline is logged, costs nothing more, and leaves the house loop playing; the Chronicle's Page records `music_meta` either way (provider, model, cost, latency, or the failure). Music is prompted from the Gives alone — the Bookends are still being written when the job starts — with a fixed house style prefix in the prompt asking for an instrumental that sits under conversation.

### Voice at play time

When a Verdict arrives — from the Assayer or as a Precedent hit with its fresh quip — and the Room's voice switch is on and a speaker exists, the Room starts a supervised `speak` task with "<band word>. <quip>". The audio bytes are held by the Room for the current Attempt and served by a small controller route under the Room's Code (the bytes for this Attempt, or 404), and the Room broadcasts `voice_ready` for that Attempt. The speaking client fetches and plays it when the quip element is on screen, or immediately if the quip is already showing. A `speak` that fails or arrives after the next Attempt has started is dropped and logged. Nothing about voice touches the beat, the reveal or the Game. The voice's cost goes on the Attempt's Verdict meta as `voice_meta`.

### The speaker and the switches

Three **Room facts**, persisted on the Room's row so a restart and a reload keep them: the speaker (a device token, or none), voice on/off (default off), house-loop-only (default off). The Room's interface gains `claim_speaker(slug, device_token)`, `release_speaker`, `set_voice`, `set_house_loop_only`; each broadcasts. Because device tokens never leave the Room, the snapshot takes the viewer's device token alongside its Seat and answers `speaker?: boolean` and `speaker_claimed?: boolean` (someone has it) plus the two switches. A stage that mounts claims the speaker for its own device token; a stage that leaves releases it; a phone claiming it takes it from whoever had it, stage included, which is the "silence by claiming" rule. The Game knows nothing of any of this.

### The client

One colocated hook, on the Room page and the stage, active only while `speaker?` is true. It builds a Web Audio graph — a music bus (house loop or the Page's track, cross-fading between them over a couple of seconds), a stings bus, a voice bus — with the music bus ducked by a fixed amount whenever a sting or the voice plays and while the beat runs. It reacts to pushed events: `foley:page` (start the house loop; later the track path), `foley:beat`, `foley:sting` with the band, `foley:ending` with the kind, `foley:voice` with the Attempt, and `foley:stop`. The server pushes these only to the speaking view, from the Room's broadcasts as the LiveView resyncs — a phase change to `:assaying` is the beat, a reveal is the sting, a close is the ending, `voice_ready` is the voice. On the stage, an AudioContext cannot start before a gesture, so the stage shows one **Tap for sound** control until the context is running, and remembers nothing across reloads (the browser rule applies every time). On a phone the speaker-icon tap is the gesture. Every file is MP3, which streams and decodes on Chrome Android, desktop Chrome and Safari without the Opus-in-Ogg caveat; the reduced-motion preference already respected by the climbing number is respected here as a "no sound" default.

### The bake-off

`mix foley.bakeoff` reads a Room's Chronicle for its last N quips (default: five from DUST), renders each through both voice providers with one chosen voice each, writes the files into a scratch directory as `01-a.mp3`, `01-b.mp3`, … with a sealed key file mapping letters to providers, and prints the directory. Jacob and Melissa listen; the letter they prefer is looked up; the winner goes into the `voice` job's config and the decision, the voice ids, and the key are recorded on the bake-off ticket. The task runs under `va bash` on the Mac; it never runs in the release.

### Spend

Foley's meta rides where the rest does: `music_meta` on the Page, `voice_meta` on the Verdict, the forge's costs on nothing (they are one-off and printed). The Chronicle's `spend` sums them into the same total, by role and model, and the spend page shows Foley beside Author, Assayer and Scribe.

### Schema

Three switches on the Room row; a track-cache table (gives key, path, duration, meta, inserted order); `music_meta` on Pages and `voice_meta` on Verdicts. No Game state changes.

### Build order

1. The Steward: the four callbacks, the Fake, the ElevenLabs, Hume and Mureka providers against recorded responses, the Gemini audio-input request, the `foley` role and its jobs, the price table.
2. The forge and the bake-off tasks; run both under `va bash`; commit the chosen assets; record the voice decision.
3. The Room: the three facts and their interface, the snapshot's device-token viewer, the score task with cache and the speak task, the broadcasts, the voice route, spend.
4. The client: the hook, the tap-for-sound gate, the speaker icon and switches, the pushes from the two LiveViews.
5. Deploy; verify by ear on the couch with a stage and without one; record what was heard on the integration ticket.

## Testing Decisions

A good test crosses one of the four surfaces and asserts on what a player, an operator or the speaking browser could observe. It never calls a provider, never asserts on a prompt, and never decodes audio: a fixture file's bytes are opaque.

**The Steward, against recorded responses and the Fake.** The Fake scores, speaks and forges with fixtures; Mureka's start-then-poll is driven from recorded `preparing → running → succeeded` and `→ failed` sequences and a deadline that expires; ElevenLabs sound generation and both voice providers parse recorded answers and errors and read the cost header when present; the Gemini ear builds an inline-audio request with N parts and parses a ranking, and rejects one that names an index it was not given; the cache answers a hit without a provider call and normalizes Give order and case. One tagged live smoke test per provider stays excluded. Prior art is the Steward, Gemini and author tests.

**The Room, through its interface with the Fake.** A claimed speaker is the only viewer whose snapshot says so; claiming from another device moves it; a mounting stage takes it and a leaving stage releases it; the switches persist across a Room process restart; a scored track lands on the Page that asked for it and is dropped for a Page that has moved on; house-loop-only stops the score task from starting; a Fake `speak` after a verdict makes `voice_ready` for that Attempt and its bytes are served for that Attempt only; a failing or slow Fake changes nothing about the reveal's timing. Prior art is the Rooms test and the Room fixtures.

**The LiveViews.** With two phones and a stage: the stage's view pushes `foley:beat`, `foley:sting` and `foley:voice` in order across one Attempt and the phones' views push nothing; after a phone claims the speaker the pushes move to it and stop on the stage; the switches render only on the speaking view and their taps change the Room's facts; the tap-for-sound control renders on a fresh stage; the spend page shows Foley's line. Asserted with pushed-event assertions and rendered HTML. Prior art is the Room LiveView test.

**The tasks.** The forge with the Fake writes N candidates per brief, prints a ranking and, given a manifest, copies winners to fixed names; the bake-off with the Fake writes paired files and a key. Prior art is the export tasks' tests.

**By ear, on the deployment (a ticket, not a test).** Beat, stings, endings, house loop, a Give's track fading in mid-Page, the spoken quip landing with the text on a Pixel and on the laptop, ducking under both, the switches, and the claim-and-silence rule with two phones.

## Out of Scope

- Reading the Bookends aloud; a commit tick; a per-Room or per-player choice of voice; vocals or lyrics in the music.
- Live Gemini gating or ranking of per-Page music — the first Mureka answer is the track, by decision, for latency.
- A track per Attempt; sound on any device other than the speaker; a volume slider beyond the browser's.
- Any speech *input*; the Assayer speaking in a native audio-out model (Gemini 3.8 Flash has no audio output — `docs/research/tts-for-the-assayers-voice.md` §2).
- Rights beyond private use: ElevenLabs' free plan carries no commercial licence and Mureka's paid API output does; both are fine for the couch and re-checked before any release (ADR-0008 Falsifier 3).

## Further Notes

- **Why one role and not three.** Foley's three jobs disagree about vendors and about time — effects made once, music in a minute, voice in a second — which is exactly the per-job configuration the Scribe already has. One role keeps the Steward's promise of one seam.
- **Why the stage claims the speaker on mount.** The design's default is "the stage when one is open"; making that a claim rather than a rule keeps the speaker a single Room fact with one owner and lets a phone take it back at the table.
- **Latency arithmetic.** Mureka's own job runs 30–90 s and gives a multi-minute track; a Page is 10–15 minutes, so the track arrives during the first or second Attempt and loops for the rest. Every voice provider on the shortlist publishes first-audio well under a second, and the reveal shows the quip about 1.2 s after the beat ends, so the spoken line is normally waiting for the text rather than the other way round.
- **Facts gathered 2026-09-05** that shaped this: Mureka has a first-class instrumental endpoint, no length parameter, `n` default 2, URLs valid thirty days, ~$0.03–0.045 per track; ElevenLabs sound generation runs 0.5–30 s per clip with a loop option on v2 and MP3 or 48 kHz WAV out; Gemini 3.8 Flash takes inline audio up to 20 MB per request at 32 tokens per second of audio; Chrome and Safari block audible playback before a gesture on the page, every time.
