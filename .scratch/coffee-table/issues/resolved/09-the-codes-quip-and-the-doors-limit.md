# 09: The Code's quip, and the door's limit

**What to build:** The Code arrives with a line. When the Scribe names a Room from a phone's history, the same request now also answers a **quip**: one line of at most 90 characters about the Code, in the Assayer's register and the Scribe's voice, naming no player because none exists yet. A Room with no history — which today draws a random word with no model call — makes one quip-only request with the drawn word under the same short deadline, so the Room still opens in a moment and a slow model leaves it without a quip, never without a Room. The quip is stored on the Room and shown beneath the Code on the Code card, in the Stage's header beside the join line, and under each rejoin link on the front page. No page load makes a model call. Because creation now always makes one, creation is rate-limited per device token and per remote address — a small in-memory counter over a sliding hour, generous for a household and closed to a loop; over the limit the door says "Give it a minute" and creates nothing. Spec section: The Code's quip.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The naming request's schema gains `quip`; the gate accepts a non-empty single line of at most 90 characters and drops a failing quip without failing the word
- [x] A Room created from a phone with no history draws its random word and makes one quip-only request under the naming job's deadline; a Fake that is slow, raises or answers nothing leaves the quip empty and creation succeeds within the configured wait
- [x] The Room row gains `quip`; it renders on the Code card, in the Stage's header and under each rejoin link on the front page when present, and nothing renders when absent
- [x] Room creation is limited per device token and per remote address with limits in configuration; the Nth creation in an hour is refused with the door's message and the first after the window is admitted; the counter is in memory and a restart forgets it
- [x] Steward tests for the schema and gate; Room tests for the history and no-history paths and the limit; LiveView tests for the three renderings and the refused door
