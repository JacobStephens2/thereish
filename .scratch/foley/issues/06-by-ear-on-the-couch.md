# 06: By ear, on the couch

**What to build:** Nothing — this is the listening. Foley is verified where no test can hear: on the couch, with a stage and without one. The findings go here, and any level, fade or ducking change they call for goes into configuration or the assets, not into a rewrite.

**Blocked by:** 03 (A track for the Page, from the Gives), 05 (The Assayer speaks).

**Status:** ready-for-human

- [ ] With a stage: one tap for sound; the house loop under bridging; the beat figure through the beat; the right sting for each band met tonight; the ending for a Meld and for an unmelded Page; a Give's track fading in mid-Page; the spoken band and quip landing with the text; music ducked under all three
- [ ] Without a stage: one phone claims the speaker and plays everything; a second phone claims it and the first goes silent; the switches follow the speaker
- [ ] The house-loop-only switch on a track nobody likes; the voice switch off and on
- [ ] Reduced-motion on a phone means no sound by default
- [ ] Levels: the loop sits under talk; stings and voice are heard across a room from a laptop
- [ ] What was heard is recorded here, with any level or fade changes made and the spend for the evening from `/spend`

## Comments

### Preparation & verification readiness (Agent check)
- Prerequisites 01 through 05 are fully merged and automated tests are passing across the test suite (588 tests passing).
- Resolved issue `04-the-bake-off.md` moved to `resolved/` per issue tracker conventions.
- Bug fixed in `MeaningGameWeb.RoomComponents.Foley`: guarded `updated()` and `destroyed()` hook lifecycle methods when `prefers-reduced-motion` is active to prevent uncaught TypeError exceptions on re-render.
- Added unit tests for `foley_switches` and `foley_hook` in `MeaningGameWeb.RoomComponentsTest`.
- All code is formatted and compiles cleanly without warnings.
- The ticket remains `Status: ready-for-human` for the physical listening session on the couch with laptop and phones on deployment.

