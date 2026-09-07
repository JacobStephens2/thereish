# 12: The stage fits the laptop

**What to build:** The stage is a laptop on the coffee table, full screen, that nobody touches while they play — the screen in a Jackbox evening. On the third playtest (2026-09-06; screenshot at `.scratch/ideas/screenshots/stage-not-showing-as-much-info-on-laptop.png`, a 1512×908 CSS-pixel viewport) the reveal did not fit: the header, the join line, the Attempt, the Bookends, three Bridges and the number filled the screen, the quip was cut off at the bottom edge, and someone had to reach over and scroll. Everything the reveal is made of — the Bookends, every Bridge (up to the seat cap of six), the number and its band, and the quip — fits above the fold at once. The header shrinks to one line; the join URL and the roster become one compact strip at the foot of the screen rather than sections of their own; the vertical rhythm is set by the viewport rather than by fixed gaps. The phone layout is 11 and is untouched here.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] At 1512×908 and at 1366×768 CSS pixels, a Page in `:reveal` with three Bridges shows the Attempt, the Bookends, every Bridge, the number and band, and the whole quip without scrolling; with six Bridges the same, the Bridges wrapping
- [x] The same two viewports in `:giving`, `:writing`, `:bridging`, `:assaying` and `:closed` (the ending and the arc) fit without scrolling
- [x] The Thereish heading, the stage's controls and the Chronicle link share one line; the join URL and the roster are one strip at the foot
- [x] The Bridges and the number stay the largest type on the screen — the stage is read from a couch, not a chair
- [x] The stage LiveView tests pass unchanged or with position assertions added; verified by screenshot at both viewports, recorded here

## Answer

1. **Header**: Shrunk to a single line containing the "Thereish" heading, sound / foley controls, and the Chronicle link. Join URL was removed from the header.
2. **Footer Strip**: The join URL and roster now share a single compact horizontal strip across the foot of the stage (`<footer ...>`). The separate "In the Room" section heading and vertical list were replaced by horizontal inline seat badges and open seats indicator (`mode: :stage`).
3. **Viewport Vertical Rhythm**: The stage layout container now uses viewport height (`h-screen max-h-screen`) and adaptive spacing (`gap-[clamp(0.5rem,1.8vh,1.5rem)]`) with centered middle content, replacing fixed margins and large gaps (`py-16`, `gap-12`).
4. **Reveal & Typography**:
   - Comparison cards and container max-width were expanded on stage (`max-w-4xl`) with `min-w-[120px] max-w-[240px] basis-40 sm:basis-48` so 3 bridges fit side-by-side on one row and 6 bridges wrap cleanly without overflowing.
   - The Number (`text-7xl sm:text-8xl md:text-9xl` = 128px) and Bridges (`text-2xl sm:text-3xl md:text-4xl` = 36px) remain the largest type on the screen, readable from the couch.
   - Quip (`text-xl sm:text-2xl md:text-3xl`) and ending lines / arc in `:closed` fit comfortably within the viewport.
5. **Verification**:
   - Automated CDP Chrome script verified that across both viewports (1512×908 and 1366×768) and all 7 states (`giving`, `writing`, `bridging`, `assaying`, `reveal_3bridges`, `reveal_6bridges`, and `closed_arc`), `scrollHeight <= innerHeight` (no scrollbar / no overflow).
   - Screenshots captured and recorded at `.scratch/at-the-table/screenshots/`:
     - `giving_1512x908.png`, `giving_1366x768.png`
     - `writing_1512x908.png`, `writing_1366x768.png`
     - `bridging_1512x908.png`, `bridging_1366x768.png`
     - `assaying_1512x908.png`, `assaying_1366x768.png`
     - `reveal_3bridges_1512x908.png`, `reveal_3bridges_1366x768.png`
     - `reveal_6bridges_1512x908.png`, `reveal_6bridges_1366x768.png`
     - `closed_arc_1512x908.png`, `closed_arc_1366x768.png`
   - All tests pass (611 tests, 0 failures).
