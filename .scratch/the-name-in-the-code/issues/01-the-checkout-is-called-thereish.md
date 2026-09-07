# 01: The checkout is called Thereish

**What to build:** The working copy on Jacob's laptop is `~/GitHub/JacobStephens2/meaning-game` and the remote is `github.com/JacobStephens2/thereish.git`. Nothing breaks, because GitHub redirects a renamed repository and git does not care what the directory is called, but every path Jacob types and every path an agent records still says the old name. This ticket renames the checkout and fixes the references that point at the old repository by name. No Elixir identifier changes here; that is `02`.

The one live staleness worth naming: `deploy/env.sh:6` sets `REPO="https://github.com/JacobStephens2/meaning-game.git"`. It works today only because GitHub forwards it, and a redirect is not a plan — a future repository at the old name would silently take the deploy.

**Blocked by:** None (can start immediately). Best done before `02`, so the namespace pass happens in a directory with the right name.

**Status:** ready-for-human

This one is `ready-for-human` rather than `ready-for-agent` because the rename moves the directory an agent is running inside, and because it changes a path Jacob's own tooling remembers.

**What Jacob should know before renaming the directory.** Claude Code keys its per-project state — the session history and the auto-memory index under `~/.claude/projects/-Users-jacob-GitHub-JacobStephens2-meaning-game/` — to the absolute path of the working directory. Renaming the checkout starts a fresh project directory and the existing memories stop being loaded. They are files, so the fix is to rename that directory alongside the checkout, or to copy `memory/` across; the point is to do it deliberately rather than discover it later. The same applies to any editor workspace or shell alias pointing at the old path.

- [ ] `deploy/env.sh` names `thereish.git`; a deploy from a clean host still clones, builds and boots
- [ ] The checkout is renamed to `~/GitHub/JacobStephens2/thereish`, and `git remote -v`, a `git pull` and a `mix test` all still work from the new path
- [ ] `~/.claude/projects/-Users-jacob-GitHub-JacobStephens2-meaning-game/` is carried over to the new path's project directory, or its `memory/` copied, so the auto-memory index survives — recorded here either way
- [ ] Any remaining reference to the `meaning-game` repository by name outside the research notes is updated; the research notes and `docs/research/llm-in-word-games.md` are left alone as historical record
- [ ] The deployment is untouched by this ticket — no restart, no migration, nothing on the server changes

## Comments

**2026-09-07.** Filed from Jacob's playtest notes (`.scratch/ideas/ideas.md`): "I also want to rename this directory from Meaning Game to Thereish."
