# 02: No recap landed on couch night

**What to fix:** Seven Pages closed in Room DUST on the evening of 2026-09-04 (00:49–01:22 UTC on 2026-09-05) and `chronicle_recaps` holds zero rows for any Room. The Scribe's recap job — shipped in `scribe/01`, `Scribe.write_about/2` called from `Rooms.Server.perform({:chronicle, _})` after every close — wrote nothing, and nothing on any screen said so.

**Blocked by:** nothing.

**Status:** ready-for-agent

**Category:** bug

**Evidence, gathered 2026-09-05.**

- `select count(*) from chronicle_recaps` on the VPS → `0`. `GET /r/dust/chronicle.md` lists the seven Pages with Verdicts and no `Recap:` lines.
- The Author ran fine the same evening — Pages for four different Gives arrived — so `ANTHROPIC_API_KEY` is present in the server's `.env`, and the recap job uses the same key.
- The container restarted at 02:08:51 UTC (`Running MeaningGameWeb.Endpoint with Bandit`) and the Room processes re-initialised at 02:27:41 (five pool Pages marked played in one second). Both are after the Pages closed, so a restart did not eat the recaps; a recap that fails is meant to be logged and dropped.
- `docker compose logs --since 2026-09-05T00:00:00 app | grep -i recap` returned nothing at all — no attempt, no error. Either the task never started, it raised before logging, or the log line is worded without "recap"/"scribe".

**Where to look, in order.** `Scribe.write_about/2` — is the task started, and does it rescue silently? The Vale gate: `vale` is pinned in `mise.toml` and installed into the release image per the design brief — confirm `which vale` inside the running container, because a gate whose binary is missing may be failing every candidate. `Steward.role(:scribe, :recap)` — the job's `api_key` is `nil` in `config.exs` and filled by `runtime.exs`; confirm the scribe role gets the Anthropic key and not only the author role. Then read `chronicle_recaps` again after one closed Page in a test Room on the VPS.

- [ ] The cause is named in this ticket's comments with the log line or code path that proves it
- [ ] A recap lands for a Page closed on the VPS, and `GET /r/<Code>/chronicle.md` shows it
- [ ] A recap job that fails leaves one `Logger.error` line naming the Room, the Page and the reason, so silence is never the failure mode again
- [ ] The seven Pages of Room DUST get recaps, by re-running the Scribe over closed Pages that have none (`mix scribe.sync` exists for this; confirm it covers them)
- [ ] Tests: a Scribe adapter that raises, times out, or fails the gate produces exactly one error log and no row
