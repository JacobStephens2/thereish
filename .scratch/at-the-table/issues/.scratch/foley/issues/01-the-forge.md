# 01: The forge

**What to build:** The sounds the game ships are made once and chosen by ear. A mix task takes a fixed set of briefs — the beat figure (2.5 s, rising, resolving on the downbeat), six stings (miss, adjacent, close, almost, meld, deep meld), two endings (an arrival, a settle), and the house loop — and for each asks Foley for several candidates: ElevenLabs sound generation for the effects, Mureka for the house loop. Gemini 3.8 Flash listens to the candidates against each brief and ranks them with a sentence each; the task prints the ranking and the file paths and stops. Jacob listens, writes the chosen index per brief into a manifest, and a second run copies the winners into the game's static audio directory under fixed names, which are committed. This builds the `foley` role and three of its jobs. Spec sections: The Steward widens, Assets made once: the forge.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The Steward behaviour gains `forge` (N candidate effects for a brief) and `rank` (an ordering of clips against a brief); the Fake answers fixture MP3s and a fixed ordering
- [ ] The `foley` role exists in configuration with `effects` (ElevenLabs sound generation, `eleven_text_to_sound_v2`, MP3 44.1 kHz, `loop` for the house loop if made there), `music` (Mureka instrumental, `n: 1`, model `auto`, a three-minute deadline) and `ear` (Gemini 3.8 Flash, audio in, JSON out) jobs; keys from `MUREKA_API_KEY` and `ELEVENLABS_API_KEY` through runtime configuration; the price table gains both
- [ ] An ElevenLabs provider builds a sound-generation request and parses a recorded answer, a recorded error and the character-cost header
- [ ] A Mureka provider starts a job, polls until succeeded, failed or the deadline, and downloads the chosen URL — driven in tests from recorded `preparing → running → succeeded` and `→ failed` sequences and an expired deadline
- [ ] The Gemini provider sends N clips as inline audio parts with a brief and parses a ranking, rejecting an ordering that names an index it was not given
- [ ] `mix foley.forge` renders four candidates per brief, ranks them, prints ranking, reasons and paths; given a manifest it copies winners to fixed names in the static audio directory; tested with the Fake
- [ ] Run under `va bash`; Jacob has chosen every asset; the ten files are committed; the spend printed is recorded here
