# 04: Never

**What to build:** A Room can refuse a Repertoire member forever, without flipping House. Never is this Room’s verdict, persisted, shown next to Next on wait music and still shown on this Page’s Track. It does not delete the file or other Rooms’ draws. The last remaining playable member cannot be Never’d. Never on this Page’s Track: banish, Speaker shuffles the Repertoire, mode stays Written for this Page, this Track will not hold over. Spec sections: Next and Never; Schema.

**Blocked by:** 03 (Next).

**Status:** ready-for-agent

- [ ] Never in this Room leaves the member out of every later draw here, including after a reload and a process restart
- [ ] The same member remains drawable in another Room
- [ ] Never on the last remaining playable member is refused; Next stays hidden
- [ ] Never on this Page’s Track banishes it, the Speaker advances the deal, mode stays `page`, and that Track does not hold over into the next Page
- [ ] Never on holdover banishes that old Track here and advances the deal; this Page’s in-flight Track can still land
- [ ] Never renders on the speaking screen only, including while this Page’s Track is playing (when Next is hidden)
- [ ] Room tests for persistence, cross-Room isolation, last-member protection, and no-holdover after Never on this Track; LiveView tests for the control’s visibility
