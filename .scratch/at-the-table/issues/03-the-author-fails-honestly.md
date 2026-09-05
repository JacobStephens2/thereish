# 03: The Author fails honestly

**What to build:** A slow or broken Author never strands the table. Five seconds after the last Give every screen says the Author is still writing; at the deadline the phones say it could not write from these settings and why, and offer **Try again** (asks the Author once more with the same Gives) and **New settings** (clears every Give and returns to giving). The stage, which sees no Give text, shows "Waiting for settings: 1 of 2" while Gives come in and the same writing and failure states after. A duplicate answer from a retried task changes nothing. Spec sections: The Game (events), The Steward (escalation), The web.

**Blocked by:** 02 (The Page is written at the table).

**Status:** ready-for-agent

- [ ] At five seconds in `writing` every screen says the Author is still writing; the Author's rungs are configuration beside the Assayer's
- [ ] At the deadline, or when the Author task raises, exits, or answers an error, the Room applies `author_failed` with a reason; the phase stays `writing` and every phone shows the reason with Try again and New settings
- [ ] Try again (`author_retried`) clears the failure and owes the Author effect again; New settings (`gives_reset`) clears every Give and returns the Room to `giving`; either Seat may tap either
- [ ] A second `page_written` for a Page that already exists is ignored
- [ ] The stage shows "Waiting for settings: N of M" with no Give text, then the writing animation, then the failure state
- [ ] Rules tests cover each event; a Room test with a slow Fake Author reaches still-writing and then failure and recovers on retry; a LiveView test sees both buttons and their effects on two phones
