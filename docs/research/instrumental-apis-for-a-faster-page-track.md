# Instrumental APIs for a faster Page Track — can playable music land before a fast Page closes?

Researched 2026-09-07 for the [design brief](../design-brief.md), under Foley's *Music* job. Question: Thereish currently asks **Mureka** for one instrumental per Page, prompted from the players' Gives. Spec: started when the Author starts (last Give lands), `n=1`, 30–90 s to arrive, fade in over a house loop, cached by Give set. Code: `POST https://api.mureka.ai/v1/instrumental/generate` then poll `GET /v1/instrumental/query/{task_id}` every 2 s, deadline 150–180 s, then download the full file. Mureka enforces concurrent requests limit 1 on the cheapest top-up. The table plays fast: a Page can meld on the first Attempt in under a minute. Can any **documented, callable music/instrumental generation API** land playable instrumental audio fast enough that a Track written from the Gives is heard before a fast Page closes — and we do **not** have to stay on Mureka?

Method: every claim traces to a primary source — vendor API references, OpenAPI schemas, pricing pages, model cards, first-party FAQs and terms — all fetched 2026-09-07. Mureka's rendered docs still hide schemas; the OpenAPI document the docs site loads at runtime (`https://platform.mureka.ai/docs/assets/chunks/theme.Cv864CFs.js`) was re-read today, as on 2026-09-06. Secondary sources (aggregator APIs, unofficial Suno/Udio wrappers, blogs) were used only to discover vendor names, then dropped unless a first-party page confirmed a callable API. Where an official page does not state a figure the cell says **not found**; nothing is estimated except the explicitly *computed* cost column, which is arithmetic on cited rates. No vendor is recommended; §8 states implications only.

Working assumptions used only for arithmetic: a **150 s** instrumental is the current Page-length track (Mureka's BGM product is “not exceeding 4m30s”; the titling note treated instrumentals as two to three minutes). A **30 s** clip and a **20 s** clip are the shorter alternatives if a vendor exposes length. Stability credits convert at **$1 USD per 100 credits** ([getting started](https://platform.stability.ai/docs/getting-started)). ElevenLabs Music is **$0.15 per minute** ([API pricing](https://elevenlabs.io/pricing/api)). A couch night is **~7–15 Pages**, one Track each, cached by normalized Give set.

---

## 1. What the current path actually does

From `lib/thereish/steward/mureka.ex`, `lib/thereish/steward/music.ex`, `lib/thereish/steward/track_cache.ex`, and `docs/design-brief.md` (Foley, decided 2026-09-05):

- Prompt: house style prefix plus the Page's Gives. Instrumental-only by using the instrumental endpoint, not a no-vocals flag.
- Job: `POST https://api.mureka.ai/v1/instrumental/generate` with `{prompt, model: "auto", n: 1}`, Bearer key. Poll `GET /v1/instrumental/query/{task_id}` every 2 s until `status == "succeeded"`, then `Req.get` the first choice's `url`. Default deadline **180 s**; the brief writes 30–90 s to arrive.
- Audio: mixed MP3 bytes written to disk and cached by normalized Give set. The speaking browser fades the house loop into that file. Late audio plays late; missing audio is silence-under-loop.
- Cost in `config/config.exs`: `"auto" => {:track, 0.04}` — a 2026-09-05 Foley figure. Re-verified pricing is in §2.
- The client never sees `stream_url`, `flac_url`, or `wav_url`.

---

## 2. Mureka, re-verified 2026-09-07

### Endpoints and auth

| Item | Fact | Source |
|---|---|---|
| Base | `https://api.mureka.ai` | [quickstart](https://platform.mureka.ai/docs/en/quickstart.html) |
| Auth | `Authorization: Bearer $MUREKA_API_KEY` | [quickstart](https://platform.mureka.ai/docs/en/quickstart.html) |
| Start | `POST /v1/instrumental/generate` — “Generate instrumental based on the input by the user.” Returns an `InstrumentalTask`; “Use the instrumental/query/{task_id} API to poll” | OpenAPI in `theme.Cv864CFs.js`; [operation page](https://platform.mureka.ai/docs/api/operations/post-v1-instrumental-generate.html) |
| Poll | `GET /v1/instrumental/query/{task_id}` | same OpenAPI |
| Key required | yes | quickstart |

### Request (`InstrumentalGenerateReq`)

Required: `model`. Enum: `auto`, `mureka-7.6`, `mureka-8`, `mureka-9`, `mureka-9.5`. “Use **auto** to select the latest version of the regular model.”

Optional:

- `n` — “Defaults to 2, maximum 3. How many instrumentals to generate for each request. Note that you will be charged based on the number of instrumentals.”
- `prompt` — “maximum 1024 characters.” “Besides individual control, this option does not support combination with other control options.”
- `instrumental_id` — reference upload; mutually exclusive with prompt.
- `stream` — boolean. Full schema text:

  > If set to true, the status of the generation task will include a streaming phase. During this phase, you can obtain the stream_url of the generated instrumental and play this URL, enabling playback while the generation is in progress.

There is **no** duration / length field on `InstrumentalGenerateReq`. Length is not an API knob.

### Task and choice (`InstrumentalTask` / `Instrumental`)

`status` enum: `preparing`, `queued`, `running`, `streaming`, `succeeded`, `failed`, `timeouted`, `cancelled`.

`choices`: “The generated instrumentals, **when the status is succeeded**.”

Each `Instrumental`:

| Field | Schema description |
|---|---|
| `url` | “The URL of the generated instrumental. Valid for 30 days.” |
| `flac_url` | lossless FLAC, “Valid for 30 days.” |
| `wav_url` | lossless WAV, “Valid for 30 days.” |
| `stream_url` | “When the request parameter stream is set to true, the URL that can be played during the streaming phase.” |
| `duration` | “The duration of the instrumental, in milliseconds.” |

So: `stream_url` is documented as a **during-generation** play URL, not as a stream of an already-finished file. `url` / `flac_url` / `wav_url` are documented only as 30-day finished-file URLs, and `choices` is documented only for `succeeded`. Current code waits for `succeeded` and downloads `url`; it never sets `stream: true` and never reads `stream_url`. Time-to-first-playable-byte on `stream_url` is **not found** — the schema says playback is possible “while the generation is in progress,” not how many seconds that phase starts.

The docs index still describes **Mureka V7.5** as “Supports streaming playback — listen as the music is generated, boosting efficiency.” The instrumental `model` enum as of today starts at `mureka-7.6`, not `7.5`. The `stream` flag on instrumental has **no** `mureka-o1` exclusion (that exclusion is only on the song generate schema).

### Job shape and latency

Start-and-poll. No p50/p90, no “excluding network,” no clip-length vs wall-clock relationship on any first-party page fetched today. The 30–90 s band in the design brief is a product assumption, not a Mureka SLA. **not found.**

### Length, loop, prompting, formats

- Length: BGM product line “BGM length not exceeding 4m30s”; song line “Song length not exceeding 5m30s.” No 15 / 30 / 60 s request field. Whether a shorter prompt yields a shorter file faster is **not found**.
- Loop / seamless flag: **not found** on the instrumental schema.
- Prompting: free-text `prompt`, max 1024 characters. Instrumental-only by endpoint. Style prefix is ours (`music.ex`), not a vendor field.
- Formats: `url` is the MP3 the current client plays; FLAC and WAV are extra URLs. Sample rate **not found**. MP3 is browser-playable.

### Concurrency and price (pricing page, rendered 2026-09-07)

Top-up tiers (one-time purchase, 12-month validity, concurrency **per purchase** not summed):

| Plan | Price | Concurrent requests |
|---|---|---|
| TRAIL | $10 | 1 |
| BASIC | $1,000 | 5 |
| STANDARD | $3,000 | 15 |
| BUSINESS | $5,000 | 25 |
| ENTERPRISE | $30,000 | 150 |

FAQ: concurrent requests = “the number of song generation tasks that can be processed simultaneously. Each task is counted from the launch of the request to the completion of song generation.” “Higher-value top-up tiers offer a higher number of concurrent requests.” ([FAQ](https://platform.mureka.ai/docs/en/faq.html))

**BGM (Back Ground Music) generation** — the instrumental product on the price list:

| Model | Price |
|---|---|
| V8 / V9 | **$0.045 / BGM** |
| V7.6 | **$0.03 / BGM** |
| 9.5 | **$0.15 / BGM** |

Same concurrent ladder as songs. “Generate up to 3 songs per time (Default is 2).” Code sends `n=1`. Downloading songs is free; stems are extra ($0.06 / $0.20 / $0.70 per song depending on separator model). Lyrics-to-song on V8/V9/O2 is also $0.045/song; prompt-to-song is $0.30/song ($0.50 on 9.5) — a different SKU.

The 2026-09-05 Foley notes' “~$0.03–0.045/track” matches V7.6 and V8/V9 BGM on the 2026-09-07 price list. `config.exs` `$0.04` is in that band, not a published SKU. 9.5 is 3–5× that.

Computed cost (length is not billed): one Page = **$0.03** (V7.6) / **$0.045** (V8/V9) / **$0.15** (9.5), same for a 20–30 s clip because there is no length knob.

### Licence and URL lifetime

FAQ: “All content generated through paid API calls comes with full usage rights and commercial authorization. You are free to use it in commercial products, platform distribution, advertisements, videos, and other business scenarios.” Finished URLs “Valid for 30 days.” The game already persists bytes.

### Streaming — the specific question

**Yes, Mureka's own `stream_url` is documented as playback before the job finishes**, not as a stream of a finished file. Conditions: request `stream: true`; task `status` includes `streaming`; `stream_url` is “the URL that can be played during the streaming phase”; the `stream` flag text is “enabling playback while the generation is in progress.” What format `stream_url` serves, when the first byte is available, and whether a browser `<audio>` element can fade it in, are **not found**. `choices[].url` remains a finished-file URL that appears at `succeeded`.

---

## 3. Surviving vendors — callable HTTP (or documented WebSocket) music-gen APIs

A vendor survives if a first-party page today documents a generate-music HTTP or WebSocket API a server can call with an owner-held key. Consumer-only products, unofficial wrappers, and self-host-only weights are in §6.

### 3a. Comparison table

Latency cells are the vendor's own words and conditions. “TTFB” = time to first playable byte; “complete” = time to a finished file. Network from a New York VPS is on top of every figure.

| Vendor | Endpoint(s), auth, instrumental control | Job shape / vendor latency | Length / loop | Prompting | Formats | Concurrency | Price (date) | Computed 150 s / 30 s / 20 s | Licence | URL lifetime | Streaming first audio before complete file? |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Mureka** instrumental | `POST /v1/instrumental/generate`, `GET /v1/instrumental/query/{id}`; Bearer. Instrumental by endpoint. | Start-and-poll. Latency **not found**. | No length field. BGM “not exceeding 4m30s.” Loop flag **not found**. | Text `prompt` ≤1024. | MP3 `url`; FLAC; WAV. | 1 on $10 TRAIL; 5 at $1,000. Task occupies a slot until completion. | BGM V8/V9 **$0.045**, V7.6 **$0.03**, 9.5 **$0.15** per BGM (2026-09-07 pricing page). | $0.03–0.15 / same / same | Paid API: full commercial rights ([FAQ](https://platform.mureka.ai/docs/en/faq.html)). | 30 days; persist bytes. | **Yes, if `stream: true`:** `stream_url` during `streaming` status. TTFB **not found**. |
| **ElevenLabs Music** | `POST https://api.elevenlabs.io/v1/music` (compose) and `/v1/music/stream`; `xi-api-key`. `force_instrumental: true` “guarantees that the generated song will be instrumental” with `prompt` only ([compose](https://elevenlabs.io/docs/api-reference/music/compose)). Paid users only. | Compose: HTTP file body. Stream: “Streaming audio data in the format specified.” Music latency **not found** (TTS Flash “~75ms” is a different product). | `music_length_ms` 3000–600000 (3 s–10 min in the field; overview says “minimum duration of 3 seconds and a maximum duration of 5 minutes”). No loop flag. Loops via composition-plan “glue” chunks ([inpainting](https://elevenlabs.io/docs/eleven-api/guides/how-to/music/inpainting)). | Text `prompt` ≤4100, or composition plan with styles / negative styles / lyrics lines. | `mp3_44100_128` (v1 default) / `mp3_48000_192` (v2); WAV/PCM/Opus enums. Browser-playable MP3 yes. | Music-specific concurrency **not found**. Platform metering is concurrency, not RPM ([rate-limiting blog](https://elevenlabs.io/blog/ai-rate-limiting-for-voice) is about voice). | **$0.15 / minute**; Free 3 min, Starter 40 min, … ([API pricing](https://elevenlabs.io/pricing/api), 2026-09-07). | **$0.375 / $0.075 / $0.05** | “Commercial use licensing on Starter+ plans.” Music terms last updated 26 May 2026; Free plan requires Attribution. Prohibited industries and artist-name prompts ([music terms](https://elevenlabs.io/music-terms)). | Bytes in the HTTP body; no expiring CDN URL. | Stream endpoint is documented as chunked generation. Whether the first MP3 frame is playable before the file ends is implied by “stream” but TTFB **not found**. The how-to example buffers the whole stream then plays. |
| **Google Lyria 3.5 / 3 Clip** (Gemini API) | `POST https://generativelanguage.googleapis.com/v1beta/interactions`; `x-goog-api-key`. Models `lyria-3.5`, `lyria-3-clip-preview`. Instrumental via prompt (“Instrumental only, no vocals”), not a flag ([music generation](https://ai.google.dev/gemini-api/docs/music-generation)). | Unary `interactions.create` returns audio in the response. Clip is called “faster” than Pro; no milliseconds. Latency **not found**. | Clip: **always 30 seconds**. Pro: “A couple of minutes (controllable using prompt)” / timestamps. Loop flag **not found**. | Text (and up to 10 images). Section tags, timestamps. | MP3 44.1 kHz stereo default; WAV via `response_format`. | Lyria rows **not found** on [rate limits](https://ai.google.dev/gemini-api/docs/rate-limits); “Rate limits are more restricted for experimental and preview models.” `lyria-3.5` is Preview. | Clip **$0.04 / song**; 3.5 **$0.08 / song** (paid; free **Not available**) ([pricing](https://ai.google.dev/gemini-api/docs/pricing), page updated 2026-09-04). | $0.08 / $0.04 (clip is 30 s) / 20 s **not a documented length** | Paid: content not used to improve products; free would be, but music is paid-only. SynthID watermark always. Safety filters block artist voices / copyrighted lyrics. | Audio is in the JSON (`output_audio`); persist bytes. | No streaming on 3.5 / Clip. “Music generation is a single-turn process.” |
| **Google Lyria RealTime** | `wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateMusic`; API key. Model `models/lyria-realtime-exp`. “Instrumental only.” | Persistent WebSocket. Chunks of PCM. Magenta: “Low latency – maximum of 2 seconds between control change and effect.” Docs: experimental. First-audio-from-prompt TTFB **not found** (2 s is control-to-effect, not cold start). | Continuous stream, not a clip length. No file duration. `mute_drums` / `mute_bass` / `only_bass_and_drums`. | Weighted text prompts; BPM 60–200; density; brightness; scale. | Raw 16-bit PCM, 48 kHz, stereo — **not MP3**. Browser needs Web Audio, not `<audio src=mp3>`. | **not found** | **not found** on the [pricing](https://ai.google.dev/gemini-api/docs/pricing) page (no Lyria RealTime row). | not computable | Experimental. “Output audio is always watermarked.” | No URL; live bytes. Persist only if the client records the stream. | **Yes — that is the product.** First playable byte is a PCM chunk on the socket. |
| **Google Lyria 2** (`lyria-002`, Vertex / Gemini Enterprise Agent Platform) | `POST https://{LOCATION}-aiplatform.googleapis.com/v1/projects/{PROJECT}/locations/{LOCATION}/publishers/google/models/lyria-002:predict`; OAuth Bearer (`gcloud auth print-access-token`), not an API key. “instrumental music from text prompts.” | Unary `predict`; JSON with base64 WAV. Latency **not found** on the API page (it points at a Model Garden card for “generation times”). | **Each clip is 30 seconds.** `sample_count` for more clips. No loop flag. | `prompt` + `negative_prompt`. US English prompts. | WAV 48 kHz, `audio/wav` in JSON. | **not found** | **$0.06 per 30 seconds** of output ([Lyria API](https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/models/lyria-music-generation), updated 2026-09-02). | n/a (always 30 s) / **$0.06** / 20 s not offered | Google Cloud terms; SynthID, safety, recitation checks. | Audio in the response; persist bytes. | No. |
| **Stability Stable Audio 2.5** | `POST https://api.stability.ai/v2beta/audio/stable-audio-2/text-to-audio`; `Authorization: Bearer`. `model=stable-audio-2.5`. Instrumental via prompt / AudioSparx tags (`TrackType: Music, VocalType: Instrumental`) ([prompt guide](https://stability.ai/guides/stable-audio-3-prompt-guide)). | **Synchronous HTTP 200** with audio bytes in the sample. Latency **not found**. | `duration` 1–**190** s (default 190). No loop flag. | Text ≤10,000 chars. | MP3 or WAV, 44.1 kHz stereo. | **150 requests / 10 seconds**, then 429 + 60 s timeout ([FAQ](https://platform.stability.ai/faq)). | **20 credits** flat / success; $1 / 100 credits ⇒ **$0.20** (2026-09-07 docs + [pricing](https://platform.stability.ai/pricing)). | **$0.20 / $0.20 / $0.20** (flat; shorter is not cheaper) | “Yes, you can use the outputs generated by our APIs for commercial purposes, as long as the output doesn't violate any copyrights” ([FAQ](https://platform.stability.ai/faq)). Trained on licensed AudioSparx (+ Freesound for 2.5). | Bytes in the HTTP body. | Sync complete-file. No first-byte-before-complete. |
| **Stability Stable Audio 3.0** | `POST https://api.stability.ai/v2beta/audio/stable-audio/text-to-audio`; same auth. “This endpoint is asynchronous — it returns a generation id immediately (HTTP 202). Poll `GET /v2beta/audio/results/{id}`.” | Start-and-poll (sample sleeps 10 s). Latency **not found**. | `duration` 1–**380** s (default 190); “up to 6-minute … 44.1 kHz stereo.” | Same prompt style; `TrackType: Instrument` for stems. | MP3 or WAV. | Same 150 / 10 s. | **26 credits** flat ⇒ **$0.26**. | **$0.26 / $0.26 / $0.26** | Same commercial FAQ. | Poll returns bytes; 404 if “the generation either does not exist or has expired” — expiry window **not found**. | Poll 202 until complete; no streaming playback. |
| **MiniMax Music** | `POST https://api.minimax.io/v1/music_generation`; Bearer. `is_instrumental: true` on `music-3.0` / `music-2.6` (and free SKUs). | Unary JSON; `stream: true` “Whether to use streaming output” (hex only). Latency **not found** first-party. | “$0.15/up-to-5 minutes music.” No 15/30/60 field. Loop **not found**. | `prompt` 1–2000 chars when instrumental. | mp3 / wav / pcm; 16–44.1 kHz; bitrate 32–256 kbps. `output_format` `url` or `hex`. | **RPM 120** on paid; 3 on free. | **$0.15 / up-to-5 minutes** ([paygo](https://platform.minimax.io/docs/guides/pricing-paygo)). | **$0.15 / $0.15 / $0.15** | **Closed to new users 2026-08-20.** “The paid APIs … will no longer be available to new users; existing paying users can continue.” Free SKUs discontinued. OSS weights on Hugging Face as an alternative they name. | “`url` links expire after 24 hours.” | `stream: true` exists; TTFB **not found**. |
| **Beatoven** | `POST https://public-api.beatoven.ai/api/v1/tracks/compose`; Bearer. Background music by product. | Start-and-poll `GET /api/v1/tasks/{task_id}` until `composed`. Latency: marketing “near-instant audio generation”; figure **not found**. | Duration is written into the prompt text (example: “30 seconds peaceful lo-fi…”). `looping: true/false`. | `prompt.text`. | `mp3`, `aac`, `wav` (default wav). | **not found** | **not found** on [api](https://www.beatoven.ai/api) or the GitHub spec. Key via [apiDashboard](https://sync.beatoven.ai/apiDashboard) / `hello@beatoven.ai`. | not computable | “always cleared for commercial use.” Fairly Trained certified. | `track_url` + four `stems_url`s in the composed payload; lifetime **not found**. | No. |
| **Mubert** API v3 | `POST https://music-api.mubert.com/api/v3/public/tracks`; headers `customer-id` + `access-token` (issued from a company license). Text-2-music: `prompt` instead of `playlist_index`. Also `GET .../streaming/get-link`. | Start-and-poll `GET .../tracks/{TRACK_ID}` (`status: processing` → `done`) or webhook. Streaming is a live URL. Latency: product copy “Generate in Seconds”; API 2.0 landing “3s buffering”; v3 figure **not found**. | `duration` **mandatory**, seconds. `mode`: `track` / `loop` / `jingle` (≤40 s) / `mix`. Prompt max **200 characters, English**. | Channel index or text prompt. | mp3 or wav; bitrate 32–320. | License field `max_concurrent_track_generations` (example `-1` = unlimited). | Trial **$49 / mo** (sale from $99) for 100 generations + 100 streaming minutes; Startup $199 / 5,000; Startup+ $499 / 30,000 ([docs/pricing](https://mubert.com/api/docs), 2026-09-07). Per-track **not found**. | not computable per track; Trial ≈ $0.49 / generation if the 100 are used. | Royalty-free / DMCA-free / “Cleared for monetization” on the API site. Website footer still says music on `*.mubert.com` is “licensed … only for personal use” — the **API** pages are the ones that grant product use. | License example `track_expiration_time: 900` (seconds). Persist bytes. | **Live stream URL** (HTTP or WebRTC) is a different SKU from file generation. File gen is poll-then-download. |
| **Loudly** | Base `https://soundtracks.loudly.com/`. `API-KEY` header. `POST /api/ai/songs` (parameters), `POST /api/ai/prompt/songs` (text). Also catalog, remix, stems, Manta (vocals; `manta_access`). | **not found** (sync vs poll) on the public playground pages fetched; OpenAPI at `b2b-soundtracks-swagger-prd.loudly.com`. Marketing “in seconds.” | Consumer UI: duration among controls, “7 minutes maximum song length” on a plan. API duration field **not confirmed** in the pages that rendered. Loop **not found**. | Genre / energy / instruments **or** text prompt. | MP3, WAV on consumer plans. | account_limit schema exists; numbers **not found**. | Consumer subscriptions on [pricing](https://www.loudly.com/music/pricing). API: “Contact us” on the marketing page; knowledge base mentions “pay-as-you-go API pricing.” Per-track **not found**. | not computable | “automatic Royalty-Free license” for consumer; API “Perpetual license / Monetize your products / Legal guarantee.” | **not found** | **not found** |

### 3b. Notes that do not fit a cell

**ElevenLabs Music vs Sound Effects.** Music is the Track-shaped product (3 s–5 min, `$0.15/min`, `force_instrumental`). Sound Effects is already in this repo as `eleven_text_to_sound_v2` (`POST /v1/sound-generation`). See §5.

**Lyria family is three APIs, not one.** Clip (fixed 30 s MP3, $0.04), 3.5 (few-minute MP3, $0.08), RealTime (PCM WebSocket, instrumental-only, 2 s control latency). Vertex `lyria-002` is a fourth, 30 s WAV at $0.06, OAuth. Foley law 14 (no Gemini in the Give→track path) is a *Gemini-the-LLM* constraint; Lyria is a different model on the same key. Whether that law is meant to cover the Gemini *API project* is a product question, not a vendor fact.

**Stability 2.5 vs 3.0 is a latency-shape fork.** 2.5 text-to-audio is documented as HTTP 200 with bytes (the sample writes `response.content` immediately). 3.0 text-to-audio is HTTP 202 + poll, with the sample waiting 10 s between polls. Both are flat-priced regardless of 20 s vs 3 min. 2.5 max 190 s; 3.0 max 380 s.

**MiniMax is a live API that is closed to new accounts.** The OpenAPI is still published. A new Thereish key cannot be created after 2026-08-20 according to MiniMax's own notice.

**Mubert file generation vs Mubert streaming.** File tracks are exclusive downloads with a duration. Streaming is an endless HTTP/WebRTC URL whose intensity can change without breaking the stream, plus `set-loop-state`. The 3 s buffering claim is on the API 2.0 landing page (`landing.mubert.com/api-2-0`), not restated with a number on the v3 docs.

---

## 4. ElevenLabs Sound Generation — a Track alternative, or the wrong product?

Already wired: `Thereish.Steward.ElevenLabs.generate/1` → `POST https://api.elevenlabs.io/v1/sound-generation`, model `eleven_text_to_sound_v2`.

| Item | First-party fact |
|---|---|
| Endpoint | `POST /v1/sound-generation`, `xi-api-key` ([convert](https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert)) |
| Length | API: `duration_seconds` “at least 0.5 and at most 30.” Overview: “Range: 0.1 to 30 seconds.” Two pages disagree on the floor; the ceiling is 30 s on both. |
| Loop | `loop` boolean, “Only available for the 'eleven_text_to_sound_v2 model'.” Overview: “Enable seamless looping for sound effects longer than 30 seconds” by generating ≤30 s then looping; “no audible start or end point.” |
| Musical content | Overview lists “90s hip-hop drum loop, 90 BPM,” “Vintage brass stabs,” “Atmospheric synth pad.” Key facts: “Drum loops, bass lines, and melodic samples can be generated; **for full music production use the Music API**.” |
| Formats | “MP3 for all effects; WAV at 48 kHz for non-looping effects.” |
| Price | API pricing **$0.12 / minute** (2026-09-07). Overview also: “Cost: 40 credits per second when duration is specified” — Creative-platform credits, not the API dollar rate. Computed at $0.12/min: 30 s = **$0.06**; 20 s = **$0.04**. |
| Latency | API reference: **not found**. First-party blog (SB1 soundboard, 2025-05-16): “Typical generation time is under two seconds.” That is a blog, not the API spec. |
| Job shape | HTTP 200 file body (same as current Foley stings). |

So: it **can** emit a Give-themed looping bed, at most 30 s, designed to repeat. It is the product Foley already uses for stings. It is **not** a 2–3 minute composed instrumental. ElevenLabs themselves point “full music production” at Music. Whether a 30 s loop under conversation is a Track, or a second house loop, is a product question; on latency it sits in the sting band (seconds), not the current 30–90 s music band.

---

## 5. Real-time / streaming music, stems, MIDI

### Real-time beds within a few seconds of a text prompt

Documented as such:

1. **Lyria RealTime** (Gemini API, experimental WebSocket). Instrumental-only PCM 48 kHz stereo. “maximum of 2 seconds between control change and effect” ([Magenta announcement](https://magenta.withgoogle.com/lyria-realtime), 2025-06-12; restated in the [Gemini guide](https://ai.google.dev/gemini-api/docs/realtime-music-generation), updated 2026-09-04). Cold-start TTFB **not found**. Output is PCM, so the speaking browser cannot reuse the current MP3 fade path; it needs Web Audio scheduling. Pricing **not found**. Watermarked.

2. **Magenta RealTime 2** — open weights, not a hosted HTTP API. Real-time streaming “requires Apple Silicon”; `mrt2_small` 230M, `mrt2_base` 2.4B. The New York VPS has no GPU and is not Apple Silicon. Out of scope as a hosted API; named because it is the open twin of Lyria RealTime ([repo](https://github.com/magenta/magenta-realtime)).

3. **Mubert streaming** — `GET /api/v3/public/streaming/get-link` returns `https://stream.mubert.com/b2b/v3?...`. HTTP or WebRTC. Intensity changes “seamlessly without breaking the stream.” API 2.0 copy: “3s buffering / We buffer tracks to make experience instant.” Prompting is a channel index (or, for files, a 200-char English prompt). This is a live radio, not a cached Give-set file.

4. **Mureka `stream_url`** — see §2. Same vendor, same key, still a start-and-poll job, but the schema says the browser can play before `succeeded`.

5. **ElevenLabs `POST /v1/music/stream`** — chunked music bytes. How-to buffers everything then plays. TTFB **not found**. Length still 3 s–5 min billed at $0.15/min.

Not real-time, despite “stream” in the name: Stability 3.0 (async poll), MiniMax `stream: true` (hex chunks of a song, TTFB not found), Beatoven (poll to `composed`).

### Stems and MIDI vs a mixed instrumental MP3

| Vendor | Stems / MIDI | Would the speaking client change? |
|---|---|---|
| Mureka | Separate SKU after generation: V1 five WAV stems $0.06; V2 up to 12 WAV+MIDI $0.70; V3 vocal+instrumental $0.20. “Download 1 song at once.” Concurrent stems = 1. | Yes if Foley mixes stems in the browser; no if we keep fading in the mixed `url`. Extra wait after the mixed file. |
| Beatoven | `stems_url` for bass, chords, melody, percussion **in the same composed payload** as `track_url`. | Optional: the mix is already there. Stems are extra files, not a faster path. |
| Stability | Prompt tags `TrackType: Instrument` / `Format: Duo` for isolated parts. Still one generation, not faster than a mix. | Same fade-in if we take the mix. |
| ElevenLabs | Marketing: “Generate stems, lyrics, and full compositions.” Stem **endpoint** on the Music API reference **not found** today (compose returns one audio body). | Mixed MP3/PCM from compose/stream. |
| Loudly | Stems tag in the OpenAPI. | **not found** whether stems return faster than the mix. |
| Mubert | Replace/delete instruments and stems on an existing track (`DRUMS`, `BASS`, `LEADS`, …). | Edit path, not a faster first file. |
| Lyria RealTime | No stems; `mute_drums` / `mute_bass` / `only_bass_and_drums` on the live mix. | Client is already PCM. |
| MIDI-only APIs | AIVA exports MIDI on the **consumer** app; no public generate API (§6). Magenta RealTime is audio. | A MIDI client would be a new synth in the browser — a different product. |

Nothing first-party documents stems or MIDI arriving *faster* than a mixed instrumental of the same length. The thing that changes time-to-first-sound is **streaming first audio** (Lyria RealTime, Mureka `stream_url`, ElevenLabs music stream, Mubert live stream), not stem layout.

---

## 6. Dropped candidates

Dropped if, on 2026-09-07, there is no first-party callable music-generation API, or the API is dead / consumer-only / new-users-closed without a replacement HTTP API.

| Name | Why dropped |
|---|---|
| **Suno** | Consumer app + Pro/Premier commercial downloads ([suno.com](https://suno.com/l/royalty-free-music-download)). No first-party developer API. `docs.sunoapi.org` and similar are aggregators. |
| **Udio** | Consumer site + help center. No first-party HTTP generate API. |
| **AIVA** | Consumer composer at [aiva.ai](https://aiva.ai/). MIDI/MP3 downloads on plans. No public generate API on aiva.ai; `aiva.help` is an unrelated call-centre product. |
| **Riffusion** | Consumer composer ([riffusion.com/docs](https://www.riffusion.com/docs)). Unofficial wrappers exist; useapi.net: “Riffusion API has been decommissioned.” |
| **OpenAI** | [Models](https://developers.openai.com/api/docs/models) list speech generation, transcription, realtime voice, images, video. **No music-generation model or endpoint.** |
| **Amazon Bedrock / AWS** | No music-generation foundation model on Bedrock. AWS samples that “make BGM” call Claude for MIDI-like numbers or ElevenLabs Music. |
| **Azure** | Speech, OpenAI, vision. No music-generation endpoint found on learn.microsoft.com. |
| **Meta MusicGen** | Research / self-host (AudioCraft). Meta's hosted API is Muse Spark (general multimodal), not MusicGen. No Meta music-gen HTTP API. |
| **Google MusicFX / consumer Flow** | Consumer UIs on top of Lyria. The callable APIs are Gemini Lyria 3.5 / Clip / RealTime and Vertex `lyria-002` (§3). |
| **MiniMax (new accounts)** | API docs remain; **new users blocked since 2026-08-20**. Kept in §3 as a live-but-closed row, not as something Thereish can key up tomorrow. |
| **ACE-Step hosted** | Weights + third-party hosts (fal, etc.). No first-party ACE-Step HTTP API from the authors. |
| **DiffRhythm** | Research / self-host. No first-party hosted API found. |
| **SongDo** | No first-party developer API found. |
| **Sonauto** | Consumer generator; status page names a “Public API” incident (2025-08) but **no public API reference** was found on sonauto.ai. |
| **Soundraw** | Consumer generator. First-party blog discusses “API Starter / API Pro” plans; **OpenAPI / endpoint docs not found** on a public docs host today. |
| **Kits.ai** | Voice conversion / TTS, not a music-generation API. |
| **Magenta RealTime** | Open weights, on-device; see §5. Not a hosted HTTP API. |
| **Hume / Cartesia / Deepgram / etc.** | Voice or SFX, not music. |

---

## 7. Foley / client constraints that the facts run into

- **HTTP from Elixir on a NY VPS.** Lyria RealTime is a WebSocket (`wss://…BidiGenerateMusic`), still callable from the VPS (Mint) or from the speaking browser. Vertex Lyria is OAuth, not an API key. Mubert uses two headers (`customer-id`, `access-token`) issued from a company license. Everyone else in §3 is Bearer or `xi-api-key` or `API-KEY`.
- **Instrumental, no lyrics.** Native flags: Mureka instrumental endpoint; ElevenLabs `force_instrumental`; MiniMax `is_instrumental`; Lyria RealTime “Instrumental only”; Vertex Lyria 2 instrumental-only. Prompt-only: Lyria 3.5/Clip, Stability, Beatoven, Mubert, Loudly.
- **One track per Page, cached by Give set.** Live streams (Lyria RealTime, Mubert radio) are not files: caching means recording the session or not caching. File APIs cache as today.
- **MP3 in Chrome / Safari / Chrome Android.** Lyria RealTime's PCM and Mubert WebRTC are different clients. Opus-in-Ogg still has the Safari caveat from [tts-for-the-assayers-voice.md](tts-for-the-assayers-voice.md) §4.
- **House loop already playing.** Anything that can fade in mid-generation (Mureka `stream_url`, ElevenLabs music stream, Lyria RealTime, Mubert stream) can overlap the loop the way a finished MP3 does; poll-then-download vendors cannot start the fade until the file exists.
- **No Gemini-the-Assayer in the Give→track path.** Lyria lives on the Gemini *API* with the same key style as the Assayer. That is a policy call, not a latency fact.
- **Couch volume 7–15 Pages, concurrency 1.** On Mureka TRAIL, Page 2's generate does not start until Page 1's task leaves `running`/`streaming`. ElevenLabs/Stability/Lyria/Beatoven/Mubert publish higher or unstated caps; MiniMax paid RPM 120 (closed to new users).

---

## 8. Implications for the latency bands

Bands, from the brief and this question: **Bookends ~5 s / before first reveal ~20–40 s / before a fast Page closes ~45–60 s / current 30–90 s.** Facts only — no vendor pick.

**Inside ~5 s (Bookends), on paper, only products that emit audio before a full mix exists.** Lyria RealTime is the one hosted API whose owner states a **2-second** bound, and that bound is *control-to-effect on an already-running stream*, not cold-start TTFB. Magenta's architecture text requires generating “2 seconds of audio in less than 2 seconds.” Mubert's older API landing says **3 s buffering**. ElevenLabs SFX's blog says **under two seconds** for a ≤30 s effect, not a song. Mureka `stream_url`, ElevenLabs `/v1/music/stream`, and Stability 2.5 (sync file) publish **no** millisecond figures; they cannot be placed in this band from docs. Nothing in §3 publishes a p50/p90 for a 2–3 min instrumental that is under 5 s complete.

**Before first reveal (~20–40 s).** Still no p50 from anyone for a finished 2–3 min mix. Vendors whose *shape* could fit, if measured: Stability 2.5 sync (especially a 20–30 s `duration`, which is a documented knob — whether shorter is faster is **not found**); Lyria 3 Clip (always 30 s, called “faster,” $0.04, no latency number); ElevenLabs Music with `music_length_ms=20000–30000` (billed cheaper, latency **not found**); Mureka `stream_url` if the streaming phase starts in this window (unmeasured); Beatoven/Loudly/Mubert file gen with “near-instant” / “seconds” copy and no number. MiniMax's own docs do not give a time; they are closed to new users anyway.

**Before a fast Page closes (~45–60 s).** This is the band the current 30–90 s Mureka poll *sometimes* already hits, and the band a concurrency-1 queue misses on Page 2. Docs that speak to *finished files* in a minute-ish window: none with a SLA. Stability 3.0's own sample polls every **10 s** with no expected iteration count. ElevenLabs Music at 2–3 min is $0.30–0.45 and untimed. Lyria 3.5 is $0.08 per full song and untimed. Mureka remains untimed; enabling `stream: true` changes *when playback can start*, not the documented time to `succeeded`.

**Current 30–90 s complete-file path.** Still the only band with an in-repo assumption (not a vendor number). Re-verified Mureka pricing is **$0.03 / $0.045 / $0.15** per BGM, URLs still 30 days, concurrency still 1 on $10. Shorter clips are not a Mureka API option. Switching length at another vendor (Stability 20–30 s, ElevenLabs 20–30 s, Lyria Clip 30 s, Mubert `duration` + `mode: loop`/`jingle`) is the documented way to ask for less audio; none of them say that less audio returns proportionally sooner.

**Concurrency-1 is a queue, not a latency, problem.** A 45 s generate that cannot overlap means Page 2 starts after Page 1 finishes. Every surviving vendor except Mureka TRAIL either publishes a higher cap (Stability 150/10 s, MiniMax RPM 120, Mureka $1,000 → 5 concurrent) or does not publish one. Lyria RealTime is one long session per bed, which is a different occupancy model (one socket, not one job per Page).

**Format vs fade-in.** Keeping MP3 keeps Safari/Chrome simple and matches the house loop. Lyria RealTime (PCM 48 kHz stereo) and Mubert WebRTC are the two documented “few seconds” beds, and both change the client. Mureka `stream_url` and ElevenLabs music stream stay in HTTP-audio territory if the URL/chunks are MP3 (Mureka format of `stream_url` **not found**; ElevenLabs stream `output_format` can be `mp3_*`).

**SFX loop vs Track.** ElevenLabs Sound Generation can put a Give-themed **≤30 s seamless loop** under talk on the sting-like path already in the repo, at **$0.06 / 30 s**, with a blog latency of under two seconds. The same vendor's Music API is the thing that makes a 2–3 min instrumental with `force_instrumental`. Using SFX as the Page Track is using the product they describe as samples and ambience, not “full music production.”

**Stems/MIDI do not move a mix into an earlier band** on any first-party page. They add files (and, at Mureka, a second paid job).

**Could not verify.** Mureka `stream_url` codec, TTFB, and whether `choices` is empty during `streaming`. ElevenLabs Music TTFB and music-specific concurrency. Lyria 3.5 / Clip wall-clock. Lyria RealTime cold start and price. Stability 2.5 actual sync time vs duration. Beatoven and Loudly rate cards. Mubert v3 generate time (vs “seconds” / “3s buffering”). Whether Vertex `lyria-002` “generation times” on the Model Garden card state a number — the API page does not. MiniMax stream TTFB (and new-key availability: documented as no).

---

## Sources

All fetched 2026-09-07 unless noted.

**Mureka**
- OpenAPI loaded by the docs site: `https://platform.mureka.ai/docs/assets/chunks/theme.Cv864CFs.js` (schemas `InstrumentalGenerateReq`, `InstrumentalTask`, `Instrumental`; paths `/v1/instrumental/generate`, `/v1/instrumental/query/{task_id}`)
- https://platform.mureka.ai/pricing (rendered; TRAIL–ENTERPRISE concurrency; BGM V7.6 / V8 / V9 / 9.5 prices)
- https://platform.mureka.ai/docs/
- https://platform.mureka.ai/docs/en/quickstart.html
- https://platform.mureka.ai/docs/en/faq.html
- https://platform.mureka.ai/docs/api/operations/post-v1-instrumental-generate.html

**ElevenLabs**
- https://elevenlabs.io/docs/overview/capabilities/music
- https://elevenlabs.io/docs/api-reference/music/compose
- https://elevenlabs.io/docs/api-reference/music/stream
- https://elevenlabs.io/docs/eleven-api/guides/how-to/music/streaming
- https://elevenlabs.io/docs/eleven-api/guides/how-to/music/inpainting
- https://elevenlabs.io/docs/overview/capabilities/music/best-practices
- https://elevenlabs.io/docs/overview/capabilities/sound-effects
- https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
- https://elevenlabs.io/pricing/api
- https://elevenlabs.io/music-terms
- https://elevenlabs.io/eleven-music-model-specific-terms
- https://elevenlabs.io/blog/how-we-created-a-soundboard-using-elevenlabs-sfx-api (SFX “under two seconds”; blog)

**Google / Lyria**
- https://ai.google.dev/gemini-api/docs/music-generation
- https://ai.google.dev/gemini-api/docs/realtime-music-generation
- https://ai.google.dev/api/live_music
- https://ai.google.dev/gemini-api/docs/models/lyria-3.5
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/rate-limits
- https://magenta.withgoogle.com/lyria-realtime
- https://docs.cloud.google.com/gemini-enterprise-agent-platform/reference/models/lyria-music-generation
- https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/music/generate-music
- https://github.com/magenta/magenta-realtime

**Stability**
- https://platform.stability.ai/docs/api-reference (Stable Audio 2.5 / 3.0 text-to-audio, results poll; rendered)
- https://platform.stability.ai/pricing
- https://platform.stability.ai/docs/getting-started
- https://platform.stability.ai/faq
- https://platform.stability.ai/docs/release-notes
- https://stability.ai/guides/stable-audio-3-prompt-guide

**MiniMax**
- https://platform.minimax.io/docs/api-reference/music-generation
- https://platform.minimax.io/docs/guides/music-generation
- https://platform.minimax.io/docs/guides/pricing-paygo

**Beatoven**
- https://github.com/Beatoven/public-api/blob/main/docs/api-spec.md
- https://github.com/Beatoven/public-api/blob/main/README.md
- https://www.beatoven.ai/api

**Mubert**
- https://mubert.com/api/docs
- https://mubert.com/api/plans
- https://landing.mubert.com/ (and `/api-2-0` for the “3s buffering” line)
- https://mubert.com/render/how-it-works

**Loudly**
- https://www.loudly.com/developers
- https://www.loudly.com/
- https://www.loudly.com/music/pricing
- https://b2b-soundtracks-swagger-prd.loudly.com/swagger/b2b_swagger.yaml

**Dropped / existence checks**
- https://suno.com/l/royalty-free-music-download
- https://www.udio.com/
- https://aiva.ai/
- https://www.riffusion.com/docs
- https://developers.openai.com/api/docs/models
- https://sonauto.ai/ (status.sonauto.ai incident naming “Public API”)
- https://soundraw.io/blog/post/music-api-developers-guide
- In-repo: `lib/thereish/steward/mureka.ex`, `lib/thereish/steward/eleven_labs.ex`, `config/config.exs`, `docs/design-brief.md`
