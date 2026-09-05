# 07: Move the deployment and buy the domains

**What to build:** The game is served from a subdomain that carries its real name, and the domain forms worth holding are held. This is the only part of the rename that costs money and cannot be undone with a `git revert`, so it is spent exactly once.

**Blocked by:** 06 (Apply the chosen name). The name is **Thereish**; the target is `thereish.stephens.page`. Round three (`docs/research/name-candidate-clearance-round3.md` §8b) lists which Thereish domain forms were free on 2026-09-04 — re-check at the registry before buying.

**Status:** ready-for-human

`bin/deploy` and `deploy/meld.stephens.page.conf` currently target **meld.stephens.page**; the vhost, the log paths and the certbot cert all carry it. That subdomain deliberately stood through the whole naming session rather than being moved to a candidate — moving it twice was the one cost worth avoiding.

**Domains.** Buy the good form for the winner, not a portfolio. `.game` is out at **$309 to register and $340/yr to renew**; its availability across every candidate was a price signal, not an opportunity. No broker approach for any `.com`: for a game distributed through an app store the `.com` does almost nothing, discovery happens in store search and in the `<name> game` query, and approaching a portfolio holder mainly teaches them someone wants it. Trademark filing stays out of scope and is an attorney's question if the game ever leaves the couch.

- [ ] DNS record for the new subdomain exists
- [ ] The Apache vhost and log paths are renamed, and the old vhost is retired
- [ ] A certbot cert covers the new subdomain
- [ ] `bin/deploy` targets it, and a deploy succeeds end to end
- [ ] The deployment is still `noindex`
- [ ] The domain form for the chosen name is registered
- [ ] ADR-0008 records what was bought, so the next reader knows what is held
