# 06: The reveal, revised

**What to build:** On a Pixel, the reveal is the Bridges, the number climbing into its band, and the quip — visible together without scrolling. The Assayer's reasoning is no longer on any screen; it lives in the Chronicle, book and export. The band's flavour line and the "furthest apart" line are gone (the Again button already names both words). The game's name, the Chronicle link and "You are …" move to a footer. The Code card is present in every phase so a player can show a friend how to join. The fairness taps, the arc at the close and every control stay. The stage shows the same reveal, large, without reasoning. Spec section: The web; the view's `reasoning` in The Game.

**Blocked by:** 01 (Anchors become Bookends).

**Status:** ready-for-agent

- [ ] The rules' reveal view carries no reasoning; the Chronicle entry and the Verdict rows still do, and the book and Markdown export still show it
- [ ] The phone reveal renders Bridges, then the number and band, then the quip; the flavour line, the reasoning card and the furthest line are removed on phone and stage
- [ ] The header (name, Chronicle link) and "You are …" render below the reveal as a footer; the Code card renders in every phase, full Room included
- [ ] The fairness taps, the arc at the close, Again, One more and Overrule are where they were
- [ ] LiveView and component tests assert the new order and the absence of reasoning on screen
- [ ] Verified on a Pixel on the deployment: Bridges, number, band and quip fit the first screen
