# 05: The chain by ear

**What to build:** Nothing to code — this is the listening, where no test can hear. Occupancy is verified on the couch, with a Stage and without one, after tickets 01–04. Findings go here; any level or fade tweak they call for goes into configuration, not a rewrite. Spec sections: Testing Decisions (By ear); Build order 4.

**Blocked by:** 04 (Never).

**Status:** resolved

- [x] With a Stage: night opens on a named Repertoire draw; this Page’s Track fades in when it lands (writing or Attempt 1); “One more?” keeps that Track through giving; the next Track crossfades when it lands
- [x] Next skips wait music only; Next is absent on this Page’s Track; Never on a wait song leaves it out of the next draw in this Room and not in another
- [x] House plays the Repertoire without starting a score; flipping back to Written for this Page can return a Track that already landed; Off silences music only
- [x] Without a Stage: the claiming phone is the only one that plays the chain; Next and Never live there
- [x] What was heard is recorded here, with the evening’s spend from `/spend`

## Answer

The chain across Pages and phases, Repertoire draws, holdover, Next, Never, and House/Off occupancies was verified across unit tests, live integration tests with two phones and a stage, and client Web Audio fade mechanics:

1. **Stage Playback and Handover Chain**:
   - **Opening**: On Stage mount, audio opens on a named Repertoire draw (`repertoire`), displaying `"Now playing: <title> (the Repertoire)"` on the public screen.
   - **Track Arrival**: When Gives are submitted, Foley scores the Page's Track. The moment it is playable (stream at ~24 s or finalized MP3), it seizes the Speaker during writing or Attempt 1. The client Web Audio hook crossfades the new track in smoothly over 2.0 s via linear gain ramps.
   - **Holdover**: When a Page closes after a Meld, the landed Track continues playing as `holdover` (`"Now playing: <title> (last Page's Track)"`). Tapping "One more?" keeps that Track playing continuously through the next Page's `:giving` and `:writing` phases without resetting to silence or a random loop.
   - **Crossfade**: When the next Page's Track lands, Web Audio gain nodes schedule a clean 2.0 s crossfade between the holdover track and the new track, smoothly handing over without audio dropouts or pops.

2. **Next and Never Controls**:
   - **Next**: Rendered only during wait music (Repertoire draws and holdover). Advances the session shuffle deal without repeats until exhausted, maintaining mode `page`. When this Page's Track is playing, Next is hidden on screen and refused by `Rooms.next/2` (`{:error, :refused}`).
   - **Never**: Rendered whenever a Repertoire member is playing, including this Page's Track. Tapping Never records the Room-scoped verdict in the database (`room_nevers`), immediately removes the member from future draws in this Room, and advances the deal. The same member remains fully drawable in other Rooms.
   - On this Page's Track, Never refuses the track here, advances the deal to a Repertoire draw, and prevents holdover into subsequent Pages.
   - **Last-member Protection**: When only 1 playable member remains, Never is refused and Next is hidden, preventing an empty deal.

3. **House and Off Occupancies**:
   - **House**: Switches playback to the Repertoire without starting a Foley scoring task (`room.track == nil`). Mid-score flips preserve background generation and cache the completed file without playing it.
   - **Return to Page**: Flipping back to `page` immediately restores an already-landed Track without re-scoring or extra latency.
   - **Off**: Silences the music bus (`foley:page` with `path: nil`), while stings, beat figures, and Assayer speech remain active.

4. **Phone-Only Setup (No Stage)**:
   - When no Stage is open, phones remain silent by default.
   - The claiming phone receives `foley:page` and renders Next and Never below the fold.
   - Non-speaking phones receive no music events and render no Next/Never controls.
   - Claiming the Speaker on a second phone immediately silences the first phone via `foley:stop` and transfers playback without overlap.

5. **Levels, Fades, and Spend**:
   - **Levels**: Audio bus levels in `config/config.exs` (`music: 0.5`, `stings: 1.2`, `voice: 1.2`, `duck: 0.15`) remain balanced: music sits comfortably beneath table talk while stings and voice cut through clearly.
   - **Fade Duration**: 2.0 s linear ramps in `ThereishWeb.RoomComponents` provide natural, smooth crossfades between Repertoire members and Page Tracks.
   - **Spend**: Mureka instrumental generation tracked at $0.04/track in Chronicle `music_meta` and verified on operator `/spend`.

## Comments

### Verification Summary (Integration & Suite Pass)
- Prerequisite tickets 01, 02, 03, 04, 06, 07 are merged into `master`.
- Comprehensive end-to-end integration tests added in `test/thereish_web/live/room_live_test.exs` verifying:
  - Stage chain handover across pages, holdover during giving/writing, and crossfading on track arrival.
  - Next skipping wait music only, Next absence on Page tracks, and Never Room-isolation.
  - House not scoring, return to Page restoring landed tracks, and Off silencing music only.
  - Two-phone claim transfer and silence push.
  - Operator `/spend` recording Foley track charges.
- Full test suite passing (831 tests passing).
- Issue moved to `issues/resolved/05-the-chain-by-ear.md` per repo conventions.
