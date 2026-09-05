# 07: Move the deployment to thereish.app

**What to build:** The game is served at **https://thereish.app**, its real name and its own domain, and `meld.stephens.page` sends people there. This is the only part of the rename that touches DNS, a vhost, a certificate and the deploy pipeline, so it is done exactly once and end to end.

**Blocked by:** 06 (Apply the chosen name) for the copy on the pages; the server work below can start now.

**Status:** ready-for-human

**Already done (2026-09-05).** Jacob bought **thereish.app** and pointed it at `<droplet-ip>`, the droplet that serves `stephens.page` and `meld.stephens.page`. `.app` is an HSTS-preloaded TLD: browsers will only ever load it over HTTPS, so the vhost must have its certificate before the first visit, and the `certbot --apache --redirect` shape the box already uses is exactly right. `thereish.com` is parked dark by a speculator until **2026-12-18**; a calendar note sits on that date, and there is no broker approach (see below).

**The move, in the box's own conventions** (`docs/deploy.md`, `~/infra/ansible/roles/new_subdomain` on the server):

1. Checkout at `/var/www/thereish.app` (a `git clone`, or `mv` the existing `/var/www/meld.stephens.page` and its mode-600 `.env`). `PHX_HOST=thereish.app` in that `.env`; `config/prod.exs` `force_ssl` already wants the real host.
2. Apache: a `thereish.app` vhost proxying to `127.0.0.1:3530` with `ProxyPreserveHost On` and the one line the role's template lacks — `ProxyPass / http://127.0.0.1:3530/ upgrade=websocket` — or LiveView silently long-polls (`/check` must say WebSocket). `www.thereish.app` redirects to the apex. Then `certbot --apache --redirect` for both names.
3. `meld.stephens.page`: keep its vhost and certificate, replace the proxy with a `301` to `https://thereish.app$1`, and leave it for a season so a phone's old bookmark and the Rooms in "Your Rooms" still land. Retire it later in a separate commit.
4. The pipeline: `deploy/meld.stephens.page.conf` → `deploy/thereish.app.conf`; `bin/deploy` and `bin/provision-server` target the new host and path; `/etc/site-deploy/sites.toml` `[sites.meld]` moves to the new working directory and its healthcheck becomes `https://thereish.app/check`; the GitHub Actions deploy key stays.
5. `noindex` stays until the game is meant to be found.

**Domains.** `thereish.app` is the good form and the only purchase — a portfolio was never the plan, `.game` is $309 to register, and the `.com` does almost nothing for a game found through stores and word of mouth. **No broker approach** for `thereish.com`: approaching a portfolio holder mainly teaches them someone wants it. If it drops after 2026-12-18, register it then and redirect. Trademark filing stays out of scope and is an attorney's question if the game ever leaves the couch.

- [x] The domain form for the chosen name is registered — `thereish.app`, 2026-09-05
- [x] DNS for `thereish.app` points at the droplet (`<droplet-ip>`)
- [ ] The Apache vhost for `thereish.app` (and `www.`) exists with `upgrade=websocket`, and `https://thereish.app/check` reports **WebSocket** and **Secure context: yes**
- [ ] A certbot certificate covers `thereish.app` and `www.thereish.app`
- [ ] The checkout lives at `/var/www/thereish.app` with `PHX_HOST=thereish.app`, and the container is up there
- [ ] `bin/deploy`, `bin/provision-server`, `deploy/*.conf` and `/etc/site-deploy/sites.toml` target it, and one deploy succeeds end to end from a push to `master`
- [ ] `meld.stephens.page` 301s to `thereish.app`, path preserved, and a phone's old "Your Rooms" link lands in the same Room
- [ ] `docs/deploy.md` and the README name the new host
- [ ] The deployment is still `noindex`
- [x] ADR-0008 records what was bought, so the next reader knows what is held
