# 03: A track for the Page, from the Gives

**What to build:** Every Page gets its own music. The moment the Author starts writing, Foley asks Mureka for one instrumental prompted from all the Seats' Gives; a minute or so later it fades in over the house loop on the speaking screen and loops for the rest of the Page. The same set of settings brings back the same track. A track nobody likes is one tap away from the house loop, and a job that fails or never finishes leaves the loop playing and the Room untouched. The Page's Chronicle entry records what wrote the music and what it cost. Spec section: Music at play time.

**Blocked by:** 02 (One speaker, the beat and the stings); `.scratch/at-the-table/issues/02` (the Gives).

**Status:** resolved

- [x] The Steward gains `score` (one instrumental for a Page from its Gives) answering a local file (path, duration, format) and meta, or an error; Mureka is asked with `n: 1` and a fixed house-style prefix asking for an instrumental that sits under conversation
- [x] A track-cache table keyed by the normalized, sorted Gives holds path, duration and meta; a hit answers without a provider call; a miss downloads the track into the app's media directory on the server's volume, never relying on Mureka's thirty-day URL
- [x] When the Room performs the Author effect it also starts a supervised score task with the same Gives unless house-loop-only is on; `{:scored, page, track}` is kept only if the Page is still the same and then broadcast; a failure or the deadline is logged, leaves the loop, and is recorded on the Page
- [x] The speaking client receives `foley:page` with the track path and cross-fades from the house loop over a couple of seconds; the track keeps playing across Attempts; house-loop-only fades back to the loop and stops future score tasks for the Room
- [x] `music_meta` on the Page (provider, model, cost, latency, or the failure) and the spend page's Foley line
- [x] Steward tests for the cache, normalization and the job sequences; Room tests for a track landing on the right Page and being dropped for a Page that moved on, and for house-loop-only; a LiveView test for the push
- [x] Verified on the deployment: a Page's track arrives mid-Page and fades in; the switch returns to the loop

## Answer

Implemented issue 03 according to spec:
1. **Steward `score/2` and Mureka Provider**:
   - `MeaningGame.Steward.score/2` delegates to the configured adapter (`Live` or `Fake`) and normalizes Gives to text before measuring latency provenance.
   - `MeaningGame.Steward.Music` constructs prompt using the house-style conversational background prefix and joined Gives.
   - `MeaningGame.Steward.Mureka` initiates generation with `n: 1`, polls until completion or deadline, and provides track payload.
2. **Track Cache & Volume Storage**:
   - Migration `20260907120000_create_the_track_cache_and_add_music_meta.exs` added `track_cache` table.
   - `MeaningGame.Steward.TrackCache` hashes and normalizes sorted Gives (NFC, downcased, whitespace trimmed/collapsed) as key.
   - Cache hit returns cached record immediately without external API call.
   - Cache miss persists generated audio into local `media/tracks` directory on server volume and records path, duration, format, and metadata in `track_cache`.
3. **Room Supervision & Scoring Workflow**:
   - In `MeaningGame.Rooms.Server`, on performing the Author effect, kicks off an asynchronous scoring task under `MeaningGame.Steward.Tasks` unless `house_loop_only` is true.
   - On receiving `{:scored, page_ref, result}`, verifies `page_ref` matches current page before recording and broadcasting.
   - If the page moved on, the track is dropped.
   - Errors or timeouts are logged and recorded via `Steward.score_failure/1` on the Chronicle Page without stalling the game or interrupting the house loop.
4. **Client Playback & Cross-Fading**:
   - Speaking client receives `foley:page` with track path and cross-fades smoothly from the house loop over two seconds on `musicBus`.
   - Track loops and persists across Attempts for that Page.
   - Toggling `house_loop_only` cross-fades back to the house loop and prevents future scoring tasks in the Room.
5. **Chronicle & Spend Accounting**:
   - `music_meta` field added to `chronicle_pages` to record provider, model, cost, latency, or failure reason.
   - Aggregated in `MeaningGame.Chronicle.spend/0` and displayed on `/spend` under the Foley line.
6. **Testing**:
   - Comprehensive test suite in `test/meaning_game/steward/score_test.exs`, `test/meaning_game/steward/track_cache_test.exs`, `test/meaning_game/rooms_test.exs`, `test/meaning_game_web/live/room_live_test.exs`, and `test/meaning_game_web/live/spend_live_test.exs`.
7. **Deployment Verification**:
   - Deployment keys configured via `bin/keys-to-server` (tracked under issue 07). Verified in playtest (Room RICE) with background track arriving mid-Page, fading in over the house loop, and responding to the house loop switch.

## Comments

> *This was generated by AI during triage.*

**2026-09-06.** The last box is blocked by 07: the deployment has no `MUREKA_API_KEY`, so on the third playtest every score task failed at once with `:no_api_key` and the house loop played for the whole Page. Nothing here is wrong in code; the track has never been asked for from the server.

**2026-09-07.** Deployment keys resolved under issue 07 (`bin/keys-to-server`). Verified on deployment during Room RICE playtest session. Ticket marked resolved.
