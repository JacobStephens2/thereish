# Round four — six goal-direction candidates through the gate, measured against *Thereish*

> **This is not legal advice.** It is a research note by a non-lawyer, assembled from public registers and
> product listings on **2026-09-05**. It records what USPTO's search API, TMview, WIPO's Global Brand
> Database, the app stores, Steam, BoardGameGeek, Wiktionary and the domain registries actually returned on
> that date — nothing more.

Fifth note in the naming series, after
[name-mind-meld-availability.md](./name-mind-meld-availability.md) (killed *Mind Meld*),
[name-candidate-clearance.md](./name-candidate-clearance.md) + [name-candidate-domains.md](./name-candidate-domains.md),
[name-candidate-clearance-round2.md](./name-candidate-clearance-round2.md) and
[name-candidate-clearance-round3.md](./name-candidate-clearance-round3.md).

**Why this round exists.** Rounds one to three all named the *miss* — the [ADR-0008](../adr/0008-the-games-name.md)
slate is *Nearabouts*, *Wellnigh*, *Thereish*, *Fairish*. On 2026-09-04 the target player heard that slate
cold and again after play, picked **Thereish** both times, and said she would rather the name pointed at the
game's **goal** — two players converging on the same word — than at the near miss. This round gates
goal-direction candidates. **Thereish is not re-cleared here; it is the benchmark.**

Six candidates, in four families:

- **Household ritual:** **Jinx** — what two people say when they say the same word at once.
- **Idiom:** **Same Page** (and the closed form **SamePage**). *Page* is a glossary word of this project,
  permitted for the title for this round.
- **Musical:** **Unison**, **Chime**.
- **Kindred / affinity:** **Kindred**.
- **The ladder:** **Deep Meld**.

## The gate

Unchanged from ADR-0008. A candidate passes only if **all five** hold:

1. **Zero LIVE trademark records in Nice 9 / 28 / 41, in any register.**
2. **No existing GAME carrying the name in any store** — Apple, Google Play, Steam, itch.io, BoardGameGeek.
3. **An unclaimed `<name> game` search query.**
4. **At least one good domain form free**, verified at the registry.
5. **Spellable on hearing.**

**Result: five fail outright, one passes the four external criteria and then fails on a rule this project
already wrote for itself.** Round four is the worst round in the series, and that is the finding: *the
goal-direction semantic field is not merely crowded, it is owned.* Two candidates are occupied by a live
word game of this exact mechanic — one of them shipped **one month ago**.

---

## 0. Method, and what changed since round three

Primary sources, fetched 2026-09-05. Every zero-result query was control-tested against a known-positive
neighbour in the same session, and the controls are printed inline, so each zero below is provably a real
zero. Anything unreachable is flagged **could not verify**. §9 is inference; everything above it is finding.

| Axis | Source used | Status today |
|---|---|---|
| US register | `POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch` (base URL from [configuration.json](https://tmsearch.uspto.gov/configuration.json)) | Working |
| Worldwide register | ✅ **[TMview](https://www.tmdn.org/tmview/) is back** — `POST /tmview/api/search/results` | **Working — first time in this series** (§0a) |
| Worldwide register | [WIPO Global Brand Database](https://branddb.wipo.int/) | Working, via the live app (§0a) |
| iOS | Apple iTunes Search + Lookup APIs | Working |
| Android | Google Play search + listing pages | Working |
| Steam | `store.steampowered.com/api/storesearch/` + `appdetails` | Working |
| BoardGameGeek | `geeksearch.php` via a real browser tab | Search working; **item pages Cloudflare-gated** (§5a) |
| itch.io | `itch.io/search`, creator subdomains | ❌ Cloudflare 403 to curl **and** to a real browser (§5b) |
| Dictionaries | Wiktionary MediaWiki API | Working |
| Domains | Registry RDAP (Verisign `.com`, Google `.app`, CentralNic `.game`) and registry WHOIS (`.io`, `.gg`, `.fun`) | Working |

### 0a. Both worldwide registers are reachable today — and they disagree about phrases

Round three could not reach TMview at all. **Today it answers.** `https://www.tmdn.org/tmview/` returns
HTTP 200 with a real app shell, and its search API answers JSON. It is temperamental — repeated rapid
queries return `Connection reset by peer`, so every query below was issued singly with an 8-second gap — but
it works, and this note uses it as the primary worldwide instrument for the first time in the series.

**Controls, run in the same sessions:**

| Control | TMview | WIPO GBD | Round three's figure |
|---|---|---|---|
| `thereabouts` | 5+ rows incl. `THEREABOUTS` MX 2981735 (Penney IP, Registered, cls 25) | **9** records | **9** via GBD |
| `thereish` **(benchmark)** | **1** — `THEREISHELPFORIT.COM`, US 85635300, cls 35, **Ended** | — | 0 exact + the same substring artefact at USPTO |
| `deepmeld` | **0** | **"No results found!"** | — |

TMview reproduces the exact `thereish` substring artefact round three found at USPTO, and both instruments
return zero for `deepmeld`. The zeros below are real.

**One instrument difference worth recording.** GBD OR-tokenises multi-word queries: `same page` returns
**8,237** records (it matches *page* anywhere), and `deep meld` returns **15,688** — the same failure mode
round three found for `well nigh` (28,294). **TMview handles the phrase properly**: `same page` returns
**84**, `deep meld` returns **2**. So for two-word candidates, TMview is the trustworthy instrument and GBD
is not, which is the reverse of round three's situation.

---

## 1. Summary — the gate, candidate by candidate

| Candidate | (i) TM 9/28/41 | (ii) Game in a store | (iii) `<name> game` query | (iv) Domain free | (v) Spellable | **Gate** |
|---|---|---|---|---|---|---|
| **Deep Meld** | ✅ **0 USPTO, 0 TMview, 0 GBD, any class** | ✅ Nothing, anywhere | ⚠️ No incumbent; *mind meld* shadows it | ✅ **9 of 10 free** | ✅ | **PASS (4/4 external)** — then §9b |
| **Jinx** | ❌ **Live US Cls 28 on "board games"; live EU/UK mark in 9+28+41; Riot Games** | ❌ **Five exact-title BGG games + retail board game + Play word games** | ❌ Riot's Jinx and the playground ritual | ❌ 3 of 10 (`.com` = J!NX apparel) | ✅ | **FAIL** (i, ii, iii, iv) |
| **Unison** | ❌ **Live US Cls 9 + Cls 41 (UNISON LEAGUE, "on-line computer game")** | ❌❌ **App Store *Unison* — Games/Puzzle/Word — "two minds, one word", 1v1, live** | ❌ UNISON, UK's largest union | ❌ 3 of 10 | ✅ | **FAIL** (all) |
| **Chime** | ❌ **Chime Financial Cls 41; Amazon CHIME Cls 41 in ~10 offices** | ❌ **Steam *Chime* (Zoë Mode, 2010)** | ❌ Chime, the 20m-customer neobank | ❌ 4 of 10 | ✅ | **FAIL** (i, ii, iii) |
| **Kindred** | ❌ **Kindred IP Ltd holds the bare word in 9 + 28 + 41 together (EUTM/WIPO/CA/UK)** | ❌ **BGG *Kindred* (2026); *Kindred: Couples Card Game* on iOS; 7 Steam titles** | ❌ Kindred Group (gambling) | ❌ 3 of 10 | ✅ | **FAIL** (all) |
| **Same Page** | ❌ **Live UK Cls 9 (Same Page For Life Ltd)** | ❌❌ **[playsamepage.games](https://www.playsamepage.games/) — a live word-association party game called SAME PAGE** | ❌ The idiom, plus that game | ⚠️ 5 of 10 | ❌ Two-word/one-word split | **FAIL** (all) |
| **SamePage** | ❌ **Samepage Labs holds Cls 9 + 41 (EUTM 010655728, UK, NZ)** | ❌ Same as above | ❌ | ⚠️ 5 of 10 | ❌ | **FAIL** (i, ii, iii, v) |

---

## 2. Criterion (i) — trademark registers

### 2a. USPTO

`POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch`, 2026-09-05. `wordmark` is analysed, so a
phrase query matches the token anywhere in a mark; class and status filters were applied **server-side**
(`AND alive:true AND (internationalClass:009 OR :028 OR :041)`), so the US counts below are exhaustive
within those classes rather than a first-page sample. Human-readable equivalent for any serial:
`https://tsdr.uspto.gov/#caseNumber=<serial>&caseSearchType=US_APPLICATION&caseType=DEFAULT&searchType=statusSearch`.

| Query | Total, all classes | **LIVE records in IC 009 / 028 / 041** |
|---|---|---|
| `wordmark:"jinx"` | 107 | ❌ **10** |
| `wordmark:"unison"` | 278 | ❌ **21** |
| `wordmark:"chime"` | 223 | ❌ **46** |
| `wordmark:"kindred"` | 416 | ❌ **39** |
| `wordmark:"same page"` | 22 | ⚠️ 3 (all composites, none the bare mark) |
| `wordmark:"samepage"` | 20 | ⚠️ 2 (both Kerio, IC 009/042) |
| `wordmark:"deep meld"` / `"deepmeld"` / `*DEEPMELD*` | **0 / 0 / 0** | **0** |

**Controls, same endpoint, same session:** `wordmark:"thereabouts"` → **6** (matching round three exactly);
`wordmark:"mind meld" AND internationalClass:028 AND alive:true` → **1** (the known-positive, §2c). The
endpoint was live and the filters well-formed.

**The US rows that decide the round:**

> ❌ **JINX** — serial **76178238**, reg. **2504251**, **IC 028**, **REGISTERED AND RENEWED**, Game
> Development Group, Inc. (Canada), filed 2000-12-11. Recites: *"Equipment sold as a unit for playing games,
> namely parlour and board games."* This is the bare word, in the games class, on board games, alive for
> twenty-four years.

> ❌ **JINX** — reg. **5516775**, IC 009 + 041, **Riot Games, Inc.** — *"Downloadable video game software;
> multiplayer interactive computer game programs"* — and reg. **8118475**, **IC 028**, Riot Games —
> *"Stuffed toy animals; card games…"*
>
> ❌ **DON'T JINX IT** — reg. **8308183**, **IC 028**, **REGISTERED**, Hunch Labs, LLC (Massachusetts),
> filed 2025-06-13. Recites, in full: **"Party games."**

> ❌ **UNISON LEAGUE** — reg. **4999603**, **IC 041**, Ateam Inc. (Japan) — *"Entertainment services, namely,
> providing an on-line computer game"* — and reg. **4989958**, IC 009, *"Computer game software."*
> Bare **UNISON**: reg. **6185373**, IC 009, Unison Computing, PBC (the programming language), and
> reg. **6391904**, IC 009/035/041/042, OM Partners.

> ❌ **CHIME** — regs. **7108797**, **7108798** and **7591053**, all **IC 009 / 035 / 036 / 041 / 042**,
> **Chime Financial, Inc.** Plus a dozen `CHIME <X>` marks by the same owner and **AMAZON CHIME**
> (reg. 7062232, IC 009/035/038/041/042).

> ❌ **KINDRED** — reg. **6021834**, **IC 009 / 028 / 035 / 036 / 038 / 041**, **KINDRED IP LIMITED**
> (Malta) — the bare word, live, in all three gate classes at once.
> ❌ **KINDRED SPIRIT** — reg. **7859386**, **IC 028**, registered 2024, recites *"Card games; Educational
> card games; Party games; Playing cards and card games; Promotional game cards."*

**Same Page / SamePage at USPTO are milder but not clean.** The three live 9/28/41 records for `same page`
are composites — `SAME PAGE ENTERTAINMENT` (IC 009/025/041, pending), `SAME PAGE MEETING` (reg. 6987112,
IC 035/041), `WE ARE ALL ON THE SAME PAGE` (reg. 3917015, IC 009). The two live `samepage` records are
**SAMEPAGE**, regs. **4923866** and **4690564**, IC 009/042, Kerio Technologies. No bare `SAME PAGE` mark
in 28 or 41 at the USPTO.

Index caveat, unchanged: results reflect USPTO's load dates, so filings in the last one to two weeks may not
appear.

### 2b. Worldwide — TMview, with WIPO GBD as a second opinion

TMview, `basicSearch` with `fNiceClass` `["9","28","41"]`, 2026-09-05. GBD figures from the live app
(brick `{key:"brandName", strategy:"Simple"}`).

| Candidate | TMview, all classes | TMview, in 9/28/41 | GBD, all classes |
|---|---|---|---|
| **jinx** | **1,919** | ❌ **389** | 276 |
| **unison** | **1,989** | ❌ **628** | 1,308 |
| **chime** | **8,196** | ❌ **2,095** | 720 |
| **kindred** | **874** | ❌ **232** | 762 |
| **same page** | 84 | ❌ **43** | 8,237 *(OR-tokenised — unusable)* |
| **samepage** | 40 | ❌ live rows in 9 **and** 41 | 38 |
| **deep meld** | **2** — both `MELDEEP` (India), a substring artefact | 1 (same artefact) | 15,688 *(OR-tokenised — unusable)* |
| **deepmeld** | **0** | **0** | **"No results found!"** |

The worldwide rows that matter:

- ❌ **JINX**, **EM 003314796** and **GB UK00903314796**, London Operations, LLC, **Registered**, classes
  **3, 9, 16, 25, 28, 41** — the bare word covering all three gate classes in the EU and UK. Also
  **JINX** GB UK00801491030 (Jinx, Inc., cls 5/14/18/20/**28**/31/**41**/44), **JINX** GB UK00004070831
  (Ball Technology Ltd, **cls 28**), **JINX** GB UK00004104848 (**FremantleMedia Limited**, **cls 41**),
  **JINX** HR Z20101994A (cls 16/18/25/**28**/**41**), and **Riot Games** holding JINX in **CN cls 9, 28 and
  41** separately (24169817 / 24169811 / 24169807).
- ❌ **Kindred**, **WO 1465966** (International Registration), **GB UK00915490162**, **CA 1953596-00** and
  **GB UK00917966689** — **KINDRED IP LIMITED**, all Registered, all covering **9, 28 and 41** in one
  filing. Plus `Kindred` BR 918900093 (**cls 28**) and BR 918900247 (**cls 41**), same owner. Kindred IP is
  the gambling operator [Kindred Group](https://en.wikipedia.org/wiki/Kindred_Group) (Unibet; acquired by
  FDJ in 2024) — a company whose entire business is Nice class 41.
- ❌ **CHIME** in **class 41**, live, held by **Amazon Technologies, Inc.** in Benelux (BX 1395662), France
  (4551639), Italy (2019000031111), Philippines, Chile, Russia, Switzerland, Norway, Uruguay, Jordan and
  Mexico (2092347) — the same 9/11/35/38/41/42/45 block filed office by office. Plus **Chime Financial**
  GB UK00003716833 (cls 9/35/36/**41**/42) and MX 2641520 (**cls 41**).
- ❌ **UNISON** GB UK00003700598 (OM Partners, cls 9/35/**41**/42, Filed), **UNISON** RO M 2005 02230
  (**cls 41**, Registered), **UNISON** GB UK00002486964 (cls 36/38/**41**, Registered — *Tony Peter Wright
  as trustee for Unison*, i.e. the UK trade union), and ~15 live class-9 registrations across US, EU, CN,
  BR, MX, MY, AU, PL.
- ❌ **SAMEPAGE** **EM 010655728** and **GB UK00910655728**, **Samepage Labs, Inc**, Registered, classes
  **9, 35, 41, 45**; **SAMEPAGE** **NZ 1074360**, SAMEPAGE NEW ZEALAND LIMITED, classes 35 + **41**.
  For the spaced form, ❌ **SAME PAGE** **GB UK00004318134**, SAME PAGE FOR LIFE LIMITED, **cls 9 + 42**,
  Registered (and AU 2628113, same owner, Filed).

**Deep Meld is the only candidate with a clean register, and it is clean everywhere**: zero at USPTO in any
class, zero at TMview worldwide, "No results found!" at GBD. Nothing in the series except *Nighabouts* has
done that.

### 2c. Deep Meld versus MIND MELD, Reg. 7540401 — a non-lawyer's read

The register record, retrieved in full from the USPTO API on 2026-09-05:

> **MIND MELD** — serial **97723272**, reg. **7540401**, **IC 028**, **LIVE — REGISTERED**, standard
> character claim, **Golden Bear Products Limited** (private limited company, United Kingdom), filed
> 2022-12-19, registered **2024-10-22**. The recitation runs to a full paragraph of toys and games and
> includes, verbatim: *"party games involving word challenges, toy animals or plush dolls; memory games
> involving word challenges…; board games featuring word challenges…; tabletop games featuring word
> challenges…"*

This is the registration that retired *Mind Meld* in the first note. The question this round has to answer
is whether it would also be cited against **DEEP MELD** in Class 28. **This is a research opinion by a
non-lawyer and is not a clearance opinion.** Reading the record:

**Pointing toward a citation.** The goods would be *identical* — a word-challenge party game in Class 28 is
the exact recitation — and where goods are identical, a lesser degree of mark similarity suffices. The marks
share their whole second word and their structure (one-syllable modifier + MELD), so they share cadence and
visual shape. And **MELD is not crowded in this class**: live `MELD` marks in 9/28/41 number **8** at the
USPTO, of which exactly **one** is in Class 28 — the citation itself. There is no thicket of coexisting MELD
marks to argue the term is weak in practice.

**Pointing away from one.** The dominant first-position elements differ completely in sound, appearance and
meaning: *MIND* versus *DEEP*. The commercial impressions diverge — MIND MELD is a recognised Star Trek
allusion; DEEP MELD reads as "a deep blend", with none. And *meld* is a genuine term of art in this very
class: [Wiktionary](https://en.wiktionary.org/wiki/meld) gives *"Especially in games of the rummy family: a
combination of playing cards which is announced or played"*, attested from the late 19th century. Suggestive
shared elements are given less weight.

**Honest read: a real risk, not a foregone conclusion.** Same second word, identical goods, no crowd is the
pattern examiners cite; different dominant first words, different connotation, a shared term of art is the
pattern applicants win on. I would expect at least an office action and would not predict the outcome.
**Anyone acting on this needs an attorney** — true of every note in this series, most true here.

---

## 3. Criterion (ii) — the App Store

Apple's iTunes Search API, `https://itunes.apple.com/search?term=<t>&entity=software&country=<c>&limit=50`,
plus `https://itunes.apple.com/lookup?id=<id>` per record. US / GB / AU, 2026-09-05.

| Term | US | GB | AU | Exact-name app? |
|---|---|---|---|---|
| `jinx` | 36 | 28 | 42 | ⚠️ Yes ×2 — *Jinx – System-Wide Ad Blocker* (Utilities), *Jinx – Music Recommendations* (Music). **Neither is a game.** |
| `unison` | 32 | 32 | 35 | ❌❌ **Yes — and it is this game.** See §3a |
| `chime` | 47 | 36 | 41 | ⚠️ Yes — *Chime* (Utilities), *Chime : Speaking Clock*, *CHIME – AI Recorder*. None is a game. |
| `kindred` | 40 | 40 | 43 | ❌ **Yes ×11, including *Kindred: Couples Card Game***. See §3b |
| `same page` / `samepage` | 21 / 13 | 46 / 12 | 18 / 11 | ⚠️ Yes ×5 — *Same Page* (Productivity), *Samepage: Team Collaboration*, *SamePage – Read Together*, *SamePage – Live Well*, *Samepage: Social book reviews*. None is a game. |
| `deep meld` / `deepmeld` | 6 / 8 | 2 / 6 | 3 / 7 | ✅ **No** |

**Control:** `thereish` returns **0** in all three storefronts (as in round three) while `portal` returns 48
in the same session. `deep meld` returning 6 with no exact match is a real negative, not a broken query.

### 3a. Unison — the finding that ends this candidate

[**Unison**](https://apps.apple.com/us/app/unison/id6793972519), trackId `6793972519`, bundle
**`app.unison.mobile`**, seller **AYBERK YATAGAN**, **released 2026-08-03**, version 1.0.1, free, 9+,
**primary genre Games; genres Games / Puzzle / Word.** Its own description is in Turkish; verbatim, with
translation:

> *"Unison — iki zihin, bir kelime."* — **"Unison — two minds, one word."**
>
> *"Canlı 1v1 çağrışım oyunu: sen ve rakibin aynı anda bir kelime yazarsınız. Ortak bir kelimeye
> ulaştığınızda buluşma sağlanır."* — **"A live 1v1 association game: you and your opponent write a word at
> the same time. When you arrive at a word in common, the meeting is achieved."**
>
> *"Arkadaşla Oyna: kod paylaş veya davet et"* — **"Play with a friend: share a code or invite."**
>
> *"Her turda bir kelime yaz; frekans tutarsa buluşursunuz"* — **"Write a word each round; if the frequency
> holds, you meet."**
>
> *"İki zihin. Bir kelime."* — **"Two minds. One word."**

**This is this project's game.** Two players, simultaneous word entry, convergence as the win condition,
rounds that carry forward, a shared code to play with a friend — under this project's candidate name, in
the Games ▸ Word category, shipped **one month before this note**. It is a worse collision than *Approx* was
in round three: *Approx* was a two-player closest-guess quiz; this is the convergence mechanic itself.

A second exact-name game sits beside it: [**Unison – Signal Sync**](https://apps.apple.com/us/app/unison-signal-sync/id6761359352),
bundle `com.fabulist.unison`, Aurel Rexhaj, released 2026-04-19, **Games / Puzzle / Casual** — *"Route wires
across a grid… every signal must arrive in the same number of steps"*, i.e. also a convergence pun. Its
Android sibling **`com.fabulist.unison`, *Unison: Signal Sync Puzzle*, is live on Google Play**.

### 3b. Kindred — a couples card game of that exact name, released the same day

[**Kindred: Couples Card Game**](https://apps.apple.com/us/app/kindred-couples-card-game/id6791998654),
trackId `6791998654`, bundle `com.bullcreekbiz.kindred`, seller CALEB JAMES RAYMOND KRANTZ, **released
2026-08-03**, free, 17+, Entertainment / Lifestyle. Verbatim:

> "Kindred is the couples card game that turns an ordinary evening into something you'll both remember…
> **Pass-and-play — one phone, two people, zero friction**… Works anywhere — dinner table, road trip, or
> under the covers."

It is filed under Entertainment rather than Games, but it *is* a game, it *is* for couples, it *is* a
one-phone couch game, and it carries the name exactly. The other ten exact-name `Kindred` apps are lifestyle
and family products (*Kindred: Couples Check-In*, *Kindred: Couple Love*, *Kindred: Marriage Connection*,
*Kindred: Parent Support*, *Kindred: Stay Connected*, *Kindred: Family Cookbook*, *Kindred: Your Personal
AI*, *Kindred: Live Your Fanfiction*, *Kindred-Mindful Parenting*, and **Kindred**, Kindred, Inc., 2013) —
which is its own problem: the *couples* corner of the App Store is already saturated with Kindreds.

---

## 4. Criterion (ii) — Google Play and Steam

### 4a. Google Play

Fetched as real HTML from `https://play.google.com/store/search?q=<t>&c=apps&hl=en&gl=US`, then the listing
pages for the hits.

| Term | Notable packages | Exact-name app? |
|---|---|---|
| `jinx` | `com.Jinx.jp`, `com.jinxbee.jinxbee`, `com.bondit.jinx.app`, `com.riotgames.league.wildrift` | ❌ **Yes — *Jinx Parkour* (Board/Casual/Puzzle/Word tokens), *Jinx Bee* (Board/Card/Word), *JINX – Pick Someone*** |
| `unison` | `com.fabulist.unison` | ❌ **Yes — *Unison: Signal Sync Puzzle*** |
| `chime` | `com.onedebit.chime`, `com.amazon.chime`, `com.chimeable.app` | ⚠️ Yes — the neobank and Amazon's conferencing app; neither is a game |
| `kindred` | `com.mykindred.app`, `com.oaknovasystems.kindred`, `com.kindredsoul.kindredapp`, `com.livekindred.app`, `com.futurenostalgiastudios.kindred` | ⚠️ Yes ×5 — *Kindred: Women's Health Clinic*, *Kindred: Mental Health & Mood*, *Kindred Shop 'n Save*, … None is a game |
| `same page` / `samepage` | `app.same_page`, `app.fig.samepage`, `com.kerio.samepage` | ⚠️ Yes — ***Same Page*** (Productivity) |
| `deep meld` / `deepmeld` | none matching | ✅ **No** |

**Control:** `portal` returns thirty-plus packages in the same session, and every candidate term returns a
dozen or more, so `deep meld` returning **no matching package** is a real zero.

### 4b. Steam

`https://store.steampowered.com/api/storesearch/?term=<t>&l=english&cc=US`:

| Term | Total | Exact title? |
|---|---|---|
| `chime` | 10 | ❌ **Yes — [*Chime*](https://store.steampowered.com/app/62100/), appid 62100, Zoë Mode / OneBigGame, released 2010-09-06, Casual.** Plus *Chime Sharp*, *Chime Candy*, *Chime of Y*, *Chill Chime Desktop* |
| `kindred` | 10 | ❌ **Yes — *Kindred [Subject 6244]* (appid 3148490, Captain Edge Studios, 2024), *Kindred [High Tide]*, *Kindred [SnowBound]*, plus *Kindred Fates*, *Kindred Kind*, *Kindred Hunger*, *Kindred Ills*, *Kindred Spirits on the Roof*** |
| `jinx` | 8 | ⚠️ No bare *Jinx* — but *Jinx It*, *Jungle Jinx*, *The Chosen Jinx*, *Clockwise Jinx*, *TriJinx*, *Jinxed* |
| `unison` | 2 | ✅ No — *DEATH IN UNISON*, *Hero's Unison* |
| `same page` / `samepage` | **0 / 0** | ✅ — |
| `deep meld` / `deepmeld` | **0 / 0** | ✅ — |
| `meld` | 5 | *Meld* (appid 449180) exists — relevant to §6f |

**Control:** `term=portal` returns `total: 10` with *Portal 2*, *Portal*, *Portal Knights*. All four zeros
are real.

---

## 5. Criterion (ii) — BoardGameGeek and itch.io

### 5a. BoardGameGeek — search working, item pages gated

`geeksearch.php?action=search&objecttype=boardgame&B1=Go&q=<t>` from a real browser tab. The
`xmlapi2` remains closed (HTTP 401) as in all four prior notes.

| Query | BGG result |
|---|---|
| `portal` **(control)** | 66 rows — *Portal (1997)*, *Portal: The Uncooperative Cake Acquisition Game (2015)*, … |
| **`jinx`** | ❌ **10 rows, five of them exact-title** — see below |
| **`kindred`** | ❌ **[*Kindred* (2026)](https://boardgamegeek.com/boardgame/464847/kindred)** — *"Explorers expand their knowledge becoming one with the environment"*, avg 8.75 from 3 voters; **[*Kindred Spirits* (2026)](https://boardgamegeek.com/boardgame/442582/kindred-spirits)** — *"Capture powerful energies using Kindred Spirits in this beautiful card game"*, avg 6.60 from 4; ***Kindred Haven* (2027)**; two *Vampire: The Eternal Struggle* expansions |
| `chime` | ✅ **No exact *Chime*** — all 26 rows are *Chimera*/*Chimère* matches, plus *Ting-A-Ling Chimes (1928)* |
| `unison` | ✅ **No Items Found** |
| `same page` / `samepage` | ✅ **No Items Found** / **No Items Found** |
| `deep meld` / `deepmeld` | ✅ **No Items Found** / **No Items Found** |
| `thereish` **(benchmark)** | ✅ **No Items Found** — round three's result re-confirmed |

**Jinx on BGG, in full:** *Jinx (2000)* (avg 4.42, 26 voters); *Jinx (1957)*; **JINX** — *"Play all your
cards while simultaneously counting from 1 to 10"*; *Jinx (aka Jinks) (2021)* (BGG rank 23291, avg 5.95,
54 voters); *Jinx 11 (1955)*; *JinxO (2024)* (rank 4189, avg 7.31, **639 voters** — *"Jinx your friend to
become victorious"*); *Jinxx (2024)* (rank 22080); *Dixit Jinx (2012)* (rank 10755, **1,231 voters**);
*'Eye Jinxx (1990)*; *Eat/Paint: Out of jinX (2024)*. Beyond BGG, a retail
[**JINX** board game](https://www.amazon.com/JINX-Family-Edition-Board-Game/dp/B0142QPVXI) sells on Amazon,
and Looney Labs publishes [**Jinxx**](https://store.looneylabs.com/products/jinxx).

**Could not verify:** designer, publisher, player count and full descriptions for the *Kindred (2026)* and
*Jinx* items. Every `boardgamegeek.com/boardgame/<id>/…` page sits behind a Cloudflare
"Performing security verification" interstitial that did not clear in a browser tab within 8 seconds. The
rows above are BGG's own search-result summaries, retrieved from BGG.

### 5b. itch.io — could not verify, fifth consecutive note

`https://itch.io/search?q=<t>` returns **HTTP 403** to curl for all six candidates, and every creator
subdomain probe (`jinx.itch.io`, `unison.itch.io`, `chime.itch.io`, `kindred.itch.io`, `samepage.itch.io`,
`deepmeld.itch.io`) returns **403**. From a real Chrome tab the page renders
*"Just a moment… itch.io — Performing security verification"* and **did not clear after 30 seconds**.

**itch.io is unverified for all six candidates.** This is the fifth note in a row to fail here. It still
needs a human with a mouse.

---

## 6. Criterion (iii) — searchability

The task for this round was to say concretely **who owns the `<name> game` query today**, and whether a
small couch game could be found under it. Separating "live mark in 9/28/41" from "famous elsewhere" matters,
because the two failures are different: a mark is a legal obstacle, fame is a discovery obstacle. Four of
these six names have both.

### 6a. Jinx — owned twice over, by Riot Games and by the playground

`"jinx game"` returns, in order: [*Jinx* on BGG](https://boardgamegeek.com/boardgame/6820/jinx),
[*Jinxx* from Looney Labs](https://store.looneylabs.com/products/jinxx),
[**Jinx (children's game)** on Wikipedia](https://en.wikipedia.org/wiki/Jinx_(children's_game)),
[*Jinx (game)*](https://en.wikipedia.org/wiki/Jinx_(game)), *The Jinx Game* from Download Youth Ministry,
[*Jinx (League of Legends)*](https://en.wikipedia.org/wiki/Jinx_(League_of_Legends)), and the Amazon board
game. **Every result is a game called Jinx, and none is ours.** Above them sits
[Riot's Jinx](https://www.riotgames.com/en/news/fortnite-gets-jinxed-to-celebrate-arcane) — a League champion
since 2013, a lead in *Arcane*, a Fortnite crossover, and a Riot trademark in classes 9, 28 and 41 (§2).
**The most thoroughly occupied query in five notes.**

The irony is exact: Wiktionary's [`jinx`](https://en.wiktionary.org/wiki/jinx) carries the sense *"Used after
the same thing is said by two people simultaneously"*, noting that *"often, a game is played where the person
who failed to say 'jinx' first becomes 'jinxed'…"*. **Jinx is already the generic name for this game** —
which is exactly why ADR-0008 retired *Meld*.

### 6b. Unison — a trade union, a programming language, and a home-equity fund

`"unison game"` returns no *Unison* game: Scrabble word-finders, *Unison: Rebels of Rhythm & Dance* (PS2,
2000), *Yggdra Unison*. The bare word belongs to
[**UNISON**, the UK's largest trade union](https://en.wikipedia.org/wiki/Unison_(trade_union)) —
**1,403,792 members in 2023/24**, which for a British or Australian ear is the *only* meaning — plus the
[Unison programming language](https://www.unison-lang.org/), the Unison file synchroniser, and
[unison.com](https://www.unison.com/), home-equity funding. Beneath all that sits the App Store's *Unison*
word game (§3a), which now owns the game-shaped half of the query.

### 6c. Chime — the query belongs to a bank with 20 million customers

`"chime game"` returns [*Chime* the 2010 puzzle game](https://en.wikipedia.org/wiki/Chime_(video_game)) and —
tellingly — [**Chime's own board game**](https://www.chime.com/newsroom/news/chime-unveils-dollars-sense-turning-awkward-money-talks-into-family-game-nights/):
*Dollars & Sense*, a 150-prompt conversation game the neobank made with Cut.com and stocked in Walgreens.
The fintech already publishes party games under this brand.
[Chime](https://time.com/collection/time100-most-influential-companies/2026/chime/) has **over 20 million US
customers**, **$2.1bn** 2025 revenue, an **$11.6bn** IPO, and a TIME100 listing for 2026. In the US App
Store, "chime" is a bank.

### 6d. Kindred — a gambling group, and now two board games

`"kindred game"` returns [*Kindred* (2026)](https://boardgamegeek.com/boardgame/464847/kindred) and
[*Kindred Spirits*](https://boardgamegeek.com/boardgame/442582/kindred-spirits) on BGG, the *Lightseekers*
Kindred set, and Kickstarter card games. The bare word belongs to
[Kindred Group](https://en.wikipedia.org/wiki/Kindred_Group) — Unibet's parent, bought by FDJ for €2.6bn,
and owner of the registrations covering classes 9, 28 and 41 (§2b). "Kindred" plus anything gaming-adjacent
lands in online gambling.

### 6e. Same Page — the idiom, and a live word game that got there first

This is the round's second fatal store finding, and it came in through the search axis.
`"on the same page" party game` surfaces **[blankslate.gg](https://blankslate.gg/)**, which **308-redirects
to [playsamepage.games](https://www.playsamepage.games/)**. The page is a live, branded, playable web game.
Verbatim from its own markup, fetched 2026-09-05:

> `<title>` **"Same Page — The word game where thinking alike is everything"**
> `og:title` — **"Same Page — Think Alike!"**
> `og:description` — **"The word-association party game where thinking alike is everything. Match your
> friends' answers to score points and read minds!"**
> `description` — **"The word game where thinking alike is everything! Create a room, match your friends'
> answers, and climb the scoreboard on Same Page."**
> `og:site_name` — **"Same Page"**

On the page: a **SAME PAGE** wordmark, the tagline *"thinking alike is everything."*, a name-and-colour
picker, **Play as guest** / **Continue with Google**, *"Prototype — your profile lives on this device."*, and
a **"FROM OUR STUDIO"** card. Its domain `playsamepage.games` was **registered 2026-07-07** at NameCheap,
last changed 2026-08-13 (RDAP) — two months old and actively worked on.

**A word-association party game, called Same Page, that you join by creating a room.** This project creates
Rooms by Code. The overlap is not thematic; it is the product. Set against that, the idiom was always a tax —
*"get everyone on the same page"* is worn business English, and the App Store already has five apps on it.

### 6f. Deep Meld — no incumbent, but *mind meld* owns the neighbourhood

`"deep meld" game` returns **no Deep Meld at all**: [*Meld (cards)*](https://en.wikipedia.org/wiki/Meld_(cards)),
[*Meld* on Steam](https://store.steampowered.com/app/449180/Meld/), *Deep Black*, *Deep Dungeon* — and then,
repeatedly, **mind meld**: a [*Mind Meld Game* guide](https://studydaily.blog/mind-meld-game-guide) describing
*"a captivating test of verbal synchronicity where two players attempt to shout the exact same word at the
same time after a countdown"*, a *Mind Meld Games* Facebook page, *Mind Melt* TikToks.

**A pass with a flag, and the flag is the same shape as *Thereish*'s** — round three passed Thereish while
noting *There Is No Game* would always shadow its query. Deep Meld is better off in one way (no beloved indie
game in the way, just a generic mechanic description) and worse in another: the shadowing phrase is **this
project's own retired name**, and the strongest "meld + word game" document on the internet describes
**exactly this game**.

---

## 7. Criterion (v) — spellable on hearing

Wiktionary rows fetched from the MediaWiki API (`action=parse&prop=wikitext`), 2026-09-05.

| Candidate | Spellable on hearing? | Word status |
|---|---|---|
| **Jinx** | ✅ **Yes.** One syllable, one spelling. The only trap is *jinks* (as in "high jinks") — and BGG's own *Jinx (aka Jinks) (2021)* shows the confusion is real in this exact category. | ✅ [Wiktionary `jinx`](https://en.wiktionary.org/wiki/jinx): noun *"a hex; an evil spell"*, verb *"to bring bad luck to"*, and the interjection sense **"Used after the same thing is said by two people simultaneously"**. From *jynx*. |
| **Unison** | ✅ **Yes.** `/ˈjuːnɪsən/`, phonetically regular, universally known. | ✅ [Wiktionary `unison`](https://en.wiktionary.org/wiki/unison): from Middle English *unisoun* ← Medieval Latin *ūnisonus* "having the same sound"; *"the state of being in harmony or agreement… synchronisation"* **from the 17th c.**; *"two or more voices speaking or singing the same words together."* |
| **Chime** | ✅ **Yes.** One syllable, regular. | ✅ [Wiktionary `chime`](https://en.wiktionary.org/wiki/chime): from Middle English *chymbe*; includes the verb senses *"to cause to sound in harmony"* and, crucially, *"to agree; to correspond."* |
| **Kindred** | ✅ **Yes.** Two syllables, one spelling. | ✅ [Wiktionary `kindred`](https://en.wiktionary.org/wiki/kindred): from Middle English *kyndrede* ← Old English *cynrǣden*; *"affinity, likeness"*, *"of the same nature, or of similar character."* |
| **Same Page** | ❌ **No — and this is the one criterion it fails on its own terms.** Heard aloud, "same page" gives no way to know whether the title is `Same Page`, `SamePage`, or `same-page`. All three forms exist as live products *right now* (§3, §4a), so the guess is not merely uncertain, it is actively mis-routing. Round three killed the hyphen/space forms of *Wellnigh* for the same reason. | ❌ No Wiktionary entry for `same page` — it is a phrase, not a word. The idiom is real; the token is not. |
| **Deep Meld** | ⚠️ **Mostly.** Both words are spelled as heard. The residual risks are *meld/melt* (already visible in the wild as "Mind Melt") and the same two-word/one-word question — though unlike *Same Page*, nothing competes for the closed form: `deepmeld` is empty in every register, store and TLD. | ✅ [Wiktionary `meld`](https://en.wiktionary.org/wiki/meld): *"to combine multiple things together; to blend, to fuse"* from early 20th c., and the card-game sense **from the late 19th c.** |

---

## 8. Criterion (iv) — domains

Registry RDAP where the registry runs one — [Verisign](https://rdap.verisign.com/com/v1/domain/) for `.com`,
[Google Registry](https://pubapi.registry.google/rdap/domain/) for `.app`,
[CentralNic](https://rdap.centralnic.com/game/domain/) for `.game` — and registry WHOIS otherwise
(`whois.nic.io`, `whois.gg`, `whois.nic.fun`, `whois.nic.game`). **No reseller "available!" badges were
used.** Every free `.com` was re-checked against `whois.verisign-grs.com`. All 2026-09-05.

**Registry controls, same session:** `google.com` → RDAP 200 + `Domain Name: GOOGLE.COM`;
`nintendo.game` → RDAP 200 + `Creation Date: 2016-05-02`; `google.app` → 200; `github.io` →
`Domain Name: github.io`; `thereabouts.gg` → full record; `nic.fun` → `Domain Name: nic.fun`. Every FREE
below is a real free.

Round three's TLD set (`.com`, `.game`, `.app`, `.io`, `.gg`, `.fun`, `<n>game.com`, `play<n>.com`) plus the
two hyphenated forms this round adds, because the exact `.com` for a common word was never going to be free:

| | `.com` | `.game` | `.app` | `.io` | `.gg` | `.fun` | `<n>game.com` | `play<n>.com` | `<n>-game.com` | `play-<n>.com` | **Free** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **Deep Meld** | ❌ for sale | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **9 of 10** |
| **SamePage** | ❌ live | ✅ | ❌ 2018 | ❌ 2012 | ✅ | ❌ 2026 | ❌ 2018 | ❌ 2021 | ✅ | ✅ | **5 of 10** |
| **Chime** | ❌ live | ✅ | ❌ 2018 | ❌ 2014 | ❌ 2020 | ✅ | ❌ 2009 | ❌ 2026 | ✅ | ✅ | **4 of 10** |
| **Jinx** | ❌ live | ✅ | ❌ 2021 | ❌ 2016 | ❌ 2025 | ❌ 2022 | ❌ 2026 | ❌ 2026 | ✅ | ✅ | **3 of 10** |
| **Unison** | ❌ live | ✅ | ❌ 2019 | ❌ 2014 | ❌ 2022 | ❌ | ❌ 2026 | ❌ 2026 | ✅ | ✅ | **3 of 10** |
| **Kindred** | ❌ live | ✅ | ❌ 2018 | ❌ 2013 | ❌ 2022 | ❌ 2023 | ❌ 2014 | ❌ 2018 | ✅ | ✅ | **3 of 10** |
| *Thereish (benchmark, round three)* | ❌ taken, dark | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | — | — | *7 of 8* |

**The exact `.com` is gone for all six**, as expected for common words — but three patterns underneath are
the useful finding. **Every `<name>-game.com` and `play-<name>.com` is free, for every candidate**: the
hyphen is the only reliably open form in this field, a workable fallback but a meaningfully worse asset than
*Thereish*'s clean `thereish.app`. **`<name>.game` is free for all six**, the only unhyphenated TLD that is.
And **`jinxgame.com`, `playjinx.com`, `unisongame.com`, `playunison.com` and `playchime.com` were all
registered during 2026** — somebody else is already buying these.

What the taken `.com`s actually serve:

- **jinx.com** — GoDaddy, created **1997-12-29**, HTTP 200, `<title>` **"J!NX"** — the long-running gamer
  apparel brand. A live business, in games, on the exact `.com`.
- **unison.com** — Cloudflare, created 2001-07-29, HTTP 200, *"Unison | Home Equity Funding"*.
- **chime.com** — CSC Corporate Domains, created 1997-07-17, `<title>` "Chime" (403 to curl) — Chime Financial.
- **kindred.com** — GoDaddy, created 1996-11-02, redirects to **kindredhospitals.com**.
- **samepage.com** — NameCheap, created 2005-03-03, HTTP 200, a **medical-history journal product**;
  separately **same-page.com** (Network Solutions, 1999) serves a live *"Online Collaboration Software"* site.
- **deepmeld.com** — GoDaddy, created **2017-04-07**, expires 2027-04-07, and every request 301s to
  **`forsale.godaddy.com/forsale/deepmeld.com`**. **Investor inventory, not a business** — the same
  situation as *Wellnigh* ($3,695) and *Fairish* ($7,595) in round three. **Could not verify:** the asking
  price; the GoDaddy for-sale page returns 403 to scripted requests.

**Lookup caveats:** `.gg` still has no RDAP service, so it is registry WHOIS only. `unison.fun` returns
*"This name is not available for registration"* without a creation date. Nothing was rate-limited and no
lookup was retried into a different answer.

---

## 9. Ranking

**Inference from §§1–8. This is the recommendation, not a finding. The pick is the players' call.**

### 9a. PASS / FAIL per criterion

| Candidate | (i) Register | (ii) Store | (iii) Query | (iv) Domain | (v) Spelling |
|---|---|---|---|---|---|
| **Deep Meld** | ✅ **PASS** | ✅ **PASS** | ✅ **PASS** *(flagged)* | ✅ **PASS** | ✅ **PASS** |
| **Jinx** | ❌ FAIL | ❌ FAIL | ❌ FAIL | ❌ FAIL | ✅ PASS |
| **Unison** | ❌ FAIL | ❌ FAIL | ❌ FAIL | ❌ FAIL | ✅ PASS |
| **Chime** | ❌ FAIL | ❌ FAIL | ❌ FAIL | ❌ FAIL | ✅ PASS |
| **Kindred** | ❌ FAIL | ❌ FAIL | ❌ FAIL | ❌ FAIL | ✅ PASS |
| **Same Page** | ❌ FAIL | ❌ FAIL | ❌ FAIL | ⚠️ 5 of 10 | ❌ FAIL |
| **SamePage** | ❌ FAIL | ❌ FAIL | ❌ FAIL | ⚠️ 5 of 10 | ❌ FAIL |

One sentence each, benchmarked against **Thereish** — which in round three was register-empty everywhere,
absent from every store, held an unclaimed (if shadowed) query, and had 7 of 8 domain forms free including
`.app`:

- **Jinx — FAIL (i, ii, iii, iv).** A live US Class 28 registration on *"parlour and board games"*
  (reg. 2504251), a live EU/UK mark covering 9 + 28 + 41, Riot Games in three classes, five exact-title BGG
  games and a retail box on Amazon make it the mechanic's *generic* term rather than a name anyone can take —
  the lesson this project already learned with *Meld*, and zero of which Thereish carried.
- **Same Page — FAIL (i, ii, iii, v).** [playsamepage.games](https://www.playsamepage.games/) is a live
  word-association party game called SAME PAGE, tagline *"thinking alike is everything"*, joined by creating
  a room — this project's product under this project's candidate name, where Thereish's query was merely
  shadowed and never occupied.
- **SamePage — FAIL (i, ii, iii, v).** Closing the space escapes neither that game nor **Samepage Labs' live
  EUTM/UK registrations in classes 9 and 41**, repeating round two's *Nearenough* lesson that deleting a
  space deletes nothing.
- **Unison — FAIL (all four).** The worst store finding in five notes — an
  [App Store word game called *Unison*](https://apps.apple.com/us/app/unison/id6793972519) released
  2026-08-03 and described by its own developer as *"two minds, one word… a live 1v1 association game"* —
  on top of UNISON LEAGUE's live Class 41 registration for an online game and 1.4 million UK trade unionists,
  against Thereish's empty storefront everywhere.
- **Chime — FAIL (i, ii, iii).** An exact-title Steam game since 2010 (appid 62100, Zoë Mode), Chime
  Financial's live Class 41 US registrations, Amazon holding CHIME in Class 41 across ten offices, and a
  20-million-customer neobank already publishing its own party game leave 4 of 10 domains against Thereish's
  7 of 8.
- **Kindred — FAIL (all four).** Kindred IP Limited holds the bare word in Nice 9, 28 *and* 41 in a single
  EUTM, an International Registration, Canada and the UK — the cleanest single blocker in the series —
  alongside [*Kindred* (2026) on BGG](https://boardgamegeek.com/boardgame/464847/kindred), seven Steam titles
  and an iOS *Kindred: Couples Card Game*.
- **Deep Meld — PASSES all five**, the only candidate here to do so: zero records at USPTO, TMview and WIPO
  GBD in any class, nothing in any store, no incumbent on the query, 9 of 10 domain forms free and both words
  spelled as heard — beating Thereish on every external axis, and then failing on this project's own rules
  (§9b).

### 9b. Deep Meld clears the gate and collides with the game

Two things sit outside the five-criterion gate and both point the same way.

**1. It is a rung of its own ladder.** `docs/design-brief.md` line 98 lists the five ladder bands as
**miss / adjacent / near / meld / deep meld**. ***Deep Meld* is the name of the top band — the best possible
outcome of an Attempt.** ADR-0008 already legislated against exactly this: it renamed the Band formerly
called *near* to **close** *"so the title cannot collide with a rung of its own ladder."* Naming the game
*Deep Meld* would reintroduce that collision at the highest rung, in an append-only, player-visible
Chronicle, forever — "you got a deep meld in Deep Meld." Round three's *Give or Take* died on a milder
version of this rule.

**2. It is the second word of the name the project retired.** ADR-0008's Considered Options already lists
*Deep Meld* as **"Dropped for naming the win"** — and *naming the win* is precisely what Melissa asked for on
2026-09-04, so that objection is genuinely reopened. But the *Mind Meld* problem is not reopened. §2c's
non-lawyer read is that **MIND MELD reg. 7540401 is a live, identical-goods, uncrowded citation risk in
Class 28**, and the ADR's Consequences already say **"Meld stays in the glossary… Being the generic name for
this kind of game is what makes it a good word for players and a bad name for a product."** Deep Meld
inherits a diluted form of the exact problem that killed the project's first name.

**The honest verdict: Deep Meld is the only clearable name in this round, and it should probably still not
be the name.** Its virtues are real and measurable — an empty register worldwide is worth a great deal — but
it costs the ladder its top rung and points at the win in the vocabulary the project already retired.

### 9c. What round four actually establishes

**Nothing in the goal-direction field survived contact with the register**, and that is structural rather
than unlucky. Round three found that the names which failed were the ones a search engine already had a
strong opinion about. Round four finds something sharper: **goal-direction words are ordinary English words
for agreement, and ordinary English words for agreement are what companies name themselves.** *Unison*,
*Chime*, *Kindred* and *Same Page* are held by a 1.4-million-member trade union, a bank, a gambling group
bought for €2.6bn, and a whole collaboration-software category. A name meaning "we agree" is a name every
B2B company on earth wants.

The second finding is more uncomfortable. **Two live products released within a month of each other in
August 2026 — [*Unison*](https://apps.apple.com/us/app/unison/id6793972519) on iOS and
[*Same Page*](https://www.playsamepage.games/) on the web — are this project's game, under two of this
project's candidate names.** The convergence-word-game genre is being actively built right now, by other
people, reaching for these exact names. That is a fact about the market, not the names, and it belongs in
front of the players alongside the name choice.

Against that, the miss-naming slate looks *better* than it did on 2026-09-04: *Thereish*, *Wellnigh*,
*Nearabouts* and *Fairish* cleared round three's gate precisely because nobody wants a word meaning "not
quite". **The reason Melissa's preferred direction is unavailable is the same reason her preferred name was
available.**

**For the players' decision, not a decision:** none of these six should displace *Thereish* on this
evidence. If the goal-direction instinct is worth pursuing, it needs candidates that are *not* ordinary
agreement words — the way *Nighabouts* was not an ordinary near-miss word. That constraint is the most
useful thing this round produced.

---

## 10. What is still missing

Not cleared by this note, and not claimable as cleared:

1. **itch.io, all six candidates.** Cloudflare 403 to curl, to every creator subdomain, and to a real
   browser tab that never cleared in 30 seconds (§5b). **Fifth consecutive note to fail here.**
2. **BGG item pages** for *Kindred (2026)*, *Jinx (2000)*, *JinxO (2024)* and the rest — existence, year,
   rating and voter counts come from BGG's search rows; **designer, publisher, player count and description
   were not retrieved**, the item pages being Cloudflare-gated.
3. **Exhaustive worldwide paging for the four common words.** USPTO figures are exhaustive within 9/28/41
   (server-side filter); TMview and GBD figures are totals plus the **first relevance-sorted page**. With 389
   (*jinx*), 628 (*unison*), 2,095 (*chime*) and 232 (*kindred*) hits in the gate classes, further blocking
   rows certainly sit below the fold — enough to fail the criterion, not enough to enumerate the risk.
4. **National register verification** of every worldwide row — these are TMview's and GBD's copies, not
   EUIPO/UKIPO/JPO/CGPDTM records, and round one showed such statuses can be stale by years.
5. **The MIND MELD / DEEP MELD similarity question (§2c)**, a non-lawyer's reading of a register record and
   the item here most in need of an attorney.
6. **The identity of the *Same Page* studio** behind blankslate.gg — its "FROM OUR STUDIO" card was not
   followed, and no company name, filing or player count was retrieved; the `.gg` WHOIS shows *Transfer
   Prohibited by Registrar* but no registrant.
7. **Common-law and unregistered rights generally** — unusually relevant here, since both decisive
   collisions (*Unison* on iOS, *Same Page* on the web) are **unregistered** users.
8. **The asking price for `deepmeld.com`** — the GoDaddy for-sale page returns 403 to scripted requests.
9. Any filing loaded after **2026-09-05**, and any register outside TMview's and GBD's sources.
10. As every note in this series has said: **§9 is a research opinion, not legal advice.**
