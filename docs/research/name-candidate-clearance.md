# Near Enough / Ballpark / Thereabouts — finishing the collision clearance

> **This is not legal advice.** It is a research note by a non-lawyer, assembled from public registers and
> product listings on **2026-09-04**. It records what the app stores, Steam, TMview, IP Australia and the
> open web actually returned on that date — nothing more.

Companion to [name-mind-meld-availability.md](./name-mind-meld-availability.md), which killed *Mind Meld*
and left three survivors. That note did the **US trademark register** half of the clearance
([§6](./name-mind-meld-availability.md#6-first-pass-clearance-of-the-shortlist-alternatives)): all three
candidates came back at or near zero USPTO records in Classes 9/28/41. **That work is not repeated here.**
This note finishes the other five axes the earlier note explicitly listed as missing: app stores, other game
storefronts, search visibility, non-US registers, and common-law use.

Method: primary sources, fetched 2026-09-04. iOS facts come from Apple's own iTunes Search API. Android
facts come from the Google Play listing pages themselves. Steam facts come from Steam's own store-search
JSON. Non-US register facts come from **TMview** (`POST https://www.tmdn.org/tmview/api/search/results`,
the API behind [tmdn.org/tmview](https://www.tmdn.org/tmview/)) and, where TMview's status looked stale,
from the national register directly. Every zero-result query was control-tested against a near neighbour so
the zero is provably a real zero and not a broken query. Where a source could not be reached it is flagged
**could not verify** inline and never guessed. §7 is inference; everything above it is finding.

**Headline: the ranking changes.** *Near Enough* stays the top pick but is no longer "completely untouched" —
there is a live, exact-name game on Google Play. *Ballpark* is the worst of the three by a wide margin and
should be dropped. *Thereabouts* is register-clean outside the US but is already the name of a live
two-player "who got closer" web game, which is the single most on-the-nose collision found in this whole
pass.

---

## 1. Summary table

| | **Near Enough** | **Ballpark** | **Thereabouts** |
|---|---|---|---|
| **Apple App Store** | Clear — 0 results, US/GB/AU | Clear on the bare word, but the category is MLB's | Clear — 0 results, US/GB/AU |
| **Google Play** | ❌ **Exact-name game, live** (Kernelx, upd. 2026-02-25) | ❌ **MLB Ballpark**, official, tens of millions of installs | Clear — no app of that name; JCPenney's app tops the query |
| **Steam** | Clear | Clear (no title *Ballpark*; genre is full of baseball) | Clear |
| **itch.io** | **could not verify** (Cloudflare 403) | **could not verify** (Cloudflare 403) | **could not verify** (Cloudflare 403) |
| **BoardGameGeek** | No game found | ❌ Several *Ballpark*-formative baseball games | No game found |
| **Live web game with the exact name** | No (defunct *studio* of that name) | ❌ **ballparkgame.com** — daily business guessing game | ❌ **thereabouts.gg** — two-player geography guessing duel |
| **UKIPO / EUIPO, cls. 9/28/41** | **Zero records, any class, any status** | 4 records; one **live GB cls. 28 application** | **Zero records, any class, any status** |
| **Worldwide exact-match register** | 1 record ever, dead, unrelated | 39 records in 9/28/41 alone | 9 records; JCPenney owns the live ones (cls. 25) |
| **Searchability of `<name> game`** | Poor — dominated by a defunct indie studio | **Hopeless** — baseball, MLB, and a daily game already there | Poor — thereabouts.gg is result #1 for the game sense |
| **Reads as generic?** | Yes, as a British/Australian colloquialism | Yes, "ballpark figure" is the idiom | Mildly — a formal adverb, less worn |

---

## 2. Near Enough

### 2a. Apple App Store — clear

`https://itunes.apple.com/search?term=near+enough&entity=software&country=us` → **`resultCount: 0`**.
Same query at `country=gb` and `country=au` → **0** and **0**. `term=nearenough` → **0**.

**Control test:** the identical query for `close+enough` returns **23** results, and `hereabouts` returns
**1** ([Hereabout App](https://apps.apple.com/us/app/hereabout-app/id6478040527)). So the endpoint works and
the zero is real. Caveat worth stating: Apple's search API is relevance-ranked and not a title index, so a
zero is strong evidence of no *findable* app by that name, not proof of no listing anywhere.

### 2b. Google Play — **not clear. Exact name, live, and it is a game.**

[**Near Enough**](https://play.google.com/store/apps/details?id=com.kernelx.nearenough), package
`com.kernelx.nearenough`, developer **Kernelx**, **updated 2026-02-25**, contains ads and in-app purchases.
It is the **top result** for the Play query `near enough`. Verbatim from the listing's own metadata:

> "Annoying fun game where one small mistake sends you back. Stay near, fail fast!"

and from the description body:

> "Near Enough is a fun and annoying adventure game made to test your patience, timing, and focus… If you
> enjoy rage games, challenging gameplay, and shouting 'I was so close!' — Near Enough game is for you."

So: a live, maintained, monetised **rage/precision platformer** under our exact name. Developer site given
in the listing metadata is `https://workkhushalkd-blip.github.io`, which reads as a hobbyist/asset-flip
operation rather than a company — but it is live, and Play's own duplicate-name and impersonation
complaint processes do not weigh how serious a developer is.

Note the irony, which is also the problem: its pitch — *"I was so close!"* — is the same emotional register
this project chose the name for. The name is doing the same job for someone else, in the same store.

### 2c. Steam, itch.io, BGG

- **Steam: clear.** `store.steampowered.com/api/storesearch/?term=near enough` → **0 results**;
  the HTML search endpoint returns 25 fuzzy-matched titles (*Dumpster Gang*, *The Long Dark*, …) and **no
  title containing the phrase**. Control: the same endpoint for `portal` returns *Portal*, *Portal 2*, etc.
- **itch.io: could not verify.** `https://itch.io/search?q=near+enough` returns **HTTP 403** (Cloudflare) to
  curl, as it did for the earlier note. Indirect search restricted to itch.io surfaces
  [*Close Enough* by EmGM](https://emgm.itch.io/close-enough) (a math game) but nothing titled *Near Enough*.
  Worth one manual look in a browser.
- **BoardGameGeek: no game found.** BGG's XML API returns `Unauthorized. See
  https://boardgamegeek.com/using_the_xml_api` to every scripted request and the site itself is behind a
  Cloudflare challenge, so this is an indirect negative. Searches surface *Near and Far*, *Fair Enough*, and
  a publisher called *Good Enough Games* — **not** a game called *Near Enough*.

### 2d. Search visibility — **the weakest part of this candidate**

Query: `near enough game`. What comes back is dominated by **Near Enough Games**, a defunct indie studio:

- [giantbomb.com/near-enough-games](https://www.giantbomb.com/near-enough-games/3010-9035/)
- [delistedgames.com/companies/near-enough-games](https://delistedgames.com/companies/near-enough-games/)
- [under-the-ocean.fandom.com/wiki/Near_Enough_Games](https://under-the-ocean.fandom.com/wiki/Near_Enough_Games)

Founded by Paul Hart (formerly Paul Greasley), it made *Under the Garden* (2010) and *Under the Ocean*,
which was **pulled from Steam Early Access on 2015-02-05** and abandoned with a "The Last Update" post on
2018-09-26 ([PC Gamer](https://www.pcgamer.com/under-the-ocean-pulled-from-steam-early-access/),
[Kotaku](https://kotaku.com/game-maker-says-fuck-that-to-keeping-unfinished-game-on-1684274354)).

This is a **soft** blocker, not a hard one: the studio is dead, holds no register entry, and "Games" is part
of its name. But it means the exact query `near enough game` currently returns *a game company called Near
Enough* as its dominant sense, and that SEO position was earned over a decade. A new small project would sit
behind it, plus behind the Play listing in §2b, plus behind the ordinary English use of the phrase.

### 2e. UKIPO / EUIPO — **completely clear**

TMview, offices `GB` + `EM` (EUIPO):

| Query | Result |
|---|---|
| `criteria=E` (exact), `near enough`, GB+EM, all classes | **0** |
| `criteria=C` (contains), `near enough`, GB+EM, all classes | **0** |
| `criteria=C`, `near enough`, GB+EM, Nice 9/28/41 | **0** |
| `criteria=C`, `near enough`, **worldwide**, Nice 9/28/41 | **0** |
| `criteria=E`, `near enough`, **worldwide, all offices, all classes** | **1** — *NEAR 'NUFF*, US 75107831, Advanced Health Institute, cls. 5/29/30/31/32, **Ended** |

**Control test:** the identical GB+EM query for `lego` returns records beginning with UK00001109710 (LEGO
Juris A/S), so the office filter and the endpoint both work.

That is as clean as a register result gets: **one dead US filing on a misspelling, worldwide, ever.**

### 2f. Common-law use as a game name, and the genericism question

- **Near Enough Games** (§2d) — a defunct studio, not a game.
- No party game, quiz or puzzle of this name found on any storefront, on BGG, or in general search.
- **It is a stock colloquialism.** Longman records it as a phrase meaning "so nearly true that the
  difference does not matter" ([ldoceonline.com/dictionary/near-enough](https://www.ldoceonline.com/dictionary/near-enough))
  and it carries an entry in the [Free Dictionary's idiom
  database](https://idioms.thefreedictionary.com/near+enough). Usage is chiefly British, and shared with
  Australian English; the fuller Australian form *"near enough is good enough"* is a well-worn
  disparagement of sloppy work. **Could not verify:** no dictionary consulted labels the phrase
  *Australian* specifically, so treat "notably Australian" as folk knowledge rather than an established
  lexicographic fact.

**Does that make it generic?** For trademark purposes, no — genericness is judged against the goods, and
"near enough" does not name a category of game the way *Mind Meld* named the improv warm-up. For
*findability*, it is a real cost: the phrase is unremarkable English, and unremarkable English is what makes
a name unsearchable.

---

## 3. Ballpark

### 3a. Apple App Store — the word belongs to baseball

`itunes.apple.com/search?term=ballpark&entity=software&country=us` → **30 results**. No app is titled
exactly *Ballpark*, but the field is owned:

| App | Publisher | Category |
|---|---|---|
| [MLB Ballpark](https://apps.apple.com/us/app/mlb-ballpark/id513135722) | Major League Baseball Advanced Media | Sports |
| [BallparkDJ Walkout Intros](https://apps.apple.com/us/app/ballparkdj-walkout-intros/id821956884) | Chad Payne | Sports |
| [BallParked](https://apps.apple.com/us/app/ballparked/id6761742844) | Benjamin Strauss | Sports |
| [The Ballpark at AFS](https://apps.apple.com/us/app/the-ballpark-at-afs/id6742337189) | Overlap Interactive LLC | Entertainment |
| [Ballpark Matchups](https://apps.apple.com/us/app/ballpark-matchups/id6770288002) | Nicolas Richards | Sports |
| [Ballpark Bucket List](https://apps.apple.com/us/app/ballpark-bucket-list/id6760527708) | Sunny LLC | Sports |
| [Ballpark Events](https://apps.apple.com/us/app/ballpark-events/id6450802025) | Ball Park Entertainment Pty Ltd | Business |
| [Las Vegas Ballpark](https://apps.apple.com/us/app/las-vegas-ballpark/id6477839620) | Summerlin LV Baseball Club | Sports |

GB and AU storefronts return the same shape, plus [Ballpark Research](https://apps.apple.com/gb/app/ballpark-research/id1490459570)
(Ballpark Labs Ltd, Productivity) in the UK. **Zero of these are word games.** The exact single word is
technically free on iOS — and completely buried.

### 3b. Google Play — MLB owns the query

Play search `ballpark` returns ten apps, headed by
[**MLB Ballpark**](https://play.google.com/store/apps/details?id=com.bamnetworks.mobile.android.ballpark)
(`com.bamnetworks.mobile.android.ballpark`), MLB's official ticketing/at-the-park app, followed by MLB
At Bat, MiLB, Ballparks of America, BallparkDJ, SeatGeek, Ticketmaster, StubHub. No app is titled exactly
*Ballpark*; every result is baseball or ticketing. A word game called *Ballpark* would rank behind all of
them forever.

### 3c. Steam, itch.io, BGG

- **Steam: clear on the exact title.** `storesearch` → **0**; the HTML endpoint returns 25 baseball titles
  (*Backyard Baseball '01*, *Super Mega Baseball 3*, *Out of the Park Baseball 26*, …) and **no game named
  *Ballpark***.
- **itch.io: could not verify** (403, as above). Indirect search finds baseball games and tags, no title
  *Ballpark*.
- **BoardGameGeek: crowded.** [Ballpark Classics Baseball](https://boardgamegeek.com/boardgame/42966/ballpark-classics-baseball),
  [Ball Park Baseball](https://boardgamegeek.com/boardgame/18600/ball-park-baseball),
  [Old School Ball Park](https://boardgamegeek.com/boardgame/91341/old-school-ball-park),
  [Pocket Ballpark](https://boardgamegeek.com/boardgame/257802/pocket-ballpark),
  [Cranium Ballpark Blast](https://boardgamegeek.com/boardgame/30208/cranium-ballpark-blast), and
  [Ballpark Classics](https://boardgamegeek.com/boardgamepublisher/9550/ballpark-classics) as a publisher.
  All baseball; none is a word game; all of them stand between us and the name.

### 3d. Search visibility — **the deciding finding, and it is fatal**

Query `ballpark game` returns, in order: BGG baseball games, dictionary entries for the word
([Merriam-Webster](https://www.merriam-webster.com/dictionary/ballpark),
[Vocabulary.com](https://www.vocabulary.com/dictionary/ballpark)), MLB's
[official Ballpark app page](https://www.mlb.com/apps/ballpark), baseball-stadium Wikipedia articles,
[Ballpark Pal](https://www.ballparkpal.com/) — and then:

> [**Ballpark — The Daily Business Guessing Game**](https://ballparkgame.com/)

From the site's own `<head>`, fetched 2026-09-04:

> `<title>Ballpark — The Daily Business Guessing Game | Guess Revenue, Valuation & Founding Year</title>`
> `<meta name="description" content="Ballpark is a free daily game for business minds. You know the company — now guess its founding year, revenue, and valuation. Score how close you get and share your result. A new company every day.">`

Read that description again. It is a **free daily guessing game scored on how close you got, with a
shareable result** — the Wordle-descendant shape, under our exact candidate name, on the exact domain
`ballparkgame.com`. Free, no account, browser-based; "hundreds of well-known American and European
companies, with a new one featured every day." No creator name, copyright line or trademark notice appears
on the page, and no app is mentioned. **Could not verify:** who runs it, when it launched, or how much
traffic it has.

So *Ballpark* is not merely a crowded English word. The one non-baseball slot in that search space is
already occupied by a game of the same genre.

### 3e. UKIPO / EUIPO / elsewhere

TMview, offices `GB` + `EM`:

| Mark | Office | Number | Status | Nice | Owner | Filed |
|---|---|---|---|---|---|---|
| BALLPARK | GB | UK00001492859 | Expired | 9 | BMC Programs Ltd | 1992-03-03 |
| BallPark | EM | 003869344 | Expired | 18, 25, 28 | SAMATEX S.r.l. | 2004-06-03 |
| Ballpark Cost | GB | UK00002648614 | Expired | 9, 42 | Presson Ltd | 2013-01-14 |
| **BALLPARK LEGENDS** | **GB** | **UK00004432973** | **Filed (live, pending)** | **28** | Mr Jamie Cuffy | **2026-08-19** |

The GB and EUIPO exact-word marks are both **expired**, which is good. The live item is
**BALLPARK LEGENDS**, a UK **Class 28** application filed three weeks ago and not yet examined — a
games-and-toys filing in the same family, in the register we would care about if this ever went to
cardboard in the UK. **Could not verify:** its goods recitation. UKIPO's own search service
(`trademarks.ipo.gov.uk`, `www.ipo.gov.uk/trademark/data/…`, `soap.ipo.gov.uk`) returns **HTTP 403 "Service
Captcha"** to every scripted request, so this row is TMview's summary only.

Worldwide, `BALLPARK` **exact** in Nice 9/28/41 returns **39 records** — the densest of the three candidates
by an order of magnitude. Highlights: **MLB BALLPARK** (US 88787756, cls. 9, Registered, MLB Advanced Media)
and **MLB BALLPARK** (US 88787685, cls. 41, Registered) — i.e. MLB holds the exact "MLB Ballpark" string in
*the software class a game app would file in*; **AT THE BALLPARK** (US 85591272, cls. 9/35/38/41,
Registered, MLB Advanced Media); **BALLPARK** (CN 57117553, cls. 28, Registered, 2021); *TD BALLPARK*,
*SMITH'S BALLPARK*, *BOUT AT THE BALLPARK*, *BRAWL IN THE BALLPARK* (All Elite Wrestling, filed 2026-05-20).

**One TMview row needed correcting from the national register.** TMview reports `BALLPARK`, **AU 623620**,
Class 28, as *Registered* — which would have been a live Australian toys-and-games registration on the exact
word. [IP Australia's own record](https://search.ipaustralia.gov.au/trademarks/search/view/623620) says
otherwise:

> Status: "removed - not renewed: Renewal fee not paid" · Status change to Removed/Ceased — Not Renewed,
> **08 Sep 2021** · Kind: **Figurative** · Class 28: "Baseball bats, fielding gloves, batting gloves,
> catchers and umpires protective equipment in this class" · Endorsement: **"Registration gives no right to
> the exclusive use of … the word BALLPARK."**

Three things follow. The mark is **dead**. It was a *device* mark for baseball equipment, never the bare
word. And IP Australia made the owners **disclaim exclusive rights in the word BALLPARK** outright — a
registrar's finding, on the record, that the word alone is not distinctive. Also live in Australia:
`Ballpark`, AU 2055666, cls. 35/36/39/41, **Registered**, **Crocmedia Pty Ltd**, filed 2019-12-05 — a sports
media company, in a class that touches entertainment services. **Treat TMview status fields as
indicative only; they are demonstrably stale.**

### 3f. Common-law use

"Ballpark" is not a game name in common law so much as a **stock idiom**: *ballpark figure*, *in the
ballpark*, *ballpark estimate*. Merriam-Webster carries it as an ordinary
[dictionary entry](https://www.merriam-webster.com/dictionary/ballpark). The word's commercial identity in
the US is baseball stadia and MLB's app; its estimation sense is the *reason* it is attractive for this
game, and also the reason it cannot be owned or found.

---

## 4. Thereabouts

### 4a. Apple App Store — clear

`itunes.apple.com/search?term=thereabouts&entity=software` → **`resultCount: 0`** in **US, GB and AU**.
Control: `hereabouts` returns 1 result on the same endpoint, so the query is sound. Nothing on iOS.

### 4b. Google Play — no app of the name, but the query belongs to JCPenney

Play search `thereabouts` returns 30 apps and **none is called Thereabouts**. The top hit is `com.jcp` —
**the JCPenney app** — followed by unrelated retail and school apps (Kohl's, Wayfair, Depop, Torrid,
ThredUp, ParentSquare). The reason JCPenney tops the query is §4e: *Thereabouts* is their kids' clothing
brand. So the name is *free* on Play and simultaneously *not yours* in Play's own search index.

### 4c. Steam, itch.io, BGG

- **Steam: clear.** `storesearch` → **0 results**. No title contains the word.
- **itch.io: could not verify** (Cloudflare 403). Indirect search surfaces no game of this title.
- **BoardGameGeek: no game found.** Same indirect-negative caveat as §2c.

### 4d. Search visibility — **an exact-name live game, and it is two-player**

Query `thereabouts game`. Result: [**thereabouts.gg**](https://thereabouts.gg/). From the page's own
`<head>`, fetched 2026-09-04:

> `<title>Thereabouts — Cultural Geography Guessing Game</title>`
> `<meta name="description" content="Challenge a friend to a cultural geography guessing duel. Place your pin, compare guesses, and see who got closer.">`
> `<meta property="og:description" content="Challenge a friend: look at the clue, place your pin, and see who got closer.">`

**This is the most uncomfortable finding in the note.** It is a live, currently-served web game (HTTP 200),
named exactly *Thereabouts*, on the obvious `.gg` domain, whose entire premise is **two people, one clue,
compare answers, see who got closer**. That is a different subject matter (map pins, not words) but the same
shape and the same emotional promise: *near-miss scoring between two players*.

**Could not verify:** who made it, when it launched, whether it is maintained, or whether it has any users.
It is a Vite single-page app (`/assets/index-D0wZmMlm.js`) with no visible copyright, author, footer or
about page in the served HTML; the only attribution present is a commented-out Noun Project icon credit.
It could be a weekend project with fifty players. It is nonetheless result #1 for the game sense of the word.

Other noise on the query: the [*Thereabouts* cycling film series](https://velo.outsideonline.com/gravel/gravel-culture/thereabouts-reprise/)
by Australian pro cyclists Lachlan and Angus Morton (which is also the source of the dead AU/US marks in
§4e), a [Merriam-Webster entry](https://www.merriam-webster.com/dictionary/thereabouts), and JCPenney
pyjamas on eBay. The word is less crowded than "ballpark", but the game slot is taken.

### 4e. UKIPO / EUIPO / elsewhere

TMview, offices `GB` + `EM`:

| Query | Result |
|---|---|
| `criteria=E` (exact), `thereabouts`, GB+EM, all classes | **0** |
| `criteria=C` (contains), `thereabouts`, GB+EM, all classes | **0** |
| `criteria=C`, `thereabouts`, GB+EM, Nice 9/28/41 | **0** |

**Zero UK and zero EU records of any kind, in any class, in any status.** Same `lego` control as §2e.

Worldwide **exact** match, all offices, all classes — 9 records, none of them games:

| Mark | Office | Number | Status | Nice | Owner | Filed |
|---|---|---|---|---|---|---|
| THEREABOUTS | US | 88984666 | **Registered** | 25 | **PENNEY IP LLC** | 2020-05-04 |
| THEREABOUTS | US | 90978089 | **Registered** | 25 | **PENNEY IP LLC** | 2020-11-02 |
| THEREABOUTS | MX | 2981735 | **Registered** | 25 | **PENNEY IP LLC** | 2023-07-14 |
| THEREABOUTS | US | 98077954 | **Registered** | 21, 30, 32, 33, 35 | Flavor Purveyor LLC | 2023-07-10 |
| THEREABOUTS | US | 86829583 | Ended | 12 | Lachlan D. Morton | 2015-11-23 |
| THEREABOUTS | AU | 1736801 | Expired | 12 | A. & L. Morton | 2015-11-24 |
| THEREABOUTS | US | 90293662 | Ended | 18, 24 | Copper Purchasing LLC | 2020-11-02 |
| THEREABOUTS | US | 88899635 | Ended | 18, 24 | Copper Purchasing LLC | 2020-05-04 |
| 40 SOMETHING…OR THEREABOUTS | AU | 640268 | Ended | 41 | Milarepa Corporation | 1994-09-13 |

Worldwide `contains` in Nice 9/28/41 → **1 record**, the dead Australian one in the last row. **Nothing
live in any games, toys, software or entertainment class anywhere in TMview's coverage.**

The live owners are **PENNEY IP LLC** (JCPenney) in Class 25, clothing, and a food/beverage company in 21/30/32/33/35.
Neither is remotely related goods — but JCPenney is a large retailer with a live brand, and large retailers
police brand names past the boundaries of their classes.

### 4f. Common-law use

- **thereabouts.gg** (§4d) — a live web game with the exact name. The strongest common-law use found for
  any of the three.
- **JCPenney's Thereabouts™** — launched **2021-07-15** as an inclusive/adaptive kids' apparel private
  brand, sold exclusively at JCPenney
  ([corporate.jcpenney.com](https://corporate.jcpenney.com/2021/07/15/jcpenney-introduces-thereabouts-brand-for-fully-inclusive-back-to-school-style/),
  [BusinessWire](https://www.businesswire.com/news/home/20210715005669/en/JCPenney-Introduces-Thereabouts-Brand-for-Fully-Inclusive-Back-to-School-Style),
  [product pages](https://www.jcpenney.com/g/baby-kids/thereabouts?id=cat11100001545)). They use the ™
  symbol and hold the Class 25 registrations above. Not a game, but it is why Play and general search return
  retail for this word.
- **The Thereabouts cycling films** (Lachlan & Angus Morton) — an established creative use of the name,
  Australian, with two now-dead Class 12 marks behind it.
- No board game, party game or quiz of this name found.
- **Genericism:** *thereabouts* is a real English adverb but a comparatively formal, low-frequency one —
  people say "or thereabouts", they rarely say it alone. Of the three candidates it is the **least** generic
  and the most name-shaped.

---

## 5. What could not be verified

Recorded rather than smoothed over.

1. **itch.io, all three names.** `itch.io/search` returns **HTTP 403** (Cloudflare) to curl for every query;
   the earlier note hit the same wall with WebFetch and a real browser session. Every itch.io statement here
   is an indirect negative. One manual browser check would close this.
2. **BoardGameGeek, all three names.** The XML API answers `Unauthorized` and the site is Cloudflare-gated,
   so BGG results are search-derived, not fetched from BGG's own index. The *Ballpark* positives are solid
   (BGG URLs returned directly); the *Near Enough* and *Thereabouts* negatives are weaker.
3. **UKIPO detail records.** `trademarks.ipo.gov.uk`, `www.ipo.gov.uk/trademark/data/…` and
   `soap.ipo.gov.uk` all return **HTTP 403 "Service Captcha — … to keep our services safe from automated
   systems"**. GB rows come from TMview's summary only; goods recitations for UK00004432973
   (*BALLPARK LEGENDS*) were not obtained.
4. **TMview status reliability.** Demonstrated stale in §3e: it reported AU 623620 as *Registered* when IP
   Australia's own record shows it removed on 2021-09-08. Assume any TMview status may be out of date; check
   the national register for anything load-bearing.
5. **Provenance of thereabouts.gg and ballparkgame.com.** No owner, launch date, copyright line or traffic
   figure could be established for either. Both are single-page apps with no about page in the served HTML.
6. **App-store completeness.** Apple's iTunes Search API is a relevance-ranked search, not a title registry;
   Google Play's page returns a scraped result list, not an exhaustive index. A zero means "not findable by
   that query", which is the thing that actually matters here, but it is not proof of absence.
7. **Domains.** Not checked in this pass, beyond the observation that `ballparkgame.com` and
   `thereabouts.gg` are both in use by the games described above.
8. **The US register.** Deliberately not re-run — see
   [name-mind-meld-availability.md §6](./name-mind-meld-availability.md#6-first-pass-clearance-of-the-shortlist-alternatives).
   Note that §3e and §4e above surfaced US rows *incidentally* via TMview (MLB's Class 9/41 registrations,
   JCPenney's Class 25 registrations) that a Class-9/28/41-only search would not have shown.

---

## 6. Does any of it actually matter?

Two scenarios, per the framework in
[name-mind-meld-availability.md §7](./name-mind-meld-availability.md#7-what-actually-matters-hobby-use-vs-shipping):
trademark rights come from **use in commerce** (15 U.S.C. §1127) and turn on **likelihood of confusion**,
neither of which a private couch game triggers.

### (a) Private and unlisted today — a `noindex` page on `stephens.page`, two players, no money

| | Does it matter? |
|---|---|
| **Near Enough** | **No.** The Play listing is a different game in a different medium, not sold against us; there is no plaintiff and no injury. |
| **Ballpark** | **No** — legally. But see the caveat below: this is the one axis on which "private today" does not fully protect you. |
| **Thereabouts** | **No.** Same reasoning. thereabouts.gg has no registered right anywhere and no visible owner. |

**The caveat that applies to all three:** the private scenario is safe on *trademark*, but naming is not
only a trademark question. The name is going into the Chronicle, into module names, and into prose my wife
reads, and the earlier note already established that **rename cost is monotonic**. A name that would have to
be abandoned later is a name that costs more the longer it is kept — so the "hypothetically listed" column
is the one that should drive the decision even though today's exposure is nil.

### (b) Hypothetically listed on an app store later

| | Does it matter? |
|---|---|
| **Near Enough** | **Yes, on Google Play specifically — and only there.** A second game titled *Near Enough* in the same store is a direct duplicate-name collision, resolvable by Google's complaint process without any likelihood-of-confusion analysis, exactly as the earlier note warned about Mind Meld. iOS is clean. Registers are clean worldwide. **This is a one-store problem with a live but weak occupant.** |
| **Ballpark** | **Yes, comprehensively.** MLB holds **MLB BALLPARK** registered in **Class 9** (US 88787756) and **Class 41** (US 88787685) plus **AT THE BALLPARK** across 9/35/38/41 — the exact classes a game app files in — and MLB is an aggressive rights-holder. A live GB Class 28 application (*BALLPARK LEGENDS*) is pending. And the store search for "ballpark" is MLB's, top to bottom, in every storefront checked. Even winning every argument, the listing would be invisible. |
| **Thereabouts** | **Partly.** The register is genuinely clear for games in the UK, EU and worldwide — the cleanest of the three on that axis. The exposure is (i) JCPenney, a live ™-asserting brand owner in Class 25 with the money to send letters outside its class, and (ii) thereabouts.gg, whose common-law claim as a two-player "who got closer" game would be *more* directly on-point than any registration found. It would also mean shipping under a name whose first search result is a different game with the same premise. |

---

## 7. Ranking

**Inference from §§2–6. This is the recommendation, not a finding.**

### 1st — **Thereabouts** *(promoted)*

The cleanest **register** result of the three, worldwide, and the only candidate with a genuinely
name-shaped word. Zero GB records. Zero EU records. Zero live records in any games, software or
entertainment class anywhere in TMview. Nothing on iOS, nothing on Play, nothing on Steam, nothing on BGG.

Its problem is entirely §4d: **thereabouts.gg exists, is live, and is a two-player who-got-closer guessing
game.** That is a common-law collision on the exact name in the exact genre. But it is an unregistered,
unattributed, ownerless-looking web toy with no register footprint and no store presence — the weakest kind
of prior use — whereas *Near Enough*'s collision is a **maintained, monetised listing inside a store that
removes duplicate names on request**. A store takedown is the failure mode the earlier note identified as
the sharpest real-world edge, and Thereabouts is the only one of the three that does not have one waiting.

### 2nd — **Near Enough** *(demoted from top pick)*

Still excellent on paper: one dead misspelling worldwide, zero UK/EU, zero iOS, zero Steam, zero BGG. But
the earlier note's verdict — "**completely untouched**" — does not survive this pass. There is a **live,
maintained, exact-name game on Google Play**, updated six months ago, monetised, ranked first for the query.
Plus a defunct studio called *Near Enough Games* that owns the `near enough game` search result. Plus the
underlying phrase being ordinary British/Australian English.

For a private couch game today, none of that matters. For a listed app later, it is precisely the collision
that killed *Mind Meld*: not a lawsuit, a store complaint form. **Keep it as the fallback, not the default —
and if it is chosen anyway, choose it knowing the Play collision exists.**

### 3rd — **Ballpark** — *drop it*

The single worst outcome of this pass, and it fails on every axis at once:

- **MLB owns the query.** MLB Ballpark is the #1 result on both stores; the word's commercial meaning in the
  US is baseball stadia.
- **MLB owns the classes.** *MLB BALLPARK* registered in Class 9 **and** Class 41; *AT THE BALLPARK* across
  9/35/38/41.
- **39 exact-match records in Nice 9/28/41 worldwide** — 39 times denser than either alternative — plus a
  live GB Class 28 application filed three weeks ago.
- **The genre slot is already taken**: [ballparkgame.com](https://ballparkgame.com/) is a free daily
  guessing game scored on how close you got, with a shareable result. Same shape, same name, already there.
- **A registrar has ruled on the word.** IP Australia required the owners of AU 623620 to disclaim any
  exclusive right in the word BALLPARK. That is an official finding that the word is not distinctive.
- **It is a pure idiom** — *ballpark figure* — with a dictionary entry to prove it.

The only good news is that the bare word is technically unregistered and unlisted. That is worth nothing
when nobody could ever find it.

### The pattern worth naming

All three candidates were chosen for the same reason: they **name the near-miss**, which the naming ticket
correctly identified as this game's actual pleasure. The trouble is that a whole genre of daily browser
games is scored on exactly that — how close did you get — and its designers keep reaching for the same three
or four words. Two of our three candidates are already in use by games of precisely that shape
(`ballparkgame.com`, `thereabouts.gg`), and the third is in use by a rage platformer whose store pitch is
*"I was so close!"*

That is not bad luck; it is a crowded semantic field. If none of the three survives Jacob's taste, the next
shortlist should look for names that **evoke** the near-miss without **naming** it — the same lesson §9 of
the earlier note drew about *Mind Meld* naming the win.
