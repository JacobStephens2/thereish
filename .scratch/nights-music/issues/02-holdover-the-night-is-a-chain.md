# 02: Holdover — the night is a chain

**What to build:** A landed Track does not die at “One more?”. It keeps playing through close, giving, and writing until the next Page’s Track is playable, then that Track crossfades in — including during writing, not waiting for bridging. A score for a Page that has already moved on is still dropped and must not overwrite holdover. Spec sections: The night as a chain; Occupancy in the Room.

**Blocked by:** 01 (The Repertoire is wait music).

**Status:** ready-for-agent

- [ ] After a Page closes, the landed Track is still what the Speaker is playing; the snapshot kind is holdover and “Now playing” keeps that title
- [ ] Giving and writing for the next Page keep that Track; `foley:page` is not a fresh Repertoire draw and is not silence
- [ ] When the new Page’s Track is playable it seizes the Speaker in whatever phase the Room is in, including writing
- [ ] A `scored` result whose Page is not the current one is ignored and does not replace holdover
- [ ] If the previous Page never landed a Track, wait music is still a Repertoire draw from ticket 01
- [ ] Room tests cover holdover across `next_page` and a stale score; the old expectation that the Track is nil after `next_page` is gone. LiveView tests cover `foley:page` on giving/writing for holdover and for a Track that lands during writing
