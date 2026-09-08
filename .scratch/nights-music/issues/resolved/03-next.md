# 03: Next

**What to build:** Wait music can be skipped without a verdict. Next advances a session shuffle of the eligible Repertoire pool (ticket 01’s draw): deal, advance, no repeat until the deal is exhausted, then reshuffle, never the thing now playing. It is offered on a Repertoire draw and on holdover, hidden while this Page’s own Track is playing, and only on the speaking screen. Mode stays Written for this Page, so an in-flight Track still seizes the Speaker when it lands. Spec sections: Next and Never.

**Blocked by:** 01 (The Repertoire is wait music), 02 (Holdover — the night is a chain).

**Status:** resolved

- [x] Next on a Repertoire draw changes the song to another eligible member; the previous one can return only after the deal is exhausted
- [x] Next on holdover leaves last Page’s Track and plays a shuffle from the same pool the opening would use; mode stays `page`
- [x] Next is not shown (and is a no-op) while this Page’s Track is on the Speaker
- [x] Next is not shown when only one playable member remains
- [x] Next renders only on the speaking screen, below the fold with the music control
- [x] Room tests for the deal, for holdover skip, and for refusal on this Page’s Track; LiveView tests for visibility on speaker vs not and for the pushed path after a tap

## Resolution
- `Thereish.Foley.Repertoire`: Added `deal/2` and `next_deal/3` (accepting a room ID or explicit member list) to manage shuffling the eligible Repertoire without repeats until exhausted, and reshuffling without repeating the currently playing member.
- `Thereish.Rooms`: Added `next/2` API function to dispatch Next requests to the Room GenServer.
- `Thereish.Rooms.Server`:
  - Maintained `deal` and cached `eligible_members` in Room server state, updated at room init and `next_page` to prevent database queries during snapshot evaluations.
  - Handled `{:next, device_token}` calls: verified caller is the speaking device (`speaking_device?/2`); verified `next_offered?` condition; advanced the deal; on holdover skip, cleared `current_track` and `track_page_ref` while keeping mode `page`; broadcasted room state updates.
  - Exposed `:next?` boolean in snapshot view via `next_offered?/2` (offered on Repertoire draw or holdover when >1 playable member exists; hidden when this Page's own Track is playing).
  - Handled invalid Next calls by refusing with `{:reply, {:error, :refused}, state}` when conditions are not met (e.g. track playing or single member), or treating as a no-op `{:reply, :ok, state}` when the caller is not the speaking device.
- `ThereishWeb.RoomComponents`: Added Next button with `data-role="music-next"` and `phx-click="next_music"` below the fold inside `foley_switches/1`, conditionally rendered when `@room[:speaker?] and @room[:next?]`.
- `ThereishWeb.RoomLive` and `ThereishWeb.StageLive`: Added `handle_event("next_music", ...)` delegating to `Rooms.next/2`.
- Tests: Added comprehensive unit tests in `repertoire_test.exs`, room server tests in `rooms_test.exs` (deal advance, holdover skip, single-member hiding, non-speaker refusal/no-op, track playing refusal), component tests in `room_components_test.exs`, and LiveView integration tests in `room_live_test.exs`. All tests in the test suite pass.
