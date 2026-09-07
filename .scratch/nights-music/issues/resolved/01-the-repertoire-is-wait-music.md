# 01: The Repertoire is wait music

**What to build:** Wait music is the Repertoire, not five loops that always start the same. An unsettled Room (no kept Track in this Chronicle) shuffles the five shipped loops plus every kept Track in the game. A settled Room shuffles this Chronicle’s Tracks plus the five. The pick plays from giving onward when this night has no Track yet, and “Now playing” names it as a Repertoire draw. House does not start a score and does not cancel one in flight; Off starts none. “One more?” may still reset until ticket 02. Spec sections: The Repertoire; House and Off; Snapshot and pushes.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] A brand-new Room’s wait music is a shuffle of the five shipped loops and every kept Track; it is not always the same shipped loop
- [x] Once this Room’s Chronicle holds a Track, wait music is a shuffle of that Room’s Tracks plus the five; a stranger’s Track is no longer required in the draw
- [x] The five shipped loops remain eligible in both draws
- [x] Wait music plays during giving and writing when no Page Track is on the Speaker; `foley:page` carries the path, title, and kind Repertoire
- [x] House starts no score; an in-flight or already-landed score finishes and is kept, not played; switching back to Written for this Page plays it if ready or starts a score if none was started
- [x] Off starts no score and silences the music bus
- [x] Room tests for unsettled vs settled draw and for House/Off scoring; LiveView tests for the push and “Now playing” on the speaking view during giving
