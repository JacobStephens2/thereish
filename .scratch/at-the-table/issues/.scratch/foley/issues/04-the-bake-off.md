# 04: The bake-off

**What to build:** The Assayer's voice is chosen by ear. A mix task reads a Room's Chronicle for its last five quips (Room DUST by default), speaks each through ElevenLabs v3 Conversational and through Hume Octave 2 with one chosen voice each, and writes the files blind — `01-a`, `01-b`, … — with a sealed key. Jacob and his wife listen; the letter they prefer names the provider, which goes into the `voice` job's configuration, with the other kept as a one-line alternative. Both providers and the `speak` callback are built here. Spec sections: The Steward widens (voice), The bake-off; research: `docs/research/tts-for-the-assayers-voice.md`.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The Steward gains `speak` (one line as audio bytes with format and meta); the Fake answers a fixture MP3, an error, or after a delay
- [ ] An ElevenLabs text-to-speech provider (v3 Conversational, MP3, audio tags permitted in the line) and a Hume Octave 2 provider each build a request and parse a recorded answer and a recorded error, reading cost where the response gives it; keys from `ELEVENLABS_API_KEY`, `HUME_API_KEY` and `HUME_SECRET_KEY` through runtime configuration; the price table gains per-character prices
- [ ] The `voice` job is configured with a provider, a voice id and a 3 s timeout; either provider is one config line
- [ ] `mix foley.bakeoff` takes a Room's Code and a count, renders each quip through both providers, writes paired files with blind letters and a key file, prints the directory; tested with the Fake
- [ ] Run under `va bash` on the Mac; Jacob and his wife have listened; the decision, both voice ids and the unsealed key are recorded here; the winner is in configuration
