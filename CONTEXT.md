# Thereish

Shared language for a couch word game for Jacob and Melissa — two players by default, more when friends join — with a machine author-scribe. Glossary only; the design itself lives in docs/design-brief.md.

## Language

**Room**:
Where a set of Seats plays Pages together — N seats, two by default — with private phone views and, when there is a screen for it, a public stage view. A Room of four phones and no stage is still a Room.
_Avoid_: game, session, lobby, table

**Code**:
The four-letter word a Room is known by, read aloud so others can join. The Scribe picks it with a nod to the creator's past play when there is any; otherwise it is drawn at random.
_Avoid_: slug, link, room id, PIN, join code

**Stage**:
The Room's public screen — a laptop on the table, holding no Seat — where the reveal is performed to everyone at once while the phones go quiet. Any phone can make its device the Stage; a Room without one is still a Room.
_Avoid_: display, TV, big screen, host screen, dashboard, "the laptop" (in copy)

**Game**:
The rules themselves, as a pure function: what a Room's state is, what each event does to it, and what a given Seat may see. It is not a synonym for Room — a Room is the process and the people; the Game is only the ruling.
_Avoid_: engine, state machine, logic, rules service

**Seat**:
A place in a Room held by a player under a name. It carries a stable id and its own Chronicle history, and may be claimed by an Account later.
_Avoid_: player (the person), user, slot

**Side**:
A grouping of Seats within a Room that play together as a unit — two couples at a table play as two Sides on the same Bookends.
_Avoid_: team, pair (pair is the Assayer's two Bridges), couple (informal copy only), squad

**Account**:
An identity that has claimed one or more Seats' histories, so a person's play across rooms and evenings can be read together. Never required to join a Room.
_Avoid_: user, login, profile

**Page**:
One self-contained unit of play — ends cleanly in one sitting (about 10–15 minutes) and chains into the next. Every Page played is written into the Chronicle.
_Avoid_: board, round, hand, session, match

**Chapter**:
A themed run of Pages exploring one meaning-space — a place, an era, a season of life, a thinker's vein. A direction, not yet a mechanism: since Pages are written at the table from Gives (ADR-0011) nothing groups them.
_Avoid_: campaign, level, theme pack, world, mode

**Give**:
A theme a player supplies to open a Page — improv's audience suggestion, at Page scale rather than Chapter scale. Every Seat gives one before a Page is written, each Bookend comes from a different Give, and a Give is secret to its giver until the Page's first reveal. Player-facing copy says "setting".
_Avoid_: suggestion, request, custom theme, prompt

**Mask**:
The small picture a Seat wears for one Page, drawn by the Limner from that Seat's Give: abstracted a step away from the Give rather than illustrating it, so it hints without telling. A Mask shows to its own giver at once; on the Stage it lies face-down from the moment the Give lands until the Page's first reveal, then turns over and stays with the Page in the Chronicle. It is also the marker that lights when that Seat's Bridge lands.
_Avoid_: avatar, icon (in copy), profile picture, token, sigil, portrait

**Steward**:
The one seam through which the game talks to generative models — language, music, sound, and pictures. The Author, the Assayer, the Scribe, the Foley, and the Limner are its roles; model choice, caching, hedging, A/B assignment, spend, and guardrails live behind it.
_Avoid_: Keeper (the earlier name), AI, "the LLM", model service, brain

**Author**:
The machine role that writes a Page at the table: two Bookends drawn from the Seats' Gives, in the seconds after the last Give lands. It wrote Pages ahead of play, with Bait, until ADR-0011.
_Avoid_: generator, constructor, game master, "the LLM"

**Assayer**:
The machine role that measures at the reveal — how close the Bridges landed — and writes its reasoning into the Chronicle rather than saying it aloud. It grades; it never rules. (A nod to Melissa's daily lab assays.)
_Avoid_: judge, referee, grader, meter, reader, umpire

**Scribe**:
The machine role that writes the Chronicle after play — records, recaps, callbacks.
_Avoid_: logger, narrator, historian

**Foley**:
The machine role that makes what the Room hears — the stings, the Repertoire, and the Track written for a Page's Gives. (Named for the theatre's sound artist; the stage, the beat and the reveal are already its vocabulary.)
_Avoid_: composer, sound designer, DJ, audio service

**Limner**:
The machine role that draws — a Mask for every Seat at the top of every Page, in one house style so a night's Masks read as a set. (Named for the illustrator of a manuscript's pages.) Lives behind the Steward like the other roles.
_Avoid_: illustrator, image model, artist, "the image AI", painter

**Speaker**:
The one device in a Room that plays what Foley makes — the Stage when one is open, otherwise the phone that claimed it; claiming it silences whoever had it. Held by a device, not a Seat, so a phone with no Seat can hold it.
_Avoid_: audio device, output, host phone, "the sound", speakerphone

**Voice**:
Foley speaking the Assayer's band word, and its Quip when Quips are shown, at the reveal. A setting of the device holding the Speaker, off unless that device turns it on; stings sound regardless.
_Avoid_: narration, TTS, voiceover, announcer, read-aloud

**Track**:
The instrumental Foley writes for one Page from its Gives. It is titled by the Scribe and kept, so the same Gives bring the same Track back — a song the Chronicle can remember. A Track belongs to its Page; it may still be what the Speaker is playing after that Page has closed, until the next Page's Track lands.
_Avoid_: song (in code), background music, BGM, soundtrack, loop (a Repertoire draw is not this Page's Track)

**Prologue**:
The three sentences that tell a table what Thereish is and what a Meld is, spoken by Foley from the Stage's first tap the first time a Room with no Chronicle opens, and on request after that. A fixed script, kept in several readings so a repeat hearing is not the same take. It stays silent when Voice is off and shows its words on the Stage either way; a phone-only Room shows the words as a card instead. Skipping it is the Room's, remembered.
_Avoid_: tutorial, onboarding, intro (in code), how-to-play, rules screen, narration

**Vamp**:
The short instrumental Foley gets back in seconds so the Speaker has something written for this Page's Gives while the Track is still being made. Thrown away once the Track lands: never titled, never kept, never a Repertoire member. (Theatre's word for the band playing until the singer is ready.)
_Avoid_: intro clip, placeholder track, bed (the listen report's word), stopgap, preview

**Repertoire**:
The instrumentals Foley may play when this night has no Track of its own on the Speaker yet — the five loops shipped with the game, and every Track that has been kept. A Room whose Chronicle already holds a Track is drawn from that Room's Tracks and the five loops; a Room with none is drawn from the whole set. The pick is a shuffle, not a fixed starter. A Room may mark a member Never so it is not drawn there again; the last remaining member cannot be.
_Avoid_: library, catalog, playlist, pool, house book, house loop (the loops are members; the set is the Repertoire)

**House**:
Speaker occupancy that plays a shuffle from the Repertoire rather than this Page's Track. Not a verdict on the Track.
_Avoid_: house loop (the loops are Repertoire members), "house loop only" (the earlier switch)

**Never**:
A Room's verdict that one Repertoire member will not be drawn again in that Room. The file remains for every other Room.
_Avoid_: dismiss, hide, ban, skip (that is Next)

**Bookends**:
The two words — or two-word phrases — a Page shows; each player writes the Bridge between them. Chosen from different Gives to stand far apart.
_Avoid_: anchors (the earlier name), clues, prompt (collides with the model-prompt sense), pair, cue

**Bridge**:
A player's answer — the word or phrase whose meaning spans the Bookends. Anything goes except a Bookend or a Bridge this Page has already seen, root and all.
_Avoid_: answer, guess, submission

**Attempt**:
One try at a Page: a set of Bookends, a Bridge from every Seat, and one Verdict on all of them. A Page gets a fixed number of them, and a miss carries the two Bridges that landed furthest apart forward as the next Attempt's Bookends, so the Attempts of one Page are a converging arc rather than repeated guesses.
_Avoid_: try, turn, round, guess, retry

**Meld**:
A converged Bridge — the players' Bridges assayed close enough to count as one mind.
_Avoid_: match, hit, win

**Verdict**:
What the Assayer says about one Attempt's Bridges, read together: a Closeness, the reasoning behind it, and which two Bridges landed furthest apart. An Attempt the Assayer could not grade has no Verdict, which is a thing the game says out loud rather than a zero it invents.
_Avoid_: result, judgement, ruling (the players rule; the Assayer only grades)

**Quip**:
The Assayer's one line of comedy at the reveal, written about the Bridges the players actually wrote. It rides on the Verdict beside the reasoning and is not the grade's justification — it is what makes the graded number a punchline rather than a ruling. Also the Scribe's one line about the Room's Code, shown beneath the Code on the Code card, in the Stage's header beside the join line, and under each rejoin link on the front page.
_Avoid_: joke (on its own), flavour text, band script (the Author's prewritten fallback), roast

**Phase**:
Where a Page has got to — waiting for the Room to fill, bridging, assaying, revealed. It is derived from the state rather than stored in it, so nothing has to remember to advance it.
_Avoid_: status, step, stage (the laptop is the stage), state

**Closeness**:
How far an Attempt's Bridges are from being one mind, on the Ladder's scale — one reading for the whole set, which at two Seats is how near two words landed to each other. Three tight words and one stray read as close, not as a miss.
_Avoid_: score, similarity, distance, rating

**Ladder**:
The scale a Closeness is read on and the bands it is read into — miss, adjacent, close, almost, meld, deep meld. A Meld starts at the floor of the meld band; deep meld is the top rung, the same word written twice. Boundaries are configuration, because every one of them is a calibration question the couch answers; the wording that dresses a band is the Assayer's.
_Avoid_: scale (on its own), rubric, tiers, grade bands

**Beat**:
The fixed pause between the last Bridge committed and the reveal. It is theatre, not a wait: the Assayer grades during it, and a verdict that lands early is held until it is over.
_Avoid_: delay, loading, spinner, timeout

**Bait**:
Retired (ADR-0011). The obvious Bridge the Author used to plant, converging on which was a Meld on the lowest rung; kept here so the `bait_against_plain` lines in early Chronicles can be read.
_Avoid_: decoy, trap, red herring

**Band**:
One rung of the ladder the Assayer grades onto, named in words the players hear rather than by its number.
_Avoid_: tier, bucket, rank, grade (that's the number itself)

**Precedent**:
The cached verdict that future identical inputs inherit — the grade the players saw. Only a joint overrule rewrites it.
_Avoid_: cache entry, ruling, second opinion

**Recap**:
The Scribe's paragraph about one closed Page, written after play in the players' own words back to them. It carries no number: the grade is the Verdict's and a recap never restates one. Player-editable like everything else in the Chronicle, and a Page the Scribe could not write about simply has none.
_Avoid_: summary, narration, AI summary, blurb

**Callback**:
The line in a Recap that reaches back to an earlier Page — the sentence next month that remembers tonight's candy cane. It touches the Chronicle and nothing else: a callback never becomes the Author's next Bookends. A Room with nothing behind it has no callback rather than an invented one.
_Avoid_: reference, easter egg, throwback, memory

**Chronicle**:
The persistent, player-visible and player-editable record of one Room's play history — every Page, every ruling, every overrule — kept by the machine and woven back into that Room's future Pages. Every Room has its own.
_Avoid_: save file, memory file, history, CONTEXT.md (that's this glossary)
