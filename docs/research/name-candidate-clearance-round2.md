# Nearabouts vs Nearish — round-two clearance, and how they compare to *Near Enough*

> **This is not legal advice.** It is a research note by a non-lawyer, assembled from public registers and
> product listings on **2026-09-04**. It records what USPTO's search API, TMview, the app stores, Steam, the
> dictionaries and the domain registries actually returned on that date — nothing more.

Third note in the naming series, after
[name-mind-meld-availability.md](./name-mind-meld-availability.md) (killed *Mind Meld*, first-pass register
sweep of eight alternatives) and [name-candidate-clearance.md](./name-candidate-clearance.md) +
[name-candidate-domains.md](./name-candidate-domains.md) (finished *Near Enough*, *Ballpark*,
*Thereabouts*). Two new candidates arrived after those: **Nearabouts** and **Nearish**. This note runs both
through the full six-axis treatment — registers, app stores, game storefronts, search visibility, word
status, domains — and then ranks them against the incumbent front-runner.

Method: primary sources, fetched 2026-09-04. US register facts come from
`POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch`, the Elasticsearch API behind
[tmsearch.uspto.gov](https://tmsearch.uspto.gov/) (base URL published at
[configuration.json](https://tmsearch.uspto.gov/configuration.json)). Non-US register facts come from
**TMview** (`POST https://www.tmdn.org/tmview/api/search/results`, the API behind
[tmdn.org/tmview](https://www.tmdn.org/tmview/)). iOS facts come from Apple's own iTunes Search and Lookup
APIs. Android facts come from the Google Play listing and search pages themselves. Steam facts come from
Steam's own store-search JSON. Domain facts come from **registry** RDAP and **registry** WHOIS, never from a
reseller's "available!" badge. **Every zero-result query was control-tested against a near neighbour**, so
each zero below is provably a real zero and not a broken query; the controls are printed inline. Anything
that could not be reached is flagged **could not verify** and never guessed. §8 is inference; everything
above it is finding.

**Headline: Nearish is dead and Nearabouts is the best-cleared name the project has found.**
*Nearish* is the exact title of a **live party guessing game on the US App Store, in Games › Word** — a
Wavelength-style "how close did you get" game, i.e. this project's own genre — plus the top Google Play
result for the query and a UK trademark registration. *Nearabouts* is register-clean worldwide in every
class, has **no game** anywhere (Play, iOS, Steam), and its `.game` / `.io` / `.gg` / `.fun` and both
`play-`/`-game` `.com` forms are all free. Its one real problem is a **live iOS app and LLC of that exact
name**, `Nearabouts LLC` — but in Lifestyle/Travel, not games.

---

## 1. Summary table

| | **Nearabouts** | **Nearish** | **Near Enough** (incumbent, from the earlier notes) |
|---|---|---|---|
| **USPTO, any class, any status** | **0 records** (control-tested) | **0 records** (control-tested) | 0 exact records |
| **Worldwide register (TMview), cls. 9/28/41** | **0** | **0** | 0 |
| **Worldwide register, all classes** | **0** | ❌ **6 live** — 1 GB + 5 CN, one owner, cls. 3/5/29/30/32/35/42 | 2 records, both dead, both unrelated |
| **Apple App Store** | ❌ **Exact-name app, live** — *Nearabouts* (Lifestyle/Travel) | ❌❌ **Exact-name party WORD GAME, live**, plus 2 more apps | Clear — 0 results US/GB/AU |
| **Google Play** | **Clear** — no app of that name | ❌ **Nearish: Long Distance Couples**, top result | ❌ **Near Enough**, exact-name live game |
| **Steam** | Clear — 0 | Clear — 0 | Clear |
| **itch.io / BGG** | could not verify (Cloudflare); nothing surfaced indirectly | could not verify; nothing surfaced indirectly | could not verify; nothing surfaced |
| **`<name> game` searchability** | **Good** — no incumbent at all | Poor — swamped by "in the nearish future" chatter | Poor — defunct studio *Near Enough Games* owns the query |
| **Bare-word searchability** | Good — dictionaries only, no brand | Good — dictionaries only, no brand | Poor — common phrase |
| **Word status** | Attested; **OED 1634**, MW "chiefly South & Midland", DARE entry | Attested; **OED 1853** | Not a word — common phrase |
| **Domains: free of 9 forms** | **6 of 9** (`.game .io .gg .fun`, `play-`, `-game`, `near-abouts.com`) | **7 of 9** | 7 of 9 |
| **Exact `.com`** | Taken (investor, dark) | Taken since 2005 (investor, parked for sale) | Taken (HugeDomains, **$6,295**) |
| **`.app`** | ❌ **Taken and live** — the Nearabouts LLC site | **FREE** | **FREE** |

---

## 2. Trademark registers

### 2a. USPTO — both candidates are at absolute zero

Queries against `POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch`, 2026-09-04. `wordmark` is an
analyzed field, so a phrase query matches the phrase anywhere in the mark; wildcard queries were run as well
to catch formatives. Human-readable equivalent for any serial:
`https://tsdr.uspto.gov/#caseNumber=<serial>&caseSearchType=US_APPLICATION&caseType=DEFAULT&searchType=statusSearch`.

| Query | Hits |
|---|---|
| `wordmark:"nearabouts"` | **0** |
| `wordmark:"near abouts"` | **0** |
| `wordmark:*NEARABOUT*` (wildcard — catches NEARABOUT, NEARABOUTS, X NEARABOUTS Y) | **0** |
| `wordmark:"nearish"` | **0** |
| `wordmark:*NEARISH*` (wildcard) | **0** |

**Controls, run on the same endpoint in the same session** — these prove the endpoint was live and the
wildcards were well-formed:

| Control query | Hits |
|---|---|
| `wordmark:*THEREABOUT*` | **6** (all *THEREABOUTS*: Copper Purchasing LLC ×3, Penney IP LLC, Flavor Purveyor LLC, Morton/Morton) |
| `wordmark:*HEREABOUT*` | **29** |
| `wordmark:*NEARLY*` | **174** |

So: **zero USPTO records for either candidate, in any class, in any status, ever.** That is a stronger
result than *Near Enough* got (which had two dead phrase-containing records) and far stronger than
*Ballpark* or *Thereabouts*.

Index caveat, same as the earlier notes: results reflect USPTO's load dates, so filings in the last one to
two weeks may not appear.

### 2b. TMview — worldwide, and here the two candidates separate

`POST https://www.tmdn.org/tmview/api/search/results`, `criteria: "C"` (contains), 2026-09-04. A cookie jar
is required; the first request of a session returns an empty body, which is why the numbers below were
re-run after the `traefik_persistence` / `TS…` cookies were established.

**Nearabouts — nothing, anywhere:**

| Query | Offices | Nice | Result |
|---|---|---|---|
| `nearabouts`, exact | GB + EM (EUIPO) | all | **0** |
| `nearabouts`, contains | GB + EM | all | **0** |
| `nearabouts`, contains | **all offices** | all | **0** |
| `nearabouts`, contains | **all offices** | **9, 28, 41** | **0** |

**Nearish — registered, by one owner, across seven classes in two jurisdictions:**

| Mark | Office | Number | Status | Nice | Owner | Filed |
|---|---|---|---|---|---|---|
| **Nearish** | **GB (UKIPO)** | **UK00003665527** | **Registered** | **3, 5, 30, 32, 35** | **UK HEALTURAL LIMITED** | 2021-07-07 |
| NEARISH | CN | 57458180 | Registered | 3 | 英国萃境生物科技有限公司 UK HEALTURAL LIMITED | 2021-07-05 |
| NEARISH | CN | 58526410 | Registered | 30 | UK HEALTURAL LIMITED | 2021-08-17 |
| NEARISH | CN | 58527432 | Registered | 35 | UK HEALTURAL LIMITED | 2021-08-17 |
| NEARISH | CN | 58642084 | Registered | 29 | UK HEALTURAL LIMITED | 2021-08-20 |
| NEARISH | CN | 61746774 | Registered | 42 | "Not available" | 2021-12-28 |

(The seventh worldwide hit, `ＬＩＮＥＡＲＥＧＩＮＡ` JP 1987061703, is a substring artefact and is ignored.)

Restricted to **Nice 9 / 28 / 41**, `nearish` returns **0** worldwide. So the games classes are formally
clear — but a UK registration on the *identical single word* exists and is live, held by a company whose
recitations run to cosmetics, foodstuffs, beverages and retail. That is not a blocker for a word game, and
it is not nothing either: it is a registered owner with an incentive to police, in the jurisdiction the
project's likeliest first non-US listing would touch.

**Controls for these zeros, same endpoint, same session:**

| Control | Offices | Nice | Result |
|---|---|---|---|
| `hereabouts`, contains | all | all | **51** |
| `whereabouts`, contains | all | **9, 28, 41** | **15** — including a **live GB registration in exactly 9/28/41**, WHEREABOUTS (UK00004102104) and WHEREABOUTS ITW (UK00004102105), both Whereabouts ITW Limited, registered 2025-04-04 |
| `thereabouts`, contains | all | 9, 28, 41 | **1** (dead AU) |
| `near enough`, contains | all | all | **2** (both dead US) |

The `whereabouts` control is the useful one: it proves the class filter actually surfaces live 9/28/41
registrations when they exist. Nearabouts and Nearish returning 0 under the identical filter is therefore a
real finding. It also flags, in passing, that the `-abouts` family is being actively claimed in the games
classes right now — just not on our two words.

**Could not verify:** UKIPO's own case-detail service was checked directly at
`https://trademarks.ipo.gov.uk/ipo-tmcase/page/Results/1/UK00003665527` and at
`https://www.ipo.gov.uk/trademark/details/UK00003665527`, and both returned **HTTP 403** behind a "Service
Captcha" page. The UK row above is therefore TMview's copy of the UKIPO record, not the UKIPO record
itself. TMview status data is generally current but can lag; the goods recitations were not retrieved.

---

## 3. App stores

### 3a. Apple App Store

Apple's own iTunes Search API, `https://itunes.apple.com/search?term=<t>&entity=software&country=<c>`,
2026-09-04, plus `https://itunes.apple.com/lookup?id=<id>&country=<c>` per record.

| Term | US | GB | AU |
|---|---|---|---|
| `nearabouts` | **7** results, incl. an exact-name app | 4 (no exact) | 6 (no exact) |
| `nearish` | **3** results, **all three carry the name** | 2 | 2 |
| `thereabouts` (control from earlier note) | 0 | 0 | 0 |
| `near enough` (control) | 0 | 0 | 0 |

The zero-returning controls are the same ones the earlier note used and they still return zero, so the
non-zero results here are real hits, not noise.

**Nearabouts — one exact-name app, not a game.**
[**Nearabouts**](https://apps.apple.com/us/app/nearabouts/id6775552870), trackId `6775552870`, bundle
`app.replit.nearabouts`, seller **Nearabouts LLC**, released **2026-06-28**, last updated **2026-08-06**,
version 1.0.2, free, **Lifestyle / Travel**. Verbatim from its own listing:

> "Nearabouts is a digital passport for real-world exploration. Visit local cafés, bookstores, parks, record
> shops, theaters, galleries, and other analog-friendly places. When you're there, stamp your passport and
> build a personal collection of the places you've discovered… No social feed. No likes. No endless
> scrolling."

Three things about it. It is **US-storefront only** — `lookup?id=6775552870` returns `resultCount: 0` for
`gb`, `au` and `ca`. It is a **Replit-built app by a named LLC** (see §6a for its matching domain), i.e. a
real, if small and very new, commercial user of the name. And it is **not in Games**, which is the axis that
matters most for both trademark relatedness and store-listing collision.

**Nearish — and this is the finding that decides the candidate.**

1. [**Nearish - Party Guessing Game**](https://apps.apple.com/us/app/nearish-party-guessing-game/id6760411590),
   trackId `6760411590`, bundle `com.wakefield.nearish`, seller "CODY FRANK,WAKEFIELD TANNER", released
   **2026-03-15**, updated **2026-05-15**, version **1.47.0**, free, rated 12+, 5.0★ from 3 ratings.
   Genres: **Games / Family / Word.** Verbatim from its own listing:

   > "Nearish is a party game about reading minds and giving the perfect clue. Each round, one player is the
   > Psychic. They see a hidden target on a spectrum between two opposites -- like 'Hot vs. Cold' or
   > 'Overrated vs. Underrated' -- and give a clue to help everyone else guess where the target lands.
   > **The closer your guess, the more points you score.**"
   > … "Pass-and-play: Hand the phone around with 2-12 players" … "Online multiplayer: Create a room, share
   > a 4-letter code" … "500+ spectrum cards" … "Free to play. No ads. No in-app purchases."

   That is a *Wavelength* implementation. It is in the **Word** genre. It is **pass-and-play on one phone,
   two players upwards** — the exact couch shape this project is designed for. It is maintained (version
   1.47.0 in two months). And it is named Nearish because *closeness is the scoring mechanic*, which is the
   same reason this project would want the name. It is US-storefront only (`gb`/`au`/`ca` → 0), but that is
   thin comfort: the US store is where an app-store listing would land.

2. [**couples questions: nearish**](https://apps.apple.com/us/app/couples-questions-nearish/id6757454751),
   bundle **`com.nearish.app.ios`**, seller Pinky Khimani, released 2026-02-05, 17+, Lifestyle. Its own
   description opens: *"Nearish is the all-in-one relationship hub designed to keep couples connected…"* and
   its feature list is "The Game Night Suite: Play Truth or Dare, Never Have I Ever, Would You Rather…" —
   i.e. a **couples game app** called Nearish, which is this project's exact target audience (see the
   memory note: My wife, couple-game slot).

3. [**Nearish**](https://apps.apple.com/us/app/nearish/id6761356371), bundle `es.nearish.app`, Rafael Esteban
   Clares, Travel/Utilities, Spanish-language nearby-places search, seller site
   `http://nearish.trecesietes.es`.

**Three live iOS apps named Nearish, two of them games-adjacent, one of them literally a two-player-up
pass-and-play word-genre guessing game about how close you got.**

### 3b. Google Play

Fetched as real HTML from `https://play.google.com/store/search?q=<t>&c=apps&hl=en&gl=US` and, for the
hits, the listing pages themselves.

**Nearabouts — clear.** The search page returns 30 packages, none named Nearabouts; the top-listed apps are
`NearJoy - Nearby Friend Alerts` and, tellingly, **`Near Enough`** (`com.kernelx.nearenough` — the
incumbent's blocker, §7). Direct package probes for `com.nearabouts.app` and `app.replit.nearabouts` (the
iOS bundle) both return **HTTP 404** — the Nearabouts LLC app has no Android build.

**Nearish — not clear.** The **top result** for the Play query `nearish` is
[**Nearish: Long Distance Couples**](https://play.google.com/store/apps/details?id=com.tetherapp.distance),
package `com.tetherapp.distance`, developer **Martin Labs**, **updated Aug 29, 2026**, version **2.9.6**,
**100+ downloads**, **in-app purchases**, rated Everyone. Verbatim from its own listing:

> "**Nearish: The space between us made smaller.**"
> "Nearish: The ultimate alignment and communication toolkit for Long Distance Couples (LDR)."
> "Nearish automatically detects when you're close, shifting into real-time Live Sync, and opening Meet Up
> Mode to plot a walk…"

So the Play name is held, by a maintained, monetised, actively-shipping app, **aimed at couples**. Not a
game — but the audience overlap with a two-player couch/couple game is total, and Play's duplicate-name and
impersonation complaint processes do not weigh genre.

**Control test for the Play method:** the identical fetch for `wavelength` returns *MONOPOLY GO!*,
*Taboo - Official Party Game* and others; for `thereabouts` it returns *Kohl's*, *TalkingParents* etc. The
scraper works and populates `aria-label` titles, so the Nearabouts zero is a real zero.

---

## 4. Steam, itch.io, BoardGameGeek

- **Steam — both clear.** `https://store.steampowered.com/api/storesearch/?term=nearabouts&l=english&cc=US`
  → `{"total":0,"items":[]}`; same for `nearish`. **Control:** `term=portal` on the same endpoint returns
  `total: 10` with *Portal 2*, *Portal* etc. So both zeros are real.
- **itch.io — could not verify.** `https://itch.io/search?q=nearabouts` and `?q=nearish` both return
  **HTTP 403** (Cloudflare) to curl, exactly as they did for the two earlier notes. Direct subdomain probes
  `https://nearabouts.itch.io/` and `https://nearish.itch.io/` also return **403**, so even the "does this
  creator page exist" question is unanswered. Indirect search restricted to `itch.io` surfaces only
  developer devlogs using *nearish* colloquially ("a proper release will be on its way in the nearish
  future"), no game of either name. **Worth one manual look in a browser.**
- **BoardGameGeek — could not verify directly; nothing found indirectly.** `xmlapi2/search` returns
  `Unauthorized. See https://boardgamegeek.com/using_the_xml_api` for both terms **and for the control term
  `thereabouts`**; `api.geekdo.com/api/geekitems` returns `null`; the HTML search returns **403**. Search
  restricted to `boardgamegeek.com` surfaces only forum posts using the words casually ("in Falmouth (or
  nearish)"). No board game of either name was found, but this is an indirect negative, same caveat as the
  earlier notes.

---

## 5. Search visibility

### 5a. `nearabouts game` — **the cleanest result of any candidate so far**

Nothing game-shaped owns this query. What comes back is: a YouTube pronunciation clip
([*"Nearabouts = close to; more or less"*](https://www.youtube.com/watch?v=-mq5P22OUkA)), the OneLook and
Wordunscrambler dictionary aggregators, **[nearabouts.app](https://nearabouts.app/)** (the §3a LLC), and then
unrelated Ryan Laukat board games matched on "near" — [*Near and Far*](https://boardgamegeek.com/boardgame/195421/near-and-far)
and [*Near-Mage*](https://en.wikipedia.org/wiki/Near-Mage).

**There is no incumbent.** Compare *Near Enough*, whose `near enough game` query is owned by a decade of SEO
belonging to a defunct studio, and *Thereabouts*, whose query is owned by `thereabouts.gg`. A small game
called Nearabouts would be the first game-shaped thing in that result set, and `nearabouts.app` is the only
competitor for the bare word.

### 5b. `nearish game` — buried under casual usage, as feared

The query returns no *Nearish*. It returns MW's Scrabble finder, a "valid Scrabble word?" page, and then
fuzzy `near`-matches: [*Near Site*](https://store.steampowered.com/app/1879060/Near_Site/) (Steam),
*NearEscape* (Play), *Near-Mage*, *Near and Far*. Notably it does **not** surface the actual iOS *Nearish -
Party Guessing Game* — which is worse, not better: it means the name is so noisy that even a shipped,
correctly-titled game in the exact genre cannot rank for it.

The mechanism is the one the task anticipated: **"in the nearish future" is the dominant use of the word.**
The itch.io and BGG searches in §4 returned nothing *but* that construction. A game named Nearish is
competing with an adverbial hedge that appears in every developer changelog on the internet.

### 5c. Bare words — both fine, neither owned by a brand

`nearabouts` returns OneLook, Wiktionary, Merriam-Webster, the two OED entries, Thesaurus.com, WordHippo,
Urban Dictionary. `nearish` returns OneLook, Lexico, Merriam-Webster, Wiktionary, Wordnik, OED,
TheFreeDictionary, bab.la, Reverso, Definitions.net. **Both bare words are dictionary territory with no
commercial squatter** — which is genuinely good, and better than *Near Enough* (whose bare phrase is
ordinary English used millions of times a day).

---

## 6. Word status

Both are real, attested English. Both are in the OED. That is the answer to the task's framing question, and
it cuts the way the question suspected: **an attested word is evocative but less distinctive.**

| | **nearabouts** | **nearish** |
|---|---|---|
| **OED** | [`nearabouts, adv.`](https://www.oed.com/dictionary/nearabouts_adv) — entry exists. Earliest known use **1634**, in Thomas Herbert (traveller and government official). The parent [`nearabout, adv. & prep.`](https://www.oed.com/dictionary/nearabout_adv) is dated **before 1425**, Middle English. | [`nearish, adj.`](https://www.oed.com/dictionary/nearish_adj) — entry exists. Earliest known use **1853**; entry last revised **July 2023**. |
| **Merriam-Webster** | [`nearabout`](https://www.merriam-webster.com/dictionary/nearabout) — "nearly, almost", labelled **"chiefly South & Midland"**, with **nearabouts** listed as a variant. | [`nearish`](https://www.merriam-webster.com/dictionary/nearish) — entry exists (indexed; page content not retrievable, see caveat). |
| **DARE** | [`nearabout(s)`](https://www.daredictionary.com/view/dare/ID_00040098) — a Dictionary of American Regional English headword. Regional label consistent with MW's. | Not found in DARE. |
| **Wiktionary** | [`nearabouts`](https://en.wiktionary.org/wiki/nearabouts) — "From *near* + *about* + *-s* (see adverbial genitive)", "Synonym of *nearabout*", example "*nearabouts the library, nearabouts ten o'clock*", with a **c. 1613–1621 Francis Bacon** citation. | [`nearish`](https://en.wiktionary.org/wiki/nearish) — "From *near* + *-ish*", adjective, "**Somewhat near**", not comparable. |
| **Dictionary.com** | No entry — `/browse/nearabouts` redirects to `/browse/hereabouts?…&mismatchType=misspelling`, i.e. treated as a **misspelling of "hereabouts"**. | No entry — `/browse/nearish` redirects to `/browse/bearish?…&mismatchType=misspelling`, i.e. treated as a **misspelling of "bearish"**. |
| **Cambridge** | No entry — redirects to the dictionary home page. | No entry — redirects to home. |
| **American Heritage 5e** | No entry found. | Not separately checked. |

**Reading it.** *Nearabouts* is the older and more interesting word: a genuine dialect adverb with 400 years
of attestation, a regional label ("chiefly South & Midland"), a DARE entry, and a Bacon citation. It reads
as a *word* — slightly archaic, slightly rural, warm. *Nearish* is a productive `-ish` derivation: real,
OED-listed since 1853, but morphologically transparent in the way "bluish" or "smallish" is. It is the
difference between a word you *find* and a word you *form*.

For distinctiveness this is a genuine trade-off. Neither is a coinage, so neither gets the "fanciful mark"
top tier of trademark strength. But *nearabouts* is rare enough in modern English that it functions close to
an arbitrary mark for a game, whereas *nearish* is so productive that it will read as generic hedging — and
§5b shows that reading is already the dominant one online.

Two caveats, recorded rather than smoothed over:

- **Could not verify (OED full text).** `oed.com` 302-redirects every `/dictionary/<entry>` and
  `/search/dictionary/` request to `https://www.oed.com/?tl=true` for unauthenticated clients, and WebFetch
  is bounced into the `oup2-idp.sams-sigma.com` OAuth flow. The entry URLs above are confirmed to exist and
  the dates come from the public search-result metadata for those pages; the **definition text, frequency
  band and full quotation paragraphs were not read from OED directly.**
- **Could not verify (Merriam-Webster, Collins, DARE).** `merriam-webster.com`, `collinsdictionary.com` and
  `daredictionary.com` all return **HTTP 403** (Cloudflare "Just a moment…") to curl and to WebFetch, with
  full desktop browser headers. Their rows above come from the search index's rendering of those pages, not
  from the pages. The existence of the DARE headword and the MW "chiefly South & Midland" label are
  well-supported but are one step removed from the source.

---

## 7. Domains

Same method as [name-candidate-domains.md](./name-candidate-domains.md): **registry** RDAP where the registry
runs one (Verisign for `.com`, Google Registry for `.app`, CentralNic for `.game`) and **registry** WHOIS
otherwise (`whois.nic.io`, `whois.gg`, `whois.nic.fun`). Every `.com` result was re-checked a second time
against `whois.verisign-grs.com` directly. "Serves anything?" comes from `dig` plus a real `curl` fetch of
the apex. All 2026-09-04.

### 7a. Nearabouts — 6 of 9 free, but `.app` is taken and live

| Domain | Status | Registrar | Created | Expires | Serves anything? |
|---|---|---|---|---|---|
| nearabouts.com | **Registered** | Dynadot Inc | **2025-05-20** | 2027-05-20 | **Nothing** — dark, see §7c |
| **nearabouts.game** | **AVAILABLE** | — | — | — | — |
| nearabouts.app | ❌ **Registered — live site** | Squarespace Domains II LLC | **2026-05-19** | 2027-05-19 | **Yes** — the Nearabouts LLC app site, §7d |
| **nearabouts.io** | **AVAILABLE** | — | — | — | — |
| **nearabouts.gg** | **AVAILABLE** | — | — | — | — |
| **nearabouts.fun** | **AVAILABLE** | — | — | — | — |
| **playnearabouts.com** | **AVAILABLE** | — | — | — | — |
| **nearaboutsgame.com** | **AVAILABLE** | — | — | — | — |
| **near-abouts.com** | **AVAILABLE** | — | — | — | — |

Sources: [`rdap.verisign.com/com/v1/domain/nearabouts.com`](https://rdap.verisign.com/com/v1/domain/nearabouts.com)
(HTTP 200) and the same endpoint per name (HTTP 404 for the three free `.com`s), independently corroborated
by `whois -h whois.verisign-grs.com "domain <name>"` returning `No match for domain "NEARABOUTSGAME.COM"`,
`"PLAYNEARABOUTS.COM"`; `https://rdap.centralnic.com/game/domain/nearabouts.game` → **404** with
`whois -h whois.nic.game` agreeing `The queried object does not exist: DOMAIN NOT FOUND`;
`https://pubapi.registry.google/rdap/domain/nearabouts.app` → **HTTP 200**;
`whois -h whois.nic.io nearabouts.io` → `Domain not found.`; `whois -h whois.gg nearabouts.gg` → `NOT FOUND`;
`whois -h whois.nic.fun nearabouts.fun` → `>>> Domain nearabouts.fun is available for registration`.

### 7b. Nearish — 7 of 9 free, and `.app` is free

| Domain | Status | Registrar | Created | Expires | Serves anything? |
|---|---|---|---|---|---|
| nearish.com | **Registered** — domain-investor inventory | Dynadot Inc | **2005-01-26** | 2027-01-26 | **Parked for sale** at NamePros, §7e |
| **nearish.game** | **AVAILABLE** | — | — | — | — |
| **nearish.app** | **AVAILABLE** | — | — | — | — |
| **nearish.io** | **AVAILABLE** — "available for application via the Identity Digital Dropzone service" | — | — | — | — |
| **nearish.gg** | **AVAILABLE** | — | — | — | — |
| **nearish.fun** | **AVAILABLE** | — | — | — | — |
| **playnearish.com** | **AVAILABLE** | — | — | — | — |
| **nearishgame.com** | **AVAILABLE** | — | — | — | — |

Same sources; `pubapi.registry.google/rdap/domain/nearish.app` → **HTTP 404**;
`rdap.centralnic.com/game/domain/nearish.game` → 404 + `DOMAIN NOT FOUND`;
`whois.nic.io nearish.io` → *"This domain is currently available for application via the Identity Digital
Dropzone service"* (i.e. unregistered, but routed through Identity Digital's application queue rather than
plain first-come registration — worth knowing before assuming a one-click purchase).

**Lookup caveats, recorded rather than smoothed over:** `.gg` still has **no RDAP service at all**, so it is
registry WHOIS only; `rdap.org` was not relied on for `.io` or `.fun`. Nothing was rate-limited and no lookup
was retried into a different answer.

### 7c. nearabouts.com — and a small discovery about who holds it

Registered **2025-05-20** at **Dynadot**, `clientTransferProhibited`, nameservers `ns1/ns2.dyna-ns.net`
(Dynadot's own). It resolves to **`54.215.31.113`** with **nothing listening** — `curl https://nearabouts.com/`
returns HTTP 000.

That IP is worth a second look. `dig +short thereabouts.com A` returns **the same `54.215.31.113`**, and
`dig -x` gives `ec2-54-215-31-113.us-west-1.compute.amazonaws.com` for both. *thereabouts.com* is the
26-year-old, Dynadot-held, dark domain documented in
[name-candidate-domains.md §2b](./name-candidate-domains.md). **Same IP, same registrar, same nameserver
pair, same dead EC2 box.** The reasonable read is a single domain investor holding an `-abouts` portfolio
and pointing all of it at one abandoned host.

Practical consequence: `nearabouts.com` is **not a business using the name** — it is inventory. But no public
asking price could be found. `.com` registry RDAP is thin (no registrant published) and Dynadot's registrar
RDAP publishes nothing useful. **Could not verify** whether it is listed for sale or at what price.

### 7d. nearabouts.app — the one taken domain that is actually in use

`https://nearabouts.app/` returns **HTTP 200** with a real single-page app. From the page's own head:

> `<title>Nearabouts</title>`
> `<meta name="description" content="Nearabouts — built on Replit. Update this description to reflect the app." />`
> `<meta name="robots" content="index, follow" />`

It is a React SPA served from Google Cloud (`ns-cloud-e{1..4}.googledomains.com`, A record
`34.111.179.208`), registered through Squarespace on 2026-05-19, five weeks before the iOS app shipped on
2026-06-28. Together with the iOS bundle id `app.replit.nearabouts` and the seller name **Nearabouts LLC**,
this is one coherent, current, named commercial user of the word.

Note the tell in that meta description: **the placeholder text was never replaced.** The site is a Replit
scaffold that went live unedited. That is a signal about how much operation is behind Nearabouts LLC — a
solo builder, not a company with a brand team — but it is not a signal that the name is free.

### 7e. nearish.com — twenty-one years of investor inventory

Created **2005-01-26**, at **Dynadot**, `clientTransferProhibited`. It resolves to `3.233.30.191` and
**302-redirects to `https://www.namepros.com/parked/nearish.com?domain=nearish.com&v=20260803b`** — NamePros
is the domain-investor forum, and that path is its parking service. So the name is held for resale, not use,
and has been held for 21 years.

**Could not verify:** the asking price. The NamePros parked page sits behind a Cloudflare challenge
(`cf-mitigated: challenge`, HTTP 403, `<title>Just a moment...</title>`) that a curl with full desktop
browser headers cannot pass. No public buy-now figure was obtained. One manual browser look would settle it.
For calibration, the comparable exact-match `.com` in this series, `nearenough.com`, carries a published
**$6,295** buy-now on HugeDomains.

---

## 8. Ranking, and the comparison against *Near Enough*

**Inference from §§1–7. This is the recommendation, not a finding.**

### 8a. Nearish — drop it

It fails on the axis that matters most and it fails there twice.

1. **There is already a live iOS game called Nearish, in Games › Word, that is a two-player-up pass-and-play
   guessing game scored on how close you got.** *Nearish - Party Guessing Game* (§3a) is not adjacent to
   this project; it is a *Wavelength* in the same genre, the same store category, the same couch format, and
   it is actively maintained. Shipping a second word game called Nearish into the US App Store is the
   self-inflicted wound the Mind Meld note already described: Apple's duplicate-name complaint process
   removes listings on request, fast, with no likelihood-of-confusion analysis.
2. **Google Play's `nearish` query is owned by a monetised couples app** (§3b), and couples are precisely
   this project's audience.
3. **Three live iOS apps carry the name**, one of them a couples game hub whose own bundle id is
   `com.nearish.app.ios`.
4. **A live UK registration exists** on the identical single word (§2b), with five Chinese siblings, one
   owner. Not in the games classes — but an owner who files in seven classes across two jurisdictions is an
   owner who polices.
5. **The word is unsearchable in the game sense** (§5b). "In the nearish future" is the dominant use, and it
   is so dominant that the shipped iOS game of that exact name does not rank for `nearish game`.

The only good news is domains (7 of 9 free, `.app` included) and a clean USPTO. Neither compensates.

### 8b. Nearabouts — the best-cleared name in the series, with one asterisk

**What it wins on:**

- **Zero trademark records worldwide.** Not "zero in the games classes" — zero, in every class, in every
  status, at USPTO and across every TMview office, control-tested twice. No candidate in any of the three
  notes has come back this clean. *Near Enough* had two dead records; *Thereabouts* had nine including
  JCPenney's live ones; *Ballpark* had thirty-nine in 9/28/41 alone.
- **No game anywhere.** Play: nothing. iOS: nothing in Games. Steam: zero, controlled. BGG: nothing
  surfaced. That is better than *Near Enough* (live exact-name Play game), better than *Thereabouts* (live
  `.gg` browser game), and far better than *Nearish*.
- **The `<name> game` query is unclaimed** (§5a). This is the axis every other candidate has lost on, and it
  is the one that decides whether my wife's friends can find the thing. There is no defunct studio, no
  daily-puzzle incumbent, no `.gg` duel. A small game would be the first game-shaped result.
- **It is a better word.** 1634 in the OED, before 1425 for the parent form, a DARE headword, a
  "chiefly South & Midland" regional label, a Bacon citation. It sounds like something and it means
  *approximately there* — which is this game's whole subject. It is also, unlike "near enough", **ownable as
  a single token**: one word, no space, no article, spellable, typeable, and not a phrase people already say
  ten times a day.
- **`nearaboutsgame.com`, `playnearabouts.com`, `near-abouts.com`, `nearabouts.game`, `.io`, `.gg`, `.fun`
  are all free.**

**The asterisk — and it is a real one:** `Nearabouts LLC` exists, ships an iOS app called Nearabouts, and
owns `nearabouts.app`. All of it started in 2026 (domain 2026-05-19, app 2026-06-28). This is a **common-law
user with no registration**, in **Lifestyle/Travel**, US-only, with an unedited Replit placeholder still in
its meta description. Three consequences:

1. **`.app` is gone.** For a project whose earlier note made "an app-store listing is now a real
   possibility" the premise, that stings — *Near Enough* and *Nearish* both have a free `.app`.
   `nearabouts.game` is free and is the better address for a game anyway, and `nearaboutsgame.com` is free
   as the `.com` fallback.
2. **There is a same-name entity that could complain.** Not on the register, not in Class 9/28/41, not in
   games — but an LLC that has adopted the name for a consumer mobile app in the same store is exactly the
   party who files an App Store name complaint. Its exposure is much lower than *Nearish*'s or
   *Near Enough*'s (different category, no registration, no traction), but it is not zero.
3. **It also caps the name's upside slightly**: `nearabouts` as a bare-word search now has one commercial
   result, where six months ago it had none.

**And one thing that is not an asterisk:** `nearabouts.com` being dark investor inventory (§7c) is normal and
matches every other candidate. Nobody is *using* it.

### 8c. Against the incumbent

| | **Nearabouts** | **Near Enough** |
|---|---|---|
| Register | **0 records, worldwide, all classes** | 0 exact; 2 dead phrase-containing |
| Live game with the exact name | **None found anywhere** | ❌ [**Near Enough**](https://play.google.com/store/apps/details?id=com.kernelx.nearenough), Kernelx, Google Play, **re-verified live 2026-09-04**, updated Feb 25 2026, **contains ads + in-app purchases** |
| Other same-name commercial user | Nearabouts LLC — iOS Lifestyle app, 2026, no registration | Near Enough Games — defunct studio, but a decade of SEO |
| `<name> game` searchability | **Unclaimed** | Owned by the defunct studio |
| Coinability / ownership as a token | **One word, rare, ownable** | ❌ Uncoinable common English phrase |
| Domains free (of 9) | 6 — incl. `.game`, `.io`, `.gg`, `.fun`, `play-`, `-game` | 7 — incl. `.app` (**re-verified free 2026-09-04**), `.game` (**re-verified free**) |
| Exact `.com` price | Unknown (investor-held, no public price) | **$6,295**, published |

**Nearabouts beats Near Enough on every axis except `.app`.** The incumbent's three known problems are all
real and all still true today — the Play game is live and monetised as of this morning, the studio still owns
the search query, and the phrase is still uncoinable. Nearabouts' single problem is a five-week-old
Lifestyle app by a solo builder, in a different store category, holding one domain.

The uncoinability point deserves the last word, because it is the one that outlives every lookup. *Near
Enough* is two ordinary words in an order English uses constantly; it cannot be owned, cannot be searched
for, and cannot be defended, and no amount of register-cleanliness changes that. *Nearabouts* is a single
low-frequency token that people will have to look up the first time they see it — which is a cost on day one
and an asset every day after.

**Recommendation: promote Nearabouts to front-runner ahead of Near Enough. Drop Nearish entirely.**

If Nearabouts is adopted, the cheap defensive moves are, in order: register **`nearabouts.game`** (free) as
the primary address and **`nearaboutsgame.com`** (free) as the `.com` fallback; keep the game clearly in the
word/party-game category so the Lifestyle app and this project stay visibly different products; and — because
the register is *completely* empty, which will not stay true forever — treat a Class 9/28/41 filing as
cheaper now than later if the app-store premise firms up.

### 8d. What is still missing

Not cleared by this note, and not claimable as cleared:

1. **itch.io** for both names — Cloudflare-blocked on every path tried, including creator subdomains. One
   manual browser look.
2. **BoardGameGeek** for both names — indirect negative only; the API is closed to scripts and the control
   term failed the same way.
3. **The UKIPO record itself** for `Nearish` UK00003665527 — TMview's copy only; UKIPO returned a captcha.
   Goods recitations unretrieved. (Moot if Nearish is dropped.)
4. **OED, Merriam-Webster, Collins and DARE full text** — all four block scripted access; §6 rests on entry
   URLs plus search-index metadata.
5. **Asking prices** for `nearabouts.com` and `nearish.com` — both investor-held, neither publishes a
   reachable figure.
6. **Common-law and unregistered rights** generally, and **Nearabouts LLC's** in particular. The register
   cannot see them. Whether a word game called Nearabouts is confusable with a place-stamping passport app
   called Nearabouts is exactly the DuPont-factor judgment call that §8 of the Mind Meld note says needs an
   attorney before anything ships.
7. **Madrid / national registers outside TMview's coverage**, and any filing loaded after 2026-09-04.
