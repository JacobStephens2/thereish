# 08: Bookends and Your bridge

**What to build:** The table gets the game's names for its parts. A small caption reading "Bookends", in the style of the "Attempt 1 of 5" line, sits over the pair on the phone and on the Stage; the Bridge input is labelled "Your bridge" instead of "The word between them", and the committed-Bridge line says the same. Nothing else about the layout moves — the fold is `.scratch/at-the-table/issues/11` and `12`. Spec section: the Solution's fourth sentence; design brief, Captions.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] "Bookends" renders as a caption over the pair wherever the Bookends render, phone and Stage, in the existing caption style
- [x] The Bridge input's label reads "Your bridge"; the committed-Bridge line under bridging reads "Your bridge: …"
- [x] The LiveView tests that read the label or the pair are updated and pass; a components test asserts the caption

## Answer

1. Extracted reusable `<.caption>` component in `lib/meaning_game_web/components/room_components.ex` sharing the caption styling (`text-center text-sm uppercase tracking-widest opacity-60`) across `<.attempt>` and `<.bookends>`, rendering the "Bookends" caption over the pair on both phone and Stage.
2. Updated Bridge input form label in `lib/meaning_game_web/live/room_live.ex` from "The word between them" to "Your bridge".
3. Updated committed Bridge line in `lib/meaning_game_web/live/room_live.ex` to `Your bridge: <span class="font-semibold">{@room.your_bridge}</span>`.
4. Added component tests in `test/meaning_game_web/components/room_components_test.exs` verifying `<.caption>` and the "Bookends" caption.
5. Updated `test/meaning_game_web/live/room_live_test.exs` asserting the "Bookends" caption on phone and stage, the "Your bridge" input label, and the "Your bridge: <word>" committed text.
