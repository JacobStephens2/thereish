---
status: accepted
---

# Sides retired: one Verdict for every Room

ADR-0012 added Sides so two couples could race on the same Bookends, with a three-request grading path, a side-by-side reveal, and an overrule that needed only the proposing Side. After two nights on the two-Bookend rule, that variant is not a game Jacob wants to play, and any work on carry-forward has to route around it. Decision (2026-09-11): **Sides are retired.** A four-Seat Room is one table under ADR-0010: one request per Attempt, the standard reveal at every seat count, and an overrule that needs the whole Room. Partners are not offered. Chronicle rows that already hold side verdicts stay as they are and still render.

## Considered options

- **Keep Sides and build Full table around them.** Rejected: the rival-team path is unused, its grading is three requests, and the next spec would have to special-case it.
- **Leave the pairing calls in place, unused.** Rejected: a four-Seat Room that still asks "I'm with Melissa" is offering a game that is gone.

## Consequences

This supersedes ADR-0012. ADR-0010's one Verdict per Attempt is the rule at every seat count. Pairing, the Sides flag, the three-request Assayer path, and the Sides reveal are removed from the Game, the Room, and the phones.
