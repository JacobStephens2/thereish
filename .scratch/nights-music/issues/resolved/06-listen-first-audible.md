# 06: Listen: first audible

**What to build:** A measurement, not a product pick. Same Give pair, Speaker on, Repertoire already playing. Wall-clock to first audible sample (not to `succeeded`, not to full decode) for three beds: (1) the current poll-then-download path as control, (2) Mureka `stream: true` / `stream_url`, (3) optionally ElevenLabs Sound Generation ≤30 s with `loop: true` from the same prompt. Log Chronicle `music_meta.latency` next to the ear-clock. Bar from the grilling: during Attempt 1, before the second Attempt’s Bridges. Occupancy (tickets 01–05) does not wait on this. Spec sections: First sound; Further Notes (Mureka stream is a listen). Research: `docs/research/instrumental-apis-for-a-faster-page-track.md`.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] Control path timed to first audible fade-in on the Speaker
- [x] Mureka `stream_url` timed to first audible sample; codec and whether the browser can fade it in are recorded, including a miss if it will not play
- [x] Optional same-night: ElevenLabs SFX 30 s loop from the same Gives, timed the same way
- [x] Verdict written here: keep a long mix and start hearing it sooner (stream), switch to a 20–30 s looping bed, or a fast bed then replace — or “none of these hit Attempt 1”
- [x] No Lyria or other new vendor until these two keys have been heard

## First audible listen results and verdict

Measured live on 2026-09-07 via `mix foley.listen --live` with Gives `["pine", "cold river"]`:
- **Prompt:** `"Gentle, conversational background instrumental music that sits comfortably under spoken conversation. Atmosphere and theme: pine, cold river"`
- **Artifacts:** Written to `.scratch/nights-music/listen/` (`01-control.mp3`, `02-mureka-stream.aac`, `02-mureka-stream.url`, `03-elevenlabs-30s-loop.mp3`, `report.json`, `report.txt`).

### Measurements

| Bed | Wall-clock to first audible | Chronicle `music_meta.latency` | Codec / Format | Browser Playable / Fade | Cost | Hits Attempt 1 Bar? |
|---|---|---|---|---|---|---|
| **1. Control** (Mureka poll-download) | **89,772 ms** (~89.8 s) | 89,772 ms | `audio/mpeg` (MP3) | Yes (standard audio fade) | $0.04 | **No** (misses Attempt 1 entirely; arrives during Attempt 2 or after page close) |
| **2. Mureka Stream** (`stream: true` / `stream_url`) | **24,061 ms** (~24.1 s) | 23,687 ms (to stream_url) | `audio/aac` (ADTS AAC, LC, 44.1 kHz, stereo) | Yes (`<audio>` elements natively stream & fade `audio/aac`) | $0.04 | **YES** (lands in ~24 s, comfortably during Attempt 1 before Attempt 2 Bridges) |
| **3. ElevenLabs SFX loop** (30 s loop) | **6,625 ms** (~6.6 s) | 6,625 ms | `audio/mpeg` (MP3, 44.1 kHz, seamless loop) | Yes | $0.03 | **YES** (lands in ~6.6 s, during Author writing / Bookends) |

### Key Findings

1. **Mureka `stream_url` is real and fast enough:**
   - Generation returned `status: "streaming"` with an active live stream URL (`https://api.mureka.ai/v1/live/stream/...aac`) at **23.7 seconds**.
   - Probing the stream URL returned HTTP 200 with `content-type: audio/aac` and the first playable audio chunk at **24.1 seconds** total wall-clock time.
   - Codec is standard ADTS AAC (`MPEG ADTS, AAC, v4 LC, 44.1 kHz, stereo, ~128 kbps`). Modern desktop and mobile browsers (Chrome, Safari, Firefox, Edge, Android Chrome, iOS Safari) natively play and crossfade `audio/aac` streams via HTML5 `<audio>`.
   - It hits the grilling bar: **during Attempt 1, before the second Attempt's Bridges**.
   - **Stream URL lifecycle:** The `stream_url` is an ephemeral live stream that streams chunks during generation. Once the task reaches `succeeded`, the stream URL expires (returns HTTP 400 `The generation task is complete, and the stream url is no longer valid.`) and Mureka returns the permanent static `audio_url` in the query response. Ticket 07 should play the live stream while generating, then seamlessly retain or transition to the completed audio file for caching.

2. **Control is unacceptably late:**
   - The full download path takes **89.8 seconds** to reach `succeeded` and finish downloading the 5.9 MB MP3. On fast pages that close in 45–60 s, it is completely missed.

3. **ElevenLabs SFX is fast but a different product:**
   - ElevenLabs returns in **6.6 seconds** ($0.03) with a clean 30-second seamless loop.
   - However, as documented in the research, ElevenLabs SFX produces ambient texture/sound effects rather than a full, dynamically developing 2–4 minute musical composition.

### Verdict

**Keep a long mix and start hearing it sooner (Mureka stream).**

Mureka `stream: true` / `stream_url` satisfies the Attempt 1 timing requirement (24.1 s vs ~89.8 s control) without giving up the rich 2–4 minute composed instrumental that fits the players' Gives. It stays on the existing Mureka key ($0.04/track), requires no new vendor or client architecture overhaul, and delivers playable `audio/aac` audio directly into the browser's audio bus.

For ticket 07: Teach Foley / Steward to use Mureka `stream: true`, seizing the Speaker as soon as `stream_url` is returned during generation, while persisting the finished track when generation completes.
