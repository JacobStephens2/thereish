# 08: The Chronicle is a book the couple can read and correct

**What to build:** They open the Chronicle and read their history as a book: every Page, every Bridge, every grade, every overrule. Something is wrong or mis-recorded, so they fix it, and the fix is theirs. Jacob renders the whole thing as Markdown on demand, so he and a coding agent can read it without a database client.

Design law 5: memory is a visible, player-editable artifact. Silent forgetting and opaque rulings are the named trust-killers.

**Blocked by:** 04.

**Status:** resolved

- [x] A LiveView book page reads the Chronicle in reverse chronological order, legible on a phone
- [x] A Page in the book shows its Anchors, each attempt, both Bridges, the grade, the band, the reasoning, and any overrule
- [x] Players can correct an entry, and the correction is recorded as another append-only event rather than by mutating history
- [x] Every view is computed from the event log. No stored copy of a view exists anywhere
- [x] An on-demand Markdown render is available both as a mix task and over HTTP
- [x] A Keeper-composed digest of the Chronicle exists for feeding to models later, computed the same way
- [x] Tests: a played Page produces the expected event rows, the book page renders them, an edit appends rather than overwrites, and the Markdown export round-trips a full evening

## Comments

**The Chronicle as a phone-legible book.** `MeaningGameWeb.ChronicleLive` mounts at `/chronicle` and `/r/:slug/chronicle` (also aliased to `/book` and `/r/:slug/book`). It renders Pages in reverse chronological order (`order_by: [desc: :closed_at, desc: :id]`), showing opening anchors, convergence attempts, each player's bridge, grades, bands, reasoning, quips, and overrules.

**Append-only corrections without mutating history.** `chronicle_corrections` (`MeaningGame.Chronicle.Correction`) records player edits as append-only rows. The original rows in `chronicle_pages`, `chronicle_attempts`, and `chronicle_bridges` remain immutable. An inline correction form on each Page allows players to record fixes (target, original value, corrected value, and note), updating the live view immediately.

**Views are computed, never stored.** `MeaningGame.Chronicle.book/1` projects page views in memory directly from Postgres event rows (`Page`, `Attempt`, `Bridge`, `Verdict`, `Overrule`, `Correction`). No stored projection or cached view table exists.

**On-demand Markdown render via Mix task and HTTP.** `GET /chronicle.md` and `GET /r/:slug/chronicle.md` (`MeaningGameWeb.ChronicleController`) export the Chronicle as `text/markdown; charset=utf-8`. `mix chronicle.export` (`Mix.Tasks.Chronicle.Export`) exports the Chronicle to stdout or a designated file path via CLI. `MeaningGame.Chronicle.from_markdown/1` round-trips the exported document back into structured data.

**Keeper-composed digest for models.** `MeaningGame.Keeper.digest/1` and `MeaningGame.Chronicle.digest/1` compose a compact, structured text summary of played Pages, convergence arcs, overrules, and corrections for future Author / Scribe prompt injection. Returns `"Nothing yet; this is the first Page."` when the Chronicle is empty.

