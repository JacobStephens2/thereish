# 02: Holdover — the night is a chain

**What to build:** A landed Track does not die at “One more?”. It keeps playing through close, giving, and writing until the next Page’s Track is playable, then that Track crossfades in — including during writing, not waiting for bridging. A score for a Page that has already moved on is still dropped and must not overwrite holdover. Spec sections: The night as a chain; Occupancy in the Room.

**Blocked by:** 01 (The Repertoire is wait music).

**Status:** resolved

- [x] After a Page closes, the landed Track is still what the Speaker is playing; the snapshot kind is holdover and “Now playing” keeps that title
- [x] Giving and writing for the next Page keep that Track; `foley:page` is not a fresh Repertoire draw and is not silence
- [x] When the new Page’s Track is playable it seizes the Speaker in whatever phase the Room is in, including writing
- [x] A `scored` result whose Page is not the current one is ignored and does not replace holdover
- [x] If the previous Page never landed a Track, wait music is still a Repertoire draw from ticket 01
- [x] Room tests cover holdover across `next_page` and a stale score; the old expectation that the Track is nil after `next_page` is gone. LiveView tests cover `foley:page` on giving/writing for holdover and for a Track that lands during writing

## Resolution
- `ThereishWeb.RoomComponents.now_playing_text/1`: Added handling for `kind == "holdover"`, formatting as `"Now playing: #{title} (last Page's Track)"`, prioritizing `room[:playing]` over `room[:track]`.
- `ThereishWeb.Foley`: Added `:closed` to `@music_phases`. In `resolve_track/1`, prioritized `room[:playing]` so holdover tracks are played across closed, giving, and writing phases.
- `Thereish.Rooms.Server`:
  - Added `track_page_ref` to state to track which page reference the currently playing track belongs to.
  - Updated `resolve_playing/2` to return `kind: "holdover"` when phase is `:closed` or when `track_page_ref != current_page_ref`.
  - Maintained `current_track` across `next_page` as holdover when the previous page had landed a track (`track_page_ref == current_page_ref`), and preserved it across give resets (`reset_score_state` with `keep_track: true`).
  - When a new track lands (`{:scored, page_ref, ...}`), it updates `current_track` and `track_page_ref`, seizing the speaker immediately in whatever phase the Room is in (including `:writing`).
  - Dropped late/stale scores whose `page_ref != current_page_ref`, ensuring holdover is not replaced by stale scores.
  - Guarded titling task (`{:titled, page_ref, ...}`) from mutating the holdover track's title before the new page's audio scores.
- Tests: Added and updated comprehensive unit, Room server, and LiveView integration tests covering holdover through closed, `next_page`, giving, writing, stale scores, and track seizing during writing. Full test suite (792 tests) passes.
