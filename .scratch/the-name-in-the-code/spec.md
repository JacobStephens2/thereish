# The name in the code

ADR-0008 settled the name and `naming/06` applied it everywhere a reader can see it: every rendered title, the design brief, the ADRs, the deploy doc, the README, `CONTEXT.md`, and the tracker directory. What it deliberately did not touch is everything a reader cannot see — the module namespace `MeaningGame` / `MeaningGameWeb`, the OTP application `:meaning_game`, the release binary, the database, and the checkout on Jacob's laptop, which is still `~/GitHub/JacobStephens2/meaning-game` while the remote has been `thereish.git` for some time.

That was the right call at the time: a namespace rename is a mechanical pass over 179 files and touches the deployment, and there was a game to get to a table. It is a debt rather than a decision, and this feature is the paying of it.

Two tickets, deliberately separated by risk. **01** is the checkout and the stale references around it — no code compiles differently afterwards. **02** is the namespace, the OTP app, the release and the database, which changes the running deployment and wants care and a maintenance window rather than a spare ten minutes.

Nothing here changes what a player sees. If a ticket finds itself editing player-facing prose, it has strayed.

## Not in scope

- The four naming research notes and `docs/research/llm-in-word-games.md`, which say "Mind-Meld" and "meaning-game" as historical record. `naming/06` left them alone on purpose; so does this.
- ADRs 0004, 0005, 0007 and 0008 as historical documents — they already carry the chosen name where it matters.
- Any rename of the domain vocabulary itself (Page, Bridge, Bookend, Steward). That is `CONTEXT.md`'s business and ADR-0009's.
