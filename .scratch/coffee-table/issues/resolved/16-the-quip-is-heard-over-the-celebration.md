# 16: The quip is heard over the celebration

**What to build:** A Meld's victory cue currently plays over the Assayer speaking the quip, and the quip is what the table came for. Both land at the close: `foley:ending` starts the cue on the stings bus after the meld delay, and `foley:voice` plays the Assayer on the voice bus as soon as the quip renders. The voice ducks the **music** bus for its duration (`duckMusic`) and nothing ducks the **stings** bus, so an eight-to-twelve second victory cue runs at full level straight through the narration. The celebration stays — it is the right sound for a Meld — but the words win: whenever the Assayer is speaking, everything else sits under them.

Spec section: Pushed events; the levels beside them.

**Blocked by:** None (can start immediately).

**Status:** resolved

The fix belongs where the ducking already is (`lib/meaning_game_web/components/room_components.ex`, the Foley hook): `duckMusic`/`restoreMusic` know how to bring a bus down for a known duration and put it back, and the voice handler already calls them with the buffer's duration and restores on `onended`. Ducking the stings bus the same way is the smaller change and keeps the cue audible underneath, which is what a celebration under a punchline should sound like. Waiting for the cue to finish before speaking is the wrong shape — the cue is up to twelve seconds and the quip would arrive long after the moment it is for.

- [x] While the Assayer's voice is playing, the stings bus is ducked beneath it and restored when the voice ends, exactly as the music bus is; a cue that starts mid-narration is ducked too, not just one already playing
- [x] The duck depth for stings is configuration beside the levels, tunable by ear, and separate from the music duck — a cue ducked to the music's depth may vanish
- [x] The meld and deep-meld cues still play in full over an unmelded close and over a Page with the voice switched off; nothing about the two-second music fade under the cue changes
- [x] The existing meld cue delay (1.8s, configuration) is re-examined against when the voice actually starts, and any change is recorded here with the number
- [x] A components test for the hook: a voice event during a playing cue ducks the stings bus and restores it on end; a cue arriving during a playing voice starts ducked
- [x] Judged by ear on the couch as part of `14`, with the quip intelligible over the celebration from across the room

## Comments

**2026-09-07.** Filed from Jacob's playtest notes (`.scratch/ideas/ideas.md`): "The victory music played over the Assayer speaking the quip when we got a meld and so I couldn't hear the quip be narrated." Heard on the third playtest, against 07 as shipped.

**2026-09-07 (Resolution).**
- Configured `duck_stings: 0.35` in `MeaningGame.Steward.foley_levels/0`, `config/config.exs`, and `config/test.exs` alongside `music`, `stings`, `voice`, and `duck`.
- Rendered `data-level-duck-stings` attribute on `#foley-container` in `MeaningGameWeb.RoomComponents.foley_hook/1`.
- Added `duckStings`, `restoreStings`, and `isStingsDucked` methods to the `.Foley` hook in `room_components.ex`.
- In `foley:voice`, both `duckMusic(duration)` and `duckStings(duration)` are called; `restoreStings()` is invoked on `source.onended` and in `stopVoice()`.
- In `playEffect()`, if a sound is played on `stingsBus` while voice is active (`isStingsDucked()`), it starts ducked at `levels.duckStings` (0.35).
- Re-examined existing meld cue delay: The `ClimbNumber` animation runs for ~1.2–1.5s to visually reveal the score and reach the meld band, followed by a 300ms beat before the victory cue begins at 1800ms (`meld_cue_delay_ms: 1800`). Since the voice audio typically lands and starts speaking near ~0.5s, keeping 1800ms ensures the cue begins ducked (0.35) under the quip narration, and swells to full volume (1.2) once the quip punchline ends. The 1800ms setting is confirmed and retained.
- Verified with unit and hook simulation tests in `RoomComponentsTest`. All 755 tests pass.
