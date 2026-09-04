# Domains for "Near Enough" and "Thereabouts" — registry status and price, 2026-09-04

Researched **2026-09-04** for naming ticket `.scratch/naming/issues/01-the-games-real-name.md`, as a
follow-on to [name-mind-meld-availability.md](name-mind-meld-availability.md). That note cleared the
*trademark* half for eight candidates (§6 there); this one does the *domain* half for the two survivors,
under a new premise: an **app-store listing is now a real possibility**, so a genuinely ownable address
matters rather than a `stephens.page` path.

Method: primary sources only. Registration status comes from **registry RDAP** where the registry runs one
(Verisign for `.com`, Google Registry for `.app`, CentralNic for `.game`) and from **registry WHOIS**
otherwise (`whois.nic.io`, `whois.gg`, `whois.nic.fun`) — never from a registrar's or reseller's
"available!" badge. Every `.com` negative was re-checked a second time against
`whois.verisign-grs.com` directly. "Serves anything?" comes from `dig` plus a real `curl` fetch of the
apex. Pricing comes from **Porkbun's own JSON pricing endpoint**, cross-checked against the figure their
marketing page renders. Anything not verifiable is flagged **could not verify** inline.

**Headline: Near Enough has by far the better domain story.** Seven of its nine forms are free, including
`.game`, `.app`, `.gg`, `.io`, `.fun` and both `play-`/`-game` `.com` variants; the only taken forms are
the two `.com`s, and the exact-match `nearenough.com` has a **published buy-now price of $6,295**.
Thereabouts has two forms taken by **live, shipping products** — a browser game on `.gg` and, worse for
the app-store premise, a **pre-launch consumer mobile app on `.app`** literally named Thereabouts.

---

## 1. Near Enough

### 1a. Status

| Domain | Status | Registrar | Created | Expires | Serves anything? |
|---|---|---|---|---|---|
| **nearenough.com** | **Registered** — domain-investor inventory | DropCatch.com 627 LLC | 2023-08-10 | 2027-08-10 | **Parking / for sale** — HugeDomains listing, see §1b |
| **nearenough.game** | **AVAILABLE** | — | — | — | — |
| **nearenough.app** | **AVAILABLE** | — | — | — | — |
| **nearenough.gg** | **AVAILABLE** | — | — | — | — |
| **nearenough.io** | **AVAILABLE** | — | — | — | — |
| near-enough.com | **Registered** | GoDaddy.com, LLC | 2020-11-27 | **2026-11-27** | **Nothing usable** — see §1c |
| **playnearenough.com** | **AVAILABLE** | — | — | — | — |
| **nearenoughgame.com** | **AVAILABLE** | — | — | — | — |
| **nearenough.fun** | **AVAILABLE** | — | — | — | — |

**Seven of nine free.** Sources, each fetched 2026-09-04:

- `.com` rows: [`rdap.verisign.com/com/v1/domain/nearenough.com`](https://rdap.verisign.com/com/v1/domain/nearenough.com)
  and the same endpoint per name. The three available `.com`s return **HTTP 404**, and
  `whois -h whois.verisign-grs.com "domain playnearenough.com"` independently returns
  `No match for domain "PLAYNEARENOUGH.COM"` (likewise `NEARENOUGHGAME.COM`).
- `.game`: `https://rdap.centralnic.com/game/domain/nearenough.game` → **HTTP 404**, and
  `whois -h whois.nic.game` agrees: `The queried object does not exist: DOMAIN NOT FOUND`.
- `.app`: `https://pubapi.registry.google/rdap/domain/nearenough.app` → **HTTP 404**.
- `.io`: `whois -h whois.nic.io nearenough.io` → `Domain not found.`
- `.gg`: `whois -h whois.gg nearenough.gg` → `NOT FOUND`.
- `.fun`: `whois -h whois.nic.fun nearenough.fun` → `Domain nearenough.fun is available for registration`.

Lookup caveats, recorded rather than smoothed over: `.gg` still has **no RDAP service at all** (same as in
the Mind Meld note), so it is registry WHOIS only. `rdap.org` returns HTTP 404 "no RDAP service" for `.io`
and only a 302 bounce for `.fun`, so registry WHOIS was used for both. Nothing was rate-limited, and no
lookup was retried into a different answer.

### 1b. The aftermarket price on nearenough.com

**Publicly listed at $6,295 buy-now.** `nearenough.com` resolves to `nsg1/nsg2.namebrightdns.com` and
redirects to
[hugedomains.com/domain_profile.cfm?d=nearenough.com](https://www.hugedomains.com/domain_profile.cfm?d=nearenough.com),
whose page markup carries, verbatim:

> `<h1 class="domain-name">NearEnough.com</h1> <p class="d-t-n">This domain is for sale: <span class="green">$6,295</span></p>`

and, on the payment-plan block, "Buy now for $6,295 or pay **$262.29 per month for 24 months**". The
registrar of record (DropCatch.com 627 LLC) and the 2023-08-10 creation date are consistent with a dropped
name caught at auction and flipped into HugeDomains inventory — i.e. **it is for sale to anyone with the
money**, not held by a business using it.

For scale: $6,295 is roughly **570× one year of `.com`** at Porkbun (§3), and about **20× a year of
`.game`**.

### 1c. near-enough.com

Registered at GoDaddy since 2020-11-27, expiring 2026-11-27, carrying the full set of registrar locks
(`clientDelete/Renew/Transfer/UpdateProhibited`). It **serves nothing usable**: HTTPS fails at the TLS
handshake (`curl: (35) SSL_ERROR_SYSCALL`), and plain HTTP returns
`403 Forbidden — Request forbidden by administrative rules` from GoDaddy-fronted IPs (3.33.130.190,
15.197.148.33). That 403-from-parking-IPs shape is what GoDaddy's parked pages do to non-browser clients.

**Could not verify:** whether it carries a public asking price. No for-sale page could be reached (the 403
blocks it even with a full desktop browser User-Agent), thick WHOIS at GoDaddy timed out, and
`rdap.godaddy.com` returned nothing. Treat "is near-enough.com listed, and for how much?" as **open** —
one manual look in a real browser would settle it. It is in any case the hyphenated form, which is the
weakest of the nine.

---

## 2. Thereabouts

### 2a. Status

| Domain | Status | Registrar | Created | Expires | Serves anything? |
|---|---|---|---|---|---|
| thereabouts.com | **Registered** since **1999** | Dynadot Inc | 1999-09-29 | **2026-09-29** | **Nothing** — dark, see §2b |
| **thereabouts.game** | **AVAILABLE** | — | — | — | — |
| **thereabouts.app** | **Registered — live product** | Cloudflare, Inc. | 2026-06-16 | 2027-06-16 | **A real pre-launch app site**, see §2c |
| **thereabouts.gg** | **Registered — live game** (confirmed) | NameCheap, Inc | 2026-05-15 | "until cancelled" | **A real playable game**, see §2d |
| **thereabouts.io** | **AVAILABLE** | — | — | — | — |
| **playthereabouts.com** | **AVAILABLE** | — | — | — | — |
| **thereaboutsgame.com** | **AVAILABLE** | — | — | — | — |
| **thereabouts.fun** | **AVAILABLE** | — | — | — | — |

Same sources and same method as §1a: Verisign RDAP (404 for both `play-` and `-game` forms, corroborated by
`whois.verisign-grs.com` returning `No match`), `rdap.centralnic.com/game` 404 plus
`whois.nic.game` `DOMAIN NOT FOUND`, `pubapi.registry.google/rdap/domain/thereabouts.app` **HTTP 200**,
`whois.gg` full record, `whois.nic.io` `Domain not found.`, `whois.nic.fun` "available for registration".

### 2b. thereabouts.com — old, held, and dark

A **26-year-old** registration (created 1999-09-29), currently at Dynadot with
`clientTransferProhibited`, last changed 2025-10-28. Nameservers are Dynadot's own
(`ns1/ns2.dyna-ns.net`); the A record is `54.215.31.113`, which reverse-resolves to
`ec2-54-215-31-113.us-west-1.compute.amazonaws.com` and has **nothing listening** — HTTPS times out after
15s and HTTP returns nothing at all. So: not a site, not even a parking page. Somebody's long-held asset,
pointed at a dead EC2 box.

Two things worth noting. First, its **expiry is 2026-09-29 — 25 days from today**. That is not an
opportunity: a name held continuously since 1999 and re-registered as recently as last October is
overwhelmingly likely to renew, and even a genuine drop would go through the same catcher auctions that
produced §1b's $6,295. Second, registry RDAP for `.com` is **thin** — no registrant name is published —
and the Dynadot registrar RDAP returns a `null` entities array, so **could not verify** who owns it or
whether it is quietly for sale. No public asking price was found anywhere.

### 2c. thereabouts.app — a consumer app called Thereabouts, pre-launch, collecting a waitlist

This is the finding that matters most given the app-store premise. `https://thereabouts.app` returns
**HTTP 200** with a complete, designed marketing site behind Cloudflare. From the page itself:

> `<title>Thereabouts — Remember where you meant to go</title>`
> `<meta name="description" content="An app for remembering the spots your group meant to try.">`

It is a group place-saving mobile app — "Create a group / Add your partner or besties", "share directly
from Instagram or TikTok", screenshots of Add / Review / Saved phone screens — with a Cloudflare
Turnstile-protected **email waitlist** and an FAQ that reads: *"Is Thereabouts available now? Not yet. Join
the waitlist and we'll email you when a spot opens."*

Registered **2026-06-16**, i.e. under three months old. So this is a live, funded-enough-to-ship-a-landing-page
consumer app, named Thereabouts, **aimed at couples and small friend groups**, that has not yet reached the
app stores — which is precisely the shelf and precisely the audience this project would be listing into.

### 2d. thereabouts.gg — confirmed, and uncomfortably close in concept

Confirmed as reported. `https://thereabouts.gg` returns HTTP 200, a single-page browser game, registered at
Namecheap on **2026-05-15**, served from `45.55.229.32`. From its own markup:

> `<title>Thereabouts — Cultural Geography Guessing Game</title>`
> `<meta name="description" content="Challenge a friend to a cultural geography guessing duel. Place your pin, compare guesses, and see who got closer.">`

Note what it is, not just that it exists: a **two-player, guess-and-compare game scored on who got
closer**. The near-miss framing that makes "Thereabouts" attractive as a name for this project is the same
framing that made it attractive to them. Attribution in the page credits "Atlas by StringLabs" from Noun
Project (CC BY 3.0), so it is a small independent build — but it is playable today at the exact name, on
the TLD games use.

### 2e. App stores

Neither name is taken on the iOS App Store today. Apple's own iTunes Search API
(`https://itunes.apple.com/search?term=thereabouts&entity=software&country=us&limit=25`, and the same for
`near+enough`) returns **no app whose title contains either phrase**. This is a narrow check —
**could not verify** Google Play, which was not queried here and which the Mind Meld note (§3b there)
found to be the store that actually held collisions. Given §2c, Google Play and the iOS store should both
be re-checked for "Thereabouts" **at listing time**, not now: the app in §2c is explicitly pre-launch and
will presumably claim the name within months.

---

## 3. Porkbun pricing for the relevant TLDs

Retrieved 2026-09-04 from **Porkbun's own public pricing endpoint**,
`POST https://api.porkbun.com/api/json/v3/pricing/get` (no credentials required; the documented endpoint on
[porkbun.com/api/json/v3/documentation](https://porkbun.com/api/json/v3/documentation)). All figures USD,
per year, `"coupons": []` on every row — i.e. no promo attached to these numbers.

| TLD | Registration (1st yr) | Renewal | Transfer |
|---|---|---|---|
| **.com** | **$11.08** | **$11.08** | $11.08 |
| **.app** | **$8.75** | **$14.93** | $14.93 |
| **.fun** | **$2.57** | **$31.41** | $31.41 |
| **.io** | **$28.12** | **$51.80** | $51.80 |
| **.gg** | **$51.80** | **$51.80** | $51.80 |
| **.game** | **$309.47** | **$340.37** | $340.37 |

Cross-check on the human-readable page: [porkbun.com/products/domains](https://porkbun.com/products/domains)
renders "**.COM from $11.08**", matching the endpoint exactly.
**Method caveat:** [porkbun.com/products/domains/tld-price-list](https://porkbun.com/products/domains/tld-price-list)
is the same JS-rendered SPA bundle and exposes no per-TLD numbers to a plain fetch; the same-origin path
`porkbun.com/api/json/v3/pricing/get` returns 403 to curl. So the table above is Porkbun's own API rather
than Porkbun's own HTML, and only the `.com` figure could be confirmed against rendered page text.

**Reading the table.** The two "historically expensive" TLDs behave differently:

- **`.game` is the outlier and it is not close** — $309 to register, **$340/yr forever**. That is
  ~31× a `.com`, and roughly $1,700 over five years. The Mind Meld note repeatedly observed that "every
  `.game` is free"; this is why. It is priced as a premium registry TLD, not as a cheap alternative.
- **`.gg` is expensive but survivable** at a flat **$51.80/yr**, with no renewal cliff — you pay the same
  every year, which at least makes it predictable.
- **`.fun` has the nastiest shape**: $2.57 to register, **$31.41 to renew**. A 12× jump at year two.
- **`.app` is the quiet winner** — $8.75 first year, **$14.93** thereafter, cheaper than `.gg` by 3.5×,
  and it is an HSTS-preloaded TLD (HTTPS mandatory), which is a small correctness bonus for a web game.
- **`.io` renews at $51.80**, the same as `.gg`, with a discounted first year.

---

## 4. What this means — inference, not finding

**Near Enough wins the domain question outright, and it is not a close call.**

1. **Near Enough has a free exact-match address on every TLD that matters except `.com`.**
   `nearenough.app` is free at **$8.75/$14.93** — a legitimate, ownable, HTTPS-only exact match for
   under fifteen dollars a year, on the TLD that reads as "this is an app" to exactly the audience an
   app-store listing is aimed at. `nearenough.gg`, `nearenough.io` and `nearenough.fun` are free too,
   as are `playnearenough.com` and `nearenoughgame.com` at $11.08 if a `.com` is wanted for the marketing
   site. **Nothing anywhere is using the name.**
2. **Thereabouts is already occupied by two live products in the two places this project would go.**
   `thereabouts.gg` is a shipping two-player *guessing game scored on who got closer* — the same conceptual
   territory, playable today. `thereabouts.app` is a **pre-launch consumer app for couples and friend
   groups**, three months old, actively collecting a waitlist, and on a trajectory that ends in the app
   stores. Under the old premise (couch game on `stephens.page`) neither would matter. Under the new
   premise — a store listing — the `.app` one is a direct, imminent collision on both name and audience.
   The remaining free Thereabouts forms (`playthereabouts.com`, `thereaboutsgame.com`, `.io`, `.fun`) are
   all consolation prizes: you would be the *other* Thereabouts from day one.
3. **The exact-match `.com` is out of reach for both, and that is fine.** `nearenough.com` is
   HugeDomains inventory at **$6,295**; `thereabouts.com` has been held since 1999 by someone who points it
   at a dead EC2 instance and shows no price. Neither is a purchase this project should make, and the
   modern answer — `.app` for the product, a `play-`/`-game` `.com` for the marketing page if wanted —
   costs about **$26/yr all-in** for Near Enough.
4. **Do not buy `.game` for either name.** $340/yr in perpetuity for a TLD nobody types is the worst
   money on this page. Its universal availability across all eight candidates in the earlier note was
   never a signal of anything except price.

**Concretely, if Near Enough survives couch night:** register **`nearenough.app`** first (it is the
cheapest, the most defensible, and the one an app-store listing wants), and grab **`nearenoughgame.com`**
at $11.08 as the shareable link if a `.com` is felt to be needed. Skip `.game`, skip `.gg`, and do not
chase `nearenough.com` at $6,295 unless the game is earning money. Prices and availability were true on
**2026-09-04** and should be re-verified before spending — an available name is available only until
somebody else registers it.

**One thing this note does not settle:** it is a domain and store-title check only. The trademark half for
Near Enough is in [name-mind-meld-availability.md §6](name-mind-meld-availability.md) — zero USPTO records
in any class, in any status, the cleanest of the eight — but that pass was register-only, US-only, and did
not cover Google Play. For Thereabouts, **no trademark search has been run at all**, and given §2c and §2d
one would now be a prerequisite rather than a formality.
