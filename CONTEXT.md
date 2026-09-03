# Meaning Game

Shared language for a two-player couch word game for Jacob and his wife with a machine author-scribe. Glossary only; the design itself lives in docs/design-brief.md.

## Language

**Page**:
One self-contained unit of play — ends cleanly in one sitting (about 10–15 minutes) and chains into the next. Every Page played is written into the Chronicle.
_Avoid_: board, round, hand, session, match

**Chapter**:
A themed run of Pages exploring one meaning-space — a place, an era, a season of life, a thinker's vein.
_Avoid_: campaign, level, theme pack, world, mode

**Give**:
A theme supplied on the spot by a player that sets the current Page — improv's audience suggestion, at Page scale rather than Chapter scale.
_Avoid_: suggestion, request, custom theme

**Keeper**:
The one seam through which the game talks to language models. The Author, the Assayer, and the Scribe are its roles; model choice, caching, hedging, A/B assignment, and guardrails live behind it.
_Avoid_: AI, "the LLM", model service, brain

**Author**:
The machine role that builds Pages before play — word sets, authored misdirection, decoys, Chapter content.
_Avoid_: generator, constructor, game master, "the LLM"

**Assayer**:
The machine role that measures at the reveal — how close two answers land, whether a clue is legal — and shows its reasoning. It grades; it never rules. (A nod to my wife's daily lab assays.)
_Avoid_: judge, referee, grader, meter, reader, umpire

**Scribe**:
The machine role that writes the Chronicle after play — records, recaps, callbacks.
_Avoid_: logger, narrator, historian

**Anchors**:
The two words a Mind-Meld Page shows; each player writes the Bridge between them.
_Avoid_: prompt (collides with the model-prompt sense), pair, cue

**Bridge**:
A player's answer — the word whose meaning spans the Anchors.
_Avoid_: answer, guess, submission

**Meld**:
A converged Bridge — the players' Bridges assayed close enough to count as one mind.
_Avoid_: match, hit, win

**Bait**:
The obvious Bridge the Author plants; converging on it is a Meld on the lowest rung.
_Avoid_: decoy (the clover's word), trap, red herring

**Precedent**:
The cached verdict that future identical inputs inherit — the grade the players saw. Only a joint overrule rewrites it.
_Avoid_: cache entry, ruling, second opinion

**Chronicle**:
The persistent, player-visible and player-editable record of the couple's play history — every Page, every ruling, every overrule — kept by the machine and woven back into future Pages.
_Avoid_: save file, memory file, history, CONTEXT.md (that's this glossary)
