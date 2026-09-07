# 06: The commit sound

**What to build:** A committed Bridge makes a sound, and it comes from one place. With a Stage at the table, the Stage sounds every commit as the table fills in. Every phone sounds its own commit — a UI sound answering its own tap, on by default, silent under reduced-motion, with one tap per device to turn it off — whether or not a Stage exists and whether or not this phone holds the Speaker. No phone ever relays anyone else's commit, so the one-Speaker rule stands: two devices never play one Room sound a hundred milliseconds apart. Spec section: Pushed events.

**Blocked by:** 01 (The forge, again: seven new sounds).

**Status:** resolved

- [x] `foley:commit` is pushed to a Stage's view — and to no phone, Speaker or not — whenever the count of committed Seats rises within a Page; the hook plays the commit tick on the stings bus
- [x] `foley:own-commit` is pushed to the committing phone's own view when its commit succeeds, and to no other view; the hook plays the tick locally
- [x] The hook runs on every phone with a local-sounds mode that owns only the tick; the Speaker mode is unchanged; the local tick is gated by a per-device switch in browser storage (default on) and by reduced-motion, and the Commit tap is the audio gesture
- [x] The per-device switch renders as a small icon beside the speaker icon on every phone and its state survives a reload on that device
- [x] LiveView tests with two phones and a Stage: a commit pushes `foley:commit` to the Stage and `foley:own-commit` to the committer only; with no Stage and one phone holding the Speaker, a commit pushes `foley:own-commit` to the committer and `foley:commit` to nobody

## Comments

**2026-09-07.** Amended by `.scratch/coffee-table/issues/15-the-stage-ticks-alone.md`: when a Stage is present at the table, the Stage sounds every commit and phones stay quiet, so one commit does not make two sounds from two places.
