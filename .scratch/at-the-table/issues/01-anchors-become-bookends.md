# 01: Anchors become Bookends

**What to build:** The game says Bookends everywhere it said Anchors, and nothing else changes. A prefactor: the rules' state and views, the Room's snapshot, the components' data roles, the Chronicle's tables (attempts, verdicts, fairness taps, precedents — one migration), the calibration export and the Markdown export all use the new word, and the export's reader still accepts old `Anchors:` lines so earlier exports round-trip. Every test is green with only the rename applied, and the game plays exactly as before. Spec: `.scratch/at-the-table/spec.md`; glossary: `CONTEXT.md` (Bookends).

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The rules, the Room snapshot and every component use `bookends` / `next_bookends`; nothing in `lib/` says "anchor" except the export reader's compatibility clause
- [ ] One migration renames the `anchors` columns on attempts, verdicts, fairness taps and precedents; precedents look up by the renamed key with no change in behaviour
- [ ] The Markdown export writes `Bookends:` and its reader parses both `Bookends:` and `Anchors:`; the calibration export's field is renamed
- [ ] The test suite passes with the rename and no other change; the two-Seat rules, Room and LiveView tests are otherwise untouched
- [ ] Deployed; a Page plays from Bookends to reveal as before
