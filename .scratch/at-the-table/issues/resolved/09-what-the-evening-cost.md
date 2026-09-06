# 09: What the evening cost

**What to build:** Every model call's cost is already written down; now it adds up somewhere Jacob can see. Each Room's Chronicle ends with what that Room has cost across its Author, Assayer and Scribe calls; an operator page at `/spend` totals every Room by role and by model with call counts — computed from the rows, never stored. The Scribe's recap job moves to `xhigh` effort, since nobody waits for it and the page will say what it costs. Spec sections: The Chronicle (Spend), The Steward (The Scribe).

**Blocked by:** 02 (The Page is written at the table).

**Status:** resolved

- [x] The Chronicle answers spend for one Room and for all Rooms: total dollars, by role, by model, with call counts, from the cost on Verdicts (both orderings and any quip request), Pages (`author_meta`) and Recaps; a row without a cost is counted and shown as unpriced
- [x] The book view and the Markdown export end each Room's Chronicle with its spend line
- [x] `/spend` renders the all-Rooms answer, noindex like every other page, with a per-Room breakdown
- [x] The Scribe's recap job is configured at `xhigh`
- [x] Chronicle tests for the sums against fixture rows; a LiveView test for the page and the foot line
- [ ] Deployed; the page shows the Rooms played so far and their totals

## Answer

1. **The Chronicle Spend Answers**:
   - Implemented `MeaningGame.Chronicle.spend/1` and `MeaningGame.Chronicle.spend/0` (or `spend(:all)`), computing total dollars, spend by role (`author`, `assayer`, `scribe`), and spend by model with total call counts and unpriced counts from rows dynamically (never stored).
   - Counts and totals from `chronicle_pages.author_meta`, `chronicle_verdicts.cost_usd`, and `chronicle_recaps.cost_usd`. Rows with `nil` cost are counted and marked as unpriced.
   - Formatter `MeaningGame.Chronicle.spend_line/1` formats the spend line ending each Room's Chronicle across its Author, Assayer, and Scribe calls.

2. **Book View and Markdown Export Foot Line**:
   - `MeaningGame.Chronicle.Markdown.render/1` appends the spend line at the end of each Room's export.
   - `MeaningGame.Chronicle.Markdown.parse/1` strips the spend line cleanly so exports round-trip without disruption.
   - `MeaningGameWeb.ChronicleLive` assigns `@spend` and renders the foot line under `[data-role=chronicle-spend]` with `[data-role=spend-line]`.

3. **Operator Page at `/spend` (`MeaningGameWeb.SpendLive`)**:
   - LiveView at `/spend` rendering all-Rooms totals, total calls, unpriced counts, breakdown by role, breakdown by model, and per-Room ledger.
   - Explicit `noindex` meta tag placed in `root.html.heex` for all pages and verified in `/spend`.

4. **Scribe Recap Job**:
   - Configured `recap` job in `config/config.exs` with `effort: "xhigh"`.

5. **Testing & Standards**:
   - 499 ExUnit tests passing with 0 failures (`mix test`).
   - Strict compilation check passed with 0 warnings (`mix compile --warnings-as-errors`).
   - Code formatted cleanly with `mix format --check-formatted`.
