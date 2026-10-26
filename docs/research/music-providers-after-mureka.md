# Music providers after Mureka: a bake-off for the Page Track

Run 2026-10-26 for ticket 277. Mureka's API answers every score request with HTTP 429 ("You exceeded your current quota"), so every Page falls back to the house loop, and staying on Mureka means a ~$1,000 commitment. This bake-off asks which provider reachable with the keys already in `va bash` should score the Track instead. The constraints are instrumental only, no inference spend to Chinese first-party APIs, cost near Mureka's $0.04, and landing well inside `deadline_ms: 180_000`.

## Method

Four sets of Gives were scored on every reachable candidate. Each prompt was built by the real `Thereish.Steward.Music.prompt/1`, so every provider heard exactly what a Page would send it.

| Set | Gives |
|---|---|
| 1 | pine, cold river |
| 2 | lighthouse, can of worms, Vecna |
| 3 | surf rock, a tax audit |
| 4 | liminal spaces, lo-fi hip hop, grandma's kitchen |

Wall-clock is measured from this Mac, from request to a playable file in hand, including the download where there is one. Duration comes from `ffprobe`. The vocals column is Gemini 3.8 Flash listening to each file (Foley's ear, the same model that ranks the forge), asked whether any sung or spoken voice is audible. That is a machine ear, not a verdict, and the listening call is Jacob's. The audio is not committed (~73 MB). It is in the main checkout at `.scratch/foley-277-bakeoff/candidates/`, which git ignores, named `<candidate>_<set>.mp3` alongside the prompts and the ear's raw notes.

## Results

| Candidate | Route | Cost / Track | Wall-clock (sets 1–4) | Length | Vocals heard | Outcome |
|---|---|---|---|---|---|---|
| **Lyria 3.5** | Gemini API `generateContent`, `GEMINI_API_KEY` | **$0.08** | 25 s, 44 s, 26 s, 39 s (a first probe: 34 s) | ~3:00 | set 3: shouts in the surf rock | ✅ chosen |
| Lyria 3 Pro Preview | same | $0.08 | 23 s, 25 s (re-timed; sets 3–4 not timed) | ~3:00 | none | ✅ works, one config line |
| Lyria 3 Clip Preview | same | $0.04 | 8 s, 8 s, 8 s, 9 s | 0:30 (fixed) | none | ✅ works; too short for a Track (see below) |
| Eleven Music (`music_v1`) | ElevenLabs `POST /v1/music`, `force_instrumental: true`, 120 s | ~$0.30 (≈750 credits/min) | 11 s, 11 s, 11 s, 12 s | 2:00 (asked) | set 2: speech, shouts, whispers | ⚠️ works on Starter; credit-bound |
| Suno V5.5 | APIFRAME `POST /v2/music/generate`, `instrumental: true` | $0.11 per job (two tracks) | 40 s, 43 s, 24 s, 27 s | 2:10–3:40 | set 3: spoken "tax audit" interjections | ✅ works; second adapter; account now out of credit |

Not tried:

- **Suno v6** isn't offered. APIFRAME rejects `model_version: "V6"` and accepts `V4` through `V5_5`.
- **Mureka 9.5 through a gateway** is out of scope. Mureka appears to be Kunlun Tech's, and the maintainer rules on that.
- **MiniMax music** is ruled out on any route (no inference spend to China).
- **fal** was optional and skipped. Its Eleven Music listing is $0.80/min, dearer than ElevenLabs direct, and nothing else it hosts was needed once three routes worked.
- **Lyria RealTime** (`lyria-realtime-exp`) speaks only `bidiGenerateMusic`, a streaming session rather than a file. It doesn't fit the Track's start, wait and download shape.

## What each route actually does

**Lyria (Gemini API).** One synchronous `POST /v1beta/models/{model}:generateContent` with the prompt as a text part. The answer carries a text part (a section map like `[[A0]] [[B1]] …`, or `<instrumental>` for the clip model) and an `inlineData` part with `audio/mpeg` base64, a 192 kbps 44.1 kHz MP3. There's no job to poll, so `deadline_ms` is simply the receive timeout. Prices are from the [Gemini API pricing page](https://ai.google.dev/gemini-api/docs/pricing): Lyria 3.5 and Lyria 3 Pro Preview are $0.08 per song, and Lyria 3 Clip Preview is $0.04 per 30 s clip. There's no free tier. Two of sixteen Lyria 3.5 calls came back as a 200 with no audio. The first had no `candidates` at all. The second was a `promptFeedback.blockReason: "PROHIBITED_CONTENT"` after 7 s, on surf rock and a tax audit, a prompt that landed on the next two tries. Both were billed no output tokens. So the adapter asks once more within the deadline, and only a second empty answer is an error. The [music generation docs](https://ai.google.dev/gemini-api/docs/music-generation) describe the same models through the newer Interactions API. `generateContent` is what the model list advertises, and it worked as-is.

**Eleven Music.** `POST https://api.elevenlabs.io/v1/music` answers the MP3 bytes directly, and it was by far the fastest: 2 minutes of audio in ~11 s. The account is on Starter. Four 2-minute tracks moved its counter from 5,469 to 11,344 of 71,206 credits, about 750 credits per minute or 1,500 per Track. At Starter's $6 per 30,000 credits that is ~$0.30 a Track, and a month's credits would cover only about 45 Tracks while also paying for the Vamp and the effects. `force_instrumental: true` still let the ear hear speech and shouts on the Vecna set.

**Suno through APIFRAME.** Suno has no public API of its own, so every route is a wrapper. APIFRAME's is a job: submit `{prompt, model: "suno", sunoParams: {model_version, instrumental: true}}`, which answers a `jobId`. Then poll `GET /v2/jobs/{id}` until `COMPLETED`, and download `result.tracks[0].audioUrl`. Description-mode prompts are capped at 500 characters. One job (11 credits, ~$0.11 per [its pricing page](https://apiframe.ai/models/suno/pricing)) answers two tracks. The adapter keeps the first, so the per-Track cost is $0.11, not $0.055. After this bake-off the account had 1 credit left, and the adapter's live smoke test got `402 Insufficient credits`. Switching to it means topping it up first.

## Why Lyria 3.5

- **It works with what is already deployed.** The key is `GEMINI_API_KEY`, which the server already has for the Assayer. No new vendor, account or key.
- **It's faster than Mureka was.** Mureka's path started a job, polled every 2 s and downloaded at the end, and the brief planned on 30–90 s. Lyria 3.5 lands a whole file in 25–45 s in one request, well inside the 180 s deadline, so the Vamp covers less.
- **The extra $0.04 buys a full-length song.** Mureka was $0.04 a Track. Lyria Clip matches that price, but it is fixed at 30 seconds, and the browser loops the Track for the whole Page (`newSource.loop = true` in the Room's music player). A 30-second Track is a second Vamp, not a Track. Lyria 3.5's ~3 minutes loops far less often. At 7–15 Pages a night, the difference is $0.28–$0.60 a night.
- **It's an official API.** Suno through APIFRAME depends on an unofficial wrapper around a service without a public API, which is a reliability and terms risk for the default path.
- **Eleven Music is faster but credit-bound.** ~$0.30 a Track out of a shared monthly credit pool would need a plan upgrade to be the default.

Lyria 3 Pro Preview is the same price and was the only full-length model the ear heard no voice on. It is a preview model, though, and preview models get withdrawn. It's a one-word model swap if Jacob's listening prefers it.

## After review: a no-vocals clause

Lyria has no instrumental switch (Mureka had an instrumental endpoint, and Suno takes `instrumental: true`), so the Lyria adapter appends "No vocals, no singing, no speech, no shouts." to the Track's prompt. That is what the [music generation docs](https://ai.google.dev/gemini-api/docs/music-generation) suggest. It helps only partly. Of two surf-rock Tracks scored with it, the ear heard one clean and one with shouted "tax" and "audit" interjections. Lyria 3 Pro Preview, the one-word swap, was clean on all four sets without it.
