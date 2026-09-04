# 12: Name a setting at 9pm, and tonight's game is set there

**What to build:** A player types a Give at the couch: the world St. Thérèse grew up in, or the language of Children's Hospital, or suburban family life. The Author starts writing Pages for it in the background while the Room keeps playing from the existing pool, and the stage announces the new Pages when they land. Naming a theme never stalls the evening.

This is the Author's signature power. No publisher can print a deck for a meaning-space you name at 9pm.

**Blocked by:** 09.

**Status:** resolved

- [x] A Give can be typed from a phone during a Room, in free language
- [x] The Give queues a background Author run against that meaning-space. A supervised task is enough; no job queue in this ticket
- [x] The Room keeps playing from the existing pool while the run is in flight
- [x] The stage announces when Pages for the Give have arrived, so the players know the game heard them
- [x] Pages authored from a Give are tagged with it and appear in the Chronicle that way
- [x] A failed or refused Author run is surfaced honestly and leaves the evening playable
- [x] Tests: a Give queues a run, play continues meanwhile, arriving Pages join the pool, and a failed run degrades cleanly

## Comments

**Free-language Give input on phones.** In `MeaningGameWeb.RoomLive`, when players are in an active room (`room.phase != :waiting`), each phone displays a "Give a setting" form (`[data-role="give-form"]`) where players can submit any free-language prompt (e.g. "the world St. Thérèse grew up in", "the language of Children's Hospital", "suburban family life"). The input gives immediate visual status feedback (`[data-role="give-status"]`) indicating that the Author is writing Pages for the requested setting.

**Supervised asynchronous Author run.** In `MeaningGame.Rooms.Server`, handling `Rooms.give(slug, seat_id, give)` launches a supervised background task via `Task.Supervisor.start_child(MeaningGame.Keeper.Tasks, ...)`. The task invokes `MeaningGame.Pages.author_give(give, digest: digest)`. No external job queue or worker is used per ticket requirements.

**Non-blocking play & pool integration.** Submitting a Give never stalls the room. Players continue guessing, assaying, revealing, or closing pages from the existing pool while the Author task runs in the background. Arriving pages are stored in the database (`MeaningGame.Pages.AuthoredPage`) with their `give` attribute set and join tonight's pool. When the task completes, `Rooms.Server` records `active_give`, and subsequent `Rooms.next_page/2` calls prioritize pages matching the active give before falling back to the general pool.

**Stage announcements & setting badge.** When new pages land, `MeaningGameWeb.RoomComponents.give_announcement/1` displays a prominent banner on the stage (`[data-role="give-announcement"]`) announcing that "The Author heard you: \"<give>\"" with the count of newly added pages. When the room advances to a Give page, the stage and phones display a "Setting: <give>" tag (`[data-role="page-give"]`), and the announcement is dismissed once play on the give begins.

**Chronicle visibility and Markdown round-trip.** In `MeaningGame.Chronicle`, page views include `:give`, `:theme`, and `:chapter`. `MeaningGameWeb.ChronicleLive` highlights authored settings with a dedicated badge (`[data-role="give-tag"]`). In `MeaningGame.Chronicle.Markdown`, authored gives are written to the Markdown export as `- Give: <give>` and reliably parsed back without interfering with play records.

**Honest degradation on failure or refusal.** If an Author run fails or is refused by the model policy (e.g., content declined, timeout, or exception), `Rooms.Server` surfaces the failure honestly to the stage (`[data-role="give-failure"]`) and to the phone (`[data-role="give-status"]`) explaining that the Author couldn't write for that prompt and that play continues from the existing pool. The room and evening remain completely playable.

**Tests.** Comprehensive test coverage in `MeaningGame.RoomsTest`, `MeaningGame.PagesTest`, `MeaningGame.ChronicleTest`, and `MeaningGameWeb.RoomLiveTest` verifies queuing of background Author runs, uninterrupted play during generation, arrival of authored pages in the pool, transition to the new setting, honest surface of refusal/failure, and Chronicle presentation.
