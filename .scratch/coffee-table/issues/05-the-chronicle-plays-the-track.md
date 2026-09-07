# 05: The Chronicle plays the Track

**What to build:** An evening's songs can be found from the record. A Page's entry in the book, when its music record carries a path, names the Track and plays it through an audio element pointing at the media route that already serves Tracks; a Page without one shows no music line at all rather than an empty player. The Markdown export writes a `Track:` line with the title when there is one, and its reader accepts the line so old and new exports both round-trip. Pages from before this spec have no path and change nothing. Spec section: The Chronicle plays the Track.

**Blocked by:** 04 (The Scribe titles the Track).

**Status:** ready-for-agent

- [ ] A closed Page whose `music_meta` has a path shows its title and a player in the book; a Page without a path shows no music line; a Page under Off or with a failed score shows none
- [ ] The Markdown export writes `Track: <title>` for a Page with one and nothing otherwise; the reader accepts the line; an export from before this ticket still parses
- [ ] Chronicle LiveView tests for both renderings; Chronicle tests for the export line both ways
