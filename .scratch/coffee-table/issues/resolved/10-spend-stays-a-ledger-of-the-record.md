# 10: Spend stays a ledger of the record

**What to build:** Three small honesties about money. The spend page and each Room's Chronicle foot say how many Pages are in play and not yet counted — Rooms whose process is running and whose Phase is bridging, assaying or reveal — as a sentence omitted when the count is zero, so a Page Jacob is looking at is never forty invisible cents. A spoken quip that fails is recorded on its Attempt's Verdict — provider, voice, zero cost and the reason — the way a failed score is recorded on the Page, so the book can say a quip went unspoken; the spend page counts it as a Foley call at zero, as it counts a failed score. And the Scribe's recap job moves to low effort, with `xhigh` kept as a one-line commented alternative: the ten recaps to date were $0.71 of the $0.80 ever spent. Spec section: Spend and the record.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The spend page shows "N Pages in play, not yet counted" when N > 0 and nothing when N = 0; a Room's Chronicle foot does the same for that Room (0 or 1)
- [x] A speak task that fails records `voice_meta` for its Attempt with provider, voice, `cost_usd` 0.0 and a `failure`; it is attached to the Verdict at chronicle time and the spend page counts it as a Foley call at zero
- [x] The `recap` job's effort is `low`, with `xhigh` as a commented alternative and the reason in the comment; a test asserts the configured effort reaches the request
- [x] Chronicle tests for the in-play count and the zero-cost failure; Room tests for the recorded voice failure; a spend page test for the sentence present and absent
