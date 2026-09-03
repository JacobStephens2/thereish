# 08: The Chronicle is a book the couple can read and correct

**What to build:** They open the Chronicle and read their history as a book: every Page, every Bridge, every grade, every overrule. Something is wrong or mis-recorded, so they fix it, and the fix is theirs. Jacob renders the whole thing as Markdown on demand, so he and a coding agent can read it without a database client.

Design law 5: memory is a visible, player-editable artifact. Silent forgetting and opaque rulings are the named trust-killers.

**Blocked by:** 04.

**Status:** ready-for-agent

- [ ] A LiveView book page reads the Chronicle in reverse chronological order, legible on a phone
- [ ] A Page in the book shows its Anchors, each attempt, both Bridges, the grade, the band, the reasoning, and any overrule
- [ ] Players can correct an entry, and the correction is recorded as another append-only event rather than by mutating history
- [ ] Every view is computed from the event log. No stored copy of a view exists anywhere
- [ ] An on-demand Markdown render is available both as a mix task and over HTTP
- [ ] A Keeper-composed digest of the Chronicle exists for feeding to models later, computed the same way
- [ ] Tests: a played Page produces the expected event rows, the book page renders them, an edit appends rather than overwrites, and the Markdown export round-trips a full evening
