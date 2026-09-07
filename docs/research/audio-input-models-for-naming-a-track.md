# Audio-input models for naming a Track — is listening to the song worth more than reading the Gives?

Researched 2026-09-06 for the [design brief](../design-brief.md), under the *Tracks have titles* decision. Question: the Scribe titles each Mureka instrumental so the players can ask for "the summer camp song" again. The default plan titles it from the **text** — the Gives that were sent to Mureka in the first place. The open experiment is titling it from the **audio**: send the finished MP3 to a model that listens, get back a short title and a one-line description as JSON. Which models can actually do that, which of them understand *music* rather than only speech, what does one Page cost, and does Mureka itself already hand back a title we are throwing away?

Method: every claim traces to a primary source — vendor API references, pricing pages, model cards, published benchmark papers, and, for Mureka, the OpenAPI document that its documentation site loads at runtime (`https://platform.mureka.ai/docs/assets/chunks/theme.Cv864CFs.js`, read 2026-09-06, because the rendered pages show the endpoint names but not the schemas). Where a vendor does not publish a figure the cell says **not found** and no number is invented. The only arithmetic is the per-clip cost in §7, which is stated with its working. §9 states implications; everything above it is finding.

Working assumptions used only for the arithmetic: a titling request carries **~100 text tokens** (the Gives plus a short instruction) and returns **~50 output tokens** (a title and a one-line description as JSON). Clip lengths are **30 s** (a sampled excerpt) and **150 s** (a whole Page's track, since Mureka's instrumentals run two to three minutes).

---

## 1. Does Mureka already give us a title?

**No — not from any generation endpoint.** The `InstrumentalTask` schema returned by `POST /v1/instrumental/generate` and `GET /v1/instrumental/query/{task_id}` has exactly six top-level fields — `id`, `created_at`, `finished_at`, `model`, `status`, `failed_reason` — plus `choices`, an array of `Instrumental` objects whose *only* fields are `index`, `id`, `url`, `flac_url`, `wav_url`, `stream_url` and `duration`. There is no `title`, no `tags`, no `genres`, no `description`. The song equivalent (`SongTask` → `Song`) adds only `lyrics_sections`. So `lib/meaning_game/steward/mureka.ex` parsing `choices[0].url` and `duration` is not missing anything: for an instrumental there is nothing else there.

Two adjacent endpoints do exist, and one of them is directly relevant.

**`POST /v1/song/describe` — "Understand and describe the input song".** This is Mureka's own audio-understanding endpoint, shipped 2025-09-25 per the [changelog](https://platform.mureka.ai/docs/en/changelog.html) ("New API: song describe"). Its request (`SongDescribeReq`) takes one required field, `url`: *"The URL of the song to be processed. Supported formats: mp3, m4a. URL in base64 format is also supported, with a maximum data size of 10 MB. For example, data:audio/mp3;base64,AAAAGGZ…"*. Its response (`SongUnderstandResp`) is four fields — `instrument` (array of strings), `genres` (array), `tags` (array), `description` (string) — and the documented example is:

```json
{
  "instrument": ["Piano", "Synth Bass"],
  "genres": ["Pop", "Electropop"],
  "tags": ["Anthemic", "Motivational"],
  "description": "This is a powerfully dynamic pop-rock track that masterfully builds from an intimate piano ballad into a massive, anthemic electronic rock anthem."
}
```

It is already JSON with a fixed shape, it takes a plain URL — and Mureka's generated tracks are served from a URL valid for 30 days — and the call needs no new vendor, no new key and no new billing relationship. It does **not** return a title; it returns the raw material a titler would want. Its price is **not found**: Mureka publishes no per-endpoint price list, only a credit balance in cents via `GET /v1/account/billing` and the [FAQ](https://platform.mureka.ai/docs/en/faq.html) line that "The API top-up is a one-time payment that is consumed gradually."

**`POST /v1/lyrics/generate`** returns a `title` alongside lyrics, but it is text-to-text and is about a song's words, not an instrumental's character. Not applicable.

**Usage rights.** Mureka's FAQ: *"All content generated through paid API calls comes with full usage rights and commercial authorization. You are free to use it in commercial products, platform distribution, advertisements, videos, and other business scenarios."* Nothing there restricts feeding the audio back to Mureka or to a third party.

---

## 2. The baseline already in the game — Gemini

Gemini 3.8 Flash is already Foley's ear for ranking sound-effect candidates, so it is the thing any experiment has to beat.

- **Audio input.** The [audio guide](https://ai.google.dev/gemini-api/docs/audio) lists "WAV, MP3, AIFF, AAC, OGG, FLAC, MPEG, M4A, L16, Opus, ALAW, MULAW, WebM"; "32 tokens per second of audio (1 minute = 1,920 tokens)"; "Maximum request size is 20 MB total (including prompts and all files)" for inline data; and up to "9.5 hours of audio per prompt". Audio is "Downsampled to 16 Kbps" and "Multi-channel audio combined to single channel". A 150 s MP3 at 128 kbps is roughly 2.4 MB, about 3.2 MB base64-encoded, so it fits inline comfortably.
- **Music, not just speech.** The same guide lists "Emotion detection in speech and music" among the use cases and states that "Gemini understands non-speech sounds (birdsong, sirens, etc.)". That is Google's own claim; the independent evidence is in §5.
- **JSON.** [Structured output](https://ai.google.dev/gemini-api/docs/structured-output) is a Gemini 3-series feature and the docs' examples are text, image, video and document; the page does not name audio as a compatible input for response schemas, so the combination is **not documented** even though nothing on the page excludes it. The repo's own design law 14 already says a schema validator has the last word, so this is a thing to verify empirically rather than a blocker.
- **Price.** [Pricing](https://ai.google.dev/gemini-api/docs/pricing) for `gemini-3.8-flash`, paid tier: input "$0.75 through December 31, 2026. $1.50 starting January 1, 2027", output "$3.75 … $7.50 starting January 1, 2027". The 3.8 Flash row carries no per-modality split. Two cheaper siblings do: `gemini-3.5-flash-lite` at "$0.30 (text / image / video / audio)" in and "$2.50" out, and `gemini-3.1-flash-lite` at "$0.25 (text / image / video)" with "$0.50 (audio)" in and "$1.50" out. Both are free of charge on the free tier.
- **Latency.** No first-party figure for audio requests. The repo's own measurements of Gemini 3.8 Flash on text verdicts are in [model-selection-for-play.md](model-selection-for-play.md); audio adds tokens, not a different code path, but nothing published lets us predict it.

---

## 3. The named candidates

### 3a. MiniMax-M3, on SambaNova or MiniMax's own platform — **no audio input**

MiniMax-M3 exists. SambaNova serves it: the [supported-models page](https://docs.sambanova.ai/cloud/docs/get-started/supported-models) lists `MiniMax-M3` as a preview model with a 1M context and modalities **text + image**. SambaNova's whole catalogue is seven models — `MiniMax-M2.7`, `DeepSeek-V3.1`, `DeepSeek-V3.2`, `Meta-Llama-3.3-70B-Instruct`, `gpt-oss-120b`, `gemma-4-31B-it`, `MiniMax-M3` — and **not one of them accepts audio**; there is no ASR product on the platform either. SambaNova prices M3 at $0.60 in / $2.40 out per 1M tokens ([pricing](https://cloud.sambanova.ai/plans/pricing)).

On MiniMax's own platform the model is natively multimodal over **text, image and video** ([model page](https://www.minimax.io/models/text/m3), [text-generation docs](https://platform.minimax.io/docs/guides/text-generation)) at $0.30 in / $1.20 out per 1M for inputs up to 512K ([pay-as-you-go pricing](https://platform.minimax.io/docs/guides/pricing-paygo)). There is no `input_audio` content type and the [API overview](https://platform.minimax.io/docs/api-reference/api-overview) lists audio only in the generating direction — TTS, voice cloning, `music-3.0`. There is no documented audio-understanding endpoint.

**Verdict: a dead end for this job on both hosts.** Nothing about MiniMax-M3 is wrong; it simply cannot hear.

### 3b. Muse Spark 1.2 — this is Meta's AI API, and it is one candidate, not two

The brief named "Muse Spark 1.2" and "Meta's AI API" separately. They are the same thing: Muse Spark is Meta's closed-weights multimodal family and the Meta Model API is how you call it ([Meta developer blog](https://developer.meta.com/ai/resources/blog/build-with-muse-spark/), docs at [dev.meta.ai/docs](https://dev.meta.ai/docs)). It is a general reasoning model, not a music model — there is no music-specific "Muse Spark".

- **Models and audio.** The [models page](https://dev.meta.ai/docs/models/) lists `muse-spark-1.3`, `muse-spark-1.2` and `muse-spark-1.1`, each "Text, image, video, audio, PDF" with a 1,048,576-token context, plus `muse-image-1.0` and `muse-voice-transcribe-1.0` (ASR only). A footnote matters: *"Audio understanding in Muse Spark 1.3 is currently not fully supported, and response quality for requests including audio content may be degraded. For audio, use Muse Spark 1.2, or Muse Voice Transcribe for dedicated speech-to-text."* So the model to try is **1.2, not the newest one**.
- **Formats and limits.** [File handling](https://dev.meta.ai/docs/file-handling.md) accepts `audio/mpeg` and `audio/wav` — MP3 goes in as-is — inline up to "50 MB (50,000,000 bytes)", or 1 GiB via the Files API, attached as base64, a public URL, or an uploaded file id. **No maximum audio duration is published.**
- **JSON.** Yes, and schema-enforced: [structured output](https://dev.meta.ai/docs/structured-output.md), "Return valid JSON that matches your schema every time."
- **Price.** [Pricing and rate limits](https://dev.meta.ai/docs/pricing-rate-limits.md): $1.25 / 1M input, $4.25 / 1M output, $0.15 / 1M cached input on the standard tier; a `-contributor` tier at $0.10 / $0.20 that **trains on your data**; 3,000 RPM / 4,000,000 TPM per team. Audio is billed as tokens, with no separate audio rate.
- **The gap.** [Token counting](https://dev.meta.ai/docs/token-counting.md) refuses to publish a media-to-token rate: *"Their token contribution depends on the selected model and version, prompt template, media preprocessing, and image resolution. Fixed per-image or prompt-overhead estimates are not portable across deployments"* and *"Use `input_tokens` instead of estimating"*. **So the per-clip cost cannot be computed from published figures.** It has to be measured off a real response's usage block.
- **Music evidence: none published.** Meta's docs have pages for image understanding, video understanding and speech-to-text, but no audio-understanding page and no music benchmark. The API is a US-developer public preview.
- **Latency:** not found.

### 3c. Inkling, on DeepInfra — real, cheap, and the closest thing to a rival

"Inkling by DeepInfra" is Thinking Machines Lab's open-weights model, which DeepInfra hosts. It is genuinely audio-in.

- **Model card** ([thinkingmachines.ai](https://thinkingmachines.ai/model-card/inkling/)): a "66-layer decoder-only transformer with a sparse Mixture-of-Experts (MoE) feed-forward backbone", 975B total / 41B active, all modalities "projected into a shared hidden space and processed jointly by the decoder". Inputs: text; "Image: Any pixel-based image input"; **"Audio: WAV format, sampled at 16kHz"**, with "For optimal performance, audio length should be within 20 mins". Licence: **Apache 2.0**.
- **Music evidence.** The card reports **MMAU 77.2%** and **Audio MC 56.6%**, against **Gemini 3.1 Pro (high) at 82.5% and 66.8%** on the same rows. In other words, the model card of the best open audio contender puts Gemini ahead of it on the general audio-understanding benchmark. That is the single most useful number in this note.
- **Hosting and price.** [DeepInfra](https://deepinfra.com/thinkingmachines/Inkling) serves `thinkingmachines/Inkling` at $0.95 / 1M in, $4.05 / 1M out, 524,288 context; [`thinkingmachines/Inkling-Small`](https://deepinfra.com/thinkingmachines/Inkling-Small) at $0.45 / $1.20.
- **JSON.** DeepInfra says "JSON and function calling"; [OpenRouter's listing](https://openrouter.ai/thinkingmachines/inkling) is more precise — `response_format` for JSON output **without JSON-schema enforcement**, plus tools. Validate client-side.
- **Frictions.** MP3 must be transcoded to 16 kHz WAV before sending, which means an ffmpeg dependency on the VPS that Foley does not currently have. And **no tokens-per-second-of-audio rate is published**, so, as with Muse Spark, the per-clip cost is not computable in advance.
- **Latency:** not found.

Also on DeepInfra, and worth naming only to rule out: `mistralai/Voxtral-Small-24B-2507` at $0.003 / minute of audio is billed in a pleasantly predictable unit and does claim understanding beyond transcription, but its [model card](https://huggingface.co/mistralai/Voxtral-Small-24B-2507) is entirely about speech — "Built-in Q&A and summarization", "state-of-the-art performance in the world's most widely used languages" — and **never mentions music**. The rest of DeepInfra's audio catalogue (Whisper, Qwen3-ASR, Nemotron ASR, at $0.0002–$0.00045 / minute) is transcription, which returns nothing at all for an instrumental.

---

## 4. Models specialised in music understanding

This is the category the brief asked about, and it splits cleanly into three: one family with a hosted API, one family that is research-only, and a class of tools that returns tags rather than prose.

### 4a. Qwen-Omni — the specialists that *are* hosted, and the only real rival to Gemini

The line runs Qwen-Audio → Qwen2-Audio → Qwen2.5-Omni → Qwen3-Omni → **Qwen3.5-Omni**. There is no "Qwen3-Audio": the audio line became omni-modal, and the surviving `qwen-audio-3.0-*` model IDs on Model Studio are ASR and TTS, not understanding. Two members matter.

**The general omni models.** Alibaba's [Qwen-Omni docs](https://www.alibabacloud.com/help/en/model-studio/qwen-omni) give the numbers that let us cost the job properly:

- Formats: "AMR, WAV, 3GP, 3GPP, AAC, and MP3".
- Token rate: for Qwen3.5-Omni, "Total tokens = Audio duration (seconds) * 7"; for Qwen3-Omni-Flash, 12.5 tokens per second; for Qwen-Omni-Turbo, 25.
- Duration: Qwen3.5-Omni "Up to 3 hours"; Qwen3-Omni-Flash "Up to 20 minutes"; Qwen-Omni-Turbo "Up to 3 minutes". Base64 payloads must be "smaller than 10 MB" on all of them; public URLs up to 2 GB on the 3.5 series.
- JSON: **not addressed in the docs.**

Seven tokens per second is a fifth of Gemini's 32, which is the biggest single lever on cost.

The Qwen3.5-Omni [paper](https://huggingface.co/papers/2604.15804) reports **MMAU 82.2** against Gemini 3.1 Pro's 81.1, and — the number that should decide whether an A/B arm is worth building — **RUL-MuchoMusic 72.4 against Gemini 3.1 Pro's 59.6**. On the music-specific benchmark the specialist leads the generalist by twelve points. Qwen3.5-Omni is API-only; there are no `Qwen/Qwen3.5-Omni-*` weights on HuggingFace.

**The captioner.** [`Qwen3-Omni-30B-A3B-Captioner`](https://www.alibabacloud.com/help/en/model-studio/qwen3-omni-captioner) is a dedicated audio-caption fine-tune, described in the [repo](https://github.com/QwenLM/Qwen3-Omni) as producing "detailed, low-hallucination captions for arbitrary audio inputs". It is Apache-2.0 ([weights](https://huggingface.co/Qwen/Qwen3-Omni-30B-A3B-Captioner)) and hosted on DashScope international at $3.81 / 1M in, $3.06 / 1M out; 12.5 tokens per second of audio; up to 40 minutes, ≤10 MB base64, though the card warns "Excessively long audio clips may diminish detail perception" and recommends ≤30 s. Its music scores: **GTZAN genre 93.1%**, MagnaTagATune micro-F1 46.8, MTG Genre F1 39.5, **MTG Mood/Theme F1 21.7**, RUL-MuchoMusic 52.1, MMAU 77.5. Note the gap between genre and mood — it names instruments and styles well and reads *vibe* poorly, which is exactly the axis a title like "the summer camp song" lives on.

The captioner has one hard constraint, quoted from its docs: **"Text prompts are not supported"**, and system messages "cannot change behavior". It emits an English free-text caption, no JSON, no steering. It can only ever be the *describer* in a two-step, with the Scribe writing the title from its caption — the same shape as Mureka's `song/describe`.

International (Singapore) prices per 1M tokens, from [model pricing](https://www.alibabacloud.com/help/en/model-studio/model-pricing):

| Model | Text in | Audio in | Text out |
|---|---|---|---|
| `qwen3.5-omni-flash` | $0.4 | $3 | $2.2 |
| `qwen3.5-omni-plus` | $1.4 | $11 | $8.3 |
| `qwen3-omni-flash` | $0.43 | $3.81 | $3.06 |
| `qwen-omni-turbo` | $0.07 | $4.44 | $0.63 |
| `qwen3-omni-captioner` | $3.81 (all input) | — | $3.06 |

New accounts get "1 million tokens valid for 90 days". **DashScope is effectively the only hosted path**: OpenRouter carries Qwen ASR and TTS but no omni audio-in model; Fireworks hosts `qwen3-omni-30b-a3b-instruct` but its page says "Serverless: Not supported" (dedicated GPU only); no Qwen omni audio-understanding endpoint was found on DeepInfra or Replicate.

### 4b. NVIDIA Audio Flamingo and Music Flamingo — the best music numbers, the wrong licence

[Music Flamingo](https://research.nvidia.com/labs/adlr/MF/) is built on the Audio Flamingo 3 backbone and is exactly the model this task describes: "designed to advance music (including song) understanding", producing "long-form narratives that connect technical attributes with emotional storytelling" over "harmony, structure, timbre, lyrics, and cultural context", with "~15-minute audio inputs with a 24k-token context window for full-track reasoning". Its published results are the best in the field: **MuChoMusic 74.58** against a prior best of 52.10, **MMAU-Pro-Music 65.60** against 64.90, **MusicCaps 8.8** GPT5 score against 7.2.

And it is unusable here. The [model card](https://huggingface.co/nvidia/music-flamingo-hf) — 8B params, "WAV/MP3/FLAC", "Max Audio Length: 20 Minutes", processing "audio in 30-second windows with a 10-minute total cap per sample", output "Text (and optional speech)" — carries the **NVIDIA OneWay Noncommercial License** and states plainly: *"This model is for non-commercial research purposes only."* The card also notes the model "isn't deployed by any Inference Provider". NVIDIA's own live catalogue at `https://integrate.api.nvidia.com/v1/models` returns no model whose id contains "flamingo", so there is no NIM either. Audio Flamingo 3 is under the same licence; Replicate's community mirror `zsxkib/audio-flamingo-3` (~$0.025/run) restates the restriction on its own page. There is a free [Space](https://huggingface.co/spaces/nvidia/music-flamingo) for hand-testing.

Thereish is not a commercial product today, but it is deployed on a public VPS behind a domain, and building a shipping feature on a noncommercial licence is a trap that only springs later. **Rule it out, and note it as the ceiling the hosted models are being measured against.**

### 4c. MU-LLaMA, MusiLingo, LP-MusicCaps, CLAP, MERT — research artefacts, and a licence trap

These are the academic music-captioning and music-embedding lines. **None has a hosted API** (one exception below): they are `pip install` and a GPU, which the VPS does not have — the same constraint that ruled out self-hosted Kokoro in [tts-for-the-assayers-voice.md](tts-for-the-assayers-voice.md) §1d. Their licences vary more than their capabilities:

| Model | Licence | Hosted |
|---|---|---|
| [LP-MusicCaps](https://github.com/seungheondoh/lp-music-caps) | MIT | demo Space only |
| [SonicVerse](https://huggingface.co/amaai-lab/SonicVerse) | Apache-2.0 (but see MERT below) | demo Space only |
| [MU-LLaMA](https://github.com/shansongliu/MU-LLaMA) | **GPL-3.0** | no |
| [MusiLingo](https://github.com/zihaod/MusiLingo) | **CC-BY-NC-4.0** | no |
| [SALMONN](https://github.com/bytedance/SALMONN) | Apache-2.0; general audio, not music-specialised | no |
| [LLark](https://github.com/spotify-research/llark) (Spotify) | code Apache-2.0, **weights never released** | no |

CLAP and MERT are a different shape again — they emit **embeddings and tag scores, never free text**. `laion/larger_clap_music` is Apache-2.0 and is the one model in this whole survey with a working HuggingFace hosted inference path; MERT (`m-a-p/MERT-v1-330M`) is **CC-BY-NC-4.0**. That last fact is contagious: MU-LLaMA, MusiLingo and SonicVerse all use MERT as their encoder, so a permissive wrapper licence does not make the stack permissive. CLAP could score a track against a fixed adjective vocabulary and let us assemble a title ourselves — a real fallback, but a much duller one than a sentence of prose.

### 4d. Commercial music taggers

**[Cyanite.ai](https://cyanite.ai/)** is the mature one, and it is better than it first looks: its GraphQL `AudioAnalysisV7Result` includes a genuine free-text field, **`transformerCaption: String` — "Auto description for the audio track"** — alongside genre, subgenre, mood, `instrumentPresence`, BPM, key, energy and valence–arousal ([api-docs.cyanite.ai](https://api-docs.cyanite.ai/)). Constraints: **MP3 only, ≤15 minutes**, and integration requires a **public webhook URL** because results are pushed rather than returned. Pricing is a calculator rather than a rate card ([pricing.cyanite.app](https://pricing.cyanite.app/), example monthly fee €290), but the [FAQ](https://cyanite.ai/faq/) says free accounts get API access with 5 songs a month — enough to see what the caption actually reads like before spending anything.

**[Music.AI](https://music.ai/pricing/)** (formerly Moises) resells Cyanite's tagging as a "Music Metadata (by Cyanite)" module at **$0.15 / minute**, pay-as-you-go with no floor, plus instrument detection at $0.02/min — but it exposes the *tags*, not the `transformerCaption`. Its terms state "Music AI never trains with your data".

**[TrackTag](https://tracktag.me/developers)** is the best-documented small vendor: MP3/WAV/FLAC/AIFF/M4A/OGG, 60 MB by URL or 15 MB inline, nine fields on the core tier and 35 on "Ultra" including descriptions and production notes, at fully public pricing of $20 for 50 credits up to $499 for 5,000 (~$0.10 a track). Test keys return samples free. Caveat: **tracks over five minutes are analysed from the opening section only** — irrelevant for our two-to-three-minute instrumentals.

Ruled out, with reasons, so nobody re-checks them: **Spotify's audio-features and audio-analysis endpoints have been closed to new applications since 2024-11-27** and never accepted uploads anyway ([announcement](https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api)). **AcousticBrainz shut down in February 2022** ([post](https://blog.metabrainz.org/2022/02/16/acousticbrainz-making-a-hard-decision-to-end-the-project/)). **Hume's Expression Measurement API was sunset on 2026-06-15** — the TypeScript SDK v0.16.0 release note reads "Removed the Expression Measurement API, following its sunset on 6/15/2026" — and even alive it measured speech prosody, vocal bursts and faces, never instrumental music; Hume remains a voice-*out* vendor for us. **ElevenLabs** offers Scribe v2 transcription, which annotates non-speech `audio_event` items but has no music-analysis endpoint. **AudioShake** does separation, transcription and binary music detection, not tagging. **Musixmatch** has no audio-upload endpoint at all. **Essentia** is alive and its MTG-Jamendo classifiers cover 87 genres and 56 moods, but the library is **AGPL** — whose network clause reaches a game backend — and the models are **CC BY-NC-SA 4.0**. Beatoven, Bridge.audio, MatchTune, AIMS and Sonoteller are sales-gated or undocumented; Musicube's domain no longer resolves.

---

## 5. Independent evidence on whether any of this actually works

Two published results should temper enthusiasm.

**MMAU** ([arXiv 2410.19168](https://arxiv.org/abs/2410.19168)) covers "speech, non-speech sounds, and music" across 27 tasks. When it was published, "even the most advanced Gemini Pro v1.5 achieves only 52.97% accuracy" and "the state-of-the-art open-source Qwen2-Audio achieves only 52.50%". Scores have climbed a long way since — Gemini 3.1 Pro at 82.5% on Inkling's card — but the benchmark exists because this was hard.

**MuChoMusic** ([arXiv 2408.01337](https://arxiv.org/abs/2408.01337)) is 1,187 human-validated multiple-choice questions over 644 tracks, built specifically for music. Its headline finding was "an over-reliance on the language modality, pointing to a need for better multimodal integration", and even the best models answered under half the questions correctly.

**And the sharpest one for our purposes:** *Investigating Modality Contribution in Audio LLMs for Music* ([arXiv 2509.20641](https://arxiv.org/abs/2509.20641)) opens "it is unclear if they are truly listening to the audio or just using textual reasoning" and finds that on MuChoMusic **the more accurate model relied more heavily on text**, while still localising key sound events. Read that against our own setup and the risk is obvious: a model handed both the Gives *and* the audio may quietly title from the Gives while appearing to have listened. **Any experiment must include an audio-only arm — no Gives in the prompt — or it proves nothing.**

---

## 6. The other keys already in the vault

- **OpenAI.** `gpt-4o-audio-preview` was shut down on 2026-05-07; the current audio-input models are `gpt-audio-1.5` and `gpt-audio-mini` (Chat Completions only) and `gpt-realtime-2.1` (Realtime only). `gpt-audio-1.5` takes "text, audio" in and out, 128,000 context, at **$2.50 text in / $32.00 audio in / $10.00 text out / $64.00 audio out** per 1M tokens ([model page](https://developers.openai.com/api/docs/models/gpt-audio-1.5)); `gpt-audio-mini` charges $10.00 / 1M for audio input ([pricing](https://developers.openai.com/api/docs/pricing)). The [audio guide](https://developers.openai.com/api/docs/guides/audio) shows WAV and MP3 as base64, states no duration or size limit, and says nothing about non-speech or music. Two structural gotchas: the **Responses API does not accept audio input** (the model page lists `v1/responses` as not supported), and **Structured Outputs is not among the audio models' supported features** — streaming, function calling and prompt caching are, so a JSON title would have to come through a tool definition rather than `response_format`. No tokens-per-second-of-audio rate is published, so the per-clip cost is **not computable**; at $32 / 1M it is an order of magnitude above every other option regardless of the rate.
- **Anthropic.** The Claude API has **no audio input**, and this is stated four ways: the [models overview](https://platform.claude.com/docs/en/about-claude/models/overview) says "All current models support text and image input, text output"; the [Messages API](https://platform.claude.com/docs/en/api/messages) content-block union has no `audio` type; the [Files API](https://platform.claude.com/docs/en/build-with-claude/files) MIME table has no `audio/*` row; and the [OpenAI-compatibility layer](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk) says outright "Audio input is not supported; it will be ignored and stripped from input". [Vision](https://platform.claude.com/docs/en/build-with-claude/vision) documents images and PDFs only. There is no beta. Out of scope.
- **ElevenLabs and Hume.** Both are audio-*out* houses for our purposes and were surveyed for the Assayer's voice in [tts-for-the-assayers-voice.md](tts-for-the-assayers-voice.md). ElevenLabs' only audio-in product is Scribe v2 transcription; Hume's Expression Measurement API — the one thing that might have qualified — **was sunset on 2026-06-15** and was speech-prosody analysis in any case (§4d).
- **SambaNova.** Newly keyed, and — per §3a — has no audio product at all. The key is useful for text roles, not this one.

---

## 7. What one Page costs

Arithmetic, not estimates. Every row is `(audio tokens × audio input price) + (100 text tokens × text input price) + (50 output tokens × output price)`, using the published rates cited above. Audio tokens are `seconds × the vendor's published rate`. Where the vendor does not publish a rate, the row says so rather than guessing.

| Model (host) | Audio tokens/s | 30 s clip | 150 s clip | Working (30 s) |
|---|---|---|---|---|
| **Text-only baseline** — title from the Gives, `gemini-3.8-flash`, ~200 in / 30 out | n/a | **$0.00026** | same | 200 × $0.75/1M + 30 × $3.75/1M |
| `gemini-3.5-flash-lite` | 32 | **$0.00044** | **$0.00160** | (960 + 100) × $0.30/1M + 50 × $2.50/1M |
| `gemini-3.1-flash-lite` | 32 | **$0.00058** | **$0.00250** | 960 × $0.50/1M + 100 × $0.25/1M + 50 × $1.50/1M |
| `qwen3.5-omni-flash` (DashScope Intl) | 7 | **$0.00078** | **$0.00330** | 210 × $3/1M + 100 × $0.4/1M + 50 × $2.2/1M |
| `gemini-3.8-flash` | 32 | **$0.00098** | **$0.00386** | (960 + 100) × $0.75/1M + 50 × $3.75/1M |
| `mistralai/Voxtral-Small-24B-2507` (DeepInfra) | billed per minute | **$0.00150** | **$0.00750** | 0.5 min × $0.003/min — *speech model, no music claim* |
| `qwen3-omni-captioner` (DashScope Intl) | 12.5 | **$0.00158** | **$0.00729** | 375 × $3.81/1M + 50 × $3.06/1M |
| TrackTag Ultra | per track | **$0.10** | **$0.10** | $499 / 5,000 credits |
| Music.AI "Music Metadata (by Cyanite)" | per minute | **$0.075** | **$0.375** | 0.5 min × $0.15/min |
| Cyanite direct | — | free tier 5 tracks/month; paid is a quote (example €290/mo) | | |
| `muse-spark-1.2` (Meta Model API) | **not published** | not computable | not computable | $1.25/$4.25 per 1M, rate withheld by design |
| `thinkingmachines/Inkling-Small` (DeepInfra) | **not published** | not computable | not computable | $0.45/$1.20 per 1M |
| `thinkingmachines/Inkling` (DeepInfra) | **not published** | not computable | not computable | $0.95/$4.05 per 1M |
| `gpt-audio-1.5` (OpenAI) | **not published** | not computable | not computable | $32/1M audio in dominates whatever the rate is |
| Mureka `POST /v1/song/describe` | n/a | **not published** | **not published** | no per-endpoint price list exists |

For scale: Foley already pays Mureka for the track itself on every uncached Page, and no official per-generation price is published either. Every computable row above is a fraction of a cent. **Cost is not the deciding variable here; correctness and latency are.**

---

## 8. Latency

**No vendor in this survey publishes a latency figure for an audio-input request.** Not Google, not Meta, not Thinking Machines, not DeepInfra, not Alibaba, not OpenAI. What is known is structural: the title is not on the critical path. A Mureka track takes 30–90 s to arrive (design brief, *Foley*), the Author is running in parallel, and the Track is cached by Give set. A titling call that takes two seconds after the MP3 lands costs nobody anything, and the deterministic title-from-Gives fallback already specified means a slow or failed call degrades to a title rather than to nothing.

---

## 9. Comparison, and what it implies

| Candidate | Exists? | Audio in | Music evidence | JSON | 150 s cost | Blocker |
|---|---|---|---|---|---|---|
| `gemini-3.8-flash` | yes | MP3 direct, 20 MB inline, 32 tok/s | vendor claim; Gemini 3.1 Pro = 82.5 MMAU on a rival's card | 3-series feature; audio combo undocumented | $0.0039 | none |
| `gemini-3.5-flash-lite` | yes | as above, audio at text price | none published | as above | $0.0016 | none |
| Mureka `song/describe` | yes | MP3/M4A URL or 10 MB base64 | it is a music company's music model | fixed 4-field schema | not published | returns tags, not a title; price opaque |
| `qwen3-omni-captioner` | yes | MP3, hosted on DashScope Intl | GTZAN 93.1, MuchoMusic 52.1; mood F1 only 21.7 | caption only | $0.0073 | **no text prompt at all**; new vendor |
| `qwen3.5-omni-flash` | yes | MP3, 7 tok/s, 3 h | **RUL-MuchoMusic 72.4 vs Gemini 3.1 Pro 59.6**; MMAU 82.2 | undocumented | $0.0033 | new vendor, new region |
| `muse-spark-1.2` (Meta) | yes | MP3 direct, 50 MB inline | none published | schema-enforced | not computable | 1.3 regressed on audio; no music evidence |
| `Inkling` (DeepInfra) | yes | 16 kHz WAV only | MMAU 77.2 (below Gemini) | no schema enforcement | not computable | transcode step; loses to Gemini on its own card |
| `MiniMax-M3` (SambaNova / MiniMax) | yes | **no** | — | yes | — | cannot hear |
| Music Flamingo (NVIDIA) | yes | MP3, 20 min | MuChoMusic 74.58 — best published | text | self-host only | **noncommercial licence** |
| MU-LLaMA / MusiLingo / LP-MusicCaps | yes | weights only | research | text | GPU you own | no hosted API, no GPU; GPL / CC-BY-NC in two of three |
| CLAP / MERT | yes | weights only | embeddings | — | CLAP free on HF | cannot write prose; MERT is CC-BY-NC |
| Cyanite / Music.AI / TrackTag | yes | MP3 upload | it is their whole business | fixed fields; Cyanite has a `transformerCaption` | $0.075–$0.10 | new vendor; Cyanite needs a webhook and a quote |
| `gpt-audio-1.5` / `gpt-audio-mini` | yes | WAV/MP3 | none published | **not supported** — use function calling | not computable | $32 and $10 /1M audio in; Chat Completions only |
| Claude | — | **no** | — | — | — | audio "ignored and stripped from input" |
| "Muse Spark 1.2" as a *music* model | **no such thing** | — | — | — | — | it is Meta's general reasoning model |

**Usage rights for sending generated music to a third party.** Mureka grants "full usage rights and commercial authorization" over what it generates, so the audio is ours to send. **No vendor in this survey publishes any clause permitting or prohibiting uploads of AI-generated audio** — they are uniformly silent, and Cyanite and Music.AI both *sell* AI-music detection, so the case is plainly contemplated. The real rights problems are on the model side, not the audio side: Music Flamingo and Audio Flamingo are **noncommercial**, MERT and everything built on it is **CC-BY-NC**, MU-LLaMA is **GPL-3.0**, Essentia is **AGPL** with **CC-BY-NC-SA** models, and Meta's `-contributor` tier is a twelvefold discount bought by letting Meta train on your data. Thinking Machines' [acceptable-use policy](https://thinkingmachines.ai/model-acceptable-use-policy/) governs outputs rather than inputs, but forbids passing model output off as human-written — worth a glance if titles are ever presented as the Scribe's own.

**Recommendation.** Yes, run the experiment — but run it as one cheap fork of the model already in the game, not as a vendor evaluation. Add a second Scribe job that sends the finished MP3 to `gemini-3.8-flash` with a response schema for `{title, description}`, at about **$0.004 per Page for a whole 150 s track and $0.001 for a 30 s excerpt**, against **$0.00026** for titling from the Gives — a difference of well under a cent on a Page that already costs cents in music generation, and one that Foley's ear has already proved it can make (the same model, the same inline-audio path, the same JSON discipline). Three conditions make it an experiment rather than a feature: score the audio arm **blind against the text arm** on a handful of real Pages with Jacob and his wife picking the better title, since the only thing that matters is whether "the summer camp song" is more findable than "Viking Beaches"; run at least one arm **audio-only, with the Gives withheld**, because arXiv 2509.20641 shows audio LLMs lean on text when both are present and an unblinded test would flatter the audio arm for free; and keep the deterministic Gives-based title as the fallback the decision already specifies, so a failure is invisible. If Gemini's titles turn out to be generic, there are two next calls and they answer different questions. **Mureka's own `POST /v1/song/describe`** — same vendor, same key, no new billing, four structured fields of instrumentation, genre, tags and a description sentence — is the cheapest way to find out whether the problem is the ear or the pen, because it hands the Scribe raw perception and lets the Scribe do the writing. And **`qwen3.5-omni-flash` on DashScope international** ($0.0033 for a whole 150 s track, seven audio tokens a second, MP3 direct, prompt-steerable) is the only candidate with published evidence of actually hearing music better than Gemini: RUL-MuchoMusic 72.4 against Gemini 3.1 Pro's 59.6. That is the one arm worth the cost of a new vendor key, and only after the blind test says Gemini's ear is the weak link. Everything else here is either deaf (MiniMax-M3, Claude), unlicensed (Music Flamingo — which has the best music scores of anything, which is a genuine shame), unhosted (MU-LLaMA, MERT), voiceless (CLAP, and the commercial taggers, which return fields rather than a phrase), unpriceable in advance (Muse Spark, Inkling, `gpt-audio-1.5`), or a new vendor relationship bought to reach a place Gemini already stands.

**Could not verify.** Whether Gemini's `responseSchema` works alongside audio input (nothing says it does not; nothing says it does). OpenAI's duration and file-size limits for chat audio, and whether OpenAI's usage policies say anything about music — the policy page refuses to be fetched. The per-second audio-token rates for Muse Spark, Inkling and the OpenAI audio models, all deliberately unpublished. Mureka's price for any single endpoint. Cyanite's actual API rate card. The Audio Flamingo Next weights licence, where the arXiv page reads CC BY 4.0 but every model card says OneWay Noncommercial — the cards are the ones that bind. Music Flamingo's own parameter count and duration cap, which NVIDIA's research page (7B, ~15 min) and its HuggingFace card (8B, 20 min) disagree about.

---

## Sources

All fetched 2026-09-06.

**Mureka**
- OpenAPI document loaded by the docs site: `https://platform.mureka.ai/docs/assets/chunks/theme.Cv864CFs.js` (schemas `InstrumentalTask`, `Instrumental`, `SongTask`, `Song`, `SongDescribeReq`, `SongUnderstandResp`, `AccountBillingResp`)
- https://platform.mureka.ai/docs/ — endpoint index
- https://platform.mureka.ai/docs/api/operations/post-v1-instrumental-generate.html
- https://platform.mureka.ai/docs/api/operations/post-v1-song-describe.html
- https://platform.mureka.ai/docs/en/changelog.html
- https://platform.mureka.ai/docs/en/faq.html

**Google / Gemini**
- https://ai.google.dev/gemini-api/docs/audio
- https://ai.google.dev/gemini-api/docs/pricing
- https://ai.google.dev/gemini-api/docs/structured-output
- https://ai.google.dev/gemini-api/docs/models

**Meta**
- https://dev.meta.ai/docs
- https://dev.meta.ai/docs/models/
- https://dev.meta.ai/docs/pricing-rate-limits.md
- https://dev.meta.ai/docs/structured-output.md
- https://dev.meta.ai/docs/file-handling.md
- https://dev.meta.ai/docs/token-counting.md
- https://developer.meta.com/ai/resources/blog/build-with-muse-spark/

**SambaNova / MiniMax**
- https://docs.sambanova.ai/cloud/docs/get-started/supported-models
- https://cloud.sambanova.ai/plans/pricing
- https://www.minimax.io/models/text/m3
- https://platform.minimax.io/docs/guides/text-generation
- https://platform.minimax.io/docs/api-reference/api-overview
- https://platform.minimax.io/docs/guides/pricing-paygo

**Thinking Machines / DeepInfra / Mistral**
- https://thinkingmachines.ai/model-card/inkling/
- https://thinkingmachines.ai/model-acceptable-use-policy/
- https://deepinfra.com/thinkingmachines/Inkling
- https://deepinfra.com/thinkingmachines/Inkling-Small
- https://deepinfra.com/models/automatic-speech-recognition
- https://deepinfra.com/pricing
- https://openrouter.ai/thinkingmachines/inkling
- https://huggingface.co/mistralai/Voxtral-Small-24B-2507

**Alibaba / Qwen**
- https://www.alibabacloud.com/help/en/model-studio/qwen-omni
- https://www.alibabacloud.com/help/en/model-studio/qwen3-omni-captioner
- https://www.alibabacloud.com/help/en/model-studio/model-pricing
- https://github.com/QwenLM/Qwen3-Omni
- https://huggingface.co/Qwen/Qwen3-Omni-30B-A3B-Captioner
- https://huggingface.co/papers/2604.15804 — Qwen3.5-Omni
- https://openrouter.ai/qwen · https://fireworks.ai/models/fireworks/qwen3-omni-30b-a3b-instruct

**NVIDIA**
- https://research.nvidia.com/labs/adlr/MF/
- https://huggingface.co/nvidia/music-flamingo-hf
- https://huggingface.co/nvidia/audio-flamingo-3
- https://github.com/NVIDIA/audio-flamingo
- https://arxiv.org/abs/2511.10289 — Music Flamingo
- `https://integrate.api.nvidia.com/v1/models` — NVIDIA hosted-model catalogue (no "flamingo" entry)

**Research music models**
- https://github.com/seungheondoh/lp-music-caps · https://huggingface.co/amaai-lab/SonicVerse
- https://github.com/shansongliu/MU-LLaMA · https://github.com/zihaod/MusiLingo
- https://github.com/bytedance/SALMONN · https://github.com/spotify-research/llark
- https://huggingface.co/laion/larger_clap_music · https://huggingface.co/m-a-p/MERT-v1-330M

**OpenAI / Anthropic**
- https://developers.openai.com/api/docs/guides/audio
- https://developers.openai.com/api/docs/models/gpt-audio-1.5
- https://developers.openai.com/api/docs/pricing
- https://platform.claude.com/docs/en/build-with-claude/vision
- https://platform.claude.com/docs/en/about-claude/models/overview
- https://platform.claude.com/docs/en/api/messages
- https://platform.claude.com/docs/en/build-with-claude/files
- https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk

**Benchmarks**
- https://arxiv.org/abs/2410.19168 — MMAU
- https://arxiv.org/abs/2408.01337 — MuChoMusic
- https://arxiv.org/abs/2509.20641 — Investigating Modality Contribution in Audio LLMs for Music

**Commercial taggers, and the ones that are gone**
- https://cyanite.ai/ · https://api-docs.cyanite.ai/ · https://pricing.cyanite.app/ · https://cyanite.ai/faq/
- https://music.ai/pricing/
- https://tracktag.me/developers
- https://developer.spotify.com/blog/2024-11-27-changes-to-the-web-api — audio-features closed to new apps
- https://blog.metabrainz.org/2022/02/16/acousticbrainz-making-a-hard-decision-to-end-the-project/
- https://dev.hume.ai/intro — Expression Measurement absent following its 2026-06-15 sunset
