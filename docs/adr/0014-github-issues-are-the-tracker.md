---
status: accepted
---

# GitHub issues are the tracker

Since the first feature, specs and tickets have lived as Markdown under `.scratch/<feature>/`, with a `Status:` line in each file and resolved tickets moved into a `resolved/` folder. That worked for one branch at a time. With several worktrees open at once the same ticket carries a different status on each branch, and nothing is the source of truth. Decision (2026-09-09): from the playtest-feedback work onward, a feature's spec is a GitHub issue on `JacobStephens2/thereish`, its tickets are that issue's sub-issues, triage state is the repo's labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `resolved`, `wontfix`), and blocking is GitHub's blocked-by relation plus a `Blocked by #N` line in the body for agents that read text. The six resolved feature directories stay in `.scratch/` as history and are not migrated; the one open local ticket (coffee-table 14) moves.

## Considered options

- **Stay local, add a status file merged from every branch.** Rejected: it recreates a tracker by hand and still forks per worktree.
- **Migrate the resolved history into GitHub.** Rejected: seventy closed tickets whose only reader is `git log`; the cost is real and the value is nil.
- **A hosted board other than GitHub.** Rejected: the code, the PRs, and the `gh` CLI are already there, and sub-issues give the spec-and-tickets shape for free.

## Consequences

`docs/agents/issue-tracker.md` describes GitHub instead of `.scratch/`. Skills that "publish to the issue tracker" create issues with `gh`; "fetch the relevant ticket" reads an issue number. Working offline means working without the tracker.
