# 01: The forge, again: seven new sounds

**What to build:** The sounds the rest of this spec plays are made once and chosen by ear, exactly as the first ten were. The forge's brief set gains seven entries: four more house loops (Mureka, the same instrumental-under-conversation brief with a different mood each), two victory cues (ElevenLabs sound generation, eight to twelve seconds; meld an arrival that resolves, deep meld the same idea brighter and a beat longer), and one commit tick (under half a second, a soft click or wood tap, nothing tonal enough to fight the loop). The task renders several candidates per brief, Gemini's ear ranks them, Jacob listens and writes the manifest, a second run copies the winners under fixed names. Every loop — the existing one included — gets a short name in the manifest, and a small module lists the loops with their names and paths so the Room and the client agree on what each one is called. Spec section: Assets made once: the forge, again.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The brief set carries the seven new briefs with the kinds, durations and target names above; the manifest schema accepts a name per loop
- [ ] A loop-names module answers every loop in the manifest as name and path, the existing loop first, and a test proves the list matches the manifest
- [ ] `mix foley.forge` with the Fake writes candidates for every new brief, prints the ranking, and with a manifest copies the seven winners to their fixed names; the forge task test covers the new briefs
- [ ] Run under `va bash`; Jacob has chosen every asset; the seven files and the manifest are committed; the spend printed is recorded here
