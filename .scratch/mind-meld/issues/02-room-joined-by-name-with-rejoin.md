# 02: A Room two phones join by name, and rejoin after a lock

**What to build:** My wife opens the URL on her Pixel, types her name, and is in the Room. Jacob does the same on his phone. The laptop opens the same Room as the stage and shows both names. My wife's phone locks, the socket dies, she unlocks, and she is back in her own Seat with the Room exactly as she left it. She closes the tab, reopens the URL, and is still herself.

This ticket is ADR-0002's kill criterion. If Phoenix cannot reach this inside three evenings, the stack becomes TypeScript and Socket.IO. Build it before Pages, before the Author, before the Chronicle.

**Blocked by:** 01.

**Status:** ready-for-agent

- [ ] Joining a Room takes a name and nothing else. No account, no password, no email
- [ ] A Seat carries a stable id and a device token kept in the browser; reopening the URL restores that Seat
- [ ] Seats never expire, and rejoining after any interval lands in the same Seat
- [ ] The Room is a supervised process holding a list of Seats, N of them, two by default. Nowhere in the code is a pair hardcoded
- [ ] The Room's interface includes a full-snapshot request, and reconnect is implemented as snapshot rather than as replay
- [ ] Phone views resync on `visibilitychange`, so waking from lock needs no reload
- [ ] The stage view holds a Screen Wake Lock while a Room is active
- [ ] The stage lists who has joined; phones show the same roster
- [ ] Room state survives a client disconnect, and the Room process is supervised so a crash restarts clean
- [ ] Tests through the Room's interface: two Seats join, a third joins, a Seat disconnects and snapshots back to the identical view, a Seat rejoins by device token
- [ ] A LiveView test drives two phone views plus a stage through join and roster display
- [ ] Verified on the real deployment with two actual phones, not only in tests
