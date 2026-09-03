# Meaning Game

Shared language for a two-player couch word game for Jacob and his wife with a machine author-scribe. Glossary only; the design itself lives in docs/design-brief.md.

## Language

**Room**:
Where a set of Seats plays Pages together — N seats, two by default — with private phone views and a public stage view.
_Avoid_: game, session, lobby, table

**Game**:
The rules themselves, as a pure function: what a Room's state is, what each event does to it, and what a given Seat may see. It is not a synonym for Room — a Room is the process and the people; the Game is only the ruling.
_Avoid_: engine, state machine, logic, rules service

**Seat**:
A place in a Room held by a player under a name. It carries a stable id and its own Chronicle history, and may be claimed by an Account later.
_Avoid_: player (the person), user, slot

**Account**:
An identity that has claimed one or more Seats' histories, so a person's play across rooms and evenings can be read together. Never required to join a Room.
_Avoid_: user, login, profile

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
