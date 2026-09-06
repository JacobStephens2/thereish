# 08: The Room starts when everyone is here

**What to build:** A Room that takes whoever arrives instead of a player count chosen at creation. The Page starts when the Seats present declare themselves complete, and the count of Seats at that moment is the count the Page is played with.

**Blocked by:** tickets 01–05 of `.scratch/group-play/spec.md`, which keeps the player count chosen on the New Room page.

**Status:** resolved

Filed 2026-09-04 during the group-play grilling as a follow-up, not part of the first slice. The chosen-count model is what the code has and what the first evening with friends needs; this is the fix for the evening where a fourth person cancels and a Room of four is stuck waiting.

**What it changes in the model.** Phase is derived from the state, and today "waiting" means "fewer Seats than the count". Since ADR-0011 the start gesture already exists — a Page begins when the last Give lands — so the count-free Room needs "the Gives in hand are everyone's" to be sayable (a tap after the last Give, or a Give from a Seat that declares itself last), a rule for a Seat that joins after the start (give and bridge this Attempt, or wait for the next Page), and an answer for a Seat that leaves mid-Page and never commits — which is the same problem the two-Seat Room has when a phone goes in a pocket, and is not solved by this ticket alone.

## Decisions

1. **Starting the Page**: An "Everyone is here" / "Start Page" button appears once at least 2 Gives are submitted (`gives_in >= 2`). Any seated player can tap it to trigger the Author with the Gives in hand. If a Room reaches the maximum seat cap and all seats give, or if a legacy 2-seat Room has both gives in, it auto-starts as before.
2. **Late Joiners**: A player who joins after the Page has started writing/playing watches the current Page in progress (viewing Bookends, Beat, Reveal, and Chronicle) with a "You joined mid-Page. Watching this Page — you'll play on the next one!" note, and automatically enters play on the next Page when "One more?" is tapped.
3. **Mid-Page Abandonment**: Kept out of scope for ticket 08 as noted in the ticket (an existing two-player problem to be addressed separately).
4. **Agreed Seams**:
   - `MeaningGame.Game` (pure reducer rules)
   - `MeaningGame.Rooms` (process interface)
   - `MeaningGameWeb.NewRoomLive` & `MeaningGameWeb.RoomLive` (LiveViews end-to-end)

- [x] The New Room page needs no player count
- [x] A Page starts when the Seats present say their Gives are all in, rather than on the Room filling
- [x] A late Seat has a defined place in the current Attempt
- [ ] A Seat that never commits has a defined effect on the Attempt *(deferred: out of scope for ticket 08, existing 2-player problem)*

## Answer

Implemented across the three agreed seams:
1. `MeaningGame.Game`:
   - Added `page_seat_ids` to `Game` state to track seats participating in the active Page.
   - Added `{:start_page, %{seat_id: seat_id}}` event requiring `>= 2` gives; sets `page_seat_ids = Map.keys(state.gives)`.
   - Updated `author_request`, `assay`, `gives_for_assay`, `written_bridges`, `chronicle`, `chronicle_verdict`, `resolve_overrule_unanimity`, and `phase` to evaluate over `page_seats`.
   - Late seats (`late?: true`) watch the current page, and cannot commit bridges or vote on overrules.
   - `page_seat_ids` resets on `next_page` ("One more?"), automatically admitting late seats into the next Page.
2. `MeaningGame.Rooms` & `Rooms.Server`:
   - Added `Rooms.create/1` creating rooms at seat cap (`Steward.seat_cap() = 6`).
   - Added `Rooms.start_page/2` delegating to Server `{:start_page, seat_id}`.
3. `MeaningGameWeb`:
   - `NewRoomLive`: Removed player count selection; form submit creates room at seat cap.
   - `RoomLive` & `RoomComponents`: Added "Start Page" button when `gives_in >= 2`, added `[data-role=late-seat]` notice and roster `(watching)` tag for late joiners, guarded bridge and overrule participation for late seats, and allowed late seats to tap "One more?".
