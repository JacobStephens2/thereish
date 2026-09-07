# 08: Bookends and Your bridge

**What to build:** The table gets the game's names for its parts. A small caption reading "Bookends", in the style of the "Attempt 1 of 5" line, sits over the pair on the phone and on the Stage; the Bridge input is labelled "Your bridge" instead of "The word between them", and the committed-Bridge line says the same. Nothing else about the layout moves — the fold is `.scratch/at-the-table/issues/11` and `12`. Spec section: the Solution's fourth sentence; design brief, Captions.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] "Bookends" renders as a caption over the pair wherever the Bookends render, phone and Stage, in the existing caption style
- [ ] The Bridge input's label reads "Your bridge"; the committed-Bridge line under bridging reads "Your bridge: …"
- [ ] The LiveView tests that read the label or the pair are updated and pass; a components test asserts the caption
