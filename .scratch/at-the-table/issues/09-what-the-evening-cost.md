# 09: What the evening cost

**What to build:** Every model call's cost is already written down; now it adds up somewhere Jacob can see. Each Room's Chronicle ends with what that Room has cost across its Author, Assayer and Scribe calls; an operator page at `/spend` totals every Room by role and by model with call counts — computed from the rows, never stored. The Scribe's recap job moves to `xhigh` effort, since nobody waits for it and the page will say what it costs. Spec sections: The Chronicle (Spend), The Steward (The Scribe).

**Blocked by:** 02 (The Page is written at the table).

**Status:** ready-for-agent

- [ ] The Chronicle answers spend for one Room and for all Rooms: total dollars, by role, by model, with call counts, from the cost on Verdicts (both orderings and any quip request), Pages (`author_meta`) and Recaps; a row without a cost is counted and shown as unpriced
- [ ] The book view and the Markdown export end each Room's Chronicle with its spend line
- [ ] `/spend` renders the all-Rooms answer, noindex like every other page, with a per-Room breakdown
- [ ] The Scribe's recap job is configured at `xhigh`
- [ ] Chronicle tests for the sums against fixture rows; a LiveView test for the page and the foot line
- [ ] Deployed; the page shows the Rooms played so far and their totals
