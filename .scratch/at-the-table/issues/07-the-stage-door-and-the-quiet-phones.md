# 07: The stage door and the quiet phones

**What to build:** A laptop opens the game, types the Code, and taps **Make this device the Stage** on the Room page — no URL is ever typed. While a stage is connected, every phone's reveal goes quiet: the Bridges and the controls (Again, One more, Overrule, the fairness taps), and no number, band or quip, so every eye goes up. When the stage leaves, the phones show the full reveal again. The Room process knows nothing of this; Presence does. Spec sections: Rooms and the Room process (Presence), The web.

**Blocked by:** 02 (The Page is written at the table), 06 (The reveal, revised).

**Status:** ready-for-agent

- [ ] The Room page shows a "Make this device the Stage" button whether or not the device holds a Seat; it navigates to the Room's stage route
- [ ] A Presence module on the Room's topic tracks every connected view as stage or phone; phone views read it on mount and on every diff
- [ ] While a stage is present, a phone's reveal renders Bridges and controls only; the stage renders the full reveal; when the stage disconnects the phones return to the full reveal
- [ ] The stage's giving state (from 03) and Bookends render while phones give and bridge
- [ ] A LiveView test with two phones and a stage asserts the quiet reveal on both phones, the full reveal on the stage, and the return when the stage view exits; the two-phone tests without a stage are unchanged
- [ ] Verified on the deployment with two phones and a laptop
