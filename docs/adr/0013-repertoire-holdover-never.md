---
status: accepted
---

# Repertoire, holdover, and Never

The five shipped house loops are too small a wait set, and a Track that dies at “One more?” makes a short Page feel like the night stopped. Decision: wait music is the **Repertoire** — those five loops plus every kept Track — shuffled, not a fixed starter. A Room whose Chronicle already holds a Track draws from that Room’s Tracks and the five; a Room with none draws from the whole set, so a new Code can hear the rest of the game. Once a Page’s Track is playable it takes the Speaker (even during writing) and **holds over** until the next Page’s Track lands. **Next** advances a session shuffle of wait music only; **Never** is this Room’s verdict that a member will not be drawn here again (the last remaining member cannot be); **House** is occupancy, not a verdict — it does not start a score and does not cancel one in flight.

## Considered options

- **Keep five static loops, reset at each Page.** Rejected: the night goes silent or back to The Porch at giving, and the same five wear out.
- **Always shuffle the whole game, including other Rooms, even after this Chronicle has Tracks.** Rejected: community flavor is for an unsettled Room; once this table has songs, those take precedence.
- **Account-scoped draw or Never.** Rejected until claiming is how people find music; Chronicle and Never stay per Room.
- **Next also skips this Page’s Track; House banishes.** Rejected: this Page’s Track is the setting they just named — leave it with Never or Off; House means “not this, not a verdict.”
- **Score every Page even in House.** Rejected: a House-all-night table should listen to the Repertoire without paying for songs the Speaker never played.

## Consequences

`next_page` and the Author kickoff must not nil a playing Track. Foley must push music in giving and writing, and must fade this Page’s Track in as soon as it is playable rather than waiting for bridging. How fast that Track is *written* (Mureka stream, a shorter bed, or both) is a separate question; this ADR is occupancy.
