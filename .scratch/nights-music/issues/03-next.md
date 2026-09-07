# 03: Next

**What to build:** Wait music can be skipped without a verdict. Next advances a session shuffle of the eligible Repertoire pool (ticket 01’s draw): deal, advance, no repeat until the deal is exhausted, then reshuffle, never the thing now playing. It is offered on a Repertoire draw and on holdover, hidden while this Page’s own Track is playing, and only on the speaking screen. Mode stays Written for this Page, so an in-flight Track still seizes the Speaker when it lands. Spec sections: Next and Never.

**Blocked by:** 01 (The Repertoire is wait music), 02 (Holdover — the night is a chain).

**Status:** ready-for-agent

- [ ] Next on a Repertoire draw changes the song to another eligible member; the previous one can return only after the deal is exhausted
- [ ] Next on holdover leaves last Page’s Track and plays a shuffle from the same pool the opening would use; mode stays `page`
- [ ] Next is not shown (and is a no-op) while this Page’s Track is on the Speaker
- [ ] Next is not shown when only one playable member remains
- [ ] Next renders only on the speaking screen, below the fold with the music control
- [ ] Room tests for the deal, for holdover skip, and for refusal on this Page’s Track; LiveView tests for visibility on speaker vs not and for the pushed path after a tap
