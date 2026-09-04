# Is "Mind Meld" taken? — trademark, product, and domain availability for the working title

> **This is not legal advice.** It is a research note by a non-lawyer, assembled from public registers and
> product listings. It records what the USPTO register, the dictionaries, the app stores and the domain
> registries actually say on 2026-09-03 — nothing more. Section 8 lists the specific questions that would
> need a real trademark attorney, and the answer to every one of them is "ask a lawyer before you ship."

Researched 2026-09-03 for the [design brief](../design-brief.md) and for naming ticket
`.scratch/naming/issues/01-the-games-real-name.md`, whose first acceptance criterion is this file.
Question: is **Mind-Meld** safe to keep — as a working label inside the repo, and as the name the game
would ship under if it ever left the couch?

Method: primary sources only, fetched 2026-09-03. Trademark facts come from the USPTO's own search API
and its TSDR proxy, and from TTABVUE for proceedings — not from Trademarkia, Justia or any aggregator.
Dictionary facts come from each publisher's own site. Product facts come from the listing pages
themselves (BoardGameGeek, Apple's iTunes Search API, Google Play, Steam, retailer pages). Domain facts
come from registry RDAP and registry WHOIS. Copyright facts come from the US Copyright Office's own
circulars and its Compendium. Where a source could not be reached it is flagged inline as
**could not verify**, and never guessed. Everything in [What this means for the name
decision](#9-what-this-means-for-the-name-decision) is inference.

**Headline: yes, it is taken — in the one class that matters most.** *MIND MELD* is a live, registered US
trademark in **Class 28** covering "party games involving word challenges", owned by a UK toy company that
currently sells a physical party game of that name with a mechanic close to ours. Two shipping games and a
Google Play app already carry the name. See §9 for what that does and does not mean for a couch.

---

## 0. Two premises in the brief that this research corrected

Recording these first, because both were carried into the task assumption and neither survived.

| Premise as stated | What the sources show |
|---|---|
| "*Medium* is published by Spin Master" | **No.** *Medium* (2019) is a **Greater Than Games, LLC** title, designed by Danielle Deley, Lindsey Sherwood and Nathan Thornton ([BGG 242529](https://boardgamegeek.com/boardgame/242529/medium)). Corroborated on the register: Spin Master owns 1,537 US marks and *MEDIUM* is not among them, whereas **Greater Than Games LLC** is the applicant on serial 88269454 for *MEDIUM* in Class 28, card games (now dead — abandoned for failure to respond). |
| "The Jimmy Fallon *Tonight Show* has a segment called Mind Meld" | **Could not confirm — three independent checks came back negative.** The official channel's own search returns "This channel has no content that matched 'mind meld'" ([youtube.com/@FallonTonight](https://www.youtube.com/@FallonTonight/search?query=mind+meld), 14K videos indexed); NBC's own games round-up lists nine games and none is Mind Meld ([nbc.com](https://www.nbc.com/the-tonight-show/exclusives/games-at-home)); Wikipedia's [sketch list](https://en.wikipedia.org/wiki/List_of_The_Tonight_Show_Starring_Jimmy_Fallon_games_and_sketches) contains zero occurrences of the string. The nearest real Fallon segment is **"You Read My Mind."** The name's actual provenance for a game of this shape is **improv theatre** and a 2023 **TikTok trend** — see §3d. Caveat: nbc.com's own site search is JS-rendered and returned nothing extractable, so this is a well-supported negative rather than an exhaustive one. |

---

## 1. The US trademark register

All rows below come from `POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch` — the Elasticsearch
API behind [tmsearch.uspto.gov](https://tmsearch.uspto.gov/), whose base URL is published at
[configuration.json](https://tmsearch.uspto.gov/configuration.json). Each record was then verified
individually against USPTO's own TSDR proxy,
`https://tmsearch.uspto.gov/tsdr-api-v1-0-0/tsdr-api?serialNumber=<serial>`. Human-readable equivalent for
any row: `https://tsdr.uspto.gov/#caseNumber=<serial>&caseSearchType=US_APPLICATION&caseType=DEFAULT&searchType=statusSearch`.

The search was run as `wordmark:*MELD*` across the whole register — 217 hits, all retrieved and filtered —
so the list is exhaustive as of the index load dates in the results, which run to **2026-08-25**. Filings
in the last one to two weeks may not appear.

### 1a. LIVE marks

| Mark | Owner | Serial | Reg. | Class | Status | Filed | Reg'd |
|---|---|---|---|---|---|---|---|
| **MIND MELD** | **Golden Bear Products Limited** (UK) | 97723272 | **7540401** | **IC 028** | **LIVE — REGISTERED** | 2022-12-19 | 2024-10-22 |
| **MINDMELD** | **Cisco Technology, Inc.** | 88541298 | **6521336** | **IC 009** | **LIVE — REGISTERED** | 2019-07-26 | 2021-10-12 |
| MIND MELD | Otivm LLC (CA) | 99789350 | — | IC 041 | LIVE — PUBLISHED FOR OPPOSITION | 2026-04-27 | — |
| MIND MELD | Methodical Mind, LLC (DE) | 99252125 | — | IC 009 | LIVE — first extension granted (intent-to-use) | 2025-06-25 | — |
| METHODICAL MIND MELD | Methodical Mind, LLC | 99252120 | — | IC 009 | LIVE — first extension granted (ITU) | 2025-06-25 | — |
| METHODICAL MIND MELD 11010100101110010000011001001011011 (motion mark) | Methodical Mind, LLC | 99583777 | — | IC 009 | LIVE — response after non-final action entered | 2026-01-08 | — |
| MMP MIND MELD PSYCHOTHERAPY PLLC (design) | Mind Meld Psychotherapy PLLC (VA) | 90829221 | 6831324 | IC 044 | LIVE — REGISTERED | 2021-07-14 | 2022-08-30 |

**The blocker is row one.** Registration **7540401**, *MIND MELD*, Golden Bear Products Ltd., Class 28,
registered 2024-10-22 and live. Its recitation of goods is squarely on top of this project:

> "games, namely, board games, card games, party games…; **party games involving word challenges**…;
> **memory games involving word challenges**…; **board games featuring word challenges**…; tabletop games
> featuring word challenges…"

(TSDR record for serial 97723272.) The first §8 maintenance window — the first moment the registration can
lapse for non-use — opens **2029-10-22**. Golden Bear is not a shell: it currently sells the product (§3c).

**Row two matters for the app-store scenario.** Cisco's *MINDMELD* is live in **Class 009**, the class a
downloadable game app would sit in. Its recitation is entirely conversational-AI software — machine
learning over audio/video/text, voice recognition, chatbots, NLP, APIs — nothing about games or
entertainment. Its first §8 window runs 2026-10-12 → 2027-10-12 (2028-04-12 with grace), so it is due for
maintenance imminently; whether Cisco renews it is unknown and worth re-checking after that date, given the
product itself is dead (§5b).

**Row three matters for the "entertainment services" scenario.** A Class 41 application is already
published for opposition, though its recitation is narrow — documentary and video-portrait programming,
not games.

### 1b. DEAD marks

Recorded because a dead mark shows the name has been repeatedly wanted, and because a lapsed registration
can be revived by a new filing at any time.

| Mark | Owner | Serial | Reg. | Class | Status | Filed |
|---|---|---|---|---|---|---|
| MINDMELD | Expect Labs → **CISCO MINDMELD LLC** | 85596627 | 4419339 | IC 042 | DEAD — cancelled §8, 2020-06-05 | 2012-04-12 |
| MINDMELD | OffWhite Productions LLC | 97550437 | — | IC 035 | DEAD — abandoned, failure to respond, 2023-09-14 | 2022-08-16 |
| MINDMELD | Sierakowski, Michaline | 74434466 | 1877905 | IC 035 | DEAD — cancelled §8, 2002-02-16 | 1993-09-10 |
| MINDMELD ALLIANCE | MindMeld Alliance, LLC (TX) | 77783534 | 4067714 | IC 035, 041 | DEAD — cancelled §8, 2018-07-13 | 2009-07-17 |
| MINDMELD MULTIMEDIA INC. | Mindmeld Multimedia Inc. (Canada) | 75246390 | — | **IC 009, 041** | DEAD — abandoned, 1999-11-19 | 1997-02-24 |
| MIND MELD STUDIOS | MindMeld Studios, LLC (NY) | 98342871 | — | IC 009 | DEAD — abandoned, no statement of use, 2025-09-29 | 2024-01-04 |
| MIND MELD | Cable, Ryan G | 77298104 | — | IC 005 | DEAD — abandoned, no SOU, 2009-01-19 | 2007-10-07 |
| M M MIND MELD INCORPORATED GRAPHIC ARTS (design) | Mind Meld, Inc. (CA) | 75335406 | 2184030 | IC 042 | DEAD — cancelled §8 | 1997-08-04 |
| MEAD MIND MELD ×6 | The Mead Corporation | 75112229 / 75112238 / 75976687 / 75112236 / 75112237 / 75112241 | 2131211 / 2120529 / 2135116 / — / — / — | IC 042, 025, 018, 016 | DEAD — cancelled §8 or abandoned | 1996-05-31 |

**Fifteen US filings on this exact phrase since 1993.** That is the number to hold on to: the name is not
obscure, it is contested.

### 1c. Has the phrase ever been fought over?

**No — TTABVUE shows zero proceedings.** Checked at
[ttabvue.uspto.gov](https://ttabvue.uspto.gov/ttabvue/):

- `propname=mind meld` → "No documents match the query: Proceeding Status is: ALL and Mark Name contains all words: MIND MELD"
- `propname=mindmeld` → "word: MINDMELD is not found"
- `propname=meld` → one unrelated hit only, Cancellation **92074087**, MeldCX Pty Ltd. v. Meld Research Limited (mark *MELD*, Reg. 4644435, filed 2020-04-28, terminated 2020-08-03 on default).
- The `proceedings` array in TSDR is empty (`[]`) for **all fifteen** MIND MELD serials.

So nobody has ever opposed or cancelled a MIND MELD mark. The register has simply been letting them
coexist across unrelated classes — which is exactly what §7 predicts it would do.

---

## 2. Paramount, Star Trek, and how generic "mind meld" has become

### 2a. Paramount / CBS hold nothing on it

**Confirmed against the register: no.** Two independent checks:

- `wordmark:*MELD*` across the whole register (217 hits, all inspected) — **no** Paramount Global,
  Paramount Pictures, CBS Studios, CBS Broadcasting or Viacom entity appears as owner of any of them.
- `ownerFullText:("CBS" OR "Paramount" OR "Viacom") AND wordmark:*MIND*` → 25 hits, all *CRIMINAL MINDS*,
  *MORK & MINDY*, *FREE YOUR MIND*. Nothing MELD-formative.

And they have never asserted it: the TTABVUE queries in §1c with `pn=paramount`, `pn=cbs`,
`pn=cbs+studios` and `pn=viacom` each return "No documents match the query."

What Paramount *does* claim is the umbrella, not the phrase. Verbatim from the footer of
[startrek.com](https://www.startrek.com/):

> "© 2026 CBS Studios Inc., Paramount Pictures Corporation, and CBS Interactive Inc., Paramount companies.
> **STAR TREK and related marks are trademarks of CBS Studios Inc.** All Rights Reserved."

"Vulcan mind meld" appears to be unregistered franchise lore. **Could not verify:** this is register and
TTABVUE evidence only. It does not rule out unregistered common-law rights, nor any non-US register.

Note the shape of the risk, which is *not* trademark: a game called *Mind Meld* with a Star-Trek-adjacent
look — pointed ears, LCARS-orange UI, a Vulcan salute icon — invites a completely different complaint
(trade dress, copyright in franchise elements) that the bare phrase does not. Keep the phrase, skip the
livery.

### 2b. Genericization — what the dictionaries actually carry

Checked on each publisher's own site, 2026-09-03. The result is more interesting than a simple yes/no: the
phrase is **lexicalized in the historical record and absent from every current general dictionary.**

| Publisher | Entry for "mind meld"? | Evidence |
|---|---|---|
| **Oxford English Dictionary** | **Yes — three entries** | [`mind-meld, n.`](https://www.oed.com/dictionary/mind-meld_n) "First published 2002"; earliest known use **1968**, "in the writing of J. M. Lucas"; definition (search-results snippet; full text paywalled) "**A (supposed) technique for the psychic fusion of…**"; frequency "**Fewer than 0.01 occurrences per million words in modern written English**". [`mind-meld, v.`](https://www.oed.com/dictionary/mind-meld_v) "First published 2006"; earliest use **1984**, "in the *Washington Post*"; intransitive, "to engage in a mind-meld". `mind-melding, n.` **1968–**, per the nearby-entries list on both pages. |
| **Merriam-Webster** | **No** | [merriam-webster.com/dictionary/mind-meld](https://www.merriam-webster.com/dictionary/mind-meld) and `/dictionary/mind%20meld` both return "The word you've entered isn't in the dictionary." |
| **Dictionary.com** | **No** | [dictionary.com/browse/mind-meld](https://www.dictionary.com/browse/mind-meld) redirects to `/browse/hand-held?q=mind-meld&mismatchType=misspelling` — it is treated as a **misspelling of "hand-held"**. |
| **Collins** | **No** | [collinsdictionary.com/dictionary/english/mind-meld](https://www.collinsdictionary.com/dictionary/english/mind-meld) redirects to `/spellcheck/english?q=mind-meld`: "Sorry, no results for "mind-meld" in the English Dictionary." |
| **Cambridge** | **No** | [dictionary.cambridge.org/dictionary/english/mind-meld](https://dictionary.cambridge.org/dictionary/english/mind-meld) redirects to the dictionary home page. |
| **American Heritage, 5th ed.** | **No** | [ahdictionary.com](https://www.ahdictionary.com/word/search.html?q=mind+meld) — "No word definition found." |
| **Oxford/Lexico** (the free Oxford site) | **Formerly yes; site is dead** | Wiktionary's Further-reading cites ""mind-meld, n.", in *Lexico*, Dictionary.com; Oxford University Press, 2019–2022". lexico.com no longer answers at all (TLS connection fails, curl exit 35). |
| Wiktionary (community, not a publisher — listed for context) | Yes | [en.wiktionary.org/wiki/mind_meld](https://en.wiktionary.org/wiki/mind_meld): "(colloquial) A state of deep compatibility in opinion or plans between two people," etymology "From the Star Trek franchise, where the term was first used in 1966". |

**Reading it.** The OED — the one dictionary that records a word once and keeps it — has carried
*mind-meld* as an ordinary English noun since 2002 and as a verb since 2006, dating the noun to 1968 and
the figurative verb to a 1984 newspaper. That is real lexical status: the phrase escaped the franchise
decades ago. But the OED's own frequency band, "fewer than 0.01 occurrences per million words," and the
absence of an entry in **every current general-purpose dictionary checked**, say it is a rare, marked
idiom rather than a dead metaphor like "google" or "xerox".

For the legal question this cuts both ways and mostly does not matter: genericness is a defence against
*Paramount*, who own nothing here anyway (§2a). It is no defence at all against Golden Bear's Class 28
registration, because a mark can be perfectly generic English ("Apple", "Medium") and still be a valid
trademark **for goods it does not describe**. Party games are not psychic fusion.

---

## 3. Existing games and products carrying the name

### 3a. Board games — BoardGameGeek

BGG blocks scripted access (Cloudflare challenge on the site; the XML API now returns "Unauthorized. See
https://boardgamegeek.com/using_the_xml_api"). Results were obtained by driving a real browser against
BGG's own site-search JSON and via `api.geekdo.com/api/geekitems`, which is not gated. Method flagged
because it is a step removed from a plain page fetch.

| Game | Year | Publisher | Designer(s) | BGG |
|---|---|---|---|---|
| **Mindmeld** | 1985 | Tactical Studies Rules (TSR), in the UK RPG magazine *Imagine* #26 | Alan Paull | [99970](https://boardgamegeek.com/boardgame/99970/mindmeld) |
| **MindMeld: The Party Game** | **2023** | **TMI Games** | Zack Boatman, Aaron Frias | [387281](https://boardgamegeek.com/boardgame/387281/mindmeld-the-party-game) |
| Star Trek Panic: Vulcan Mind-Meld Promo Card | 2016 | Fireside Games / The Op Games | Justin De Witt | [205543](https://boardgamegeek.com/boardgame/205543/star-trek-panic-vulcan-mind-meld-promo-card) |

**MindMeld: The Party Game (2023) is the uncomfortable one.** BGG describes it as 4–12 players, in teams,
where "you and your partner draw cards with key words and **try to come up with a word that connects these
two key words**." That is not adjacent to our mechanic. That *is* our mechanic — two anchors, converge on
the bridging word — shipped as cardboard three years ago under our working title.

The 1985 TSR item is a psionic-warfare magazine wargame, long out of print and a database entry only. The
Star Trek item is a promo card, not a game.

### 3b. App stores, Steam, itch

- **iOS: clear.** Queried Apple's own iTunes Search API
  (`https://itunes.apple.com/search?term=mind+meld&entity=software&country=us`, and again for `mindmeld`) —
  21 and 7 results respectively, and **no game is titled Mind Meld or MindMeld in the US store**. The only
  title carrying the word is [IVP Mindmeld](https://apps.apple.com/us/app/ivp-mindmeld/id6443847759), a
  business/fintech tool from Indus Valley Partners, last updated 2023-10-06. Nearest game noise is
  "Meld: Cozy Animal Merge" and "Meld Mind" (a coding-education app), neither related.
- **Google Play: not clear — two live listings hold the string.**
  [**Mind Meld**](https://play.google.com/store/apps/details?id=com.mindmeld.app.mindmeld) by Wvalue
  Martech Private Limited, updated 2025-08-18, a word/pattern puzzle game — the exact string, in the exact
  category. And [**MindMeld: Circuit Puzzle**](https://play.google.com/store/apps/details?id=com.yildizbakansoftwarellc.mindmeld)
  by Osman Gürdal / Yildizbakan Software LLC, updated 2026-08-01, a Turkish-language circuit-rotation
  puzzle. (An older "Math Mind Meld" listing has been renamed and no longer carries the name.)
- **Steam: clear.** Store search for "mind meld" (18 results) and "mindmeld" (1) returns no game with the
  name; the nearest are *Meld*, *MeadowMeld*, *Holomeld*.
  [store.steampowered.com](https://store.steampowered.com/search/?term=mind+meld)
- **itch.io: taken, by our exact game.** [**Mind Meld** by gicklergames](https://gicklergames.itch.io/mindmeld)
  — a free browser game where you and a partner see the same prompt, each type a word, and try to match,
  built for a "Game Creation Challenge (Week 1 of 52)". **Could not verify directly:** itch.io returned a
  Cloudflare "Performing security verification" wall to curl, WebFetch *and* a real browser session on
  repeated attempts, so this description comes from itch's search index of that page, not from the page.
  Worth one manual look.

### 3c. The one that is actually selling: Golden Bear's *Mind Meld*

This is the physical product behind the Class 28 registration in §1a, and it deserves its own subsection
because it is both live and mechanically near.

It is a mass-market party game — headband, prompt cards, squeezy brain — marketed as bringing "the widely
popular TikTok challenge" home. How it plays: the player wearing the headband counts "3, 2, 1" aloud and
shouts the word on the card while another player, grabbing the brain, tries to shout **the same word at
the same time**; you score only on a simultaneous match. In stock and retailing:

- [zatu.com/en-us/products/mind-meld](https://zatu.com/en-us/products/mind-meld) — $22.72, structured data
  gives `"brand":"Golden Bear"`, `availability: InStock`
- [next.co.uk/style/su110959/n48189](https://www.next.co.uk/style/su110959/n48189) — "Golden Bear Mind Meld Game"
- [amazon.co.uk ASIN B0CHS7X2G9](https://www.amazon.co.uk/dp/B0CHS7X2G9) — "MIND MELD the Game, the Brain Game of Telepathic Snap"

**Could not verify:** Golden Bear's own site, golden-bear.co.uk, is returning Cloudflare **error 523
(origin unreachable)** today, so nothing here is confirmed from the manufacturer directly — only from
retailers and from the USPTO record. Note also that this product has **no BGG entry**, which is why §3a
misses it; a BGG-only search would have found nothing and produced the wrong answer.

### 3d. Where the name for *this kind of game* actually comes from

Not Star Trek directly, and not television. **Mind Meld is a standard improv-theatre warm-up.** Hoopla
Impro (a UK improv theatre) documents the canonical rules at
[hooplaimpro.com/mind-meld](https://www.hooplaimpro.com/mind-meld): two players count to three, both say a
word simultaneously, then repeatedly try to converge on a word connecting the previous two, until they say
the identical word.

That is worth reading twice, because it is this project's mechanic in one sentence, it predates every
product above, and it explains the 2023 TikTok trend that Golden Bear packaged. Practically: the name is
not "available and unused"; it is the **established generic name of the game type**, in the same way
"charades" is. That is why four unrelated parties arrived at it independently.

### 3e. Other live commercial uses

- **Mind Meld podcast** — the numbered episode series inside *THIRD EYE DROPS* (host Michael Phillip,
  SpectreVision Radio); every episode is "Mind Meld ###", now past #413. Active: Apple's lookup API shows
  543 episodes, most recent 2026-09-01. [podcasts.apple.com/us/podcast/third-eye-drops/id1091861630](https://podcasts.apple.com/us/podcast/third-eye-drops/id1091861630)
- **Cisco MindMeld** — see §5b. Dead as a product; the mark is live.
- **IVP Mindmeld** — live business software (§3b).

---

## 4. The *Medium* board game, and whether a mechanic can be owned

### 4a. What *Medium* actually is

**Publisher is Greater Than Games, LLC, not Spin Master** (see §0). Published **2019**, 2–8 players,
30–45 minutes; designers **Danielle Deley, Lindsey Sherwood, Nathan Thornton**, artist Sarah Kelly;
licensed editions from Broadway Toys, Conclave Editora, DSV Games, Ghenos Games, Perdix Spiele, Storm
Chaser Games and Synapses Games. [BGG 242529](https://boardgamegeek.com/boardgame/242529/medium). In print.

### 4b. Is the name protected?

**In Class 28, no.** Every *MEDIUM*-formative mark in Class 28 on the register is dead — including Greater
Than Games' own filing, serial 88269454, *MEDIUM* for card games, filed 2019-01-21 and **abandoned for
failure to respond**. The publisher of *Medium* does not hold a US registration on *Medium*.

**In Class 41, yes — and by Paramount, of all people.** Serial 78373283, Reg. **3021915**, *MEDIUM*,
IC 041, "entertainment services in the nature of a dramatic television series," owned by Paramount Pictures
Corporation / CBS Studios Inc., **live, registered and renewed** (filed 2004-02-24, registered 2005-11-29)
— that is the Patricia Arquette TV series. Separately, **A Medium Corporation** (the publishing platform)
holds serial 85893084 / Reg. 5015382 across IC 009/035/038/041/042/045 with §8 & §15 accepted, plus
Reg. 6268532 (IC 009) and Reg. 6268536 (IC 041).

The practical upshot: *Medium* is a worse name than *Mind Meld*, not a better one.

### 4c. Is the converge-on-a-shared-word mechanic protected?

**No, and this is the one part of the whole question with a clean, citable answer.**

- **Statute.** 17 U.S.C. §102(b) excludes "any idea, procedure, process, system, method of operation,
  concept, principle, or discovery, regardless of the form in which it is described, explained,
  illustrated, or embodied in such work."
- **The Copyright Office's own reading**, [Compendium of U.S. Copyright Office Practices (Third)
  ch. 300 §313.3(A)](https://www.copyright.gov/comp3/chap300/ch300-copyrightable-authorship.pdf), page
  dated 01/28/2021. Its enumerated examples include "**Ideas, procedures, processes, or methods for doing,
  making, or building things**", and it states the consequence directly:

  > "copyright owners do not have the right to prevent others from using the ideas, concepts, principles,
  > or discoveries **or from implementing the procedures, processes, systems, or methods of operation**
  > described in such works."

- **On the name itself**, [Circular 33, *Works Not Protected by Copyright*](https://www.copyright.gov/circs/circ33.pdf),
  revised **03/2021**:

  > "Words and short phrases, such as names, titles, and slogans, are uncopyrightable because they contain
  > an insufficient amount of authorship."

  Its list of uncopyrightable items expressly includes "The name of a product or service" and "A domain
  name or URL", and it points the reader onward: "Under certain circumstances, names, titles, or short
  phrases may be protectable under **federal or state trademark laws**."
- **The Office's public FAQ** says the same in one line each: "Copyright does not protect names, titles,
  slogans, or short phrases" and "Copyright does not protect ideas, concepts, systems, or methods of doing
  something." [copyright.gov/help/faq/faq-protect.html](https://www.copyright.gov/help/faq/faq-protect.html)

**Housekeeping:** the factsheet everyone cites for this, **FL-108 "Games"** — the one containing
"copyright does not protect the idea for a game, its name or title, or the method or methods for playing
it" — **is gone from copyright.gov**; `https://www.copyright.gov/fls/fl108.pdf` returns 404, as do two
other plausible paths, checked 2026-09-03. Cite Circular 33 and Compendium §313.3 instead; they say the
same thing and they are current.

What *is* protected in *Medium*, and equally in our game: the specific expression — the actual card text,
the rulebook prose, the artwork, the layout, the code. Not the loop. Copying Greater Than Games' word list
would be infringement; independently building "two anchors, converge on the bridge" is not.

---

## 5. Domains and the Cisco startup

### 5a. Domain status, from registry RDAP and registry WHOIS, 2026-09-03

| Domain | Status | Registrar | Created | Expires | Serves anything? |
|---|---|---|---|---|---|
| **mindmeld.com** | Registered — **Cisco Technology Inc.** | MarkMonitor | 1996-01-18 | 2027-01-19 | **No** — no A/AAAA record at all |
| **mindmeld.game** | **AVAILABLE** | — | — | — | — |
| mindmeld.fun | Registered | GoDaddy | 2025-04-29 | 2027-04-29 | Yes — a Replit "This app isn't live yet" 404 |
| mindmeld.app | Registered | Sav.com | 2026-02-04 | 2027-02-04 | Parked for sale (Afternic → forsale.godaddy.com) |
| mindmeld.io | Registered (Domains By Proxy) | GoDaddy | 2025-12-19 | 2026-12-19 | Parked for sale (Afternic) |
| mindmeld.gg | Registered | Namecheap | 2024-06-24 | annual, "until cancelled" | No — Cloudflare NS, no A record |
| mind-meld.com | Registered | GoDaddy | 2025-10-13 | 2026-10-13 | Parked for sale (Afternic) |
| meaninggame.com | Registered | Gname.com (SG) | 2019-10-18 | 2026-10-18 | Broken — expired TLS cert, 502 behind it |

Sources: [rdap.verisign.com/com/v1/domain/mindmeld.com](https://rdap.verisign.com/com/v1/domain/mindmeld.com)
and the same endpoint for the other `.com`s; `https://rdap.markmonitor.com/rdap/domain/MINDMELD.COM` for the
thick registrant record; `https://pubapi.registry.google/rdap/domain/mindmeld.app`;
`https://rdap.centralnic.com/game/domain/mindmeld.game` (**HTTP 404, "Object not found"** = available, and
`whois -h whois.nic.game` agrees: "DOMAIN NOT FOUND"); registry WHOIS at `whois.nic.fun`, `whois.nic.io`,
`whois.gg` for the rest.

Lookup caveats, recorded rather than smoothed over: `rdap.org` returned HTTP 000 (connection failure) for
`.fun` and `.gg` and a genuine 404 "No RDAP service is available for this resource" for `.io` — registry
WHOIS was used for all three. `.gg` has no working RDAP at all. Nothing was rate-limited.

**Only `mindmeld.game` is actually free.** Three of the rest (.app, .io, mind-meld.com) are domain-investor
inventory parked on Afternic and buyable at a brokered markup; .fun and .gg are held by people with their
own plans. None of this matters much for a game served from `stephens.page`, but it does matter the moment
the game wants its own address.

### 5b. Cisco / the MindMeld startup

The domain and the mark tell the same story from two directions.

- **mindmeld.com is Cisco's and is dark.** The thick RDAP record at MarkMonitor gives registrant
  `"org":" Cisco Technology Inc."`, `"adr": [… "170 W. Tasman Dr.","San Jose","CA","95134"]`,
  `"email":"infosec@cisco.com"`. Nameservers are Route 53, last changed 2018-04-04 — consistent with the
  2017 acquisition handover. It does **not** redirect to cisco.com; `dig` returns no A, AAAA, CNAME, MX or
  TXT, and `curl -sIL https://mindmeld.com` gets HTTP 000, nothing listening. Defensively parked, and
  unobtainable.
- **The original mark is DEAD.** Serial 85596627 / Reg. 4419339, *MINDMELD* (design), IC 042, filed
  2012-04-12 by **Expect Labs, Inc.**, registered 2013-10-15. USPTO's own TSDR `assignments` array records
  the chain **Expect Labs → MINDMELD, INC.** (Delaware, 1 Polk Street Unit 1907, San Francisco) →
  **CISCO MINDMELD LLC** (Delaware, 170 West Tasman Drive, San Jose). Cancelled under §8 on **2020-06-05** —
  Cisco simply let it lapse.
- **A newer Cisco mark is LIVE.** Serial 88541298 / Reg. 6521336, *MINDMELD*, **IC 009**, filed directly by
  Cisco Technology, Inc. 2019-07-26, registered 2021-10-12, no assignments recorded. This is the Class 9
  entry in §1a.
- **The product is dead**: the [cisco/mindmeld](https://github.com/cisco/mindmeld) repo is `archived: true`.

**Could not verify:** assignment reel/frame numbers and recording dates for the Expect Labs → MindMeld, Inc.
→ Cisco MindMeld LLC chain. `assignment-api.uspto.gov` and `assignment.uspto.gov` do not resolve from here,
and `assignmentcenter.uspto.gov` exposes no callable JSON API (its config returns AccessDenied). The chain
itself is confirmed from TSDR; only the recording metadata is missing.

---

## 6. First-pass clearance of the shortlist alternatives

The naming ticket lists eight candidates and says clearing "runs on whichever survive Jacob's reaction."
Since the working USPTO endpoint was already open, here is the register half of that pass, done now rather
than later. Same method and same caveats as §1 — `POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch`,
Classes 009 / 028 / 041, 2026-09-03. Note that `wordmark` is an analyzed field, so a phrase query matches
the phrase anywhere in the mark; every zero-hit result below was control-tested against a near neighbour
(e.g. `"CLOSE ENOUGH"` returns 15 records, `"BETWEEN US"` returns 105) to prove the zero is real and not a
broken query.

| Candidate | Live in IC 9/28/41? | Existing game with the name | Register risk for a word/party game |
|---|---|---|---|
| **Near Enough** | **None — zero records in any class, any status** | Steam 0; nothing on BGG | **Lowest of the eight.** Completely untouched. Weak/suggestive marks are harder to *enforce*, but nothing blocks it. |
| **Deep Meld** | **None — zero records, any class** | Steam 0; nothing on BGG | Clear as filed — **but** it must survive a similarity analysis against Reg. 7540401 *MIND MELD* in the same class. It reads as a deliberate step away from the blocker, which cuts both ways. |
| **Meet Me Halfway** | **None** (2 records, both dead, both out of scope) | Steam 0 | Low-moderate. Phonetically identical to the live *MEAT ME HALFWAY* (Reg. 6931353, IC 041, documentaries). Bigger exposure is a failure-to-function refusal — it is a well-known song title. |
| **The Word Between Us** | **None** — `"WORD BETWEEN US"` returns zero records in any class | Nothing found | Low on the exact phrase, but the "\_\_\_ BETWEEN US" family is busy and includes two **live IC 028 games** — *BETWEEN US GIRLS* (Reg. 7232318, Goliath IP) and *LUST BETWEEN US* (Reg. 8395707) — plus a pending *THE CHANGE BETWEEN US* (99795722, IC 028). Expect a crowded-field examiner search. |
| **Two Heads** | **None live** (only *TWO HEADS MUSIC*, Reg. 3327559, IC 025/041, cancelled §8) | Steam 0 | Low on the register, weak as a distinguisher. *TWO HEADS ARE BETTER THAN ONE* is live in adjacent classes and the phrase is a common idiom — descriptiveness and common-law pushback, not conflict, is the risk. |
| **Betwixt** | IC 028 clear; **IC 009/041 has a brand-new live application** | ⚠️ *Betwixt and Between* (2019, 1–4p) on BGG; *Dungeon Betwixt*, *Marlene Betwixt*, *Flames Betwixt* on Steam | Low-moderate. **DUNGEON BETWIXT** (serial 99928626, Xuan Zhou, IC 009 + 041, filed 2026-07-08, live, not yet examined) becomes a citable reference for any software-side filing if it registers. Cardboard-only use is near-clean. Exact *BETWIXT* is live only in IC 003 (anti-chafe cream). |
| **Halfway** | **None live in 9/28/41**, but IC 041 is dense | ❌ **Two Steam games literally titled *Halfway***, incl. the 2016 turn-based tactics game, plus *Halfway House/Down/Home* | Moderate, and the worst existing-product collision of the eight. IC 041 carries many live HALFWAY-formative registrations (Emagine's four Halloween marks, Evine's *HALFWAY TO CHRISTMAS*, *HALFWAY TO HELL*). IC 028 has only one record ever, and it is dead. |
| **Assay** | **None in 28/41**; IC 009 is full of live *ASSAY* marks | Steam 0; nothing on BGG | Low for games, poor as a brand. The IC 009 crowd is entirely biotech (*ASSAY EXPLORER* Reg. 2402712, *ASSAY CENTRAL* Reg. 6252601, *LEAP ASSAY* Reg. 6245700), so a downloadable-game filing still lands in a class full of live ASSAY marks. And it reads as lab jargon. |

One historical note worth keeping: **Hasbro filed *BIO MELD* in IC 028 in 1996** (serial 75107913) and
abandoned it for want of a statement of use. The MELD family has been circled by toy companies before.

Domains, from the same RDAP method as §5a: **every one of the eight `.com`s is registered, and every one of
the eight `.game`s is free.** So `.com` is not a differentiator among these candidates — if `.game` is
acceptable, all eight are equally open.

**What is still missing for these eight:** common-law use, non-US registers, app-store listings, and
Google Play in particular (only Steam and BGG were checked for existing games). None of them has had the
full treatment §§1–5 gave *Mind Meld*, and none should be treated as cleared on the strength of this table
alone.

---

## 7. What actually matters: hobby use vs. shipping

The law that governs a name is trademark law, and trademark law is not about the word. It is about whether
your use of the word confuses buyers about **who made the thing**. USPTO says this in its own words:

> "you don't have rights to the word or phrase in general, only to **how that word or phrase is used with
> your specific goods or services**." — [uspto.gov, What is a trademark](https://www.uspto.gov/trademarks/basics/what-trademark)

And rights come from trading, not from thinking:

> "You become a trademark owner **as soon as you start using your trademark with your goods or services.**
> You establish rights in your trademark by using it, but those rights are limited, and they only apply to
> the geographic area in which you're providing your goods or services." — same page

The statutory hook is "use in commerce", defined at 15 U.S.C. §1127 as "**the bona fide use of a mark in
the ordinary course of trade**, and not made merely to reserve a right in a mark"
([15 U.S.C. §1127](https://www.law.cornell.edu/uscode/text/15/1127)). Infringement under the Lanham Act
requires use in commerce plus **likelihood of confusion**, which USPTO frames as two questions:

> "If your trademark is confusingly similar to another trademark **and the goods and services are
> related**, consumers are likely to mistakenly believe these goods or services come from the same
> source." Marks may be alike in "sound, appearance, or meaning, or could create a similar commercial
> impression"; goods "could be related if they are identical, similar or competitive; used together; used
> by the same purchasers; advertised together; or sold by the same manufacturer or dealer."
> — [uspto.gov, Likelihood of confusion](https://www.uspto.gov/trademarks/search/likelihood-confusion)

Run this project through those tests at each of four scales:

| Scenario | Use in commerce? | Related goods? | Practical exposure |
|---|---|---|---|
| **Two people on a couch, private URL on `stephens.page`, no money, no listing, no promotion** | No — nothing is traded, nothing is advertised, no "ordinary course of trade" | Moot | **Effectively nil.** There is no plaintiff and no injury. The realistic worst case is a stern email that a robots-noindex page never provokes. |
| **Public but free web game, indexed, shared on social, named Mind Meld** | Arguable — a free service still competes for attention, and advertising a service is use | Yes — Golden Bear's Class 28 recitation is *party games involving word challenges*; ours is a word party game | **Low but real.** The likely first contact is a takedown request or a hosting/registrar complaint, not litigation. Costs nothing to comply with; costs everything if the name is by then baked into the Chronicle. |
| **Listed on the App Store or Google Play** | Yes, unambiguously | Yes — and Google Play already has a live **Mind Meld** word-puzzle app (§3b) | **The sharpest edge, and it isn't the court — it's the store.** Apple's and Google's name/impersonation complaint processes remove listings on request, fast, with no likelihood-of-confusion analysis. A second app named Mind Meld in the same puzzle category is a self-inflicted wound. Class 9 also has Cisco's live *MINDMELD* registration sitting in it. |
| **Sold, or promoted commercially, or crowdfunded as cardboard** | Yes | Directly — same class, same goods, same shelf | **Highest.** Class 28 is Golden Bear's, on the nose, and a shipping product backs it. Also collides commercially with *MindMeld: The Party Game* (2023), which is in the retail channel already. Do not do this without an attorney. |

Two asymmetries are worth naming explicitly:

1. **The register is not the constraint; the store and the search box are.** Nobody has ever litigated this
   phrase (§1c). What actually happens to small projects is a platform takedown or being invisible behind
   four other things with the same name — neither of which requires anyone to be right about the law.
2. **Rename cost is monotonic and the Chronicle makes it worse.** The naming ticket measures 17 doc
   occurrences and **zero in `lib/`** today; a `sed` and a `git mv`. After the build lands it becomes module
   names, routes and player-visible prose — and the Chronicle is append-only, so early Pages would carry
   the old name permanently. The cheap moment to decide is now; the expensive moment is after my wife's
   first session is written down.

---

## 8. What would need a real trademark attorney

Everything below is outside what a register lookup can answer. None of it is needed to keep playing on the
couch; all of it is needed before anything ships.

1. **Does a free, publicly-listed web game infringe Reg. 7540401?** Whether "party games involving word
   challenges" in Class 28 reaches an unmonetized web service, and whether a free service is "use in the
   ordinary course of trade", is a judgment call on facts and case law, not a lookup.
2. **A full likelihood-of-confusion opinion** against Golden Bear (IC 028), Cisco (IC 009) and the pending
   Otivm application (IC 041), applying the full DuPont factor analysis rather than USPTO's two-factor
   summary.
3. **Common-law and unregistered rights** — including Paramount's in Star Trek lore, TMI Games' in
   *MindMeld: The Party Game*, and the Google Play developer's. The register cannot see any of these, and
   §2a's negative finding is explicitly register-only.
4. **Whether any registration could be challenged** — e.g. genericness or descriptiveness of *MIND MELD*
   for a game whose entire subject is melding minds. This is a real argument and it is exactly the kind of
   argument that is expensive to be wrong about.
5. **Non-US registers.** Nothing outside the USPTO was searched. Golden Bear is a **UK** company; UKIPO and
   EUIPO were not checked, and neither were Madrid filings that do not designate the US.
6. **The app-store scenario specifically** — clearance for a Class 9 filing, and the collision with the
   live Google Play listing.
7. **Trade dress**, if the game ever wears Star Trek livery (§2a).

Also worth re-checking rather than lawyering: Cisco's Reg. 6521336 has its first §8 maintenance window
2026-10-12 → 2027-10-12. If Cisco lets it lapse the way it let the 2013 registration lapse, Class 9 gets
materially quieter.

---

## 9. What this means for the name decision

**Inference from §§1–8. This is the recommendation, not a finding.**

**Is it taken? Yes — decisively, and in the worst possible place.** Not by Paramount, which was the risk
everyone assumed and which turns out to be empty (§2a). By **Golden Bear Products Ltd.**, whose live
US Class 28 registration for *MIND MELD* names "party games involving word challenges" and who is selling
the box today. And separately by **MindMeld: The Party Game** (TMI Games, 2023), which already ships our
exact mechanic under our exact working title; by a **live Google Play** word puzzle called Mind Meld; and
by an **itch.io browser game** that is, as far as its own listing describes it, this project in miniature.

**The three findings that actually change the decision:**

1. **Reg. 7540401 exists and is on the nose.** A live Class 28 registration reciting *party games involving
   word challenges*, backed by a product in retail, with no maintenance window until 2029. This is not a
   dormant paper mark.
2. **Mind Meld is the generic name of this game type, not a name for it.** The improv warm-up documented at
   [Hoopla Impro](https://www.hooplaimpro.com/mind-meld) *is* our loop — count to three, converge on a
   connecting word, repeat until you match — and it predates every product found. The 2023 TikTok trend and
   Golden Bear's box are downstream of it. Calling our game Mind Meld is like calling it *Charades*: not
   wrong, but it names the category and buys no distinctiveness. It also guarantees the game is
   permanently invisible behind four other things in any search box.
3. **Paramount is a non-issue, and so is the mechanic.** No CBS/Paramount mark, no assertion ever
   (§1c, §2a); and mechanics are categorically outside copyright per the Copyright Office's own Compendium
   §313.3(A) and Circular 33 (§4c). Both of the fears that made this research feel urgent are unfounded.
   The real problem was the boring one: an ordinary toy company got there first.

**Recommendation, in two parts:**

- **As a working title, inside the repo, right now: keep it.** Nothing about a private game on
  `stephens.page`, played by two people, with no listing and no promotion, is "use in the ordinary course
  of trade." The exposure is nil (§7, row 1). Renaming before couch night would spend the project's scarce
  attention on the one question the ticket correctly says cannot be answered until my wife has played —
  what the game *feels* like. Do not let this note reopen a decision the ticket already parked well.
  Two cheap hygiene measures while it stays: keep the deployment `noindex`, and keep the visual identity
  clear of Star Trek livery.
- **As a shipped name — public, listed, promoted, or sold: no. Retire it.** It fails on trademark
  (Class 28, live, on-point), it fails on app-store collision (Google Play, same category), it fails on
  distinctiveness (it is the category's generic name), and it fails on taste for the reason the naming
  ticket already identified independently: *it names the win, and this game's pleasure is the miss.* Four
  separate reasons pointing the same direction is as clear as a naming signal gets.

**Concretely, for the ticket:** treat "Mind-Meld" the way the brief already treats "Chronicle Clover" —
explicitly a placeholder with a known collision, recorded here. Let couch night decide the real name, then
finish the clearance on whichever candidate wins; the working USPTO endpoint is recorded in §1, so the next
pass is a ten-minute job rather than a rediscovery, and §6 has already done the register half for all
eight.

The happy accident is that the register agrees with the ticket's own taste argument. The shortlist reasoned
that the names describing *the miss* are the right register for this game; §6 finds that **Near Enough** is
the single cleanest name of the eight — zero USPTO records in any class, in any status, nothing on Steam or
BGG — and **Deep Meld** is next, also at zero. **Betwixt**, the ticket's other favourite, is the one to
re-check rather than assume: Class 28 is clear, but *DUNGEON BETWIXT* was filed in Classes 9 and 41 on
2026-07-08 and is live and unexamined, and a 2019 board game called *Betwixt and Between* already sits in
the same 1–4-player space. **Halfway** should be dropped outright — two Steam games are literally titled
*Halfway*.

`mindmeld.game` being the only free domain in §5a is not an argument for keeping the name; it is the tell
that everything else was taken years ago. All eight alternatives have a free `.game` too.
