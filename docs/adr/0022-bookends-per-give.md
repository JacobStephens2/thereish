---
status: accepted
---

# Full table's dial is Bookends per Give, not one Bookend per Seat

ADR-0016 made Full table mean one Bookend per Seat, on by default, because two nights of play said the game was too easy. At two Seats that rule is a no-op: two Seats, two Bookends, which is exactly the game ADR-0016 was written to make harder. That is issue #115 — a Meld on Attempt 2 at two Seats — which was closed on 2026-09-12 without a fix, and it is the reason the couch still finds 2P too easy. Decision (2026-10-23): Full table's promise is **a word per Seat at the least**, and its dial is **Bookends per Give**. The count is `seats × bookends_per_give`, capped at `max_bookends` so a large table is not drowned, and floored at one per Seat so the promise is kept whatever the knobs say. At the shipped knobs — two per Give, six at most — two Seats open on four words, three on six, and six or eight on one each.

Difficulty becomes a function of seat count by design rather than by accident. The floor outranks the ceiling, in that order, for a reason: eight Seats get eight words even though the cap says six, because a Seat with no word of its own on the table has lost the thing ADR-0016 called the point as much as the difficulty.

Once the count can run past the Gives, one Give must head more than one Bookend, so the Author's gate trades uniqueness for coverage: with more Bookends than Gives, every Give must head at least one Bookend, and no setting may be left out. Below that, two Bookends from one Give is still a refusal.

## Considered options

- **Three Bookends flat at two Seats.** Rejected: a constant is a number nobody can tune, and the same constant is wrong at six Seats.
- **A difficulty setting with names (easy / hard).** Rejected: the Room already has Full table, and a named difficulty invites the table to argue about the label rather than the words.
- **Widening by Attempt instead — one more Bookend each miss.** Not rejected, deferred: that is Rungs, filed as its own idea, and it wants this PR's arm read first. Two dials moving at once measure nothing.
- **Having the Author re-author each Attempt's Bookends** (the other half of issue #163). Deliberately not built here: width is one change, and re-authoring the carry-forward would rewrite what a miss means (ADR-0010's carry) in the same PR that changes how wide it is.

## Consequences

- `bookends_per_give` and `max_bookends` are configuration beside `attempts_per_page`: the couch's difficulty dial, and the Arm that reads it is meld rate and mean attempts.
- The Author's prompt bumps (`author-5`) and its gate gains one refusal, "a setting heads no bookend". Cached Pages are unaffected; the Author is asked per Page.
- Two places decided "is this a Full table?" by comparing the count to the number of Gives. Both now ask whether the count is at least the Gives and at least two, so a two-Seat Full table on four words is still a Full table and still gets the Full-table brief.
- ADR-0016 is amended, not superseded: one Bookend per Seat is now the floor of this rule rather than the whole of it.
