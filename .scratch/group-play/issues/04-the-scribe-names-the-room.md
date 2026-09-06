# 04: The Scribe names the Room

**What to build:** When a phone that has played before creates a Room, the Code nods to that history — a couple that melded on candy cane last night might be handed CANE tonight. The Scribe reads the digests of the Rooms this phone holds Seats in and answers with one four-letter word; the game checks it and uses it. A phone with no history, a slow model, or a word the gate refuses twice all get a random word, and nobody at the table waits more than a moment.

**Blocked by:** 03 (Rooms are created by Code).

**Status:** ready-for-human

This is the Scribe's first job (CONTEXT.md: callbacks are the Scribe's), and the role's seat in the Steward's configuration; the Scribe proper — recaps and the Vale gate — is `.scratch/scribe/issues/01`.

**Since this was filed**, `scribe/01` shipped and built the seat: the `scribe` role exists in `config/config.exs` with the API key and retry count on the role and a `jobs:` list under it, read by `MeaningGame.Steward.role/2`. This ticket adds a `naming:` job beside `recap:` — Gemini 3.8 Flash, its own short timeout and deadline — and inherits the rest. The digest to read is `Chronicle.digest/1` (the Author's) rather than `scribe_digest/2`, which is the recaps folded in and is about the Scribe's own past prose.

**The seam.** The Steward behaviour gains a naming callback: given a list of Chronicle digests and the Codes already taken, answer with one word. Both adapters satisfy it. The fake answers a configured word, or nothing when configured to, so a test can assert either the word was used or the fallback drew a real one.

**The role.** A `scribe` role in configuration: Gemini 3.8 Flash at low effort, because a table is waiting; one request, no hedging; a short timeout and a deadline shorter than the Assayer's, both settings. The prompt asks for one real English word of four letters that nods to the history, avoiding the taken Codes, and the schema is one string. The digest it reads is the same digest the Author already reads for a Give.

**The gate has the last word** (design law 14): four letters, in the ENABLE list, not profane, not an existing Code. A failing answer is asked for once more; then the Room draws a random word as in 03. No history means no model call. A model that raises, times out, or is refused is the fallback, never a failed creation.

- [x] Creating a Room from a phone with history asks the Scribe once with that phone's digests and the taken Codes, and uses the word when the gate accepts it
- [x] The gate rejects a word that is not four letters, not in the dictionary, profane, or already a Code; one retry, then a random word
- [x] Creating a Room from a phone with no history makes no model call and draws a random word
- [x] A Scribe that is slow past its deadline, raises, or answers nothing valid falls back to a random word and creation still succeeds within the configured wait
- [x] The scribe role is configuration with model, effort, timeout and deadline, and the fake adapter answers a configured word
- [x] Steward tests cover the gate, the retry, the fallback and the no-history path; a Room test asserts the configured fake word becomes the Code
- [x] One tagged live smoke test names a Room from a real digest once by hand
- [ ] Verified on the real deployment: a Room created from Jacob's phone gets a word that nods to the couch's Chronicle

**Since this was filed (2026-09-05, ADR-0011).** Nothing here changes shape. Two facts to carry: the digest the Scribe reads now includes each Seat's Gives and the Bookends the Author wrote from them, which is richer material for a nod than the old pool's Chapters; and `MeaningGame.Steward.Legality.dictionary/0` — the ENABLE list the gate and the random word draw from — stays even though player Bridges no longer pass a dictionary check, because a Code still has to be a word.
