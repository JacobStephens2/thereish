# 10: The reveal is a performance

**What to build:** The beat, the side-by-side Bridges, the number climbing into its band, the reasoning line, the quip that names what they actually wrote, and the Meld landing like a Meld. Stage 0's finding was that a 24 out of 100 from a stub Assayer with a toy heuristic drew a laugh out loud. The graded number is the comedy delivery mechanism, so the ladder flavour and the reasoning line are load-bearing rather than chrome.

This is the ticket where the product is either fun or it isn't. Budget real effort.

**Blocked by:** 05.

**Status:** resolved

- [x] The 2.5 second beat is visibly a beat, not a spinner, on both the stage and the phones
- [x] Both Bridges land side by side before the number does, so the comparison reads first
- [x] The number arrives with weight, and the band name arrives with it
- [x] The Assayer's reasoning is always shown, phrased so the players can argue with it
- [x] The quip names the players' actual Bridges and reads as a punchline rather than as feedback
- [x] A harsh grade is staged as the shared joke, not the personal sting. The beat stays 2.5 seconds for it in v1
- [x] A Meld is staged as an arrival, distinct from a near miss
- [x] The stage and the phones show complementary things rather than the same thing shrunk, exploiting the private and public split
- [x] The 10 second no-verdict path is staged as the game handing over the ruling, and reads as deliberate rather than broken
- [x] Legible across a room on a laptop and in the hand on a Pixel

## Comments

**The 2.5s beat is theatre.** Replaced generic loading text with a visual beat meter (`[data-role="beat-meter"]`) and rhythmic cadence dots on both phones and the laptop stage. No spinners anywhere. Escalation transitions seamlessly if the Assayer exceeds the beat.

**Side-by-side comparison & climbing number.** Both Bridges land side-by-side in `[data-role="comparison"]` so players read each other's submissions before the score lands. The number climbs with weight via the `.ClimbNumber` colocated hook, counting up with ease-out cubic motion into its band.

**Meld arrival vs shared comedy miss.** A Meld is staged as an arrival with celebratory styling, prominent primary glow, and "One mind, two heads." A harsh grade (0–39 miss) is staged as a deadpan comedy punchline ("Different roads entirely.", neutral styling), never an error or personal sting.

**The Quip and the Assayer's case.** The Quip is formatted with punchline typography (`font-serif italic font-medium`) naming both bridges. The Assayer's reasoning is framed in a dedicated card ("The Assayer's reasoning"), making the argument clear so players can debate or overrule it.

**Private / public screen split.** Phones highlight `(you)` on the player's own bridge card and host actionable controls (`again`, `one-more`, `propose_overrule`). The stage renders in `data-mode="stage"` with grand cross-room typography (`text-8xl sm:text-9xl` closeness, `text-2xl sm:text-3xl` quip) and hands-free display.

**Deliberate no-verdict handover.** At the 10-second escalation limit, the game steps aside with dignity ("The Assayer steps aside. No verdict. This one is yours to call."), ceding ruling authority to the couple rather than looking broken.
