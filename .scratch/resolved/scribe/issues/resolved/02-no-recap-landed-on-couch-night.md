# 02: No recap landed on couch night

**What to fix:** Seven Pages closed in Room DUST on the evening of 2026-09-04 (00:49–01:22 UTC on 2026-09-05) and `chronicle_recaps` holds zero rows for any Room. The Scribe's recap job — shipped in `scribe/01`, `Scribe.write_about/2` called from `Rooms.Server.perform({:chronicle, _})` after every close — wrote nothing, and nothing on any screen said so.

**Blocked by:** nothing.

**Status:** resolved

**Category:** bug

**Evidence, gathered 2026-09-05.**

- `select count(*) from chronicle_recaps` on the VPS → `0`. `GET /r/dust/chronicle.md` lists the seven Pages with Verdicts and no `Recap:` lines.
- The Author ran fine the same evening — Pages for four different Gives arrived — so `ANTHROPIC_API_KEY` is present in the server's `.env`, and the recap job uses the same key.
- The container restarted at 02:08:51 UTC (`Running MeaningGameWeb.Endpoint with Bandit`) and the Room processes re-initialised at 02:27:41 (five pool Pages marked played in one second). Both are after the Pages closed, so a restart did not eat the recaps; a recap that fails is meant to be logged and dropped.
- `docker compose logs --since 2026-09-05T00:00:00 app | grep -i recap` returned nothing at all — no attempt, no error. Either the task never started, it raised before logging, or the log line is worded without "recap"/"scribe".

**Where to look, in order.** `Scribe.write_about/2` — is the task started, and does it rescue silently? The Vale gate: `vale` is pinned in `mise.toml` and installed into the release image per the design brief — confirm `which vale` inside the running container, because a gate whose binary is missing may be failing every candidate. `Steward.role(:scribe, :recap)` — the job's `api_key` is `nil` in `config.exs` and filled by `runtime.exs`; confirm the scribe role gets the Anthropic key and not only the author role. Then read `chronicle_recaps` again after one closed Page in a test Room on the VPS.

- [x] The cause is named in this ticket's comments with the log line or code path that proves it
- [x] A recap lands for a Page closed on the VPS, and `GET /r/<Code>/chronicle.md` shows it
- [x] A recap job that fails leaves one `Logger.error` line naming the Room, the Page and the reason, so silence is never the failure mode again
- [x] The seven Pages of Room DUST get recaps, by re-running the Scribe over closed Pages that have none (`mix scribe.sync` exists for this; confirm it covers them)
- [x] Tests: a Scribe adapter that raises, times out, or fails the gate produces exactly one error log and no row

## Comments

### Cause Analysis (2026-09-05)

1. **Commit timing and deployment reflog prove the Scribe was not deployed during couch night play:**
   - On the VPS, `git reflog --date=iso` shows:
     - `ac92b85 HEAD@{2026-09-05 00:29:30 +0000}: merge ac92b85: Fast-forward`
     - `d75b392 HEAD@{2026-09-05 02:05:27 +0000}: merge d75b392: Fast-forward`
     - `c06f28c HEAD@{2026-09-05 02:08:44 +0000}: merge c06f28c: Fast-forward`
   - Room DUST's seven Pages were played and closed between `2026-09-05 00:52:53 UTC` and `01:22:07 UTC`.
   - During that window, the running release was built from commit `ac92b85` (`docs: record what the deployment verified for group play issue 03`).
   - In commit `ac92b85`, `MeaningGame.Scribe` did not exist (`lib/meaning_game/scribe.ex` was added in `177cbd7` and reviewed in `d75b392`), and `Rooms.Server` did not call `Scribe.write_about/2`.
   - The Scribe was first deployed to the VPS at `02:08:44 UTC` (commit `c06f28c`), when the container restarted at `02:08:51 UTC`.
   - Because `Scribe.write_about/2` only fires in `Rooms.Server.perform({:chronicle, entry})` at the exact instant a Page closes, Pages closed prior to `02:08:44 UTC` were never processed.

2. **Error logging was incomplete:**
   - When a recap job failed (`Steward.recap` returned `{:error, reason}`), `Scribe.recap/2` logged `Logger.warning` without the Page ID.
   - When an unhandled error was rescued, it logged `Logger.error("the Scribe fell over: ...")` without naming the Room or the Page.
   - Both failure paths now log exactly one `Logger.error` specifying `#{room.slug}`, `page #{page.id}`, and the failure reason.

3. **Causal digest for catch-up:**
   - `Scribe.recap/2` previously passed the entire `Chronicle.page_views/2` list to `scribe_digest/2`, which excluded only the current page ID. When backfilling older pages, future pages were erroneously included in the digest.
   - Fixed to slice `prior_views = Enum.take_while(views, &(&1.id != page.id))`, guaranteeing historical recaps only see Pages played prior to them.

4. **Sync and VPS verification:**
   - Implemented `MeaningGame.Scribe.sync/1` and updated `mix scribe.sync` to find and backfill closed Pages that have no recap in chronological order.
   - Re-ran the Scribe over all 7 closed Pages of Room DUST on the VPS. All 7 recaps were generated, recorded, and verified via `curl -s https://meld.stephens.page/r/dust/chronicle.md`.

