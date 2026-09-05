# 03: Rooms are created by Code, never conjured

**What to build:** A player opens the game and sees a front page: a box for a Code, a New Room button, and one-tap rejoin links for every Room this phone already holds a Seat in. New Room asks how many players, two to six, default two, and opens a Room known by a four-letter word drawn from the dictionary, shown large for reading aloud. Everyone, creator included, types the Code and then a name. A Code that is not a Room is told plainly; nothing is created by a typo. COUCH still opens the couch.

**Blocked by:** None (can start immediately).

**Status:** ready-for-human (built and green; the last box is Jacob's to tick on the deployment)

This ticket stands alone because the current rules already play at N: a Room of four can be created and played with today's pairwise grading, which is how it is demoed before 02 lands.

**Rooms are created, never conjured.** The Room interface gains a create call taking a player count and the creating phone's device token; it names the Room, inserts it, starts its process and returns the Code. Opening a Code starts the Room's process if the Room exists and is a 404 if it does not; the path that created a Room on first visit goes away, and the configured default seat count survives only as the form's default. The Room process is started for a Room that exists; the test fixture creates before it starts.

**Codes.** The Code is the Room's slug: stored lowercase, shown uppercase, accepted in any case; the slug format is unchanged, so existing slugs are valid Codes. A random Code is a four-letter word from the ENABLE list less the profanity list, drawn again on collision; real words are read aloud, so no look-alike-letter rule. The Scribe's naming comes in 04; this ticket draws at random.

**The web.** The bare URL becomes the front page. `/new` is the New Room page; it creates and lands in the Room. The Room, its stage, its Chronicle and its exports stay at their Code-addressed paths; the bare stage and Chronicle routes that opened the couch go. While the Room is short of Seats, the Room page shows the Code and the join URL. Player-facing copy says Room and Code — never game, lobby, join code, PIN.

**One new query.** The Rooms in which a device token holds a Seat, with the Seat, newest first. The front page uses it for rejoin links; 04 reuses it for digests.

- [x] The front page shows a Code box, a New Room button, and a rejoin link for each Room this phone holds a Seat in
- [x] New Room takes a player count from two to six (default two), creates a Room with a random four-letter dictionary word as its Code, and lands in it with the Code shown large
- [x] The Code is accepted in any case and shown uppercase; existing slugs open as before
- [x] A Code that is not a Room is a 404, and no Room is created by visiting a path
- [x] The Room page shows the Code and the join URL while Seats are open; the roster and open-seat count work at four
- [x] A fifth phone at a Room of four is turned away with the existing message
- [x] A rejoin link lands a phone in its own Seat, and reopening the URL after any interval still does
- [x] A random Code is never profane, never a taken Code, and always a real four-letter word
- [x] LiveView tests drive the front page, New Room, four joins by Code, and the 404; Room tests cover create, open-by-Code and the device-to-Rooms query
- [ ] Verified on the real deployment: a Room of four created from a phone and joined by three others

Deployed 2026-09-04. On meld.stephens.page: New Room for four opened FLAK, the
Room page shows the Code large with its own URL, one Seat joined, an unknown
Code is a 404 and the old bare `/stage` is gone. The front page lists FLAK and
COUCH as this browser's Rooms, so the Seats that predate the door still find
their way back. FLAK is left open for the three phones the last box wants.
