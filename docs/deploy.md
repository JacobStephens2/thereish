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
until `https://meld.stephens.page/` actually serves the check page. A dirty
working tree or an unpushed `master` stops it before it touches the server.

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

To run the release image on the Mac, against the compose Postgres:

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

## Checking it

`https://meld.stephens.page/` is `MeaningGameWeb.CheckLive`, the deployment's
proof of life and nothing game-shaped. It reports three things:

- **Socket connected** — the server's own `connected?/1`, so it only says this
  once the client has upgraded through Apache. "Socket not connected" is the
  dead render, and is what you see with JavaScript off or the upgrade broken.
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
