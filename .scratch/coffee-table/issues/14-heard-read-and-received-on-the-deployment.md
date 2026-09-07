# 14: Heard, read and received, on the deployment

**What to build:** Nothing — this is the checking, where no test can hear or read a mailbox. A Page with a Stage and one without, on the deployment, after everything above has landed.

**Blocked by:** 01 through 13.

**Status:** ready-for-human

- [ ] With a Stage: the music control from a phone changes what the laptop plays; Off leaves the stings and voice; a different loop on each of three Pages, named on the "Now playing" line; the title arriving before the Track and the line changing once; every commit sounding from the Stage and phones staying quiet (ticket 15); a Meld's cue with the Track fading beneath, and a deep meld's if one happens; "Bookends" and "Your bridge" on both screens; the quip on the Code card and the Stage header
- [ ] Without a Stage: each phone ticks its own commit and the Speaker phone relays none; the control on a non-Speaker phone changes the Speaker's sound
- [ ] Levels judged with the Track and the voice in the mix; any change made in configuration and recorded, with the numbers, on `.scratch/foley/issues/06`
- [ ] The book plays the evening's Tracks by title; the export carries them; the spend page says how many Pages were in play while one was, and nothing after
- [ ] The first notice arrived for a new device's Room and none for a returning one; the first DMARC aggregate report has arrived; production access granted or its date noted
- [ ] What was heard, read and received is recorded here with the evening's spend from `/spend`

## Comments

### Verification readiness (Agent check)
- Prerequisites 01 through 13 are fully completed, merged to `master`, and deployed to production (`https://thereish.app/check` returns 200 OK).
- The full test suite passes with 0 failures: 745 passed, 11 excluded.
- Live deployment checks:
  - `https://thereish.app/check` connects over WebSocket with wake lock and prose gate active.
  - Umami analytics script (`https://analytics.stephens.page/script.js`, website ID `2787e006-03df-4ad6-9451-9edf74553410`) is present in the layout on production.
  - `/spend` renders cleanly; "N Pages in play" sentence is correctly omitted when zero pages are active.
  - SES production access was granted on 2026-09-07, DKIM and custom MAIL FROM are verified, and initial notices for new-device rooms (`odyl`, `oxen`) were received at `jacob@stephens.page`.
  - Chronicle track playback and Markdown export round-tripping (`Track: <title>`) are deployed and ready for tonight's recorded tracks.
- The ticket remains `Status: ready-for-human` for the physical playtest session on deployment to verify the checklist items above.

