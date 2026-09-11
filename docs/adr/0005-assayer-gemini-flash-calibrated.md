---
status: accepted
---

# Gemini 3.8 Flash at low effort is the live Assayer, calibrated, and it quips live

The Steward prototype (`prototype/keeper/REPORT.md` on tag `archive/prototype-keeper`) found three candidate models that fit the 2.5 s reveal beat from the VPS: GLM 5.3-Flash (fastest, noisiest — repeat range up to 35 points, one 85-point ordering swing), Gemini 3.8 Flash at low effort (GLM-class latency, Opus-class repeatability, grading the 40–75 band 10–15 points more generously than the Anthropic models), and Sonnet 5 at low (fairest, 2 s P50, thin margin). Decision (2026-09-02): **Gemini 3.8 Flash at low**, because design law 1 says consistency beats accuracy — a constant offset is a calibration problem solved once by the couple's ~100-pair labelled eval, while noise makes the first ruling on a borderline pair a dice roll that the cache then freezes as precedent. The meld threshold and ladder bands are set after calibration, not before.

Jacob also chose that the Assayer **quips live**, incorporating the players' actual bridges, rather than firing an Author-prewritten band script: an index-52 model is capable of on-the-fly wit, and a remark that names what each player wrote is more personal than any script. The grade is cached; the quip need not be. Prewritten Author scripts remain the fallback and an A/B arm.

## Considered options

- **GLM 5.3-Flash**: met the latency contingency with room; rejected for noise.
- **Sonnet 5 at low**: fairest grades; rejected for margin (2 s P50 leaves little of the beat for the quip).
- **Opus 5 at low**: misses the P50 rule by ~0.1 s.
- **Kimi K3**: harness ready, unbenched; a later candidate, not a blocker.

## Consequences

Hedging is two identical requests for the fast tier only. The Author's role in Thereish is anchors, bait, deep bridges, the trap's narration, and Chapter walks — not the live joke.
