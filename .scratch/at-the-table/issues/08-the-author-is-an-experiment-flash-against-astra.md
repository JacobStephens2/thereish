# 08: The Author is an experiment: Flash against Astra

**What to build:** Each Page's Bookends are written by one of two Authors — Gemini 3.8 Flash or GPT-6 Astra, both at low effort — assigned blind per Page and alternating within a Room, and the Chronicle records which and how the Page went: Attempts to meld, whether it melded, the closing band, and one tap per Seat at the close saying whether the Bookends were flat, fine or great. The readout is streaks and preferences, as the harness already does. Spec sections: The Steward (The Author's model is an experiment, A third provider), The Game (`bookends_tapped`), The Chronicle.

**Blocked by:** 02 (The Page is written at the table).

**Status:** ready-for-human

- [x] An OpenAI provider satisfies the provider behaviour — JSON-schema structured output, reasoning effort, the key from `OPENAI_API_KEY` through runtime configuration, cost from the price table, which gains `gpt-6-astra` — tested against recorded answers and a recorded refusal
- [x] The `author` role has `flash` and `astra` jobs with the same budgets; the Steward writes with the job the Page's arm names
- [x] The `author_model` experiment assigns an arm per Page, alternating within a Room, recorded blind in the experiment tables as `bait_against_plain` was; the unblinding path still works
- [x] At the close each Seat may tap flat / fine / great once (replaceable); the rules owe a `bookends_tap` effect carrying the Bookends, Gives, author meta and arm; the Chronicle records it
- [x] The experiment outcome per Page carries the arc (Attempts, melded, closing band) and the taps; the qualitative readout covers `author_model`
- [x] Rules tests for the tap; Room tests for alternating assignment and the recorded outcome; Steward tests for the provider and job selection; one tagged live smoke test per provider
- [ ] Deployed; two Pages played, one per arm, and both recorded
