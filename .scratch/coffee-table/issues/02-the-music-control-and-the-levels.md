# 02: The music control and the levels

**What to build:** One control says what the Room hears: **Off**, **House loop**, or **Written for this Page**, the last the default. It replaces the "House loop only" checkbox that was read backwards on the third playtest, and it renders — with the voice switch — on every phone and on the Stage, not only on the Speaker's view, because the sound facts are the Room's and one tap from anywhere should flip them; every other view shows the change. Off silences the music bus and nothing else: the beat, the stings and the voice still land. Written for this Page starts a Track when a Page is written, and choosing it mid-Page with no Track and no task running starts one. The client's levels — music, stings, voice, the duck — stop being constants in the hook and become configuration handed to it as data, so the by-ear ticket can move them without a rewrite; the loop starts lower than today and the stings and voice higher. Spec sections: Room facts: the music control; Pushed events; Levels.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The Room row gains `music` with values `off`, `house`, `page` (default `page`) and loses `house_loop_only`, migrated in one expand-and-contract pair that writes `house` where the boolean was true; the Room's interface offers `set_music` in place of the boolean's setter and the snapshot answers `music`
- [x] The score task starts only under `page`; setting `page` mid-Page with no Track and no task running starts one; `house` and `off` do not, and a running task's late answer under `house` or `off` is kept for a later switch back rather than played
- [x] The three-way control and the voice switch render on every phone and on the Stage; a tap on any phone changes the fact and every connected view re-renders it; on the phone the control lives in the speaker bar (which ticket `.scratch/at-the-table/issues/11` moves below the play controls), on the Stage in the header
- [x] `foley:page` is pushed with a nil path under `off`; the hook fades the music bus out and keeps the stings and voice buses live; a later `house` or `page` fades music back in
- [x] Levels are read from the `foley` role's configuration and rendered as data attributes on the hook's container, which the hook reads on mount; a components test asserts the attributes carry the configured values
- [x] Room tests for the migration, persistence across a restart, and the three gating cases; LiveView tests with two phones and a Stage for the control on every view and the push under `off`; the two-phone tests without a Stage pass unchanged
