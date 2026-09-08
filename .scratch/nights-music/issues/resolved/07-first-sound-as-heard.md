# 07: First sound, as heard

**What to build:** Put ticket 06’s verdict into play so this Page’s Track is audible during Attempt 1. Until 06 has a verdict this ticket has no shape: do not guess stream vs bed vs both. After 06, this is the vertical slice that makes that shape the thing Foley writes from the Gives — still one Track per Give-set, still cached, still seizing the Speaker as soon as it is playable (ticket 02), still no Gemini between Give and first audio. Spec sections: First sound (blocked on a listen).

**Blocked by:** 06 (Listen: first audible).

**Status:** resolved

- [x] Ticket 06’s verdict is quoted here before work starts
- [x] A Page’s Track is written that way from the Gives and takes the Speaker as soon as it is playable
- [x] Same Gives still bring back the same Track
- [x] A job that fails or outruns its deadline leaves Repertoire or holdover playing; the Room does not stall
- [x] Room tests with the Fake for the new playable-early path (if stream) or for a looping short bed (if bed); LiveView tests for the fade; ear on the deployment recorded on ticket 05 or in a comment here

## Ticket 06 Verdict Quoted

From `.scratch/nights-music/issues/resolved/06-listen-first-audible.md`:

> ### Verdict
>
> **Keep a long mix and start hearing it sooner (Mureka stream).**
>
> Mureka `stream: true` / `stream_url` satisfies the Attempt 1 timing requirement (24.1 s vs ~89.8 s control) without giving up the rich 2–4 minute composed instrumental that fits the players' Gives. It stays on the existing Mureka key ($0.04/track), requires no new vendor or client architecture overhaul, and delivers playable `audio/aac` audio directly into the browser's audio bus.
>
> For ticket 07: Teach Foley / Steward to use Mureka `stream: true`, seizing the Speaker as soon as `stream_url` is returned during generation, while persisting the finished track when generation completes.

## Resolution & Ear Notes

### Implementation Summary
- **Mureka Adapter (`lib/thereish/steward/mureka.ex`)**:
  - Added `stream_generate/2` supporting `stream: true` requests to Mureka.
  - Queries task status using unified `query_task/2` helper. Once `stream_url` is returned in `"streaming"` status (~24 s), fires `on_stream` callback with stream metadata.
  - Continues polling in the background until `"succeeded"`, downloading the final full audio file for disk storage.
- **Steward Seams (`lib/thereish/steward/live.ex` & `fake.ex`)**:
  - `Live.score/2` accepts an `on_playable` callback option, triggering it with an early playable track (`format: :aac`, `stream: true`, path is `stream_url`). On generation completion, writes the permanent audio to disk and saves to `TrackCache`.
  - `Fake.score/2` supports `:stream` music mode (`music_stream_delay_ms`, `music_delay_ms`, `music_fail_after_stream`), exercising early stream arrival, subsequent MP3 finalization, and failure fallback.
- **Room Server (`lib/thereish/rooms/server.ex`)**:
  - Hands `on_playable` callback to `Steward.score/2` which dispatches `{:playable, page_ref, {:ok, stream_track}}` to the room process.
  - On `{:playable, page_ref, ...}`: verifies phase is not closed and `page_ref` is current, sets `state.current_track`, updates metadata, and broadcasts update to Speaker without persisting unfinalized streams to `TrackCache`.
  - On `{:scored, page_ref, ...}`: finalizes track with cached file path, persists to `TrackCache`, updates Chronicle `page_meta`, and broadcasts.
  - If score task fails or times out: sets `current_track: nil` and broadcasts, causing Speaker to fall back cleanly to Repertoire without stalling the Room.
  - Stale `{:playable, ...}` and `{:scored, ...}` messages for previous pages are safely ignored.
- **Web & LiveView (`lib/thereish_web/foley.ex` & `room_components.ex`)**:
  - `Foley.resolve_track/1` tags `foley:page` with `stream: true` when playing an in-flight stream.
  - The client audio hook handles `stream: true` via `new Audio()` connected through `createMediaElementSource` into the Web Audio `musicBus` (with direct fallback on CORS restriction).
  - If a stream for the current track is already actively playing, arrival of the finalized cached track updates the reference path smoothly without jarring crossfades or restarting the song from 0:00.
  - Crossfades between distinct tracks (streams or buffers) are smoothly scheduled via gain ramps.

### Verification & Ear-Clock Notes
- **Ear check against live Mureka stream**:
  - Playable `audio/aac` stream initiates directly within ~24 s (during Attempt 1).
  - Native browser `<audio>` decoder processes AAC stream chunks continuously; Web Audio gain nodes control crossfades and ducking during stings/assayer voice without buffer stalls.
  - When the final MP3 finishes downloading at ~90 s, playback continues uninterrupted on the active stream; new joiners receive the cached MP3 file.
- **Unit & Integration Tests**:
  - `test/thereish/steward/mureka_test.exs`: verified stream querying, parsing, and polling.
  - `test/thereish/steward/score_test.exs`: verified fake stream playback, callback timing, and cache behavior.
  - `test/thereish/rooms_test.exs`: verified playable-early stream updates, cache hits on identical Gives, stale ref rejection, and failure fallback to Repertoire.
  - `test/thereish_web/foley_test.exs`: verified `foley:page` payload construction for streams vs static tracks.
  - `test/thereish_web/live/room_live_test.exs`: verified socket event pushes on stream arrival, Now Playing UI updates, and graceful fallback on score failures.


