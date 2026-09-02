---
status: accepted
---

# Postgres for the Chronicle

The Chronicle is an append-only event log at household scale, where SQLite's single file would be simpler and would let a coding agent query it with no credentials. We chose Postgres (2026-09-01) because Jacob wants hands-on experience with pgvector (semantic recall over past Pages, a later feature), JSONB (the Page document), and LISTEN/NOTIFY; it already runs on the server and is reachable from Docker containers; and Ecto makes the choice cheap to make now. Human- and agent-readable Markdown is rendered on demand from the database, never stored as a second copy.

## Considered options

- **SQLite**: the simplest toy shape. Rejected only on the learning axis; it remains a small Ecto adapter swap while the schema is young.
