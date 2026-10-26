---
status: accepted
---

# The Track is Lyria's

Foley scores one instrumental Track per Page from its Gives. From the start that was Mureka, at $0.04 a Track. On 2026-10-25 Mureka began answering every request with HTTP 429 ("You exceeded your current quota"), so every Page fell back to the house loop. Staying meant a ~$1,000 commitment, which this game doesn't justify. Decision (2026-10-26, ticket 277): the music job's provider is **Lyria 3.5 through the Gemini API** (`Thereish.Steward.Lyria`, `model: "lyria-3.5"`), on the same `GEMINI_API_KEY` the Assayer uses.

The bake-off is in `docs/research/music-providers-after-mureka.md`. Lyria 3.5 lands a ~3-minute MP3 in 25–45 s from one synchronous request, faster than Mureka's start, poll and download did. It costs $0.08 a Track. The extra $0.04 over Mureka is deliberate: the 30-second Lyria Clip matches Mureka's price, but the Room loops the Track for the whole Page, and a 30-second loop is a second Vamp, not a Track.

## Considered options

- **Lyria 3 Clip Preview ($0.04, ~8 s).** Rejected as the default: it is fixed at 30 seconds. It remains one word away (`model: "lyria-3-clip-preview"`) if speed ever matters more than repetition.
- **Lyria 3 Pro Preview ($0.08).** Same price and speed, and the only full-length model the ear heard no voice on in the bake-off. Not the default because it is a preview model and can be withdrawn. Also one word away.
- **Suno V5.5 through APIFRAME (~$0.11).** Works, and is implemented as `Thereish.Steward.Apiframe`, the one-line alternative. Not the default because Suno has no public API, so the route depends on a third-party wrapper, and it costs more per Track because the second of each job's two tracks is thrown away.
- **Eleven Music.** The fastest (~11 s for 2 minutes), but ~$0.30 a Track out of the Starter plan's monthly credits, which the Vamp and the effects also draw on. Not wired.
- **Mureka 9.5 through a gateway, MiniMax music.** Out of bounds: Mureka appears to be Kunlun Tech's, and there's no inference spend to Chinese first-party APIs. Mureka's own adapter stays in the tree as a commented-out alternative for the day its quota is bought back.

## Consequences

- The switch is one line in `config/config.exs`. Each alternative is written there as a complete commented-out `music:` line, as the voice's is.
- Music keys are vendor-scoped on the Foley role (`lyria_api_key`, `apiframe_api_key`, `mureka_api_key`), so whichever provider the job names finds its own key. `bin/deploy` reads the configured music provider and warns about that provider's key, as it already does for voice.
- One Gemini key now pays for both the Assayer and the Track. A Gemini quota or billing failure silences both at once.
- Lyria answers no duration, so the Track cache records its default length. Nothing reads a Track's stored length today.
- A Lyria answer can arrive with no audio in it, and the provider treats that as a failure. The Page keeps the house loop, and the Chronicle records why.
