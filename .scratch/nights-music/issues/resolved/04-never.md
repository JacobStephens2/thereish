# 04: Never

**What to build:** A Room can refuse a Repertoire member forever, without flipping House. Never is this Room’s verdict, persisted, shown next to Next on wait music and still shown on this Page’s Track. It does not delete the file or other Rooms’ draws. The last remaining playable member cannot be Never’d. Never on this Page’s Track: banish, Speaker shuffles the Repertoire, mode stays Written for this Page, this Track will not hold over. Spec sections: Next and Never; Schema.

**Blocked by:** 03 (Next).

**Status:** resolved

- [x] Never in this Room leaves the member out of every later draw here, including after a reload and a process restart
- [x] The same member remains drawable in another Room
- [x] Never on the last remaining playable member is refused; Next stays hidden
- [x] Never on this Page’s Track banishes it, the Speaker advances the deal, mode stays `page`, and that Track does not hold over into the next Page
- [x] Never on holdover banishes that old Track here and advances the deal; this Page’s in-flight Track can still land
- [x] Never renders on the speaking screen only, including while this Page’s Track is playing (when Next is hidden)
- [x] Room tests for persistence, cross-Room isolation, last-member protection, and no-holdover after Never on this Track; LiveView tests for the control’s visibility

## Resolution
- `priv/repo/migrations/20260907150000_create_room_nevers.exs`: Added migration creating `room_nevers` table with unique constraint on `[:room_id, :path]` and index on `:room_id`.
- `Thereish.Rooms.Never`: Added Ecto schema for Room-scoped Never verdicts.
- `Thereish.Rooms.Room`: Added `has_many :nevers, Thereish.Rooms.Never` association.
- `Thereish.Rooms.Store`: Added `record_never/2` and `list_nevers/1` queries.
- `Thereish.Foley.Repertoire`:
  - Added `nevers/1` to fetch nevered paths for a room.
  - Updated `members/1` to filter out nevered paths for that room.
  - Added `advance_after_never/3` to handle advancing the deal or falling back to the sole remaining member when a member is refused.
- `Thereish.Rooms`: Added `never/2` API function to dispatch Never requests to the Room GenServer.
- `Thereish.Rooms.Server`:
  - Handled `{:never, device_token}` calls: verified caller is the speaking device (`speaking_device?/2`), refused when playing is nil or the last remaining playable member (`last_playable_member?/2`), recorded never in `Store`, filtered `eligible_members` and `deal`, advanced deal using `advance_after_never/3`, cleared `current_track` and `track_page_ref` on track/holdover refusal, kept mode `page`, and broadcasted updates.
  - Exposed `:never?` boolean in snapshot view via `never_offered?/2` (offered on repertoire, holdover, and track unless it is the last playable member).
  - Maintained deal updates across `next_page`.
- `ThereishWeb.RoomComponents`: Added Never button with `data-role="music-never"` and `phx-click="never_music"` below the fold beside Next inside `foley_switches/1`, rendered when `@room[:speaker?] and @room[:never?]`.
- `ThereishWeb.RoomLive` and `ThereishWeb.StageLive`: Added `handle_event("never_music", ...)` delegating to `Rooms.never/2`.
- Tests: Added comprehensive unit tests in `repertoire_test.exs`, Room server tests in `rooms_test.exs` (persistence across restart, cross-Room isolation, last-member protection, track banishment & no-holdover, holdover banishment & subsequent track landing, non-speaker no-op), component tests in `room_components_test.exs`, and LiveView integration tests in `room_live_test.exs`. All 827 tests pass.
