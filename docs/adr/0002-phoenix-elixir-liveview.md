---
status: accepted
---

# Phoenix, Elixir, and LiveView for the game server and UI

Our research ranked Node/TypeScript + Socket.IO first and Phoenix second for this couch-multiplayer shape (docs/research/couch-sync-stack.md, docs/research/oss-couch-games.md). We chose Phoenix/LiveView anyway (2026-09-01): rooms, presence, and rejoin are framework natives; one supervised process per room matches "one authoritative state document plus a phase machine"; each seat's LiveView renders its own redacted view, so the private-phone/public-laptop split comes free; and it needs far less client code. Jacob also wants to learn Elixir — under the project's fun-first rule, the builder's fun counts.

## Considered options

- **Node/TypeScript + Socket.IO**: fastest iteration, an official Anthropic SDK, and all the read-first open-source prior art in the same ecosystem. Not rejected on merit — it remains the fallback.

## Consequences

- Every model call is raw HTTP (no official Elixir SDK from any provider), behind one adapter module; streaming is parsed by hand.
- Every interaction round-trips to the VPS. Acceptable for turn-based play with little animation; rich touch interaction, if ever needed, goes into JS hooks.
- ~~Kill criterion: if a two-phone room with rejoin isn't working after three evenings of work, switch to the TypeScript stack.~~ **Passed 2026-09-03**, well inside the three evenings: two phones and a laptop stage in a Room on <https://meld.stephens.page>, a tab closed and reopened straight back into its own Seat, a phone locked and unlocked without losing it (ticket 02). Phoenix stays and the TypeScript fallback is off the table. The design — state document, phase machine, named seats — was stack-agnostic and no longer needs to be.
