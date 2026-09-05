# 05: The Assayer speaks

**What to build:** When the voice switch is on and the Room has a speaker, every Verdict is spoken: the band word, then the quip, in the Assayer's one voice, landing as the quip appears on the speaking screen. A Precedent hit's fresh quip is spoken too. Audio that is late plays when it arrives; audio that never comes changes nothing about the reveal; audio for an Attempt that has passed is dropped. The Verdict records what spoke it and what it cost. Spec section: Voice at play time.

**Blocked by:** 02 (One speaker, the beat and the stings), 04 (The bake-off); `.scratch/at-the-table/issues/04` (the band names, `assay-3`).

**Status:** ready-for-agent

- [ ] When a Verdict arrives — from the Assayer or as a Precedent hit — and voice is on and a speaker exists, the Room starts a supervised speak task with "<band word>. <quip>"
- [ ] The Room holds the bytes for the current Attempt; a controller route under the Room's Code serves them for that Attempt and answers 404 for any other; the Room broadcasts `voice_ready` for the Attempt
- [ ] The speaking client receives `foley:voice`, fetches the bytes, and plays them when the quip element is on screen — immediately if it already is; the music bus ducks while it plays
- [ ] A speak that fails, or arrives after the next Attempt has started, is dropped and logged; the beat, the reveal and the rules are untouched in every case
- [ ] The voice switch on the speaking screen turns this on and off and persists (from 02)
- [ ] `voice_meta` on the Verdict (provider, voice, cost, latency) and the spend page's Foley line
- [ ] Room tests with the Fake for the ready broadcast, the per-Attempt route, the late and failing cases; a LiveView test for the push reaching only the speaking view
- [ ] Verified on the deployment: the spoken line lands with the text on the laptop and on a Pixel
