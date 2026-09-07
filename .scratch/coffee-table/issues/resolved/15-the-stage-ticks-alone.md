# 15: The Stage ticks alone

**What to build:** When there is a Stage at the table, the commit tick comes from the Stage and from nowhere else. 06 shipped the rule the spec asked for — the Stage sounds every commit, and every phone also sounds its own, on the grounds that a phone answering its own tap is a UI sound rather than a Room sound. On the couch that is not what it is: the laptop ticks and the committer's phone ticks a moment later, so one commit is two sounds from two places, which is the thing the one-Speaker rule exists to prevent. With a Stage the phones go quiet; with no Stage nothing changes and each phone still ticks its own, because otherwise a commit makes no sound at all.

This amends the spec's **Pushed events** section and the note **Why the Stage sounds commits and a Speaker phone does not** (`spec.md`), and narrows user story 14: a commit is still heard, but through the Stage when there is one.

**Blocked by:** None (can start immediately).

**Status:** resolved

The seam is already in place. `MeaningGameWeb.Presence.stage_present?/1` answers whether a Stage holds the Room, and `RoomLive` already assigns `@stage_present?` for the quiet-phone mode (`lib/meaning_game_web/live/room_live.ex:253`). The push is one call in the commit handler (`room_live.ex:104`, `MeaningGameWeb.Foley.push_own_commit/1`); `foley:commit` to the Stage is untouched. Decide it on the server rather than in the hook, so a test can assert it and so a phone never has to learn what else is in the Room.

- [x] `foley:own-commit` is pushed to the committing phone only when no Stage holds the Room; with a Stage present the commit pushes `foley:commit` to the Stage and nothing to any phone, Speaker or not
- [x] With no Stage the behaviour of 06 is unchanged: the committer's phone gets `foley:own-commit`, no other phone gets anything, and the per-device switch and reduced-motion still gate it
- [x] The per-device commit-sound switch stays on the phone under a Stage — it is per-device and survives the Stage closing — but says nothing misleading when it can make no sound; if that reads badly on the screen, hide it while a Stage is present and record which was chosen here
- [x] A Stage joining or leaving mid-Page moves the tick from the next commit onward; no commit is silent because the two views disagreed about whether a Stage exists
- [x] LiveView tests: with two phones and a Stage, a commit pushes `foley:commit` to the Stage and `foley:own-commit` to nobody; with the Stage gone and one phone holding the Speaker, the same commit pushes `foley:own-commit` to the committer only
- [x] The spec's Pushed events section and its "Why the Stage sounds commits" note are amended to say this, and 06's resolved ticket carries a line pointing here

## Comments

**2026-09-07.** Filed from Jacob's playtest notes (`.scratch/ideas/ideas.md`): "I want the submission / commit sounds when there is a stage to be played by the stage, not the individual phones." Heard on the third playtest, against 06 as shipped.

**2026-09-07.** Implemented and verified:
- `MeaningGameWeb.Foley.push_own_commit/2` gates pushing `foley:own-commit` on whether a Stage is present (via `MeaningGameWeb.Presence.stage_present?/1`). With a Stage present, the phone stays quiet and only the Stage receives `foley:commit`.
- With no Stage present, 06 behavior remains unchanged: the committer's phone receives `foley:own-commit`.
- When a Stage joins or leaves mid-Page, the tick transitions immediately for the next commit.
- The per-device toggle button `local_sound_switch` is retained on phones when a Stage is present, updating its `title` to "Commit sound plays from the Stage while connected" and `aria-label` to "Toggle commit sound on this device (commit sound plays from the Stage while connected)", preserving local preferences when playing without a Stage.
- `spec.md`, ticket 06, and ticket 14 checklist updated.
