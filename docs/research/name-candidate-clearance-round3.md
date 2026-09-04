# Round three — eleven candidates through a four-part gate, measured against *Nearabouts*

> **This is not legal advice.** It is a research note by a non-lawyer, assembled from public registers and
> product listings on **2026-09-04**. It records what USPTO's search API, WIPO's Global Brand Database, the
> app stores, Steam, BoardGameGeek, the dictionaries and the domain registries actually returned on that
> date — nothing more.

Fourth note in the naming series, after
[name-mind-meld-availability.md](./name-mind-meld-availability.md) (killed *Mind Meld*),
[name-candidate-clearance.md](./name-candidate-clearance.md) + [name-candidate-domains.md](./name-candidate-domains.md)
(*Near Enough*, *Ballpark*, *Thereabouts*), and [name-candidate-clearance-round2.md](./name-candidate-clearance-round2.md)
(killed *Nearish*, promoted **Nearabouts** to front-runner). **Nearabouts is not re-cleared here — it is the
benchmark.**

Eleven new candidates, in three families:

- **A — near/-abouts:** **Nighabouts**, **Nearenough** (one word, no space)
- **B — -ish diminutives:** **Closish**, **Fairish**, **Goodish**, **Thereish**
- **C — faint-praise grades:** **Middling**, **Passable**, **Tolerable**, **Wellnigh** (and *Well-nigh*), **Approx**

## The gate

A candidate passes only if **all four** hold:

1. **Zero LIVE trademark records in Nice 9 / 28 / 41, in any register.**
2. **No existing GAME carrying the name in any store** — Apple, Google Play, Steam, itch.io, BoardGameGeek.
3. **An unclaimed `<name> game` search query** — a small game must be findable, not buried.
4. **At least one good domain form free**, verified at the registry.

**Result: five pass, six fail.** *Nighabouts* passes the gate more cleanly than *Nearabouts* did — it is the
only candidate in four notes with **all nine domain forms free, including the exact `.com`**. *Approx* is the
worst finding in the series: a live Class 28 registration, a **two-player closest-guess quiz game of that
exact name on the App Store**, and a **2024 board game of that exact name on BoardGameGeek**.

---

## 0. Method, and what changed since round two

Primary sources, fetched 2026-09-04. Every zero-result query was control-tested against a near neighbour in
the same session, and the controls are printed inline, so each zero below is provably a real zero and not a
broken query. Anything unreachable is flagged **could not verify** and never guessed. §9 is inference;
everything above it is finding.

| Axis | Source used | Status today |
|---|---|---|
| US register | `POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch` (the API behind [tmsearch.uspto.gov](https://tmsearch.uspto.gov/), base URL published at [configuration.json](https://tmsearch.uspto.gov/configuration.json)) | Working |
| Worldwide register | ❗ **TMview is down to scripts *and* to a real browser today.** Substituted: **WIPO Global Brand Database**, [branddb.wipo.int](https://branddb.wipo.int/) | Working — see §0a |
| iOS | Apple iTunes Search + Lookup APIs | Working |
| Android | Google Play search + listing pages | Working |
| Steam | `store.steampowered.com/api/storesearch/` | Working |
| **BoardGameGeek** | ✅ **`geeksearch.php` via an authenticated browser session** | **Working — first time in this series** |
| itch.io | `itch.io/search` | ❌ Cloudflare 403, to curl **and** to a real browser tab (§5) |
| Dictionaries | Wiktionary MediaWiki API (direct); OED/MW/Collins/DARE via entry-URL probes + search index | OED, MW, Collins, DARE all block scripts (§7) |
| Domains | Registry RDAP (Verisign `.com`, Google `.app`, CentralNic `.game`) and registry WHOIS (`.io`, `.gg`, `.fun`) | Working |

### 0a. TMview is unreachable, and what was used instead

`https://www.tmdn.org/tmview/` **302-redirects every request to `https://www.tmdn.org/error/revise.html`**
("Our website has detected a problem when accessing this page from your computer. Reference Number: 25lej"),
behind an F5 BigIP APM JavaScript challenge. This happened to `curl` with a full desktop header set, to a
cookie-jar session primed against the error page, and — decisively — **to a real Chrome tab driven
interactively**. TMview could not be used today at all.

The substitute is **WIPO's Global Brand Database**, which the app's own banner describes as
*"76,578,096 records from 89 data sources"* and which labels its own result set **"TMview"** as the upstream
feed. Queries were driven through the live application (`/en/similarname/results`, brick
`{key:"brandName", strategy:"Simple"}`), because the underlying `POST https://api.branddb.wipo.int/search`
returns a client-decrypted ciphertext body rather than JSON.

**Equivalence controls — GBD reproduces round two's TMview numbers exactly:**

| Word | Round two, via TMview | Today, via WIPO GBD |
|---|---|---|
| `thereabouts` | **9** records worldwide | **9** records worldwide, same JCPenney / Copper Purchasing / Morton rows |
| `nearish` | 1 GB registration (UK HEALTURAL LIMITED) + CN siblings | **1** — `Nearish`, **UK HEALTURAL LIMITED** |
| `nearabouts` | **0** | **0** |

Two things follow. The zeros reported below are trustworthy — the same instrument returns 9 for
*thereabouts* and 0 for *nearabouts*, matching the prior note. And GBD carries **fewer** CN rows than TMview
did for *nearish*, so treat GBD as slightly thinner on Chinese filings. That is the one known coverage gap.

---

## 1. Summary — the gate, candidate by candidate

| Candidate | (i) TM 9/28/41 | (ii) Game in a store | (iii) `<name> game` query | (iv) Domain free | **Gate** |
|---|---|---|---|---|---|
| **Nighabouts** | ✅ 0 USPTO, 0 worldwide, **any class** | ✅ Nothing, anywhere | ✅ No incumbent at all | ✅ **9 of 9 free — incl. exact `.com`** | **PASS** |
| **Wellnigh** | ✅ 0 USPTO, 0 worldwide, any class | ✅ Nothing, anywhere | ✅ No game incumbent | ✅ 8 of 9 (`.com` for sale, $3,695) | **PASS** |
| **Thereish** | ✅ 0 USPTO exact, 0 worldwide | ✅ Nothing, anywhere | ⚠️ Pass, but *There Is No Game* shadows it | ✅ 8 of 9 (`.com` taken, dark) | **PASS** |
| **Closish** | ✅ 0 USPTO, 0 worldwide | ✅ No game — but a live consumer app | ⚠️ Bare word owned by that app | ✅ 8 of 9 (`.com` = the app) | **PASS** |
| **Fairish** | ✅ 3 worldwide, **none in 9/28/41** | ✅ No game | ⚠️ Slides to "fair game" | ✅ 8 of 9 (`.com` for sale, $7,595) | **PASS** |
| **Nearenough** | ✅ 0 as one token | ❌ **Live monetised game on Google Play** | ❌ Owned by a defunct studio | ✅ 8 of 9 | **FAIL** (ii, iii) |
| **Goodish** | ❌ **Live US Cls 41 registration** | ✅ No game | ⚠️ | ⚠️ 6 of 9 (`.com`/`.app`/`.io` taken) | **FAIL** (i) |
| **Middling** | ❌ **Live SG Cls 41 registration** | ✅ No game | ❌ "middling game" is a review verdict | ⚠️ 6 of 9 | **FAIL** (i, iii) |
| **Passable** | ❌ **Live JP Cls 9 registration** | ✅ No game | ❌ "passable game" is a review verdict | ⚠️ 6 of 9 | **FAIL** (i, iii) |
| **Tolerable** | ✅ 3 worldwide, none in 9/28/41 | ✅ No game | ❌ "tolerable game" is a review verdict | ⚠️ 7 of 9 | **FAIL** (iii) |
| **Approx** | ❌ **Live IN Cls 28 + live Cls 9 ×2** | ❌❌ **iOS 2-player closest-guess quiz game *and* a BGG board game** | ❌ | ❌ 6 of 9 (`.com`/`.app`/`.io` all live) | **FAIL** (all four) |

---

## 2. Criterion (i) — trademark registers

### 2a. USPTO

`POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch`, 2026-09-04. `wordmark` is an analyzed field, so
a phrase query matches the token anywhere in the mark; wildcard queries were run alongside to catch
formatives. Human-readable equivalent for any serial:
`https://tsdr.uspto.gov/#caseNumber=<serial>&caseSearchType=US_APPLICATION&caseType=DEFAULT&searchType=statusSearch`.

| Query | Total records | Live records in **IC 009 / 028 / 041** |
|---|---|---|
| `wordmark:"nighabouts"` / `wordmark:*NIGHABOUT*` | **0** / **0** | 0 |
| `wordmark:"nearenough"` / `wordmark:*NEARENOUGH*` | **0** / **0** | 0 |
| `wordmark:"closish"` / `wordmark:*CLOSISH*` | **0** / **0** | 0 |
| `wordmark:"fairish"` / `wordmark:*FAIRISH*` | **0** / **0** | 0 |
| `wordmark:"thereish"` | **0** | 0 |
| `wordmark:*THEREISH*` | 1 — `THEREISHELPFORIT.COM`, IC 035, **cancelled** (substring artefact) | 0 |
| `wordmark:"wellnigh"` / `wordmark:"well nigh"` / `wordmark:*WELLNIGH*` | **0** / **0** / **0** | 0 |
| `wordmark:"goodish"` | 4 | ❌ **1** — see below |
| `wordmark:"middling"` / `*MIDDLING*` | 1 / 2 — both dead | 0 |
| `wordmark:"passable"` / `*PASSABLE*` | 2 / 11 — no bare `PASSABLE` mark at all | 0 |
| `wordmark:"tolerable"` / `*TOLERABLE*` | 4 / 5 | 0 |
| `wordmark:"approx"` | 3, all dead, all long descriptive strings containing "approx." | 0 |

The one US hit that matters:

> ❌ **THE GOODISH MOMS CLUB** — serial **98140973**, reg. **7473303**, **IC 041**, **LIVE — REGISTERED**,
> Gorman, Jaclyn KO (individual, USA), filed 2023-08-19, registered 2024-08-13.

The rest of the *goodish* file is dead: `GOODISH` IC 029 (abandoned), `GOODISH GOODS` IC 014 (abandoned),
`UP MARK PLUS GOODISH ENGINE FILTERS` IC 007 (cancelled). The two dead near-misses worth naming for the
record are `MIDDLING`, serial 86189073, **IC 009/035/042/045**, filed 2014 by *A Mediocre Corporation* and
abandoned for no statement of use; and `RESPIRATORY EQUIPMENT FROM TOLERABLE TO COMFORTABLE`, IC 009/010/025,
abandoned 2023.

**Controls, same endpoint, same session** — these prove the endpoint was live and the wildcards well-formed:

| Control query | Hits |
|---|---|
| `wordmark:"thereabouts"` | **6** (Copper Purchasing ×3, Penney IP, Flavor Purveyor, Morton) |
| `wordmark:*GOODISH*` | **4** |
| `wordmark:*APPROX*` | **153** (mostly `approx.` inside long descriptive marks) |

`*APPROX*` returning 153 while `wordmark:"approx"` returns 3 is the analyzed-field behaviour working as
expected, not a contradiction: the wildcard reaches pseudo-text and translation fields.

Index caveat, unchanged from the earlier notes: results reflect USPTO's load dates, so filings in the last
one to two weeks may not appear.

### 2b. Worldwide — WIPO Global Brand Database

Brick `{key:"brandName", value:"<word>", strategy:"Simple"}`, all offices, all classes, 2026-09-04.

| Candidate | Worldwide records | Live in 9 / 28 / 41 |
|---|---|---|
| **nighabouts** | **0** | 0 |
| **nearenough** | **0** | 0 |
| **closish** | **0** | 0 |
| **thereish** | **0** | 0 |
| **wellnigh** | **0** | 0 |
| **fairish** | 3 | 0 |
| **tolerable** | 3 | 0 |
| **middling** | 2 | ❌ **1** |
| **passable** | 7 | ❌ **1** |
| **goodish** | 16 | ❌ **1** (the same US Cls 41 mark as §2a) |
| **approx** | **39** | ❌ **several** |

**Fairish** — all three clear of the games classes:
`FAIRISH` IDM000678191, Indonesia, **cls 35**, Registered 2020-03-05, Felicia Setijono;
`FAIRISH` IDM000678206, Indonesia, **cls 44**, Registered 2020-03-05, same owner;
`FAIRISH SHOES` 5106174, India, **cls 25**, Registered 2021-08-26.

**Tolerable** — all three clear:
`TOLERABLE LLC` 99805738, USA, **cls 5**, Pending (2026-05-05);
`RESPIRATORY EQUIPMENT FROM TOLERABLE TO COMFORTABLE` 90521035, USA, cls 9/25/10, **Ended**;
`WHEN IT'S INTENTIONAL, IT'S TOLERABLE!` 7468733, USA, **cls 44**, Registered 2024-08-06.

**Middling — the blocker:**

> ❌ **Middling Industries** — Singapore, **40202604508Q**, **Nice class 41**, **Registered, 20 August 2026**,
> owner MIDDLING INDUSTRIES (Singapore).

Five weeks old, in the entertainment class, on the word plus one generic noun. The only other worldwide
record is the dead US `MIDDLING` from §2a.

**Passable — the blocker:**

> ❌ **PASSABLE** — Japan, **3190082**, **Nice class 9**, **Registered, 30 August 1996**, owner アズビル株式会社
> (**Azbil Corporation**).

Also live but out of class: `PASSABLE` 3129637, India, cls 11, Registered 2015; `PASSABLE BRAND` LK/T/076112,
Sri Lanka, cls 30, Registered 1998. Dead: JP 4881574 (cls 25, expired), UK00003557091 (cls 12, ended),
JP 3123470 (cls 10, expired).

**Approx — four live records in the games classes or their neighbours:**

| Mark | Office | Number | Class | Status | Owner |
|---|---|---|---|---|---|
| **APPROX** | **India** | **5098193** | ❌ **28** | **Registered, 2021-08-21** | GAGANDEEP VERMA |
| **APPROX** | **Tunisia** | **2012/002091** | ❌ **9** | **Registered, 2013-10-01** | APPROX IBERIA, S.L. (Spain) |
| **APPROX** | **Spain** | **M4180515** | ❌ **9** | **Pending, 2022-08-05** | CON SOFT, S.A. |
| APPROX | India | 4869950 / 4869951 | 8 / 21 | Registered 2021 | Pacific Corporation |

Plus `APPROX` EM 004211983 (cls 9/16, ended), IDM000216465 Indonesia (cls 9, expired), and JP/IN rows in
classes 12/24/25. **A live Class 28 registration on the exact bare word is the single hardest register
finding in any of the four notes.**

**Goodish — one live 9/28/41 record, and a crowded file elsewhere.** Live outside the classes:
`goodish` AU 2088614 cls 25 (Registered 2020-05-22); `Goodish` IDM001194742 Indonesia cls 30 (2024);
`GOODISH` KR 4014953440000 cls 29 (2019); `GOODISH` PH4202600514508 cls 30/43 (Pending 2026-05-25);
`GOODISH ORGANICS` IN 6116623 cls 35; `グ-ディッシュ GOODISH` JP 6667317 cls 5/31/35; `G GOODISH` MY
TM2025006316 cls 40 (Pending). Dead: US 97593394, TH 848818, KR 4019910019044, CA 2076935, JP 2019-050903,
US 98270554, US 86810451, and `GOODISH(GOODISHJAPAN)` JP 4806221 (cls 25/36/37/**41**/42/43/45, **Expired**
2014).

**A note on `Well-nigh` as a search token.** `wellnigh` (one word) returns **0** worldwide. `well nigh` with
a space returns **28,294** — the query is OR-tokenised and matches every mark containing `nigh` (*Nigh
Magazine*, *MADE NIGH*, *THE NIGH*…). The hyphenated form has the same problem. **Only the closed-up spelling
is a searchable, ownable token**, which is an argument for `Wellnigh` over `Well-nigh` independent of taste.

---

## 3. Criterion (ii) — the App Store

Apple's own iTunes Search API, `https://itunes.apple.com/search?term=<t>&entity=software&country=<c>&limit=50`,
plus `https://itunes.apple.com/lookup?id=<id>&country=<c>` per record. US / GB / AU.

| Term | US | GB | AU | Exact-name app? |
|---|---|---|---|---|
| `nighabouts` | **0** | **0** | **0** | — |
| `nearenough` / `near enough` | 0 / 0 | 0 / 0 | 0 / 0 | — |
| `thereish` | **0** | **0** | **0** | — |
| `wellnigh` | 1 (*Wellxa Health*) | 1 | 1 | No |
| `middling` | 42 | 43 | 44 | **No** — all *Middle*-matches |
| `tolerable` | 38 | 37 | 37 | **No** — all *Tolerance*-matches |
| `closish` | 3 | 3 | 3 | ⚠️ **Yes** — *Closish: Trending Food Map* (Food & Drink / Travel) |
| `fairish` | 1 | 1 | 1 | ⚠️ **Yes** — *fairish*, EPARK RELAX&ESTHE, INC. (Health & Fitness / Lifestyle) |
| `goodish` | 8 | 46 | 46 | ⚠️ **Yes** — *Goodish: Daily Kindness* (Lifestyle) |
| `passable` | 46 | 5 | 46 | ⚠️ **Yes** — *Passable*, Angelo Cammalleri (Business / Productivity) |
| `approx` | 9 | rate-limited | rate-limited | ❌❌ **Yes — and it is a game.** |

**Controls:** `thereabouts` still returns **0** in US/AU (as in the earlier notes) while `middling` returns
42 on the same endpoint in the same session, so the zeros above are real. Caveat, unchanged: Apple's search
is relevance-ranked, not a title index, so a zero means "no *findable* app of that name", not proof of
absence. (`gb`/`au` for `approx` and `nearabouts` returned **HTTP 429** — **could not verify** those two
storefronts.)

### 3a. Approx — the finding that ends this candidate

[**Approx**](https://apps.apple.com/us/app/approx/id6444762394), trackId `6444762394`, bundle
**`com.AxosApps.Approx`**, seller **Alexandros Karapanos**, released **2023-01-03**, updated 2023-01-25,
version 1.1.2, free, 4+, **primary genre Games; genres Games / Education / Trivia.** Verbatim from its own
listing:

> "This is a different quiz game…"
> "Each game has 5 question from different categories, all questions have a number as the answer, there are
> no options to choose from, you have to type the number you think the right answer is. **The game is played
> online by 2 players**… **The player that has answered the closest number to the right answer increases his
> score by 1.** That means, you don't have to know the right answer for every question to win, you can guess
> and with a little bit of luck you will be closer to the right answer."

**A live, exact-name, two-player, closest-guess-wins game in the Games category.** That is this project's
mechanic, its player count and its store category, under this project's candidate name. It is the same class
of collision that killed *Nearish* in round two, and it is worse, because *Nearish*'s occupant was
2–12 players and this one is literally two.

### 3b. The other exact-name apps — none are games

- **Closish: Trending Food Map**, bundle `com.closish.android` on Android, Nikita Bondarenko, **Food & Drink
  / Travel**. A real, marketed, cross-platform consumer product (§6c).
- **fairish**, EPARK RELAX&ESTHE, INC. — a Japanese salon-booking app, Health & Fitness.
- **Goodish: Daily Kindness**, QLIQLO LAB INC., Lifestyle; plus **Goodish AI**, Robin Gajanand.
- **Passable**, Angelo Cammalleri, Business / Productivity.

None is in Games. All four are common-law users of the bare word in the same store a listing would land in.

---

## 4. Criterion (ii) — Google Play, Steam

### 4a. Google Play

Fetched as real HTML from `https://play.google.com/store/search?q=<t>&c=apps&hl=en&gl=US`, and the listing
pages themselves for the hits.

| Term | Packages returned | Exact-name app? |
|---|---|---|
| **`nighabouts`** | **0 packages** | **None — the query returns no apps at all** |
| `nearenough` | 17 titles | ❌ **`com.kernelx.nearenough` — "Near Enough"** |
| `closish` | 26 | ⚠️ `com.closish.android` — *Closish: Trending Food Map* |
| `fairish` | 23 | No (`jp.epark.salonappi1a4m3` is the iOS app's sibling) |
| `goodish` | 25 | ⚠️ `com.eitbiz.goodishai` — *Goodish AI Calorie Counter App* |
| `thereish` | 19 | **No** |
| `middling` / `passable` / `tolerable` / `wellnigh` | 22 / 14 / 20 / 19 | **No** |
| `approx` | 25 | No app named *Approx* — but ⚠️ `tech.approx.echochamber`, *Echo Chamber: **Word Chains***, and three more apps by **APPROX TEKNOLOJI ANONIM SIRKET** |

**Control test for the method:** the identical fetch returns package ids for every other term (`nearabouts`
returns `com.tetherapp.distance`, `NearJoy`, and **Near Enough**; `middling` returns `com.midlnative3`,
`gg.mid`, …). **`nighabouts` returning literally zero package links is therefore a real zero**, and the
cleanest Play result of any candidate in four notes.

Two consequences worth spelling out. **Nearenough as one word does not escape the round-two blocker** —
`com.kernelx.nearenough` is still live and still the top result for the query, and Play's duplicate-name
process does not care about a space. And **an "Approx"-branded developer already ships a word game on Play**
(*Echo Chamber: Word Chains*), which is genre-adjacency on top of everything else in §3a.

### 4b. Steam — every candidate clear

`https://store.steampowered.com/api/storesearch/?term=<t>&l=english&cc=US`:

`nighabouts` **0**, `nearenough` **0**, `near enough` **0**, `closish` **0**, `fairish` **0**, `goodish` **0**,
`thereish` **0**, `middling` **0**, `passable` **0**, `tolerable` **0**, `wellnigh` **0**, `well nigh` **0**,
`approx` **1** (*Approximately Up* — not an exact match).

**Control:** `term=portal` on the same endpoint returns `total: 10` with *Portal 2*, *Portal*, *Portal
Knights*, *Bridge Constructor Portal*. All twelve zeros are real.

---

## 5. Criterion (ii) — BoardGameGeek and itch.io

### 5a. BoardGameGeek — **verified directly for the first time in this series**

The three earlier notes all recorded BGG as *could not verify*: `xmlapi2` answers `Unauthorized` to every
scripted request, including the control term. That is still true — and it is still true from inside a
logged-in browser tab (`fetch('/xmlapi2/search?…')` → **HTTP 401**, `Unauthorized. See
https://boardgamegeek.com/using_the_xml_api`), so the API is closed to page scripts as well as to curl.

**But BGG's legacy HTML search works from a browser session.** Fetching
`/geeksearch.php?action=search&objecttype=boardgame&B1=Go&q=<t>` same-origin returns a real result table.

| Query | BGG result |
|---|---|
| `portal` **(control)** | **66 rows** — *Portal (1997)*, *Portal: The Uncooperative Cake Acquisition Game (2015)*, … |
| `nighabouts` | **No Items Found** |
| `nearenough` / `near enough` | **No Items Found** |
| `closish` | **No Items Found** |
| `fairish` | **No Items Found** |
| `goodish` | **No Items Found** |
| `thereish` | **No Items Found** |
| `wellnigh` / `well-nigh` | **No Items Found** |
| `middling` | **No Items Found** |
| `passable` | **No Items Found** |
| `tolerable` | **No Items Found** |
| `nearabouts` **(benchmark)** | **No Items Found** — the round-two indirect negative is now a direct one |
| **`approx`** | ❌ **1 game** |

> ❌ [**Approx (2024)**](https://boardgamegeek.com/boardgame/422981/approx) — BGG thing **422981**. From BGG's
> own result row: *"Approx (2024) — Discover curious and surprising facts in this exciting game"*, average
> rating **6.70** from **15** voters, no Geek Rank yet.

**Could not verify:** the game's designer, publisher, player count and full description. The item page
`boardgamegeek.com/boardgame/422981/approx` sits behind a Cloudflare "Performing security verification"
interstitial that did not clear in a browser tab within 20 seconds, and returns **HTTP 403** to WebFetch. The
row above is BGG's own search-result summary, retrieved from BGG.

This also **upgrades the round-two note's Nearabouts finding**: BGG is now a *direct* negative for
Nearabouts, not an indirect one.

### 5b. itch.io — still could not verify, now confirmed against a real browser

`https://itch.io/search?q=<t>` returns **HTTP 403** to curl for all eleven candidates, and every creator
subdomain probe (`nighabouts.itch.io`, `closish.itch.io`, `thereish.itch.io`, `wellnigh.itch.io`,
`fairish.itch.io`, `middling.itch.io`, `passable.itch.io`, `tolerable.itch.io`, `approx.itch.io`) returns
**403**.

New this round: the same request **from inside a real Chrome tab also fails**. The tab renders
`Just a moment... — itch.io — Performing security verification` (Cloudflare Ray ID `a35e2fedcad78acc`) and
does **not** clear after 21 seconds of waiting. Even a same-origin `fetch()` from that tab returns 403.

**itch.io is therefore unverified for all eleven candidates, and the wall is not a curl artefact.** It is the
one gap in this note that a human being would have to close by hand, and the earlier notes' hope that "one
manual browser look" would settle it now looks optimistic.

---

## 6. Criterion (iii) — searchability

This is the axis that killed *Ballpark*, *Near Enough* and *Nearish*, and it is where family C dies.

### 6a. Nighabouts — no incumbent, but the search engines don't know the word

`"nighabouts"` returns essentially **nothing**: one mountain-bike blog ([CHAINSLAP](https://chainslapmag.com/))
using it colloquially, and then dictionary pages for the parent word *nigh* —
[Merriam-Webster](https://www.merriam-webster.com/dictionary/nigh),
[Wordnik](https://www.wordnik.com/words/nigh),
[Wiktionary](https://en.wiktionary.org/wiki/nigh). `"nighabouts game"` returns **no Nighabouts at all**;
the engine falls back to *[The End Is Nigh](https://store.steampowered.com/app/583470/The_End_Is_Nigh/)*,
McMillen & Glaiel's 2017 platformer, and *[Watchmen: The End Is Nigh](https://en.wikipedia.org/wiki/Watchmen:_The_End_Is_Nigh)*.

**Read it honestly, both ways.** There is **no incumbent** — not a defunct studio, not a `.gg` duel, not a
daily puzzle. A game called Nighabouts would be the first Nighabouts-shaped thing in the result set, and the
first commercial use of the word anywhere. That is better than *Nearabouts*, whose bare word now has one
commercial result (`nearabouts.app`).

The cost is the other side of the same coin: the word is so rare that engines don't recognise it and
**silently relax the query to `nigh`**, where *The End Is Nigh* is waiting. That is a soft, self-correcting
problem — one shipped page with the word in the title fixes it — but it is real on day one, and it compounds
a spelling risk: *nigh* is `/naɪ/`, so **Nighabouts** reads as *NYE-abouts*, and a listener who has only
heard it will guess `niabouts`, `nyabouts` or `nighabout`.

### 6b. Wellnigh — clean of games, occupied by an Australian lender

`"wellnigh" OR "well-nigh" game app` returns **no game of that name**. What it returns is
[**Well Nigh**](https://wellnigh.com.au/), an Australian B2B financial firm (white-label funding, mortgage
manager support; [LinkedIn](https://au.linkedin.com/company/well-nigh),
[@wellnigh.official](https://www.instagram.com/wellnigh.official/)), then the dictionaries
([MW](https://www.merriam-webster.com/dictionary/well-nigh),
[WordReference](https://www.wordreference.com/definition/well-nigh)), then `nigh`- and `well`-matched games
(*The End Is Nigh*, *[ANIMAL WELL](https://store.steampowered.com/app/813230/ANIMAL_WELL/)*,
*[Well...](https://store.steampowered.com/app/2336290/Well/)*).

**The game slot is empty.** The word's commercial occupant is in a completely unrelated industry, on a `.com.au`,
with no register footprint anywhere (§2). This passes.

### 6c. Closish — the query belongs to a live app, in the same medium

`"closish" game` returns the dictionaries ([MW](https://www.merriam-webster.com/dictionary/closish),
[Wiktionary](https://en.wiktionary.org/wiki/closish), OneLook, Wordnik, bab.la, WordUnscrambler) and then
[**closish.com**](https://closish.com/) plus its
[Google Play listing](https://play.google.com/store/apps/details?id=com.closish.android). From the site's own
`<meta name="description">`, fetched 2026-09-04:

> "Every spot from TikTok and Instagram, on one map. Ranked by popularity. The posts and Google reviews in
> one tap. **The Closish app for iPhone and Android.**"

and from its `<title>`: *"Closish — food and coffee people are actually talking about"*.

**No game.** But this is a funded-looking, actively-marketed, two-platform consumer app that owns the exact
`.com`, both store listings, and the bare-word query. It is a strictly worse version of the *Nearabouts LLC*
asterisk from round two: same category of problem (a same-name mobile app in a different vertical), but
bigger, on both stores instead of one, and holding the `.com` instead of the `.app`.

### 6d. Thereish — no incumbent, but a famous game's title contains the phrase

`"thereish" game` returns no *Thereish*. It returns
*[There Is No Game: Wrong Dimension](https://en.wikipedia.org/wiki/There_Is_No_Game:_Wrong_Dimension)* (Draw
Me A Pixel, 2020) and its
[Coolmath](https://www.coolmathgames.com/0-there-is-no-game) /
[CrazyGames](https://www.crazygames.com/game/there-is-no-game) ports, plus
*[There](https://en.wikipedia.org/wiki/There_(virtual_world))* and *[Dadish](https://en.wikipedia.org/wiki/Dadish)*.

The mechanism is the same relaxation as §6a: the engine can't parse `thereish`, splits it, and *There Is No
Game* is the single strongest "there…game" document on the internet. This is a **pass with a flag** — nothing
is *named* Thereish — but of the five passers it is the one whose query is hardest to win, because the
competitor is a beloved indie game rather than a lender or a food map.

### 6e. Fairish — slides to "fair game"

`"fairish" game app board game` returns no *Fairish*. It returns
[Fair Games](https://play.google.com/store/apps/details?id=org.appfair.app.Faire_Games) (App Fair's
open-source casual collection),
[Fair Game](https://boardgamegeek.com/boardgame/321315/fair-game) on BGG,
[Fair Game](https://www.fairgamestore.com/) the game shop, and *Fair Play Backgammon*.

Nothing is called Fairish. But **"fair game" is one of the most worn idioms in English**, and every engine
will offer it. That is a permanent tax on the query, of the same kind that "near enough" pays.

### 6f. Family C — **the faint-praise names cannot be searched, by construction**

The single query `"tolerable game" OR "middling game" OR "passable game" review` returns, in order:

- [*The magic kind of middling: All my love to 6/10 games*](https://kimimithegameeatingshemonster.com/2026/08/14/the-magic-kind-of-middling-all-my-love-to-6-10-games/) — Kimimi The Game-Eating She-Monster
- [*Never Give Up Review: **Passable** but Puerile Platforming*](https://screenrant.com/never-give-up-review/) — ScreenRant
- [*'Plushed Gold Fever' Review – **Middling** Minigames…*](https://toucharcade.com/2011/09/14/plushed-gold-fever-review-middling-minigames-from-the-creators-of-plushed/) — TouchArcade
- [*Battletech Review — **Middling** Mechanized Mayhem*](https://gameinformer.com/games/battletech/b/pc/archive/2018/04/27/middling-mechanized-mayhem.aspx) — Game Informer
- [*Very brief review (**middling**)*](https://boardgamegeek.com/thread/2252322/very-brief-review-middling) — BoardGameGeek
- [*Monopoly (1997)*](https://en.wikipedia.org/wiki/Monopoly_(1997_video_game)) — "reviews ranged from middling to mediocre"

**`middling`, `passable` and `tolerable` are not just common English words — they are the specific vocabulary
games criticism uses to damn a game.** The query `<name> game` for each of them is permanently owned by
reviewers calling *some other game* mediocre, on Game Informer, TouchArcade, ScreenRant and BGG. There is no
SEO strategy that dislodges that, because the corpus grows every week.

`approx` is the same failure by a different route: the word is an abbreviation, so `approx game` competes
with every listing that says "approx. 30 minutes".

This is the honest answer the task asked for, and it is a clean **fail on criterion (iii) for all four**.

There is a second-order objection that matters more than the SEO one. These names *describe the product as
mediocre.* A review headline writes itself — "Middling is, aptly, middling" — and the joke lands once, on the
reviewer's side. *Nearabouts* names the near-miss; *Middling* names the quality.

---

## 7. Word status

Wiktionary rows were fetched directly from the MediaWiki API (`action=parse&prop=wikitext`). OED, Merriam-Webster,
Collins and DARE all block scripted access (§7a), so their rows are entry-URL existence plus search-index
metadata — one step removed from the source, and flagged as such.

| Candidate | Attested? | Evidence |
|---|---|---|
| **Nighabouts** | ✅ **Yes, narrowly** | [Wiktionary `nighabouts`](https://en.wiktionary.org/wiki/nighabouts): adverb, *"(archaic or regional) Almost, nearly"*; parent [`nighabout`](https://en.wiktionary.org/wiki/nighabout) identical. **[DARE](https://www.daredictionary.com/view/dare/ID_00040498?language=en) carries `nighabout` among the derivations under its `nigh` headword** — the same regional-American shape as `nearabout(s)`. **No OED entry** (`/dictionary/nighabout_adv` and `/nighabouts_adv` both bounce to OAuth, i.e. unconfirmed either way) and **no Merriam-Webster entry found**. |
| **Nearenough** | ❌ **Coinage as one word** | No Wiktionary entry for `nearenough` **or** `near enough`. The *phrase* is attested — [Longman](https://www.ldoceonline.com/dictionary/near-enough), [Free Dictionary idioms](https://idioms.thefreedictionary.com/near+enough) — and is genuinely Australian/British in currency, but **the closed-up single word is not a word**; it is a phrase with the space deleted. |
| **Closish** | ✅ Yes | [Wiktionary](https://en.wiktionary.org/wiki/closish): *"alternative spelling of closeish"*. **[Merriam-Webster](https://www.merriam-webster.com/dictionary/closish)** carries it — *"rather close"*. **OED** has [`closeish, adj.`](https://www.oed.com/dictionary/closeish_adj). |
| **Fairish** | ✅ **Yes, strongly** | [Wiktionary](https://en.wiktionary.org/wiki/fairish): *"Of moderate quality, size, etc."*, from *fair* + *-ish*, with citations from **D. H. Lawrence (*The Ladybird*, 1921)**, Elinor Mordaunt (1915), George Borrow, and Douglas Hurd. **[OED `fairish, adj. & adv.`](https://www.oed.com/dictionary/fairish_adj) — six senses, earliest use 1611 (Randle Cotgrave).** [MW](https://www.merriam-webster.com/dictionary/fairish) ("fairly good"), [Collins](https://www.collinsdictionary.com/dictionary/english/fairish), [Dictionary.com](https://www.dictionary.com/browse/fairish). |
| **Goodish** | ✅ Yes | [Wiktionary](https://en.wiktionary.org/wiki/goodish): *"Rather good than the contrary; not actually bad; tolerable"* and *"Considerable; goodly"*, with **Orwell (*Down and Out*)** and **Stevenson (*Treasure Island*)** citations; cites Webster 1913. **[OED `goodish, adj.`](https://www.oed.com/dictionary/goodish_adj) — earliest use 1751 (Robert Morris).** Also in [Oxford Learner's](https://www.oxfordlearnersdictionaries.com/definition/english/goodish). |
| **Thereish** | ❌ **Coinage** | **No Wiktionary entry.** No OED, MW or Collins entry found. It is a well-formed `-ish` derivation and instantly legible, but it is not a word anyone has written down in a dictionary. |
| **Middling** | ✅ Yes | [Wiktionary](https://en.wiktionary.org/wiki/middling) (a former Word of the Day): *"Of intermediate or average size, position, or quality; mediocre"*, adjective/adverb/noun, with a 1680s *Philosophical Transactions* citation. |
| **Passable** | ✅ Yes | [Wiktionary](https://en.wiktionary.org/wiki/passable): *"tolerable; adequate; no more than satisfactory"*, from French *passable*, with *Economist* (2013) and *Atlantic* (2023) citations. |
| **Tolerable** | ✅ Yes | [Wiktionary](https://en.wiktionary.org/wiki/tolerable): from Middle English via Latin *tolerābilis*; *"bearable"* **from the 15th c.**, *"moderate in degree; mediocre; **passable**"* **from 1548**. |
| **Wellnigh / Well-nigh** | ✅ **Yes, and it is the oldest word here** | [Wiktionary `wellnigh`](https://en.wiktionary.org/wiki/wellnigh) — alternative spelling of [`well-nigh`](https://en.wiktionary.org/wiki/well-nigh), with **Mark Twain (*Tom Sawyer*, ch. XXIV)** and Pindar-translation citations. `well-nigh` is a **Wiktionary Word of the Day (2021-09-10)**: *"Almost, nearly"*, from Middle English *wel-neigh* ← **Old English *wel nēah***, ultimately PIE *\*welh₁-* + *\*h₂neḱ-*; cites [MED](https://quod.lib.umich.edu/m/middle-english-dictionary/) and **OED (`well-nigh, adv.`, entry id 227460, revised December 2020)**, with a **Spenser, *Faerie Queene* (1590)** quotation and a Walter Scott one. [MW](https://www.merriam-webster.com/dictionary/well-nigh) carries it. |
| **Approx** | ⚠️ Marginal | [Wiktionary](https://en.wiktionary.org/wiki/approx): *"alternative spelling of **approx.**"* — i.e. it is an **abbreviation**, not a word. |

### 7a. Could not verify

- **OED full text.** Every `https://www.oed.com/dictionary/<entry>` request **302-redirects to
  `oed.com/oauth2/authorization/transparent?p=…`** for unauthenticated clients. Entry URLs and first-use
  dates above come from the public search-result metadata for those pages; **definition text, frequency bands
  and quotation paragraphs were not read from OED directly.**
- **Merriam-Webster.** Every `/dictionary/<word>` returns **HTTP 403** to curl with full desktop browser
  headers — for all twelve words tried, including controls. MW rows are search-index renderings.
- **Collins and DARE.** Same 403 wall as the earlier notes. The DARE `nigh` headword is confirmed to exist at
  [daredictionary.com/view/dare/ID_00040498](https://www.daredictionary.com/view/dare/ID_00040498?language=en);
  **the `nighabout` sub-entry's definition and regional label were not read from DARE itself.**

---

## 8. Criterion (iv) — domains

Registry RDAP where the registry runs one — [Verisign](https://rdap.verisign.com/com/v1/domain/) for `.com`,
[Google Registry](https://pubapi.registry.google/rdap/domain/) for `.app`,
[CentralNic](https://rdap.centralnic.com/game/domain/) for `.game` — and registry WHOIS otherwise
(`whois.nic.io`, `whois.gg`, `whois.nic.fun`). **No reseller "available!" badges were used.** Every free
`.com` was independently re-checked against `whois.verisign-grs.com`. "Serves anything?" is `dig` plus a real
`curl` of the apex. All 2026-09-04.

**Registry controls run in the same session, so every FREE below is a real free:**
`rdap.centralnic.com/game/domain/{nintendo,epic,play}.game` → **200, 200, 200**;
`pubapi.registry.google/rdap/domain/{google,blog,thereabouts,nearabouts}.app` → **200 ×4**;
`whois.nic.io github.io` → `Domain Name: github.io`; `whois.gg thereabouts.gg` → full record, NameCheap;
`whois.nic.fun nic.fun` → `Domain Name: nic.fun`; `whois.verisign-grs.com "domain google.com"` →
`Domain Name: GOOGLE.COM`.

### 8a. Nighabouts — **9 of 9 free. Nothing in this series has done that.**

| Domain | Status | Verified by |
|---|---|---|
| **nighabouts.com** | **AVAILABLE** | Verisign RDAP **404** + `whois.verisign-grs.com` → `No match for domain "NIGHABOUTS.COM"` |
| **nighabouts.game** | **AVAILABLE** | CentralNic RDAP 404 + `whois.nic.game` → `DOMAIN NOT FOUND` |
| **nighabouts.app** | **AVAILABLE** | Google Registry RDAP **404** |
| **nighabouts.io** | **AVAILABLE** | `whois.nic.io` → `Domain not found.` |
| **nighabouts.gg** | **AVAILABLE** | `whois.gg` → `NOT FOUND` |
| **nighabouts.fun** | **AVAILABLE** | `whois.nic.fun` → `available for registration` |
| **nighaboutsgame.com** | **AVAILABLE** | RDAP 404 + `No match for domain "NIGHABOUTSGAME.COM"` |
| **playnighabouts.com** | **AVAILABLE** | RDAP 404 + `No match for domain "PLAYNIGHABOUTS.COM"` |
| **nigh-abouts.com** | not checked | — |

**The exact-match `.com` is free.** *Nearabouts*, *Nearish* and *Near Enough* all had theirs held by
investors — *nearenough.com* at a published **$6,295**. This one costs a registration fee.

### 8b. The other four passers

| | `.com` | `.game` | `.app` | `.io` | `.gg` | `.fun` | `<n>game.com` | `play<n>.com` | Free |
|---|---|---|---|---|---|---|---|---|---|
| **Wellnigh** | ❌ for sale | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **7 of 8** |
| **Thereish** | ❌ taken, dark | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **7 of 8** |
| **Closish** | ❌ **live app** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **7 of 8** |
| **Fairish** | ❌ for sale | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **7 of 8** |

What the taken ones actually resolve to:

- **wellnigh.com** — TurnCommerce / NameBright, created **2017-02-09**, A `13.223.25.84`, 301s to
  [hugedomains.com/domain_profile.cfm?d=wellnigh.com](https://www.hugedomains.com/domain_profile.cfm?d=wellnigh.com).
  Verbatim from the page markup: `This domain is for sale: <span class="green">$3,695`. **Investor
  inventory, not a business** — and note the Australian lender at §6b uses `wellnigh.com.au`, not this.
- **fairish.com** — TurnCommerce / NameBright, created **2013-03-14**, same `13.223.25.84`,
  [HugeDomains, **$7,595**](https://www.hugedomains.com/domain_profile.cfm?d=fairish.com). Also investor
  inventory. (For calibration: `nearenough.com` is $6,295 on the same platform.)
- **thereish.com** — Hosting Concepts B.V. / Registrar.eu, created **2025-12-18**, expires 2026-12-18,
  A `185.53.179.136`. **Serves nothing** (`curl` → HTTP 000). That IP is Team Internet / ParkingCrew's
  parking range; a one-year registration pointed at a parking host is speculative holding, not use.
- **closish.com** — NameCheap, created **2023-03-19**, expires 2028-03-19, A `76.76.21.21` (Vercel),
  **HTTP 200 with a real marketing site** for the food-map app (§6c). **The only one of the four that is a
  business using the name.**

### 8c. The failures' domains, for completeness

| | `.com` | `.app` | `.io` | Notes |
|---|---|---|---|---|
| **Goodish** | ❌ Dynadot, 2002, dark | ❌ taken | ❌ NameCheap, 2026-05-14 | Three of the best forms gone |
| **Middling** | ❌ Tucows, 2003, dark | ❌ taken (HTTP 404) | ❌ NameSilo, 2025 — **middling.io** serves a parked lander |
| **Passable** | ❌ GoDaddy, **1999**, dark | ❌ **live** — [passable.app](https://passable.app/), *"Passable Wallet Cards"* | ❌ **live** — [passable.io](https://www.passable.io/), *"Passable — Simple NFC Passes for Loyalty, Events & Membership"* | **Two live products** on the two best game-adjacent TLDs |
| **Tolerable** | ❌ Spaceship, 2000 — [for sale at oxley.com](https://oxley.com/domain/tolerable.com/) (no public price found) | ✅ **free** | ❌ NameCheap, 2018, dark | |
| **Approx** | ❌ Hetzner, **1998-01-15**, live (empty `<title>`) | ❌ live — *"Coming Soon"* | ❌ live — redirects to `/lander` | |
| **Nearenough** | ❌ [HugeDomains **$6,295**](https://www.hugedomains.com/domain_profile.cfm?d=nearenough.com) | ✅ free | ✅ free | Unchanged from round two, **re-verified today** |

**Lookup caveats, recorded rather than smoothed over:** `.gg` still has **no RDAP service at all**, so it is
registry WHOIS only. `rdap.org` was not relied on for `.io` or `.fun`. **Could not verify:** the asking price
for `tolerable.com` — the oxley.com listing page renders no figure in its served HTML. Nothing was
rate-limited on the domain side and no lookup was retried into a different answer.

---

## 9. Ranking

**Inference from §§1–8. This is the recommendation, not a finding.**

### 9a. What fails, and on what

| Candidate | Fails on | The one-line reason |
|---|---|---|
| **Approx** | **(i) (ii) (iii) (iv)** | A **live Indian Class 28 registration** on the bare word; a **live iOS two-player closest-guess quiz game called *Approx***; a **2024 board game called *Approx* on BGG**; an "Approx" developer already shipping a word game on Play; and `.com`/`.app`/`.io` all live. It fails every criterion. **Delete it.** |
| **Passable** | **(i) (iii)** | **Azbil Corporation holds `PASSABLE` in Class 9 in Japan** (JP 3190082, registered), and *"passable game"* is a review verdict. Two live products already sit on `passable.app` and `passable.io`. |
| **Middling** | **(i) (iii)** | **`Middling Industries` is a live Singapore Class 41 registration**, five weeks old. And *"middling game"* is what Game Informer calls a Battletech. |
| **Goodish** | **(i)** | **`THE GOODISH MOMS CLUB` is a live US Class 41 registration** (reg. 7473303). Alone that is thin — a composite phrase mark, not the bare word — but the gate is the gate, and `goodish.com`/`.app`/`.io` are all gone besides. |
| **Tolerable** | **(iii)** | Register is genuinely clean (3 records worldwide, none in 9/28/41) and no game exists. But *"tolerable game"* is critic-speak for mediocre, permanently, and the name **describes the product as barely acceptable**. |
| **Nearenough** | **(ii) (iii)** | Deleting the space does not delete the blocker. **[Near Enough](https://play.google.com/store/apps/details?id=com.kernelx.nearenough)** (`com.kernelx.nearenough`, Kernelx) is still live and monetised on Google Play, still the top result for the query, **re-verified today**; and *Near Enough Games*, the defunct studio, still owns `near enough game`. Round two's verdict stands. |

**Six lost. That is the point of the exercise.** Family C was the weakest hypothesis and it lost four of five
members; the one survivor (*Wellnigh*) survives because it is not actually a faint-praise word — it means
*almost*, like the rest of the front-runners, and got sorted into the wrong family.

### 9b. What passes, ranked against *Nearabouts*

| | **Nighabouts** | **Wellnigh** | **Thereish** | **Fairish** | **Closish** | **Nearabouts** *(benchmark)* |
|---|---|---|---|---|---|---|
| USPTO, any class | **0** | **0** | 0 (1 dead artefact) | **0** | **0** | **0** |
| Worldwide, any class | **0** | **0** | **0** | 3 (none in 9/28/41) | **0** | **0** |
| Live 9/28/41 anywhere | **0** | **0** | **0** | **0** | **0** | **0** |
| iOS exact-name app | **None** | None | **None** | ⚠️ salon app | ⚠️ food map | ⚠️ Lifestyle app + LLC |
| Google Play | **0 packages returned** | None | None | None | ⚠️ `com.closish.android` | Clear |
| Steam / BGG | 0 / **No Items Found** | 0 / **No Items Found** | 0 / **No Items Found** | 0 / **No Items Found** | 0 / **No Items Found** | 0 / **No Items Found** *(now direct)* |
| `<name> game` query | **Unclaimed** | **Unclaimed** | Unclaimed, but *There Is No Game* shadows it | Unclaimed, slides to "fair game" | Bare word owned by the app | **Unclaimed** |
| Word status | Wiktionary + DARE; **no OED** | **OED, MED, Old English, Spenser, Twain** | ❌ **Coinage** | **OED 1611**, MW, Collins, Lawrence | MW + OED (`closeish`) | **OED 1634**, MW, DARE, Bacon |
| Exact `.com` | ✅ **FREE** | ❌ $3,695 | ❌ taken, parked | ❌ $7,595 | ❌ **live product** | ❌ investor-held, dark |
| `.app` | ✅ FREE | ✅ FREE | ✅ FREE | ✅ FREE | ✅ FREE | ❌ **taken and live** |
| Domain forms free | **9 of 9** | 7 of 8 | 7 of 8 | 7 of 8 | 7 of 8 | 6 of 9 |

#### 1st — **Nighabouts**

**It beats Nearabouts on the two axes Nearabouts lost on, and ties everywhere else.**

- **The exact `.com` is free** — the first candidate in four notes for which that is true. So is `.app`,
  which *Nearabouts* lost to Nearabouts LLC. So is everything else: nine of nine.
- **There is no same-name entity at all.** No LLC, no app, no site, no LinkedIn, no Instagram. `nearabouts`
  has one commercial user; `nighabouts` has zero, in any register, any store, any storefront, any domain.
  This is the cleanest name the project has found, full stop.
- **Google Play returns literally no apps** for the query — not "no exact match", *no packages*, while every
  control term returns a dozen.
- It is the **exact semantic twin of Nearabouts**: same construction (`nigh` + `about` + adverbial `-s`),
  same meaning (*almost, nearly*), same archaic-regional register, and it means *approximately there*, which
  is this game's whole subject.

**Its two real costs**, and they are the mirror of Nearabouts' strengths:

1. **Weaker attestation.** *Nearabouts* has an OED entry (1634), a Merriam-Webster headword with a regional
   label, a DARE headword and a Bacon citation. *Nighabouts* has a Wiktionary entry marked *archaic or
   regional* and a DARE derivation under `nigh` — real, but thinner, and **no confirmed OED or MW entry**.
   It sits closer to the coinage end than Nearabouts does. For trademark distinctiveness that is arguably an
   *advantage* (rarer word → closer to arbitrary); for the "it's a real word, look it up" pleasure the
   project wants, it is a small loss.
2. **Pronunciation and spelling.** *Nigh* is `/naɪ/`. **NYE-abouts.** Heard aloud, it will be spelled
   `niabouts` or `nyabouts` by a fair number of people, and typed queries get silently relaxed to `nigh`
   (§6a). *Nearabouts* has no such trap — everyone can spell *near*.

That trade is the decision: **a free exact `.com` and a genuinely virgin name, against a slightly less solid
dictionary and a slightly harder spelling.**

#### 2nd — **Wellnigh**

The best *word* in the round, and by a distance: **Old English *wel nēah***, in the OED (`well-nigh, adv.`,
entry revised December 2020), in the Middle English Dictionary, quoted in Spenser's *Faerie Queene* (1590)
and Twain's *Tom Sawyer*, a Wiktionary Word of the Day. Register-empty worldwide. No game anywhere. Query
unclaimed by any game. Seven of eight domain forms free.

Three things hold it below Nighabouts. The exact `.com` is **$3,695** of investor inventory. There is a live
Australian commercial user of the two-word form (a lender at `wellnigh.com.au`) — harmless, different
industry, no registration, but not nothing. And **the closed-up spelling is mandatory**: `well nigh` and
`well-nigh` both dissolve into 28,294 register hits and into `nigh` on every search engine (§2b), so the name
only works as one token, which fights the reader's instinct to hyphenate.

It also reads slightly *formal* where *Nearabouts* and *Nighabouts* read *warm* — "well-nigh impossible" is a
literary register, not a couch register. That is taste, not clearance.

#### 3rd — **Thereish**

Register-empty everywhere. No app, no game, no BGG entry, nothing. Seven of eight domains free including
`.app`. And it is, of all the candidates, the one that most *sounds like the mechanic* — "there-ish" is
exactly what a player says when they land close.

But it is a **coinage** — no Wiktionary, OED, MW or Collins entry — which forfeits the "attested but
uncommon" property the brief is aiming at, and it is a **productive `-ish` derivation**, which is the exact
morphological pattern that made *Nearish* read as generic hedging in round two. §8c of that note called this
"the difference between a word you *find* and a word you *form*", and *Thereish* is formed. Add the *There Is
No Game* shadow on the query (§6d) and it is a solid third, not a contender.

#### 4th — **Fairish**

Excellent word: **OED from 1611**, MW, Collins, Dictionary.com, and a D. H. Lawrence citation. Register-clear
of the games classes. No game anywhere. Seven of eight domain forms free.

Two problems, neither fatal, both permanent. *"Fair game"* is an idiom the search engines will always offer
instead (§6e). And **"fairish" means *moderately good*, not *approximately right*** — it is a quality grade,
not a distance measure, so it belongs semantically with family C even though it clears the gate. For a game
about *how close you got*, that is the wrong axis.

#### 5th — **Closish**

Clears the gate on the letter of every criterion: zero register records worldwide, no game anywhere, seven of
eight domains free, MW and OED entries.

But it is the weakest of the five on the thing that actually bites. **[Closish](https://closish.com/) is a
live, marketed, two-platform consumer app** with the exact `.com`, an App Store listing, a Play listing, and
ownership of the bare-word query. That is the *Nearabouts LLC* asterisk from round two, doubled: two stores
instead of one, the `.com` instead of the `.app`, and an actual marketing site instead of an unedited Replit
placeholder. A game called Closish would be the second Closish in both app stores.

### 9c. Recommendation

**Promote *Nighabouts* to joint front-runner with *Nearabouts*, and let the choice between them turn on
spelling versus ownership.**

- If the project weights **ownability** — a free exact `.com`, a free `.app`, no same-name company anywhere
  on earth — **Nighabouts wins outright**, and it is not close.
- If it weights **the word itself** — OED 1634, a Bacon citation, and a spelling nobody can get wrong —
  **Nearabouts keeps the crown**, and its only real cost stays what round two found: `nearabouts.app` belongs
  to somebody else.

**Keep *Wellnigh* as the fallback**, because it is the strongest word in the whole series and its problems
are cheap ones.

**Drop *Approx*, *Passable*, *Middling*, *Goodish*, *Tolerable* and *Nearenough*.**

If **Nighabouts** is adopted, the defensive moves in order are: register **`nighabouts.com`** *first* (it is
the only exact `.com` this project has ever been able to have, and it costs a registration fee), then
**`nighabouts.app`** and **`nighabouts.game`**; and — because the register is *completely* empty in every
office, which will not stay true forever — treat a Class 9/28/41 filing as cheaper now than later.

### 9d. The pattern worth naming, updated

Round two ended by observing that the near-miss semantic field is crowded because every daily-browser-game
designer reaches for the same three or four words. This round adds a sharper version of that lesson.

**The names that failed are the ones a search engine already has a strong opinion about.** *Middling*,
*Passable* and *Tolerable* lost because games criticism owns those exact words. *Approx* lost because it is
an abbreviation that appears in a million listings — and, having been thought of by two other people, is
already a quiz game and a board game. *Nearenough* lost because it is a phrase people say ten times a day.

**The names that passed are the ones nobody says.** *Nighabouts* has one recorded use on the entire open web.
That is precisely why its `.com` is free, why its register is empty, why Play returns zero packages, and why
the `<name> game` query is unclaimed. **Obscurity is not a bug in a game name; it is the whole asset.** The
cost of obscurity is that the first person to hear it has to ask how it's spelled — a cost paid once, against
an asset that compounds.

---

## 10. What is still missing

Not cleared by this note, and not claimable as cleared:

1. **itch.io, all eleven candidates.** Cloudflare 403 to curl, to every creator subdomain, **and to a real
   browser tab that never cleared the challenge** (§5b). This is the fourth consecutive note to fail here.
   It needs a human with a mouse.
2. **TMview itself.** Down to everything today (§0a). The worldwide rows above are **WIPO Global Brand
   Database**, control-matched against round two's TMview figures for three words — but GBD carries fewer CN
   filings than TMview did for *nearish*, so **Chinese filings on the passers are under-checked**.
3. **The BGG *Approx* item page.** Confirmed to exist via BGG's own search (thing 422981, 15 voters,
   avg 6.70); **designer, publisher, player count and description not retrieved** — the item page is
   Cloudflare-gated.
4. **National register verification of the three blocking rows.** `Middling Industries` (SG 40202604508Q),
   `PASSABLE` (JP 3190082) and `APPROX` (IN 5098193) are **GBD's copies**, not IPOS/JPO/CGPDTM records.
   Round one demonstrated TMview statuses can be stale by years (the AU *Ballpark* row); assume the same risk
   here. The JP *Passable* registration in particular dates from **1996** and its current renewal state was
   not confirmed at JPO.
5. **OED, Merriam-Webster, Collins and DARE full text** — all four block scripts (§7a). In particular,
   **whether OED has an entry for `nighabout(s)` at all is genuinely unknown**, and it is the single fact
   that would most sharpen the Nighabouts-vs-Nearabouts comparison.
6. **Apple GB/AU storefronts for `approx` and `nearabouts`** — HTTP 429, not retried.
7. **Asking price for `tolerable.com`** — the oxley.com listing renders no figure.
8. **Common-law and unregistered rights generally**, and **Closish's** in particular. The register cannot see
   them, and Closish is a real business with two store listings.
9. **Madrid and any national register outside GBD's 89 sources**, and any filing loaded after 2026-09-04.
10. As every note in this series has said: **§9 is a research opinion, not legal advice.** Whether a word game
    called Nighabouts is confusable with anything is the DuPont-factor judgment call that needs an attorney
    before anything ships.
