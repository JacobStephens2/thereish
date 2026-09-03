# 01: A Phoenix app reachable at stephens.page from my wife's phone

**What to build:** Jacob opens a URL on his phone and gets a page served by the real deployment, over TLS, with a live socket connected. The same Docker image runs on the Mac and on the VPS. This exists so that every later evening measures real round-trips and the deploy loop is exercised long before couch night, per the design brief's couch-night hosting decision.

Nothing game-shaped is in this ticket. It is the prefactor that makes every later slice a small change.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] Elixir and Erlang installed via mise on the Mac; `mix phx.server` runs locally against a docker-compose Postgres
- [ ] Phoenix 1.8.x with LiveView 1.2.x, generated scaffolding kept thin
- [ ] Ecto configured against Postgres; a migration runs clean on both machines. No game tables yet
- [ ] A Docker release built with `mix phx.gen.release --docker`; the identical image runs on the Mac and the VPS
- [ ] Apache vhost proxying to the app's localhost port with `ProxyPreserveHost On` and websocket upgrade; certbot TLS
- [ ] A LiveView page loads on a phone over HTTPS and visibly reports its socket as connected
- [ ] Secure context confirmed, so the Screen Wake Lock API is available to later tickets
- [ ] A one-command deploy path from `master` documented in the repo
- [ ] `mix test` runs green, including one test that boots the endpoint
