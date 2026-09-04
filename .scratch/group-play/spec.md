# Spec: Group play — a Room of N phones, one Verdict per Attempt

Status: `ready-for-agent`
Written: 2026-09-04
Sources: `docs/design-brief.md` (Group play, decided 2026-09-04), `CONTEXT.md`, ADRs 0001–0010 (0010 is this feature's ruling), the Mind-Meld spec at `.scratch/archive/mind-meld/spec.md`, the grilling of 2026-09-04, and the follow-ups filed at `.scratch/group-play/issues/` and `.scratch/scribe/issues/`.

## Problem Statement

Jacob and his wife meet another couple for an evening and want to play the game with them. Four people, four phones, no laptop. The game cannot seat them.

The rules were written for a list of Seats from the first line of code (ADR-0007), and the Room process, the Chronicle tables and the Precedent cache all hold lists rather than pairs. But nothing lets anyone open a Room with more than two Seats: the count comes from configuration, and every Room ever opened has two. And the one shape of group play that was sketched — every pair of players graded, six Verdicts on a four-person Attempt — would turn the reveal on a phone into a report: six numbers, six quips, six sentences of reasoning, scrolled past. The reveal is the product, and at four it would stop being a punchline.

There is also no way for a friend to get in. The bare URL is the couch's Room, and any other Room is a slug typed into a path. A friend at a table needs a word to type, read aloud once.

## Solution

Whoever wants to play taps New Room, picks how many players, and gets a **Code**: a four-letter word, read aloud. The Scribe chooses it with a nod to the Rooms that phone has played in before — a couple that melded on candy cane last night might be handed CANE tonight — and when there is no history to read, or the model is slow, the game draws a word itself. Everyone else opens the game, types the Code, then their name, and is in a Seat. The creator joins the same way; nobody is special.

Play is the game the couch already knows, at any table size. Everyone sees the same Anchors, everyone writes a Bridge in private, and the instant the last Bridge lands the Assayer reads them **all together**: one Closeness for how far the table is from one mind, one line of reasoning, one quip about the words the table actually wrote, and a note of which two words landed furthest apart. Those two words become the next Attempt's Anchors, so a missed Attempt converges the group exactly as it converges a couple. The Page melds when that one number reaches the meld band.

At two Seats nothing changes. One Verdict on two Bridges is the Verdict the couch has been getting, and the two furthest-apart words of two are the two words. The couch's calibration, its Chronicle, and its Precedent carry over untouched (ADR-0010).

The bare URL becomes the door: a box for a Code, a New Room button, and a one-tap way back into any Room this phone already holds a Seat in. Reopening the URL still puts my wife one tap from her Seat.

## User Stories

### Opening a Room

1. As a player, I want a New Room button on the game's front page, so that starting a Room for tonight's table needs no path, no setting and no laptop.
2. As the creator, I want to choose how many players the Room holds, from two to six, so that a Room for two couples waits for exactly four.
3. As the creator, I want the Room's Code shown large the moment it exists, so that I can read it aloud to the table.
4. As the creator, I want the Code to be a real four-letter word, so that I can say it once and everyone can spell it.
5. As the creator, I want the Code to nod to Rooms my phone has played in, so that even the door to a new Room remembers us.
6. As the creator, I want a Room to open in a moment whether or not the Scribe had anything to say, so that nobody at the table waits on a model for a word.
7. As the creator, I want to join by name like everyone else after opening the Room, so that opening it gives me nothing to manage.
8. As a player, I want the Code to work typed in any case, so that "cane", "Cane" and "CANE" all open the same door.
9. As a player, I want a Code that is not a Room to be told plainly, so that a slip of the thumb never conjures a Room out of a typo.
10. As Jacob, I want the Rooms that already exist to keep their names as Codes, so that COUCH still opens the couch.
11. As Jacob, I want the Code to be something a Room is *known by* in the code and in the glossary, so that "slug", "link" and "join code" do not creep back in.

### Getting in

12. As a friend, I want to open the game's URL and see a box for a Code, so that the first screen asks me for the one thing I was told.
13. As a friend, I want to type the Code and then my name and nothing else, so that nothing stands between me and a Seat (ADR-0007).
14. As a player, I want the front page to offer one-tap rejoin links for every Room this phone holds a Seat in, so that coming back is a tap and not a memory.
15. As Jacob's wife, I want reopening the URL after any interval to put me one tap from my own Seat, so that the rejoin story of the couch survives the door.
16. As a player, I want the Room to show who has joined and how many Seats are still open, so that the table knows when to start.
17. As a player, I want the Room's Code and its URL shown on my phone while the Room is short of Seats, so that a latecomer can be told without a stage.
18. As a player, I want a full Room to turn away a fifth person kindly, so that the table is not silently a table of five.
19. As a player, I want my phone locking, sleeping or reloading mid-Page to be harmless at four Seats as it is at two, so that a table of phones survives a table of phones.

### Playing at N

20. As a player, I want every Seat to see the same Anchors at the same moment, so that the Page starts fairly however many of us there are.
21. As a player, I want my Bridge to stay private until every Seat has committed, so that nobody at the table can follow anybody.
22. As a player, I want to see which Seats have committed without seeing what they wrote, so that I feel the table waiting on me.
23. As a player, I want the reveal to begin the instant the last of us commits, and after the same fixed beat as at two, so that the theatre is the same theatre.
24. As a player, I want every Bridge shown together at the reveal, mine marked, so that the comparison lands before the number does.
25. As a player, I want **one** Closeness for the whole table, so that the reveal is a punchline and not a report.
26. As a player, I want that number to read as how far we are from one mind, so that three of us landing together and one of us wandering reads as close rather than as a miss.
27. As a player, I want one quip that names the words we actually wrote, so that the reveal is funny about us.
28. As a player, I want the Assayer's one sentence of reasoning under the quip, so that I can argue with it.
29. As a player, I want the reveal to name the two words that landed furthest apart, so that the carry-forward is a thing we understand rather than a thing that happens.
30. As a player, I want those two words to become the next Attempt's Anchors, so that a missed Attempt converges the table.
31. As a player, I want the Page to meld when the one number reaches the meld band, so that "one mind, four heads" is a thing the game can say.
32. As a player, I want the copy to know how many of us there are, so that a table of four is never told "two heads".
33. As a player, I want a Page to end after the same number of Attempts as it does at two, so that an evening with friends has the same shape as an evening on the couch.
34. As a player, I want "one more?" to be a single tap for anyone at the table, so that the evening chains.
35. As a player, I want the fixed beat, the visible Assayer activity, the provisional reading and the ten-second "no verdict" to work exactly as they do at two, so that a slow model at a table of four is the same known thing.
36. As a player, I want a Verdict the Assayer could not give to hand the call to the table, so that the game admits what it does not know at four as it does at two.
37. As a player, I want a Give at the table to work as it does on the couch, so that four people can name a setting and go there.

### The grade, and arguing with it

38. As a player, I want the same Bridges to always get the same Verdict, so that the table never catches the game contradicting itself (design law 1).
39. As a table, I want to overrule a grade when every one of us agrees, so that the players hold final authority at four as at two.
40. As a table, I want an overrule to need every Seat in the Room, so that no two of us can quietly rewrite a ruling on all of us.
41. As a player, I want a proposed overrule shown on every phone with an agree and a decline, so that the vote is visible and quick.
42. As a table, I want our overrule to be what the game rules the next time those exact words meet, in any Room, so that the game's law is one law.
43. As a player, I want every overrule recorded in the Chronicle with what the machine said and what we said, so that the argument becomes lore.
44. As a player, I want to mark the grade fair, too harsh or too kind in one tap, so that our sense of the scale gets recorded without interrupting play.
45. As Jacob, I want those taps to join the labelled set with the number of Bridges they were about, so that calibration can read pairs and tables apart.

### The Chronicle

46. As a table, I want our Room to have its own Chronicle, so that tonight's Pages belong to tonight's Room and not to the couch.
47. As a player, I want to read the Room's Chronicle as a book from my phone, so that our history is a thing we can look at at the table.
48. As a player, I want a Chronicle entry at four Seats to list every Bridge, the one Verdict and the two words that carried, so that the book tells the story the reveal told.
49. As Jacob, I want the Markdown export and the calibration export to render N-Seat Attempts, so that a coding agent and a calibration script can read a table's evening.
50. As Jacob, I want Chronicle rows to reference Seats and never Accounts, so that a friend's Seat is claimable later (ADR-0007).

### The two-player game

51. As Jacob's wife, I want the couch's game to feel identical after this ships, so that group play costs the couple nothing.
52. As Jacob, I want every two-Seat test to keep passing with its assertions unchanged, so that "at two Seats nothing changes" is a thing the suite proves.
53. As Jacob, I want the fake Assayer's grade on two words to be the grade it gave before, so that no existing test has to be re-dialled.

### Operating it

54. As Jacob, I want the Scribe to be a role in the Steward's configuration like the Author and the Assayer, so that its model and effort are settings (ADR-0009).
55. As Jacob, I want the Scribe's word to pass a deterministic gate before it is used, so that a model never chooses a word the dictionary, the profanity list or the Room table would refuse (design law 14).
56. As Jacob, I want one grading request per Attempt rather than one per pair, so that the seat cap is about the phone and the prompt, not the bill.
57. As Jacob, I want every Verdict to still record model, prompt version, both orderings, latency and cost, so that the model policy stays measured at N.
58. As Jacob, I want the prompt version bumped, so that the grades either side of the change are never mistaken for comparable.
59. As Jacob, I want the latency measurement to include a four-word request, so that the reveal beat is measured at the table size it now serves.
60. As Jacob, I want the change to build in an order that keeps master deployable, so that the couch can play any evening in between.

## Implementation Decisions

### Seams

**No new seam.** The Mind-Meld spec's three test surfaces carry this feature whole: the Game is a pure module, the Room is a process with a small interface, the LiveViews are exercised end to end. Persistence is real. The Steward stays the one adapter seam, and it gains a third callback for the Scribe's naming job, satisfied by the same two adapters — the live one and the fake.

### The Game, at N with one Verdict

The reducer keeps its three functions and its events, and its state changes shape in one place: an Attempt holds **one Verdict or none** instead of a map of Verdicts keyed by pair. The last commit still yields a beat and an assay, but the assay is one effect carrying the Anchors and every Bridge in roster order. `verdict_received` and `verdict_unavailable` no longer carry a pair.

Phase is still derived: waiting until full, bridging until every Seat has committed, assaying until the Verdict is in or given up on, then reveal or closed. The headline Closeness is the Verdict's number, not a mean. Meld is the headline reaching the meld band. The attempt cap is unchanged.

**Carry-forward.** The Verdict names the two Bridges that landed furthest apart, and those are the next Attempt's Anchors. At two Seats they are the two Bridges. When there is no Verdict, the two carried are the first two Bridges in roster order, and the view says the Assayer did not choose them. Nothing defends against the two carried words being the same word, for the reason the current rules give.

**Overrule** targets the Attempt's Verdict. Proposal, agreement and decline keep their events; unanimity is every Seat in the Room; the `pair` attribute is gone and so is the notion of a default pair. **Fairness taps** target the Attempt's Verdict, one per Seat per Attempt.

The view for a Seat shows every Bridge with names, its own marked; the one Verdict with Closeness, band, reasoning, quip, and the two furthest words by name; the roster; and the carry words when the phase is reveal. The `pairs` list in the view goes away.

The seat limit stays a rule the Game holds, and the seat cap of six stays configuration behind the Steward; its documented reason becomes the phone layout and the prompt's length, no longer the count of requests.

### The Steward

**Assay at N.** The request is the Anchors and a list of N Bridges. The Verdict gains `furthest`: two of those Bridges, verbatim. The live adapter asks in two orderings — roster order and its reverse — hedged as configured, and reconciles as today: the mean of the two Closenesses, the forward ordering's reasoning, quip and furthest pair, the reverse ordering's Closeness and reasoning kept in meta. The deterministic check grows: `furthest` must be exactly two entries and both must be Bridges from the request (normalised for case and whitespace); an answer that fails is a retry, never a verdict.

The prompt is rewritten for N players and states what the number means: how far the set is from being one mind — the same idea in different words melds; three tight words and one stray read as close, not as a miss; at two words this is the closeness of the two. It asks for the two furthest-apart words, one sentence of reasoning, and one warm quip naming what the players wrote. The prompt version bumps, orphaning the three cached Verdicts in production and no overrules.

**The fake** grades N words deterministically so that tests keep choosing their own numbers: the Closeness is the mean of the shared-prefix grade over every pair, the furthest pair is the pair with the lowest such grade (ties broken by roster order), and at two words the result is exactly the grade the fake gives today. Its dials — delay, unavailable, raise — are unchanged.

**Precedent** already keys on a sorted list of Bridges; the row gains `furthest` so a cached Verdict carries its carry-forward. Both orderings of any list collapse to one key as before. One shared cache for the whole game; an overrule from any Room rewrites the key for every Room.

**The Bait experiment** reads "both Bridges" as "every Bridge": every Bridge equal to the Bait is the trap sprung and a Meld on the lowest rung; every Bridge among the deep Bridges is deep convergence. **The provisional reading** at eight seconds generalises the same way: all Bridges identical, then all among the likely Bridges, then any among them, then miss.

**The Scribe's first job.** The Steward behaviour gains a naming callback: given the digests of the Rooms a phone holds Seats in and the Codes already taken, answer with one four-letter word. A `scribe` role in configuration: Gemini 3.8 Flash at low effort, one request, a short timeout and a shorter deadline than the Assayer's, because a table is waiting. The prompt asks for a real English word of four letters that nods to the history, avoiding the taken Codes; the schema is one string. The deterministic gate has the last word: four letters, in the ENABLE list, not profane, not an existing Code; a failing answer is asked for once more, then the Room draws a word itself. No history means no model call.

### Rooms and Codes

A Room is **created**, never conjured. The Room interface gains a create call that takes a player count and the creating phone's device token, names the Room, inserts it, starts its process, and returns the Code. Opening a Room by Code starts its process if it exists and is a 404 if it does not; the auto-creating path goes away, and with it the configured default seat count as a creation rule (it remains the form's default). The **Code** is the Room's slug, stored lowercase, shown uppercase, accepted in any case; existing slugs are valid Codes. The slug format is unchanged.

The Room needs one new query: the Rooms in which a device token holds a Seat, with the Seat, newest first. The front page uses it for rejoin links and the creator's naming uses it for digests.

**Random Codes** come from the four-letter words in the ENABLE list less the profanity list, drawn at random and drawn again on collision. Real words are read aloud, so no look-alike-letter rule.

The Room process runs the escalation ladder against **one** outstanding assay per Attempt rather than a set of pairs. Everything else it owns — the beat, holding the Verdict until the beat is over, Gives, arms, the Chronicle write at Page close — is unchanged.

### The web

Three routes change hands. The bare URL becomes the **front page**: a Code box, a New Room button, and rejoin links for this phone's Rooms. `/new` is the **New Room** page: a player count from two to six, default two, and one button; it creates the Room and lands in it. The Room, its stage, its Chronicle and its exports stay at their Code-addressed paths. The bare stage and Chronicle routes that opened the couch go, since the couch is a Code like any other.

The Room page shows the Code and the join URL while the Room is short of Seats. The reveal component draws one Verdict: every Bridge, the number and band, the quip, the reasoning, the two furthest words, then the fairness taps. Flavour copy is count-aware ("One mind, four heads"); the carry line names the words. The stage draws the same components and keeps working for a Room that has a screen.

Player-facing copy says **Room** and **Code** — never game, lobby, join code, PIN.

### Schema

Two additive migrations: `furthest` on Chronicle Verdict rows and on Precedent rows, both arrays of strings. Rooms and Seats need no change. No data migration; the orphaned Precedents are three ungraded-by-anyone Verdicts.

### Build order

Rules first: the Game at N with one Verdict, driven by the existing three-Seat tests rewritten for one Verdict. Then the Steward: the fake at N, the live prompt and check, `furthest` through Precedent and the Chronicle. Then the Room process and the reveal. Then Codes, the front page and New Room with random words. The Scribe's naming last, behind the same seam. Master stays deployable at every step because the two-Seat game never changes.

## Testing Decisions

A good test crosses one of the three surfaces and asserts on what a player or an operator could observe. It never reads the reducer's state directly, never asserts on prompt text, and never calls a provider. The existing two-Seat tests are the regression guard: their assertions do not change.

**The Game, as a pure function.** The three-Seat tests become the N-Seat tests: four Seats commit and exactly one assay is owed carrying four Bridges in roster order; one Verdict reveals for everyone; the headline is the Verdict's number, not a mean; the two furthest words carry; no Verdict carries the first two in roster order and says so; a four-Seat overrule needs four agreements and three are not enough; a decline clears it; a fairness tap lands on the Attempt's Verdict; the view differs correctly between Seats; and every two-Seat test in the file passes unchanged. Prior art is the same file's `three_committed` harness.

**The Room, through its interface with the fake Steward.** A Room created for four names itself, takes four Seats, turns a fifth away, reveals once after the beat, escalates one slow Verdict to provisional and then to unavailable, and snapshots a Seat back to the identical view. Creation by the interface returns a Code that opens the Room; opening a Code that is not a Room raises the not-found error. The fake Scribe answers with a configured word so a test can assert it was used, and with none so a test can assert the fallback drew a real word. Prior art is the Rooms test and the Room fixtures.

**The Steward, against recorded responses.** An N-word request collapses both orderings to one key; a `furthest` pair that is not two of the Bridges is rejected and retried; the reconciled Verdict carries forward and reverse; the fake's two-word grade is unchanged and its N-word grade is the documented mean; the naming gate rejects a five-letter word, a profane word and a taken word and the fallback draws from the dictionary; the Bait arm and the provisional reading treat "every Bridge" correctly at four. One live smoke test per role stays tagged and excluded. Prior art is the Steward, Precedent and legality tests.

**The LiveViews, end to end.** The couch-night path at a table: a phone opens the front page, taps New Room, picks four, sees the Code; three more phones type the Code and a name; every phone sees the roster fill; four Bridges commit; every phone reveals one number, one quip and the two furthest words; an overrule needs all four taps; one more Page starts. A rejoin link on the front page lands a phone in its Seat. An unknown Code is a 404. The stage view still renders the same reveal. Prior art is the Room LiveView test's three-view Page.

**Persistence, for real.** A four-Seat Page writes one Verdict row per Attempt with four Seat ids and its `furthest` pair, the Markdown export and the book render it, and the calibration export carries the Bridge count. Ecto sandbox against real Postgres, no mock repository.

## Out of Scope

- Couple versus couple, and couples highlighted on a meld map (`.scratch/group-play/issues/06` and `07`).
- A Room that starts on a tap instead of filling to a chosen count (`.scratch/group-play/issues/08`). A Room's player count cannot change after creation.
- The Scribe proper: recaps after play, callbacks into Pages, the Vale gate (`.scratch/scribe/issues/01`). Only the naming job is built here.
- Accounts, magic links and Google sign-in; Seats stay claimable ids (ADR-0007).
- A stage redesign, a meld map on a stage, or any group-centroid display beyond the one number.
- Precedent scoped per Room. One shared cache was chosen.
- Any change to the meld threshold, the ladder bands, the attempt cap or the beat. They stay named configuration, and a table's calibration is a later couch question.
- Codes that survive the exhaustion of four-letter words; a household will not get there.
- Anything for the evening of 2026-09-04 itself. There is no deadline (design brief, Group play).

## Further Notes

**The reveal is still the product.** ADR-0010 was chosen for the phone reveal: every word, one number, one quip. Keep the performance the couch got — the climbing number, the band arriving, the quip — and give the two furthest words a line of their own rather than a footnote, because at four that line is where the next Attempt comes from.

**"At two Seats nothing changes" is a test, not a promise.** The fake's two-word grade, the two-Seat reducer tests and the two-Seat LiveView tests are the proof. If the rewrite makes any of them want a new assertion, that is a finding to surface, not a test to update.

**The Scribe's word is a gift, not a gate.** Creation must never wait long or fail for want of a model. The timeout is a setting; the fallback is a real word; the digest that goes to Gemini is the same digest the Author already reads for a Give.

**Position bias at N** is handled the way it is at two: two orderings, roster and reverse, averaged, disagreement recorded. Twenty-four orderings of four words are not graded and no new statistic is invented.

**Naming.** Player-facing copy says Room and Code. The glossary has both; the design brief records why "guest", "game", "join code" and "host" were not adopted.
