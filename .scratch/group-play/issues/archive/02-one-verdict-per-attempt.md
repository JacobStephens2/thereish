# 02: One Verdict per Attempt in the rules, the Room and the reveal

**What to build:** A Page at any number of Seats is graded once per Attempt. The last commit owes one assay carrying every Bridge; the reveal shows every Bridge, one number and band, one quip, one sentence of reasoning, and the two words that landed furthest apart; the Page melds when that one number reaches the meld band; and those two words become the next Attempt's Anchors. At two Seats the couch sees the game it already knows, plus a carry line that names the words. At three, the tests that used to grade three pairs now grade one set.

**Blocked by:** 01 (The Assayer reads every Bridge together).

**Status:** resolved

This is the ruling of ADR-0010 applied to the rules module, the Room process and the reveal. It is the largest ticket; it may be split into rules-only and Room-plus-reveal if one context window is not enough, in which case the rules land first with their tests and the Room follows.

**The rules.** An Attempt holds one Verdict or none instead of a map keyed by pair. `verdict_received` and `verdict_unavailable` no longer carry a pair. Phase stays derived: waiting until full, bridging until every Seat has committed, assaying until the Verdict is in or given up on, then reveal or closed. The headline is the Verdict's Closeness, not a mean. Meld is the headline reaching the meld band; the attempt cap is unchanged. Carry-forward is the Verdict's furthest pair; when there is no Verdict, the first two Bridges in roster order carry and the view says the Assayer did not choose them. An overrule targets the Attempt's Verdict — no pair attribute, no default pair — and needs every Seat in the Room; a decline clears it. A fairness tap targets the Attempt's Verdict, one per Seat per Attempt. The view for a Seat shows every Bridge with names, its own marked; the one Verdict; the furthest words by name; the roster; and the carry words at reveal. The `pairs` list in the view goes away. The rules should still read top to bottom in one sitting.

**The Room.** One outstanding assay per Attempt: the escalation ladder is armed when it is asked and stood down when it answers; `unavailable` records the one Verdict as absent. The eight-second provisional reading reads "every Bridge": all identical, then all among the likely Bridges, then any, then miss. The beat, holding the Verdict until the beat is over, Gives, arms and the Chronicle write at Page close do not change.

**The reveal.** The components draw one Verdict: every Bridge card, the climbing number and band, the quip, the reasoning, a line naming the two furthest words, then the fairness taps on phones. Flavour copy is count-aware ("One mind, two heads" at two, four at four). The carry line names the words. The stage draws the same components.

- [x] The last commit owes exactly one assay carrying every Bridge in roster order, plus the beat
- [x] One Verdict reveals for every Seat; the headline is its Closeness; the Page melds when it reaches the meld band
- [x] The two furthest words carry forward as the next Anchors; with no Verdict, the first two in roster order carry and the view says so
- [x] An overrule needs every Seat in the Room; three of four is not enough; a decline clears the proposal; the overrule rewrites Precedent for the Bridge list
- [x] A fairness tap records against the Attempt's Verdict with every Bridge
- [x] The Room escalates one slow Verdict to provisional and then to no verdict, and the provisional reading treats "every Bridge" correctly
- [x] The reveal on phone and stage shows every Bridge, one number, one band, one quip, one reasoning line, the two furthest words by name, and count-aware copy
- [x] The rules tests drive four Seats through commit, reveal, carry, overrule and tap on the projected view; the three-Seat tests are rewritten for one Verdict
- [x] The Room tests cover creation of four Seats, one reveal after the beat, escalation, and snapshot-back
- [~] Every two-Seat test in the rules, Room and LiveView suites passes with its assertions unchanged — with one exception this ticket's own ruling forces: the two-Seat tests that read `reveal.pairs` had to be rewritten against the one Verdict, because "the `pairs` list in the view goes away". Every other two-Seat test kept its assertions; the helper *call shapes* changed (one closeness rather than a list) but not what they assert.
