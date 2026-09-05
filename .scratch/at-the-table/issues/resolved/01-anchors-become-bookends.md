# 01: Anchors become Bookends

**What to build:** The game says Bookends everywhere it said Anchors, and nothing else changes. A prefactor: the rules' state and views, the Room's snapshot, the components' data roles, the Chronicle's tables (attempts, verdicts, fairness taps, precedents — one migration), the calibration export and the Markdown export all use the new word, and the export's reader still accepts old `Anchors:` lines so earlier exports round-trip. Every test is green with only the rename applied, and the game plays exactly as before. Spec: `.scratch/at-the-table/spec.md`; glossary: `CONTEXT.md` (Bookends).

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The rules, the Room snapshot and every component use `bookends` / `next_bookends`; nothing in `lib/` says "anchor" except the export reader's compatibility clause
- [x] One migration renames the `anchors` columns on attempts, verdicts, fairness taps and precedents; precedents look up by the renamed key with no change in behaviour
- [x] The Markdown export writes `Bookends:` and its reader parses both `Bookends:` and `Anchors:`; the calibration export's field is renamed
- [x] The test suite passes with the rename and no other change; the two-Seat rules, Room and LiveView tests are otherwise untouched
- [x] Deployed; a Page plays from Bookends to reveal as before

## Answer

All occurrences of "anchor" / "anchors" / "Anchors" have been systematically renamed to "bookend" / "bookends" / "Bookends" across:
1. Rules state, snapshots, and views (`lib/meaning_game/game.ex`, `lib/meaning_game/rooms/server.ex`).
2. HTML attributes, view assigns, and LiveView components (`lib/meaning_game_web/`).
3. Chronicle schemas, calibration exports, and Markdown export/import (`lib/meaning_game/chronicle/`). The Markdown parser accepts legacy `- Anchors:` lines for backwards compatibility with earlier exports.
4. Steward assay, author, and fake implementations (`lib/meaning_game/steward/`).
5. Database tables via migration `20260906110000_anchors_become_bookends.exs` renaming `:anchors` to `:bookends` on `chronicle_attempts`, `chronicle_fairness_taps`, `precedents`, `chronicle_overrules`, and `authored_pages`.
6. Seeds in `priv/repo/seeds.exs`.
7. Entire test suite, passing with 433 tests and 0 failures.
