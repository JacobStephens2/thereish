# 07: Couples highlighted on the meld map

**What to build:** A meld map for a Room that has a stage: every pair of Seats graded alongside the one Verdict, drawn as who melded with whom, with the reveal knowing which Seats are a couple. Each couple's own pair is shown as the score they care about, and a cross-couple Meld ("Jacob and Esme think alike") is presented as the surprise it is. The Page's Verdict, Meld, carry-forward and Precedent stay ADR-0010's; the pair grades are a display, not a ruling.

**Blocked by:** tickets 01–05 of `.scratch/group-play/spec.md`, which builds the N-Seat reveal this decorates — and a stage to draw the map on, since it is a report on a phone (ADR-0010).

**Status:** resolved

Filed 2026-09-04 during the group-play grilling as an idea for later. It is the cheaper cousin of 06: it keeps the one set of rules and adds a reading of it, so it can be tried before committing to a team mode. It brings back N choose 2 grading requests per Attempt, for display only, which is the cost ADR-0010 declined to pay for a phone.

**What it changes in the model.** Something has to say which Seats belong together. The smallest version is a pairing declared at join ("I'm with Mara"), kept on the Seat and shown in the roster. Whether that is a glossary term or just a display fact depends on whether any rule ever reads it; as filed, none does.

- [x] A Seat can be marked as paired with another Seat in the Room
- [x] The reveal puts each player's own couple-pair first and marks cross-couple Melds
- [x] The roster shows the couples

## Answer

**Resolved 2026-09-05.**
- Added `partner_id` to `seats` table via migration `20260907110000_add_partner_id_to_seats.exs`, supported in `Seat` schema, `Store.insert_seat/5`, and `Store.pair_seats/3`.
- In `MeaningGame.Game`, seats carry `partner_id`, updated on `:seat_joined` or `:seats_paired`.
- `MeaningGame.Rooms.join/4` and `MeaningGame.Rooms.pair_seats/3` expose pairing on the Room process.
- The roster displays couples with `(with PartnerName)` using `data-role="partner"` and `data-couple="true"`.
- When an Attempt is assayed, `MeaningGame.Rooms.Server` runs parallel pair grading tasks for $N > 2$ seats alongside the main verdict (for 2-seat rooms, the main verdict is reused directly without redundant calls).
- The pure reducer `Game.pairs_view/3` formats and sorts pair views:
  - The viewing player's own couple-pair is sorted first.
  - Melds between distinct couples are flagged with `cross_couple_meld?: true` and a surprise alert (`"Jacob and Ada think alike"`).
- On phones, the player's couple closeness is displayed prominently above the table verdict, and cross-couple meld alerts are rendered.
- On the Stage, a dedicated Meld Map grid is rendered displaying all pairs, couple badges, meld badges, and cross-couple meld highlights.
- ADR-0010 remains completely preserved: one headline verdict per attempt, headline closeness, carry-forward furthest pair, and precedent caching are untouched.
