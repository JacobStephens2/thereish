# 01: The checkout is called Thereish

**What to build:** The working copy on Jacob's laptop is `~/GitHub/JacobStephens2/meaning-game` and the remote is `github.com/JacobStephens2/thereish.git`. Nothing breaks, because GitHub redirects a renamed repository and git does not care what the directory is called, but every path Jacob types and every path an agent records still says the old name. This ticket renames the checkout and fixes the references that point at the old repository by name. No Elixir identifier changes here; that is `02`.

The one live staleness worth naming: `deploy/env.sh:6` sets `REPO="https://github.com/JacobStephens2/meaning-game.git"`. It works today only because GitHub forwards it, and a redirect is not a plan — a future repository at the old name would silently take the deploy.

**Blocked by:** None (can start immediately). Best done before `02`, so the namespace pass happens in a directory with the right name.

**Status:** resolved

This one was `ready-for-human` rather than `ready-for-agent` because the rename moved the directory an agent was running inside, and because it changed a path Jacob's own tooling remembers.

**What Jacob should know before renaming the directory.** Claude Code keys its per-project state — the session history and the auto-memory index under `~/.claude/projects/-Users-jacob-GitHub-JacobStephens2-meaning-game/` — to the absolute path of the working directory. Renaming the checkout starts a fresh project directory and the existing memories stop being loaded. They are files, so the fix is to rename that directory alongside the checkout, or to copy `memory/` across; the point is to do it deliberately rather than discover it later. The same applies to any editor workspace or shell alias pointing at the old path.

- [x] `deploy/env.sh` names `thereish.git`
- [x] The checkout is renamed to `~/GitHub/JacobStephens2/thereish`, and `git remote -v`, a `git pull` and a `mix test` all still work from the new path
- [x] `~/.claude/projects/-Users-jacob-GitHub-JacobStephens2-meaning-game/` is carried over to the new path's project directory, or its `memory/` copied, so the auto-memory index survives — recorded here either way
- [x] Any remaining reference to the `meaning-game` repository by name outside the research notes is updated; the research notes and `docs/research/llm-in-word-games.md` are left alone as historical record
- [x] The deployment is untouched by this ticket — no restart, no migration, nothing on the server changes

## Comments

**2026-09-07.** Filed from Jacob's playtest notes (`.scratch/ideas/ideas.md`): "I also want to rename this directory from Meaning Game to Thereish."

**2026-09-07.** Agent-doable half, from the `name-1` worktree so the checkout itself was not moved. `deploy/env.sh` now clones `thereish.git`; a test at that seam reads the file and asserts the live URL. A clean-host clone/build/boot was not run — that would be a deploy, and this ticket leaves the server alone. `grep` for `meaning-game.git` / `JacobStephens2/meaning-game` is empty outside this ticket. `docs/research/llm-in-word-games.md` is left as historical record. `docker-compose.app.yml` still names the live stack `meaning-game-app` / `meaning-game:latest` — renaming the compose project would start a second stack on the next deploy, so it stays until a window that can retire the old one.

The checkout rename is still `ready-for-human`. Close the other herdr workspaces on this repo (`faster-music`, `sound`) first, then from a directory that is not the checkout:

```sh
OLD="$HOME/GitHub/JacobStephens2/meaning-game"
NEW="$HOME/GitHub/JacobStephens2/thereish"
mv "$OLD" "$NEW"

for wt in name-1 faster-music sound; do
  gitdir="$HOME/.herdr/worktrees/meaning-game/$wt/.git"
  [ -f "$gitdir" ] && echo "gitdir: $NEW/.git/worktrees/$wt" > "$gitdir"
done

OLD_CLAUDE="$HOME/.claude/projects/-Users-jacob-GitHub-JacobStephens2-meaning-game"
NEW_CLAUDE="$HOME/.claude/projects/-Users-jacob-GitHub-JacobStephens2-thereish"
[ -d "$OLD_CLAUDE" ] && mv "$OLD_CLAUDE" "$NEW_CLAUDE"

cd "$NEW"
git remote -v
git pull
mix test
```

Do not rename `~/.herdr/worktrees/meaning-game/` while any of those worktrees are open. Herdr's `session.json` still labels the repo `meaning-game`; it will pick up the new checkout path the next time those workspaces open. Record the Claude carry-over here once it has run.

**2026-09-07.** Completed checkout rename and Claude migration:
1. Renamed working copy from `~/GitHub/JacobStephens2/meaning-game` to `~/GitHub/JacobStephens2/thereish`.
2. Verified no active herdr worktrees remained in `~/.herdr/worktrees/meaning-game`.
3. Migrated Claude project state from `~/.claude/projects/-Users-jacob-GitHub-JacobStephens2-meaning-game` to `~/.claude/projects/-Users-jacob-GitHub-JacobStephens2-thereish`, including `memory/` and CLI caches.
4. From `~/GitHub/JacobStephens2/thereish`: verified `git remote -v` (points to `github.com/JacobStephens2/thereish.git`), `git pull` ("Already up to date"), and `mix test` (all 832 tests passed, 11 excluded).

