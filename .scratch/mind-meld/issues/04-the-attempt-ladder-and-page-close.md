# 04: A missed Page converges, then closes and is written to the Chronicle

**What to build:** The players miss. Instead of the Page ending, their two failed Bridges become the next attempt's Anchors, and they try again. After five attempts the Page closes unmelded. A Meld closes it early and visibly. Either way the Page is written into the Chronicle, and "one more?" is a single tap that starts the next one.

This is Medium's carry-forward rule, and it is what turns a miss into a converging arc rather than a dead end.

**Blocked by:** 03.

**Status:** ready-for-agent

- [ ] A miss carries both failed Bridges forward as the next attempt's Anchors
- [ ] The attempt cap is five tries per Page, as named configuration
- [ ] Reaching the cap closes the Page unmelded, and the close reads as an ending rather than a failure state
- [ ] A Meld closes the Page immediately and visibly, so landing it feels like landing it
- [ ] Rules events extend to `attempt_advanced` and `page_closed`; the rules module stays pure
- [ ] Every closed Page is written to the Chronicle as append-only event rows, with the Page document stored as JSONB. Rows reference Seats, never Accounts
- [ ] Chronicle writes cover the Page, each attempt, and each verdict, with model, prompt version, timings, and cost carried on the verdict rows
- [ ] "One more?" is one tap and starts a fresh Page in the same Room with the same Seats
- [ ] A Page fits ten to fifteen minutes at the couch, checked by playing one
- [ ] Rules tests cover carry-forward, the cap closing a Page, and a Meld closing it early
- [ ] Persistence tests run against real Postgres through the Ecto sandbox. No mock repository
