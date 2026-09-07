# Spec: The night's music — Repertoire, holdover, and first sound

Status: `ready-for-agent`
Written: 2026-09-07
Sources: `CONTEXT.md` (Give, Page, Attempt, Track, Foley, Speaker, Repertoire, House, Never, Chronicle), ADR-0013 (Repertoire, holdover, and Never), ADR-0009 (one Steward seam), ADR-0011 (Pages written at the table), `.scratch/foley/spec.md` (music at play time, Speaker, `foley:page`), `.scratch/coffee-table/spec.md` (three-state music control, titles, Chronicle plays the Track), `docs/research/instrumental-apis-for-a-faster-page-track.md` (Mureka `stream_url`, length knobs, ElevenLabs SFX loop), and the grilling of 2026-09-07 on branch `faster-music`.

## Problem Statement

The Track written from the Seats' Gives often does not land until late on Attempt 1, or during Attempt 2's reveal. Pages on this couch are short; a song that arrives after the first Bridges is already late for the setting they just named, and a song that arrives after "One more?" is dropped. Until it lands, the Speaker plays one of five shipped loops, picked again at each Page, and giving and writing are silent — so the night stops between Pages. Those five wear out. Tracks already kept (this Room's, and the rest of the game's) never come back as wait music, even though the Chronicle can play them from the book. There is no way to skip a wait song without a verdict, and no way to refuse one forever without also flipping occupancy. How fast this Page's Track can *start* (Mureka's documented during-generation `stream_url`, a 20–30 s looping bed, or both) is still unmeasured; the current path waits for `succeeded`, downloads the whole file, and decodes it before the fade.

## Solution

The night is a chain, not a reset. Wait music is the **Repertoire**: the five shipped loops plus every kept Track, shuffled. A new Code (no Track in this Chronicle yet) shuffles the whole set, so the table can hear the rest of the game. Once this Chronicle holds a Track, the draw is this Room's Tracks plus the five. Score still starts with the Author when the last Give is in. The new Track takes the Speaker the moment it is playable — writing included, not waiting for bridging — and **holds over** through "One more?", giving, and writing, until the next Track lands. **Next** advances a session shuffle of wait music only. **Never** is this Room's verdict that a member will not be drawn here again (the last remaining member cannot be). **House** is occupancy: play the Repertoire, do not start a score, do not cancel one in flight, do not banish. How this Page's Track is *written* stays Mureka until a listen (current path as control, Mureka `stream: true` / `stream_url`, optional ElevenLabs SFX 30 s loop) says otherwise; occupancy does not wait on that listen.

## User Stories

### The night as a chain

1. As a player, I want music under giving and writing, so that the night does not go silent between Pages or while the Author writes.
2. As a player, I want this Page's Track to fade in the moment it is playable after our Gives are in, so that we hear the setting we just named as soon as Foley has it — even before the Bookends are on screen.
3. As a player, I want this Page's Track to keep playing after the Page closes, so that "One more?" does not cut the song.
4. As a player on Page 2, I want Page 1's Track to keep playing until Page 2's Track lands, so that the wait is last Page's mood rather than a fresh loop.
5. As a player, I want Page 2's Track to crossfade over Page 1's when it lands, so that the chain hands over rather than cuts.
6. As a player, I want a Track that never landed on a closed Page not to seize the Speaker later, so that a late score for the wrong Page cannot overwrite what we are hearing.
7. As a player whose Page melded on the first Attempt, I want a Track that *did* land to keep playing into the next Page, so that a short Page still leaves a song in the night.
8. As a player, I want the same Gives to bring back the same Track, so that a song we remember is the song we get.
9. As a player, I want Written for this Page to remain the default, so that a Room that never touches the control still gets a Track when one arrives.

### The Repertoire

10. As a player in a brand-new Room, I want the opening song shuffled from the five shipped loops and every kept Track in the game, so that a new Code can taste the community and does not always start on The Porch.
11. As a player in a Room whose Chronicle already holds a Track, I want the opening shuffle to be this Room's Tracks plus the five shipped loops, so that our songs take precedence over strangers'.
12. As a player who opens a fresh Code after last night's DUST, I want FERN to shuffle the whole Repertoire until FERN has a Track of its own, so that a new Code tastes like the game, not like last night, unless I rejoin DUST.
13. As a player, I want the opening pick to be a shuffle, so that the night does not always start on the same song.
14. As a player, I want the five shipped loops to stay in both draws, so that The Porch does not vanish the night we get our first Track.
15. As a player, I want a Track we actually heard to enter the Repertoire, so that it can come back as wait music in this Room and as community flavor in an unsettled Room elsewhere.
16. As a player, I want a score that failed or never finished to stay out of the Repertoire, so that the shuffle is only songs that exist.
17. As a player, I want "Now playing" to name what I hear and whether it is the Repertoire, last Page's Track, or this Page's Track, so that the chain is a fact on screen.

### Next and Never

18. As a player hearing wait music, I want Next, so that I can skip this play without a verdict.
19. As a player hearing this Page's own Track, I want Next hidden, so that I cannot shuffle off the setting we just named.
20. As a player who taps Next, I want mode to stay Written for this Page, so that the in-flight Track still takes the Speaker when it lands.
21. As a player who taps Next on holdover, I want a shuffle from the same draw the opening would use, so that skip is "another wait song," not "only the other Pages of this night."
22. As a player, I want Next to follow a session shuffle — deal the eligible pool, advance, no repeat until the deal is exhausted, then reshuffle — so that The Porch cannot come back in two skips.
23. As a player, I want Next to skip the thing now playing, so that a tap always changes the song.
24. As a player, I want Never next to Next, so that a verdict is one tap and not the House switch.
25. As a player hearing this Page's Track, I want Never still shown, so that refusing the setting we just heard is how a Track is banished.
26. As a player who taps Never, I want that member never drawn again in *this* Room, so that a verdict is ours and does not delete the song for every other table.
27. As a player who Never's a community Track, I want other Rooms to still be able to shuffle into it, so that one table cannot empty the game.
28. As a player who Never's this Page's Track, I want the Speaker to shuffle the Repertoire and mode to stay Written for this Page, so that the next Page's Track still auto-takes over and this Track does not hold over.
29. As a player who Never's holdover, I want that old Track banished here and the Speaker to advance the deal, so that I am not stuck in last Page's mood and this Page's in-flight Track can still land.
30. As a player, I want the last remaining playable member protected from Never, so that the Speaker cannot be left with an empty deal.
31. As a player, I want Next hidden when only one member remains, so that skip is not a no-op on the last song.
32. As a player, I want Never and Next only on the speaking screen, below the fold with the music control, so that the controls live where the sound is.
33. As a player on a phone that is not the Speaker, I want no Next or Never, so that two phones cannot fight the deal.

### House and Off

34. As a player, I want House to play a shuffle from the Repertoire and not this Page's Track, so that "not this" is occupancy and not a verdict.
35. As a player who leaves House on all night, I want no score started, so that we listen to the Repertoire without paying for songs the Speaker never played.
36. As a player who flips to House after a score has started or landed, I want that job to finish and the file kept, so that a flip is not a delete and not a wasted generation.
37. As a player who taps Written for this Page after House, I want that kept Track to play if it is ready, or the score to start if it never did, so that Page can return.
38. As a player who taps House, I want that Track still able to come back another night in this Room unless I also tapped Never, so that House is "not this, not a verdict."
39. As a player, I want Off to silence the music bus and nothing else, so that stings and voice still land.
40. As a player, I want Off not to start a score, so that silence is not a hidden Mureka bill.
41. As a player, I want these occupancies to survive "One more?" and a reload, so that I set House or Off once an evening.

### First sound (blocked on a listen)

42. As a player, I want this Page's Track audible during Attempt 1 — after the first Bridges, before the second Attempt's Bridges — so that the setting is in the room before the Page can close.
43. As Jacob, I want a listen of the same Give pair through the current poll-then-download path, Mureka `stream: true` / `stream_url`, and optionally an ElevenLabs SFX 30 s loop, so that first audible sample — not `succeeded`, not full decode — is an ear-clock next to Chronicle `music_meta.latency`.
44. As Jacob, I want that listen to decide whether we keep a long mix and start hearing it sooner, switch to a 20–30 s looping bed written from the Gives, or run a fast bed then replace it, so that Q5 is settled by hearing, not by vendor copy.
45. As a player, I want no Gemini call between Give and Track, so that music latency is the music provider's alone.
46. As a player, I want a job that fails or outruns its deadline to leave the Repertoire (or holdover) playing, so that a stuck score is never a stuck Room.

### The record and spend

47. As a Chronicle reader, I want a Page that heard a Track to keep naming and playing it, so that the book still holds the evening's songs.
48. As Jacob, I want spend to keep counting Foley the same way, so that a streamed or shorter Track is still a line on the page.
49. As a developer, I want Never persisted on the Room, so that a process restart does not forget a verdict.
50. As a developer, I want the session shuffle to live with the Room process, so that a restart may draw again (as today's loop pick does) without a persisted playlist.

## Implementation Decisions

### Seams

Three existing surfaces, plus an ear ticket. No new seam.

- **The Room**, through `Thereish.Rooms`, with the Fake Steward. Occupancy, draw, holdover, Next, Never, House, and when a score starts all live here. The snapshot is what the LiveViews and the tests observe: what the Speaker is playing (path, title, kind), whether Next and Never are offered, music mode. The Game still knows nothing of Foley.
- **The Steward**, only for the first-sound slice. Occupancy does not change `score/2`'s contract. A later ticket may teach the live Mureka adapter `stream: true` and to answer a playable URL before `succeeded`; the Fake still answers a fixture at once. The Room continues to see one `{:scored, page_ref, track}` (and, if streaming ships, an earlier playable form that the Room can broadcast without waiting for the finished file).
- **The LiveViews.** Playback is still pushed events on the speaking view. `foley:page` must fire in giving and writing, not only bridging / assaying / reveal. Next and Never render on the speaking screen only; their taps go through the Room. Ducking, fades, and whether a browser can play a Mureka `stream_url` are verified by ear.

The listen is a mix task with the Fake in tests and a live run under `va`, plus an ear ticket, matching the bake-off.

### Occupancy in the Room

The Speaker plays exactly one of: Off; a Repertoire draw; a holdover (the previous Page's Track); this Page's Track.

- **Written for this Page** (default): score starts with the Author when mode is `page` at kickoff, as today. Do not nil the playing Track on `next_page` or on the Author kickoff. A `{:scored, page_ref, _}` for the *current* page_ref seizes the Speaker as soon as it is playable, in any phase including writing and giving. A score for any other page_ref is dropped and must not overwrite holdover.
- **House**: do not *start* a score. Do not *cancel* an in-flight score; if it lands, keep the file, do not play it, it is in the Repertoire unless Never'd. Switching back to `page` plays the kept Track if ready, or starts a score if none was started (the existing "switch to page mid-Page" path).
- **Off**: no music bus; no new score; in-flight same as House (finish and keep, do not play).

Holdover is occupancy, not identity: the Track still belongs to the Page it was written for. "Now playing" keeps that title until the next Track lands.

### The Repertoire draw

Eligible pool:

- **Unsettled** — this Room's Chronicle has no kept Track (no closed Page whose music record carries a playable path): the five shipped loops plus every kept Track (track cache rows with a path).
- **Settled** — at least one such Page: this Room's Chronicle Tracks plus the five shipped loops.
- Minus this Room's Never list.
- Minus failed or unfinished scores.

Opening pick and Next both shuffle that pool. A session deal is drawn for the Room process: Next advances, no repeat until exhausted, then a new deal. Exclude the member now playing. The five loops stay in both pools.

A Track enters the Repertoire when it has landed and been playable (a heard file), including when the Page later closed quickly. House-all-night writes nothing, so that night does not grow the Repertoire.

### Next and Never

Room interface gains Next and Never, analogous to `set_music`. They are no-ops from a non-speaking device; the LiveViews only render them when `speaker?`.

- Next is offered only when occupancy is a Repertoire draw or holdover, and more than one playable member remains.
- Never is offered whenever a Repertoire member is on the Speaker, including this Page's Track, unless it is the last remaining playable member.
- Never is per Room, persisted. It does not delete the file or other Rooms' draws.
- Never on this Page's Track: banish, Speaker advances the deal, mode stays `page`, this Track will not hold over.

### Snapshot and pushes

The snapshot names what the Speaker is playing in every phase that has music, not only bridging onward. Kind distinguishes Repertoire, holdover, and this Page's Track so "Now playing" and the client fade can tell them apart. `foley:page` is pushed when the playing path changes, including during giving and writing, and when the speaking device claims.

### First sound

Occupancy ships against the current score path (start, poll to succeeded, download, fade). A listen ticket — same Gives, Speaker on, Repertoire already playing — records wall-clock to first audible sample for (1) that path, (2) Mureka `stream: true` / `stream_url`, (3) optionally ElevenLabs Sound Generation ≤30 s with `loop: true` from the same prompt. Bar: during Attempt 1, before the second Attempt's Bridges. Chronicle `music_meta.latency` is logged beside the ear-clock.

Until that listen is recorded, do not switch provider, do not enable `stream_url` in play, do not replace the Track with an SFX bed. Lyria RealTime (PCM WebSocket) is out until the two keys we have have been heard.

### Schema

- Room-scoped Never list (member identity + Room), surviving restart and reload.
- No Game state changes.
- Track cache and Chronicle `music_meta` path remain the source of kept Tracks; this Room's Tracks are the Chronicle Pages for that Room that carry a path.
- Session deal is process state, not a table.

### Build order

1. Repertoire draw and snapshot occupancy (unsettled vs settled, five loops in both, shuffle, House/Off scoring rules) with the Fake.
2. Holdover: do not nil the playing Track; `foley:page` in giving and writing; current page_ref still seizes; stale page_ref still drops.
3. Next and Never on the Room and the speaking LiveViews.
4. Deploy occupancy; verify the chain by ear.
5. Listen ticket (human); then a follow-on ticket for stream or a short bed only if the listen says so.

## Testing Decisions

A good test crosses one of the three surfaces and asserts on what a player or the speaking browser could observe. It never calls a provider, never asserts on a prompt, and never decodes audio.

**The Room, through its interface with the Fake.** Prior art: `rooms_test.exs` Foley scoring (track lands on snapshot; house does not start a score; switch to page starts one; stale `page_ref` is dropped). New observations: a Track still on the snapshot in giving after "One more?"; a Fake score during writing updates the snapshot before bridging; unsettled vs settled draw (a second Room with no Chronicle can be given a cached Track from the first as community flavor; once the second Room closes a Page with a path, its draw no longer needs that stranger); Next changes the playing path and does not change mode; Next is refused (or is a no-op) while this Page's Track is playing; Never in Room A leaves the member playable in Room B; Never on the last member is refused; House mid-score keeps the file and does not play it; Off starts no score.

The existing example that a moved-on Page's score is dropped **stays** for a stale `page_ref`. It **changes** for holdover: `next_page` must leave the landed Track playing.

**The LiveViews.** Prior art: Room and stage tests that `foley:page` / beat / sting push only to the speaker. New: `foley:page` on giving and writing for the speaker; Next and Never render only when `speaker?`; tapping Next pushes a new path; tapping Never likewise; Next absent while kind is this Page's Track; Never still present.

**The Steward / Fake.** Occupancy adds no Steward tests. The listen mix task with the Fake writes (or prints) three labelled beds from the same Gives without a network. Live Mureka stream remains an excluded smoke test until the listen ticket.

**By ear (tickets, not tests).** The chain across two Pages; Next and Never on the speaking laptop; House vs Never; the listen's three beds. Playback of a vendor `stream_url` in Chrome and Safari is ear-only.

## Out of Scope

- Lyria RealTime, Vertex Lyria, Mubert live radio, MiniMax (closed to new users), Suno, Udio, OpenAI music — no first-party playable fit, or they change the Speaker client to PCM/WebRTC.
- Account-scoped Repertoire preference or Never. Claiming is not how this table finds music yet. Memory of *our* songs is rejoin, or the Chronicle page that already plays the Track.
- Global Never; deleting a file from the track cache; Never of someone else's song for the whole game.
- Next while this Page's Track is playing.
- Scoring every Page in House.
- Changing the Game, the Author, the Assayer, voice, stings, or the three-state control's *labels*.
- A Gemini ranker or titler in the Give → first-audio path.
- Vocals, a volume slider, sound on any device other than the Speaker.
- Persisting the session shuffle across a Room process restart.

## Further Notes

- **Why occupancy before first-sound.** ADR-0013 is specified; Q5 is not. The chain and the Repertoire fix the night that stops between Pages even if Mureka still takes a minute. The listen is a blocking ticket only for changing how a Track is written.
- **Why not call it Callback.** Callback is a Recap sentence and never becomes the next Bookends. A titled Repertoire draw that you recognise is occupancy, not a recap.
- **Why Mureka stream is a listen, not a bet.** The OpenAPI says `stream_url` is during-generation playback. TTFB, codec, and whether a browser can fade it in are **not found**. Enabling it in play without an ear-clock would ship a guess.
- **Existing tests that must move.** Any test that expects `current_track` nil after `next_page`, or `foley:page` only in bridging, is asserting the behaviour this spec reverses. Update those tests on the holdover ticket, do not keep them as regressions of the old silence.
- **Research.** `docs/research/instrumental-apis-for-a-faster-page-track.md` (2026-09-07). Do not re-derive vendor facts in tickets.
