# 04: The Scribe titles the Track

**What to build:** Every Track has a title, so "the summer camp song" is something the table can say and later ask for. The Steward behaviour gains a title callback; the Scribe gains a `title` job — Gemini 3.8 Flash at low, a one-field schema, a timeout and deadline in the naming job's class — asked for a title of at most five words for an instrumental written from these settings. The gate: one to five words of letters, digits, spaces, hyphens and apostrophes, at most 40 characters, no quotes; one repair, then the deterministic fallback — the Gives trimmed, title-cased, joined with " · " and cut at 40. The title task starts when the Author starts, beside the score task, so the title is ready a minute before the Track and the "Now playing" line changes once. The track cache keeps the title so the same Gives bring back the same song by name; the Track and the Page's music record carry title and path, which is what lets the Chronicle play it (05). A title for a Page that has moved on is dropped like a late Track. Spec section: The Scribe titles the Track.

**Blocked by:** 03 (A loop for every Page, by name).

**Status:** resolved

- [x] The Steward behaviour gains `title_track`; the Fake answers a configured title, an error, or after a delay; the `scribe` role has a `title` job configured with model, effort, timeout and deadline
- [x] The gate rejects six words, 41 characters and a quoted title, asks once more with the reason, then falls back; the fallback is deterministic from the Gives and a test pins three examples including the 40-character cut
- [x] The title task starts beside the score task when a Page is written and only under `music: page`; its answer lands on the Room's Track (or waits for the Track) for the same Page and is dropped for a Page that moved on
- [x] The track cache row gains `title`; a hit answers file and title without a provider call; the Track map and `music_meta` carry `title` and `path`, and the title's cost rides in `music_meta` beside the Track's
- [x] `foley:page` for a landed Track carries the title and `kind: "track"`; the "Now playing" line names the title and says it was written for this Page
- [x] Steward tests for the job, the gate and the fallback; Room tests for the race (title before Track, Track before title, both late), the cache hit and the dropped title; a LiveView test for the line and the push
