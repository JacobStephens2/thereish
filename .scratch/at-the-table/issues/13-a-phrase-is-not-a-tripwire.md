# 13: A phrase is not a tripwire

**What to build:** "Any Bridge you like" (04) let a phrase commit, and then left every function word in that phrase carrying a collision. A Bridge of "the meaning of life" is refused against a Bookend of *theology*, because Legality splits the phrase into words, stems *the* to `"the"` — exactly the three-letter floor — and finds that *theology* starts with it. Nothing etymological happened: it is a three-character string prefix, and the refusal names the collision, so the table is told the two words share a root. The same tripwire is under *and* (bars *android*), *for* (*forest*, *fortune*), *one* (*onerous*), *out*, *all*, *are*. The more naturally a Bridge is phrased, the likelier it is refused — the opposite of what 04 was for.

Two changes, both narrow, in `MeaningGame.Steward.Legality`:

**Function words never carry a collision.** A small closed list of English function words — articles, conjunctions, prepositions, pronouns, the copula — is dropped from both sides before the pairwise comparison in `check_against_barred/2`: a Bridge's *the* bars nothing, and a barred phrase's *the* is barred by nothing. Content words in the same phrase collide exactly as they do now. The list is a module attribute, written out in full and readable at a glance; it is not a stopword library and not the dictionary.

**The prefix floor rises from three to four.** `prefix_overlap?/4` (`lib/meaning_game/steward/legality.ex:194`) is a blunt proxy for a shared root, and at three characters it is mostly wrong. Genuine short roots keep colliding through the stemmer and the inflection table rather than through string prefixes — *runner* / *run* collides on `priv/wordlists/inflections.txt:1`, not on the prefix rule, so the existing assertion at `test/meaning_game/steward/legality_test.exs:126` holds.

The two changes overlap deliberately: either alone would leave the other half of the class live. Together they mean a refusal names a collision a player can see.

Spec sections: The Game (Legality) in `.scratch/at-the-table/spec.md`, whose Legality paragraph and 04's "the existing three-letter floor on prefix overlap" both need the new number and the function-word rule.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] A function-word list is a module attribute in `Legality`; its words are removed from both the Bridge's words and the barred item's words before the pairwise root check, and a test pins the list's effect on *the*, *and*, *for*, *one*, *out* against *theology*, *android*, *forest*, *onerous*, *outfit*
- [ ] "the meaning of life" commits against a Bookend of *theology*; "the lava rock" is still refused against *lava*, naming *lava* — a phrase's content words are untouched
- [ ] A Bridge made only of function words ("the one", "and so") is legal and does not raise; the Assayer scores it as it finds it
- [ ] The prefix floor is four; `shared_root?/2` still answers true for *runner* / *run*, *lanterns* / *lantern*, *harbour* / *harbour*, and the whole existing legality, game and rooms suites pass unchanged
- [ ] A genuine three-letter root that is not in the inflection table (*sea* / *seashore*) no longer collides; this is the accepted cost, recorded here, and the fix if it ever bites is a line in `inflections.txt`, not a lower floor
- [ ] The Author's Bookends still go through the same gate with the same numbers — `check_author_bridge/2` is unchanged in behaviour beyond the two rules above
- [ ] The spec's Legality paragraph and 04's resolved ticket say four and say what function words do

## Comments

**2026-09-07.** Filed from Jacob's playtest notes (`.scratch/ideas/ideas.md`): "I got a strange 'the meaning of life' shares a root with 'theology' — which is an interesting idea, but I think too restrictive on what input the players are using and can type into as their bridges." Cause confirmed by reading `prefix_overlap?/4`: `stem("the")` is three characters and `"theology"` starts with it. Jacob chose both fixes over either alone.
