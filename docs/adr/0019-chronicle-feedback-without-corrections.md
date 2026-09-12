# Retrospective feedback without editing recorded play

Chronicle corrections let visitors change recorded Bridges and Recaps through appended corrections, but Jacob does not use this feature and wants to evaluate the Assayer after play instead. Decision (2026-09-12, [issue #126](https://github.com/JacobStephens2/thereish/issues/126)): retire the correction interface and its write functionality, preserve existing correction records, and offer retrospective Too harsh / Fair / Too kind feedback. Feedback does not rewrite the Verdict or Precedent; ADR-0006 still reserves Precedent changes for a joint player overrule, preserving the distinction between an opinion about the grade and a change to the ruling.

Original participants may update their own opinion about an Attempt they played. Jacob may review any Attempt as the authenticated admin, with that review identified separately from participant feedback; unrelated visitors cannot submit participant opinions.
