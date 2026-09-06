# 05: The Assayer speaks

**What to build:** When the voice switch is on and the Room has a speaker, every Verdict is spoken: the band word, then the quip, in the Assayer's one voice, landing as the quip appears on the speaking screen. A Precedent hit's fresh quip is spoken too. Audio that is late plays when it arrives; audio that never comes changes nothing about the reveal; audio for an Attempt that has passed is dropped. The Verdict records what spoke it and what it cost. Spec section: Voice at play time.

**Blocked by:** 02 (One speaker, the beat and the stings), 04 (The bake-off); `.scratch/at-the-table/issues/04` (the band names, `assay-3`).

**Status:** resolved

- [x] When a Verdict arrives — from the Assayer or as a Precedent hit — and voice is on and a speaker exists, the Room starts a supervised speak task with "<band word>. <quip>"
- [x] The Room holds the bytes for the current Attempt; a controller route under the Room's Code serves them for that Attempt and answers 404 for any other; the Room broadcasts `voice_ready` for the Attempt
- [x] The speaking client receives `foley:voice`, fetches the bytes, and plays them when the quip element is on screen — immediately if it already is; the music bus ducks while it plays
- [x] A speak that fails, or arrives after the next Attempt has started, is dropped and logged; the beat, the reveal and the rules are untouched in every case
- [x] The voice switch on the speaking screen turns this on and off and persists (from 02)
- [x] `voice_meta` on the Verdict (provider, voice, cost, latency) and the spend page's Foley line
- [x] Room tests with the Fake for the ready broadcast, the per-Attempt route, the late and failing cases; a LiveView test for the push reaching only the speaking view
- [x] Verified on the deployment: the spoken line lands with the text on the laptop and on a Pixel

## Answer

Implemented issue 05 according to spec:
1. **Supervised Speak Task**:
   - In `MeaningGame.Rooms.Server`, on receiving an assayed verdict (`{:verdict_received, verdict}`), when `state.room.voice` is true and `state.room.speaker` is present, kicks off a supervised task under `MeaningGame.Steward.Tasks` running `Steward.speak(line)`.
   - The spoken line is formatted as `"<band word>. <quip>"` (or `"<band word>"` when quip is empty).
   - On completion, sends `{:voice_spoken, attempt, result}` back to the Room GenServer.
2. **Current Attempt Audio & Controller Endpoint**:
   - GenServer holds audio bytes for `state.game.attempt` in `state.voice_audio` and broadcasts `{:voice_ready, attempt}` via PubSub.
   - Endpoint `GET /r/:slug/voice/:attempt` mapped to `MeaningGameWeb.VoiceController.show/2` serves the audio with `audio/mpeg` (or `application/octet-stream` for other formats) if the attempt matches `state.game.attempt`, and returns 404 for any other attempt or when audio is not present.
   - When the attempt advances (`next_attempt`) or a new page starts (`next_page`), previous attempt audio is cleared.
   - Audio arriving late (after attempt has advanced) or failing is safely dropped and logged without affecting the beat, reveal, or game state.
3. **Client Playback & Music Ducking**:
   - `MeaningGameWeb.Foley.push_voice/2` pushes `foley:voice` with `attempt` and verified URL `~p"/r/#{slug}/voice/#{attempt}"` exclusively to the speaking view.
   - Colocated `.Foley` hook in `MeaningGameWeb.RoomComponents` listens for `foley:voice`, fetches the audio buffer, ducks the music bus to 0.15 gain during speech, and plays the audio via `voiceBus`.
   - Audio starts immediately if the reveal/quip is already on screen, or waits via `MutationObserver` until the quip (or fairness controls) appears.
4. **Verdict `voice_meta` & Spend Accounting**:
   - Migration `20260907110000_add_voice_meta_to_chronicle_verdicts.exs` added `voice_meta` (`map` / jsonb) to `chronicle_verdicts`.
   - `MeaningGame.Chronicle.Verdict` schema casts and persists `voice_meta`.
   - `Rooms.Server` records `voice_meta` on the attempt's verdict when chronicling the page.
   - `MeaningGame.Chronicle.spend` and `MeaningGameWeb.SpendLive` aggregate and display Foley spend by role, by role and model (`:foley`), and per-room.
5. **Testing**:
   - Comprehensive test suite in `test/meaning_game/rooms_test.exs` verifying:
     - Ready broadcast and holding bytes for current attempt.
     - 404 response on non-current attempts.
     - Dropping and logging of failing or late voice synthesis without stalling reveals.
     - Preservation of audio across closed pages until `next_page`.
     - Isolation across `next_page`.
     - Correct `voice_meta` persistence in Chronicle.
   - Controller tests in `test/meaning_game_web/controllers/voice_controller_test.exs`.
   - Spend tests in `test/meaning_game/chronicle_test.exs` and `test/meaning_game_web/live/spend_live_test.exs`.
   - LiveView tests in `test/meaning_game_web/live/room_live_test.exs` asserting that `foley:beat`, `foley:sting`, and `foley:voice` push in order to the speaking view alone.
