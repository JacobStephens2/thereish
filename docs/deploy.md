# Deploying to meld.stephens.page

The game runs at **https://meld.stephens.page**, on the DigitalOcean droplet
behind Apache, from the first evening — so every session measures the real VPS
round-trips the reveal beat has to absorb (design brief, "Couch-night hosting").

The apex `stephens.page` is a static site with its own proxies, so the game took
a subdomain. `meld` names the Mind-Meld mechanic, not the game, which is still
unnamed.

## The one command

From a clean `master` that is pushed:

```sh
bin/deploy
```

It fetches `master` on the VPS, rebuilds the image from the same `Dockerfile`
used on the Mac, runs migrations, restarts the container, and does not return
until `https://meld.stephens.page/check` actually serves the check page. An unpushed
`master` stops it before it touches the server; a dirty working tree is only a
warning, since design docs are edited in this repo alongside the build and none
of that reaches the server anyway.

## What runs where

| | Mac | VPS |
|---|---|---|
| App | `mix phx.server` on `:4000` | the release image, container port 4000 published on `127.0.0.1:3530` |
| Postgres | `docker-compose.yml`, published on `127.0.0.1:5432` | the host's own Postgres 16 cluster, database `meaning_game` |
| TLS | none | Apache vhost + certbot, `deploy/meld.stephens.page.conf` |

`docker-compose.app.yml` runs the release image and is the same file in both
places. It never contains Postgres: the container reaches whichever cluster the
machine already has at `host.docker.internal`, and `network_mode: bridge` puts
it on `docker0` so its source address falls in the `172.17.0.0/16` range the
VPS's `pg_hba.conf` grants to the `meaning_game` database — the same shape as
the existing documenso and umami rules.

To run the release image on the Mac, against the compose Postgres, write a
`.env.local` once (gitignored, like the server's `.env`):

```sh
cat > .env.local <<ENV
SECRET_KEY_BASE=$(mix phx.gen.secret)
DATABASE_URL=ecto://postgres:postgres@host.docker.internal/meaning_game_dev
PHX_HOST=localhost
ENV
```

`PHX_HOST=localhost` matters: `config/prod.exs` sets `force_ssl`, and localhost
is on its exclusion list, so the image serves plain HTTP here instead of
redirecting to a TLS port that does not exist. Then:

```sh
ENV_FILE=.env.local APP_PORT=4001 docker compose -f docker-compose.app.yml up --build
```

The `Dockerfile` and the tag are identical in both places; the bits are not,
because each machine builds for its own architecture (arm64 on the Mac, amd64 on
the VPS). Nothing in the image is architecture-specific — that is the point of
building from one Dockerfile rather than one registry.

## First-time setup

Already done for `meld.stephens.page`. Re-running it is safe and is how you
repair a half-finished setup, or stand the whole thing up again after a rebuild:

```sh
bin/provision-server
```

It clones the repo to `/var/www/meld.stephens.page`, then runs
`deploy/provision.sh` on the server, which creates the `meaning_game` Postgres
role and database, adds the `pg_hba.conf` rule for the docker bridge, writes
`/var/www/meld.stephens.page/.env` with freshly generated secrets (mode 600,
never in git), installs and enables the Apache vhost, and obtains the
certificate with `certbot --apache --redirect`.

Every step checks before it acts, so it is idempotent. The one case it refuses
to guess at is a Postgres role that exists while `.env` does not — the password
is unrecoverable then, and it tells you how to reset it.

DNS needs nothing: `*.stephens.page` already resolves to the droplet.

### The websocket line

`deploy/meld.stephens.page.conf` follows the proxy template in
`~/infra/ansible/roles/new_subdomain` on the server, with one addition that
template does not have:

```apache
ProxyPass / http://127.0.0.1:3530/ upgrade=websocket
```

Without `upgrade=websocket` the LiveView socket silently falls back to long
polling, which is exactly the latency the couch-night hosting decision exists to
measure honestly. It needs Apache 2.4.47+; the VPS runs 2.4.58. If that role
ever grows a websocket option, this vhost should move back onto it.

## The URLs

| | |
|---|---|
| `https://meld.stephens.page/` | a phone: the couch's Room, joined by typing a name |
| `https://meld.stephens.page/stage` | the laptop: the same Room as the stage |
| `https://meld.stephens.page/check` | the deployment's proof of life |

The bare URL is the phone's, because that is the one a player types. `/r/<slug>`
and `/r/<slug>/stage` open any other Room; nothing needs one yet.

## Checking it

`https://meld.stephens.page/check` is `MeaningGameWeb.CheckLive`, the
deployment's proof of life and nothing game-shaped. It reports four things:

- **Socket connected** — the server's own `connected?/1`, so it only says this
  once the client has upgraded through Apache. "Socket not connected" is the
  dead render, and is what you see with JavaScript off.
- **Transport: WebSocket** — the check that matters. `connected?/1` is equally
  true over LiveView's long-poll fallback, so a vhost missing
  `upgrade=websocket` would still say "Socket connected" while quietly costing
  a round-trip per message. If this ever reads `LongPoll`, the proxy is broken.
- **Secure context: yes** — pushed back by the browser. Required for the Screen
  Wake Lock the stage view takes in ticket 02.
- **Screen Wake Lock: available** — whether this browser has the API at all.

## Operating

```sh
# logs
ssh jacob@stephens.page 'cd /var/www/meld.stephens.page && docker compose -f docker-compose.app.yml logs --tail=100 app'

# restart
ssh jacob@stephens.page 'cd /var/www/meld.stephens.page && docker compose -f docker-compose.app.yml restart app'

# a shell in the running release
ssh jacob@stephens.page 'cd /var/www/meld.stephens.page && docker compose -f docker-compose.app.yml exec app /app/bin/meaning_game remote'
```

Secrets live only in `/var/www/meld.stephens.page/.env` on the server. They are
not in git, not in the image, and not in any backup this repo controls.
