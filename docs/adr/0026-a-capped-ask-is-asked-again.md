---
status: accepted
---

# A reply cut off at the token cap is asked for again

The design brief's model policy says "a token-cap overrun is terminal, never retried". That was written for Fable at max effort, where one ask took minutes and an overrun meant the task really was too big. It no longer fits the fast roles. Gemini 3.8 Flash cannot turn thinking off. Now and then, on the Author's 3- and 4-Seat Pages, it thinks for 600–3,100 tokens before writing an answer that is never more than ~90 tokens. That ran out the Author's 400-token cap in 6 of 20 asks measured on 2026-10-26, and the table read "The Author couldn't write from these Gives: too broad or complex" about Gives that were nothing of the kind (Room RELY; Try again worked).

Decision (2026-10-26): `Thereish.Steward.Gate` treats a capped reply like a rejected one. While the role has retries left, it asks again with the same prompt and nothing quoted back, since there is no answer to correct. The Author also sends two requests at once and takes the first good answer, as the Assayer already does. The player-facing reason for a cap is now "it ran long".

## Considered options

- **A bigger cap.** Rejected: an ask that thinks that long takes 7–27 s, past the Room's 8-second Author deadline, so a bigger cap only turns "too broad or complex" into "timed out". The 400 cap stops a runaway thought in about 4.5 s, and a fresh ask usually lands in 2–3 s.
- **Retry the Author only.** Rejected: the Assayer, naming and titles are all Gemini 3.8 Flash behind the same Gate with the same small caps, and they have the same failure. The retry budget is still each role's own `retries`.

## Consequences

- A capped ask costs what it thought, and the retry is counted in the answer's `attempts` and `cost_usd` like any other.
- The Author asks at most four times per Page (two requests, each asked once more), still for well under a cent.
- The Scribe's recap, the one slow role, can now spend one more long ask on a cap. Nobody waits for it.
