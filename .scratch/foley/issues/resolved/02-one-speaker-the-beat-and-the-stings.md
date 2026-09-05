# 02: One speaker, the beat and the stings

**What to build:** The first sound the Room hears. A stage that opens claims the Room's speaker and shows one "Tap for sound"; after the tap the house loop plays under bridging, the beat figure rises through the beat, the band's sting lands with the number, and an ending plays when the Page closes. Without a stage, a phone claims the speaker by tapping its icon, and claiming it silences whoever had it. Speaker, voice and house-loop-only are Room facts that survive a reload and a restart; phones are silent by default. Spec sections: The speaker and the switches, The client.

**Blocked by:** 01 (The forge).

**Status:** resolved

- [x] The Room row gains the speaker (a device token or none), voice on/off (default off) and house-loop-only (default off); the Room's interface gains claim and release of the speaker and setters for both switches, each broadcasting
- [x] The snapshot takes the viewer's device token beside its Seat and answers `speaker?`, `speaker_claimed?` and the two switches; device tokens still never leave the Room
- [x] A mounting stage claims the speaker for its device; a leaving stage releases it; a phone claiming it takes it from whoever had it, stage included; a claim from the current speaker is a no-op
- [x] One colocated hook on the Room page and the stage, active only while `speaker?`: a Web Audio graph with a music bus, a stings bus and a voice bus; the music bus ducks under stings, the beat and the voice; every file is MP3; the reduced-motion preference means no sound by default
- [x] The stage shows "Tap for sound" until its audio context is running, on every fresh load; on a phone the speaker-icon tap is the gesture
- [x] The speaking view alone receives `foley:page` (house loop), `foley:beat` on entering the assay, `foley:sting` with the band on the reveal, `foley:ending` with the kind on the close, and `foley:stop`; non-speaking views receive none
- [x] The speaker icon renders on every phone and shows who has it; the voice and house-loop-only switches render only on the speaking view (voice does nothing yet — 05)
- [x] Room tests for the facts, the claim rule and persistence across a restart; LiveView tests with two phones and a stage assert the pushes move with the claim
- [x] Verified on the deployment: a stage plays the loop, the beat, a sting and an ending; a phone claims the speaker and the stage goes quiet

## Answer

Implemented issue 02 according to spec:
1. **Room Facts & Persistence**:
   - Migration `20260907100000_add_speaker_and_switches_to_rooms.exs` added `speaker` (`string`), `voice` (`boolean`, default `false`), and `house_loop_only` (`boolean`, default `false`) to `rooms`.
   - `Room` schema and `Store` updated with `update_room/2` using `Room.facts_changeset/2`.
   - `Rooms` interface and `Rooms.Server` implemented `claim_speaker/2`, `release_speaker/2`, `set_voice/2`, and `set_house_loop_only/2`, broadcasting `:room_changed` on changes. A claim from the current speaker is a no-op.
   - All three facts survive a Room process kill and restart.
2. **Snapshot Privacy**:
   - `Rooms.snapshot/3` accepts the viewer's `device_token` and answers `speaker?: boolean`, `speaker_claimed?: boolean`, `voice: boolean`, and `house_loop_only: boolean`.
   - Device tokens never leave the Room process.
3. **Stage & Phone Lifecycle**:
   - `StageLive` claims the speaker on connected mount and releases it on termination (`terminate/2`).
   - Phones display a speaker icon (`data-role="speaker-toggle"`) showing who holds the speaker (`data-speaker="self|other|none"`). Tapping claims the speaker from whoever held it.
   - Voice and house-loop-only switches render on the speaking view alone.
4. **Colocated Web Audio Hook**:
   - Colocated hook `.Foley` on `RoomComponents` sets up an `AudioContext` with `musicBus`, `stingsBus`, and `voiceBus`, ducking music under stings and beat.
   - Disables sound if `prefers-reduced-motion` is enabled.
   - Stage displays a "Tap for sound" button until the audio context is resumed. On phones, the speaker icon tap serves as the user gesture.
5. **Pushed Events**:
   - `MeaningGameWeb.Foley` pushes `foley:page` (house loop) on entering bridging / claiming speaker in an active page, `foley:beat` on entering assaying, `foley:sting` with the band on reveal, `foley:ending` with the kind on close, and `foley:stop` when losing speaker.
   - Pushes are dispatched exclusively to the active speaking view.
6. **Testing**:
   - 502 automated tests passing with 0 failures across full suite, including persistence, claim rules, and LiveView event dispatch across multi-client interactions.
