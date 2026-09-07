# 07: A Meld is celebrated

**What to build:** A Meld ends with a celebration rather than a sting and silence. When a Page closes on a Meld, the meld victory cue plays; when it closes on a deep meld — the same word written twice — the brighter cue plays; the Page's Track or loop fades out beneath the cue over about two seconds instead of stopping at once. An unmelded Page keeps its settle. The cues are not personalised: a cue written for the Page would arrive a minute after the moment it was for. The old "arrival" ending is retired from play. Spec section: Pushed events.

**Blocked by:** 01 (The forge, again: seven new sounds).

**Status:** resolved

- [x] `foley:ending` carries `meld`, `deep_meld` or `unmelded`, read from the closing Verdict's band and the close's reason
- [x] `meld` and `deep_meld` play their cue on the stings bus and fade the music bus out beneath it over about two seconds; `unmelded` plays the settle as today
- [x] The meld cue's existing 1.8-second delay after the sting is kept or re-tuned by ear, and the value is configuration beside the levels
- [x] LiveView tests for all three kinds; a components test for the hook's handling of the three
