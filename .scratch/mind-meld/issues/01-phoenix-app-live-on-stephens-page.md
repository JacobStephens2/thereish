# 01: A Phoenix app reachable at stephens.page from Melissa's phone

**What to build:** Jacob opens a URL on his phone and gets a page served by the real deployment, over TLS, with a live socket connected. The same Docker image runs on the Mac and on the VPS. This exists so that every later evening measures real round-trips and the deploy loop is exercised long before couch night, per the design brief's couch-night hosting decision.

Nothing game-shaped is in this ticket. It is the prefactor that makes every later slice a small change.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] Elixir and Erlang installed via mise on the Mac; `mix phx.server` runs locally against a docker-compose Postgres
- [x] Phoenix 1.8.x with LiveView 1.2.x, generated scaffolding kept thin
- [x] Ecto configured against Postgres; a migration runs clean on both machines. No game tables yet
- [x] A Docker release built with `mix phx.gen.release --docker`; the identical image runs on the Mac and the VPS
- [x] Apache vhost proxying to the app's localhost port with `ProxyPreserveHost On` and websocket upgrade; certbot TLS
- [x] A LiveView page loads on a phone over HTTPS and visibly reports its socket as connected
- [x] Secure context confirmed, so the Screen Wake Lock API is available to later tickets
- [x] A one-command deploy path from `master` documented in the repo
- [x] `mix test` runs green, including one test that boots the endpoint

## Comments

**2026-09-03 — built and deployed.** Live at <https://meld.stephens.page>. The apex is already a static site with its own proxies, so the game took a subdomain; `meld` names the Mind-Meld mechanic rather than the game, which is still unnamed. Commits `9707289`, `b8d915c`, `b5a9cc9`, `dc021a0`. Deploy notes in `docs/deploy.md`.

Two things only deploying could have found. Phoenix 1.8's generated `config/prod.exs` sets `force_ssl: [rewrite_on: [:x_forwarded_proto]]`, and the `new_subdomain` vhost template in `~/infra` does not send that header, so every HTTPS request 301'd to the URL it was already on. And `docker compose run` reads stdin, which during a deploy is the rest of the script arriving over ssh, so it swallowed `up -d` and no container ever started.

The check page reports the **transport**, not just `connected?/1`. LiveView falls back to long polling silently, so a vhost missing `upgrade=websocket` would have shown "Socket connected" while quietly costing a round-trip per message — the exact latency the couch-night hosting decision exists to measure honestly.

**2026-09-03 — closed.** Jacob confirmed <https://meld.stephens.page> reading *Socket connected*, *Transport: WebSocket*, *Secure context: yes*, *Screen Wake Lock: available*, which was the one criterion an agent could not verify for itself. A real websocket, not the long-poll fallback, so the vhost's `upgrade=websocket` is doing its job and the reveal beat will be measured against honest round-trips.

Two calls made without asking, neither creating a game table: `--binary-id` is on, because a Seat id has to be stable and claimable by an Account later (ADR-0007) and it is free to set now; and the one migration enables `citext` rather than being a no-op, because joining a Room by the name a player typed wants case-insensitive comparison in ticket 02.
