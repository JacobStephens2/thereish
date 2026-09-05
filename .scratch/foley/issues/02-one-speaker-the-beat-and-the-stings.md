# 02: One speaker, the beat and the stings

**What to build:** The first sound the Room hears. A stage that opens claims the Room's speaker and shows one "Tap for sound"; after the tap the house loop plays under bridging, the beat figure rises through the beat, the band's sting lands with the number, and an ending plays when the Page closes. Without a stage, a phone claims the speaker by tapping its icon, and claiming it silences whoever had it. Speaker, voice and house-loop-only are Room facts that survive a reload and a restart; phones are silent by default. Spec sections: The speaker and the switches, The client.

**Blocked by:** 01 (The forge).

**Status:** ready-for-agent

- [ ] The Room row gains the speaker (a device token or none), voice on/off (default off) and house-loop-only (default off); the Room's interface gains claim and release of the speaker and setters for both switches, each broadcasting
- [ ] The snapshot takes the viewer's device token beside its Seat and answers `speaker?`, `speaker_claimed?` and the two switches; device tokens still never leave the Room
- [ ] A mounting stage claims the speaker for its device; a leaving stage releases it; a phone claiming it takes it from whoever had it, stage included; a claim from the current speaker is a no-op
- [ ] One colocated hook on the Room page and the stage, active only while `speaker?`: a Web Audio graph with a music bus, a stings bus and a voice bus; the music bus ducks under stings, the beat and the voice; every file is MP3; the reduced-motion preference means no sound by default
- [ ] The stage shows "Tap for sound" until its audio context is running, on every fresh load; on a phone the speaker-icon tap is the gesture
- [ ] The speaking view alone receives `foley:page` (house loop), `foley:beat` on entering the assay, `foley:sting` with the band on the reveal, `foley:ending` with the kind on the close, and `foley:stop`; non-speaking views receive none
- [ ] The speaker icon renders on every phone and shows who has it; the voice and house-loop-only switches render only on the speaking view (voice does nothing yet — 05)
- [ ] Room tests for the facts, the claim rule and persistence across a restart; LiveView tests with two phones and a stage assert the pushes move with the claim
- [ ] Verified on the deployment: a stage plays the loop, the beat, a sting and an ending; a phone claims the speaker and the stage goes quiet
