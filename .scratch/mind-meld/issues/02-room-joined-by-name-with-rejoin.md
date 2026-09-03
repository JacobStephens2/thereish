# 02: A Room two phones join by name, and rejoin after a lock

**What to build:** My wife opens the URL on her Pixel, types her name, and is in the Room. Jacob does the same on his phone. The laptop opens the same Room as the stage and shows both names. My wife's phone locks, the socket dies, she unlocks, and she is back in her own Seat with the Room exactly as she left it. She closes the tab, reopens the URL, and is still herself.

This ticket is ADR-0002's kill criterion. If Phoenix cannot reach this inside three evenings, the stack becomes TypeScript and Socket.IO. Build it before Pages, before the Author, before the Chronicle.

**Blocked by:** 01.

**Status:** ready-for-human

- [x] Joining a Room takes a name and nothing else. No account, no password, no email
- [x] A Seat carries a stable id and a device token kept in the browser; reopening the URL restores that Seat
- [x] Seats never expire, and rejoining after any interval lands in the same Seat
- [x] The Room is a supervised process holding a list of Seats, N of them, two by default. Nowhere in the code is a pair hardcoded
- [x] The Room's interface includes a full-snapshot request, and reconnect is implemented as snapshot rather than as replay
- [x] Phone views resync on `visibilitychange`, so waking from lock needs no reload
- [x] The stage view holds a Screen Wake Lock while a Room is active
- [x] The stage lists who has joined; phones show the same roster
- [x] Room state survives a client disconnect, and the Room process is supervised so a crash restarts clean
- [x] Tests through the Room's interface: two Seats join, a third joins, a Seat disconnects and snapshots back to the identical view, a Seat rejoins by device token
- [x] A LiveView test drives two phone views plus a stage through join and roster display
- [ ] Verified on the real deployment with two actual phones, not only in tests

## Comments

**2026-09-03 — built, and waiting on two phones.** `/` is the couch's Room on a
phone, `/stage` is the same Room on the laptop, and the check page moved to
`/check`. `/r/<slug>` and `/r/<slug>/stage` open any other Room, which is what
the tests use so each one gets a Room to itself.

Shape: `MeaningGame.Game` is the pure reducer (`init`/`apply`/`view`) and holds
the seat-limit rule; `MeaningGame.Rooms` is the Room's whole interface — join,
rejoin, snapshot, subscribe — over one supervised process per Room, found by
slug in a registry. Postgres holds `rooms` and `seats`, so a crashed Room
restarts with its Seats and "any interval" really means any interval.

Three calls worth naming:

**The device token is the session cookie, not `localStorage`.** The dead render
has to already know who is asking; a token fetched by JavaScript arrives a round
trip late, so every returning phone would flash a name form it does not need.
The cookie's `max_age` is now a decade, because Seats never expire and the
shortcut back to one should not either.

**A name is the identity inside a Room; the device token is the shortcut.** If a
browser arrives with no token but types a name that is already seated, it claims
that Seat rather than making a second one — which is what the `citext` migration
from ticket 01 was for. Without it, a cleared cookie splits my wife's Chronicle
between two Maras. A phone that already holds a Seat keeps it, so typing
someone else's name cannot take theirs. A Seat holds a *list* of device tokens,
so claiming it from a second browser adds that browser rather than evicting the
first — my wife reaching her Seat from the iPad must not knock her Pixel out of
it.

**Live grading is not the only reason to be N-seat.** `seat_limit` is a column
on `rooms`, defaulted from `config :meaning_game, :seats_per_room, 2`. That
config line is the only place the number two appears.

Two phone views plus a stage are driven through `Phoenix.LiveViewTest`, and the
whole thing was also driven in a real Chrome: join, live roster push between two
origins standing in for two devices, and the same Seat after a reload.

The one thing tests cannot see is the Screen Wake Lock actually being held —
Chrome refuses `wakeLock.request` in a hidden tab, which is exactly the guard
the hook has. That, and the two-phone check, is what is left for Jacob.

**What the review caught.** The first cut of the name reclaim *moved* the device
token onto the claiming browser, so a second browser typing "Mara" would
silently evict my wife's Pixel from her own Seat — the exact thing this ticket
exists to prevent. Hence the list of tokens, and a test for the browser that was
already there. Also: `MeaningGame.Game` was exporting five functions when the
spec asks for three, and the two extra were reachable only from tests, so they
are private now and the tests go through `view/2` like everything else. A slug
no Room could have used to 500; it is a 404. `Game` is in `CONTEXT.md` now,
because it was a concept the code used and the glossary did not have.
