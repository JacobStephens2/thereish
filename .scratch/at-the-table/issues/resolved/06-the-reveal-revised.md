# 06: The reveal, revised

**What to build:** On a Pixel, the reveal is the Bridges, the number climbing into its band, and the quip — visible together without scrolling. The Assayer's reasoning is no longer on any screen; it lives in the Chronicle, book and export. The band's flavour line and the "furthest apart" line are gone (the Again button already names both words). The game's name, the Chronicle link and "You are …" move to a footer. The Code card is present in every phase so a player can show a friend how to join. The fairness taps, the arc at the close and every control stay. The stage shows the same reveal, large, without reasoning. Spec section: The web; the view's `reasoning` in The Game.

**Blocked by:** 01 (Anchors become Bookends).

**Status:** resolved

- [x] The rules' reveal view carries no reasoning; the Chronicle entry and the Verdict rows still do, and the book and Markdown export still show it
- [x] The phone reveal renders Bridges, then the number and band, then the quip; the flavour line, the reasoning card and the furthest line are removed on phone and stage
- [x] The header (name, Chronicle link) and "You are …" render below the reveal as a footer; the Code card renders in every phase, full Room included
- [x] The fairness taps, the arc at the close, Again, One more and Overrule are where they were
- [x] LiveView and component tests assert the new order and the absence of reasoning on screen
- [ ] Verified on a Pixel on the deployment: Bridges, number, band and quip fit the first screen

## Answer

1. **Rules reveal view**: `MeaningGame.Game.view/2` deletes `:reasoning` from `reveal` so no reasoning appears on screen. `chronicle_verdict` and the Chronicle entry still retain `reasoning` on each verdict.
2. **Reveal component**: In `MeaningGameWeb.RoomComponents.reveal/1`, the phone and stage reveal renders Bridges (`data-role="comparison"`), then the number and band (`data-role="closeness-display"`), then the quip (`data-role="quip"`). The reasoning card, the band flavour line, and the "furthest apart" line are removed.
3. **Header and footer**: In `MeaningGameWeb.RoomLive`, the top header (game title, Chronicle link) and "You are …" are moved to a footer below the reveal and game content.
4. **Code card**: Rendered in every phase (including when the Room is full) by removing the `:if={@room.open_seats > 0}` condition from `[data-role="room-code"]`.
5. **Controls**: Fairness controls, overrule controls, Again, One more, and ending arc remain in their established positions.
6. **Tests**: All component and LiveView tests updated to assert the new order, absence of reasoning/flavour/furthest text, and presence of room-code and footer; full test suite passes with 434 tests, 0 failures.
