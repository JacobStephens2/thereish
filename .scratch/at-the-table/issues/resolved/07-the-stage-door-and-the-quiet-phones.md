# 07: The stage door and the quiet phones

**What to build:** A laptop opens the game, types the Code, and taps **Make this device the Stage** on the Room page — no URL is ever typed. While a stage is connected, every phone's reveal goes quiet: the Bridges and the controls (Again, One more, Overrule, the fairness taps), and no number, band or quip, so every eye goes up. When the stage leaves, the phones show the full reveal again. The Room process knows nothing of this; Presence does. Spec sections: Rooms and the Room process (Presence), The web.

**Blocked by:** 02 (The Page is written at the table), 06 (The reveal, revised).

**Status:** resolved

- [x] The Room page shows a "Make this device the Stage" button whether or not the device holds a Seat; it navigates to the Room's stage route
- [x] A Presence module on the Room's topic tracks every connected view as stage or phone; phone views read it on mount and on every diff
- [x] While a stage is present, a phone's reveal renders Bridges and controls only; the stage renders the full reveal; when the stage disconnects the phones return to the full reveal
- [x] The stage's giving state (from 03) and Bookends render while phones give and bridge
- [x] A LiveView test with two phones and a stage asserts the quiet reveal on both phones, the full reveal on the stage, and the return when the stage view exits; the two-phone tests without a stage are unchanged
- [ ] Verified on the deployment with two phones and a laptop

## Answer

1. **Stage door button**: In `MeaningGameWeb.RoomLive`, the "Make this device the Stage" button is rendered unconditionally in the Room Code card (`[data-role="room-code"]`) linking to `~p"/r/#{@slug}/stage"`. Tested with and without holding a seat.
2. **Presence tracking**: `MeaningGameWeb.Presence` is added to `MeaningGame.Application`'s supervision tree, tracking views on the Room's topic (`room:<code>`) as `%{role: :phone}` or `%{role: :stage}` via `track_phone/2` and `track_stage/2`. `stage_present?/1` queries Presence for active `:stage` live views.
3. **Quiet reveal on phones**: `MeaningGameWeb.RoomLive` assigns `@stage_present?` on mount and updates it on every `presence_diff` broadcast and on `resync/1`. When a stage is connected, `<.reveal>` receives `mode={:quiet}`. In `MeaningGameWeb.RoomComponents.reveal/1`, `:quiet` mode hides the closeness number, band, quip, and no-verdict card while keeping the Bridges comparison and fairness taps. Outer controls (Again, One more, Overrule) remain accessible on phones. When the stage disconnects, phones automatically return to the full reveal. The stage always renders the full reveal.
4. **Stage giving and bookends**: The stage's giving state ("Waiting for settings: N of 2") and Bookends render while phones give and bridge.
5. **Presence broadcast handling**: `StageLive` and `ChronicleLive` handle `presence_diff` broadcasts on the room topic without crashing.
6. **Tests**: Added tests in `MeaningGameWeb.RoomLiveTest` covering stage button presence and navigation (with and without seat), stage giving and bookends, quiet reveal on phones with full reveal on stage, return on stage exit, and mid-reveal stage join/exit. Two-phone tests without a stage pass unchanged. Full test suite passes with 495 tests, 0 failures.
