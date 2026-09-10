# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues on `JacobStephens2/thereish` (ADR-0014). Use the `gh` CLI for all operations.

Historical features prior to `#69` remain in `.scratch/` as read-only history; new work no longer lands in `.scratch/`.

## Shape and conventions

- **Spec (Parent Issue)**: A feature's specification is a parent issue on GitHub (e.g. `#69`), holding the overarching design, scope, and test decisions.
- **Tickets (Sub-issues)**: Implementation tickets are GitHub sub-issues belonging to the spec's parent issue (e.g. `#70` is ticket 01 of parent `#69`), numbered sequentially in their titles (`(ticket 01)`).
- **Blocking**: Blocking relationships are represented using GitHub's native blocked-by issue dependency (`gh issue create --blocked-by <number>`) along with a visible `## Blocked by` section (e.g. `Blocked by #N` or `- None (can start immediately)`) in the body for agents and tools that read text. A ticket is unblocked when all blocker issues are closed.
- **Comments and updates**: Use GitHub issue comments (`gh issue comment <number> --body "..."`) for progress updates and resolution notes.

## Triage labels

Triage state is tracked using repo labels (see `docs/agents/triage-labels.md`):

| Label | Meaning |
| ----- | ------- |
| `needs-triage` | Maintainer needs to evaluate this issue |
| `needs-info` | Waiting on reporter for more information |
| `ready-for-agent` | Fully specified, ready for an AFK agent |
| `ready-for-human` | Requires human implementation |
| `resolved` | Work completed and verified |
| `wontfix` | Will not be actioned |

## Common CLI operations

Infer the repo from `git remote -v`; `gh` handles this automatically inside a clone.

- **Create a parent issue (spec)**:
  ```sh
  gh issue create --title "<feature-name>" --body-file "<path-or-stdin>"
  ```
- **Create a ticket (sub-issue)**:
  ```sh
  gh issue create --parent <parent-number> --title "<title> (ticket NN)" --label "<triage-label>" --blocked-by <blocker-number> --body "..."
  ```
- **Read an issue**:
  ```sh
  gh issue view <number> --comments
  ```
- **List issues**:
  ```sh
  gh issue list --state open
  ```
- **Comment on an issue**:
  ```sh
  gh issue comment <number> --body "..."
  ```
- **Apply / remove labels**:
  ```sh
  gh issue edit <number> --add-label "<label>" --remove-label "<label>"
  ```
- **Close an issue**:
  ```sh
  gh issue close <number> --comment "..."
  ```

## When a skill says "publish to the issue tracker"

Create a GitHub issue via `gh issue create`. For tickets under a feature spec, specify `--parent <spec-number>`.

## When a skill says "fetch the relevant ticket"

Read the issue via `gh issue view <number> --comments` or fetch the issue by URL/number.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as sub-issues.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body (`gh issue create --label wayfinder:map`).
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh issue create --parent <map-number>`). Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev (`gh issue edit <number> --add-assignee @me`).
- **Blocking**: GitHub's native issue dependencies plus a `Blocked by #N` line in the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open child issues (`gh issue list --state open`), drop any with an open blocker or an assignee; first in map order wins.
- **Claim**: `gh issue edit <number> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <number> --body "<answer>"`, then `gh issue close <number>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
