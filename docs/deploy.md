# Deploying to thereish.app

The game runs at **https://thereish.app**, on the DigitalOcean droplet
behind Apache, from the first evening — so every session measures the real VPS
round-trips the reveal beat has to absorb (design brief, "Couch-night hosting").

The apex `stephens.page` is a static site with its own proxies, so the game took
a subdomain originally (`meld.stephens.page`). The game is now called Thereish
(ADR-0008), served at its own domain `https://thereish.app`, with
`meld.stephens.page` 301-redirecting there for a season (naming issue 07).

## Continuous deployment (push to master)

Every push or merge to `master` deploys automatically via GitHub Actions
(`.github/workflows/deploy.yml`).

The workflow authenticates using a restricted SSH deploy key
(`github-actions-meld` in `~/.ssh/authorized_keys`) that triggers the droplet's
fleet deployment manager:

```sh
site-deploy meld <TARGET_SHA>
```

Configured in `/etc/site-deploy/sites.toml` under `[sites.meld]`:
1. Acquires a global and site-specific lock to prevent concurrent deploys on the VPS.
2. Ensures the server working directory is clean and fast-forwards `master` to the target SHA (skipping build steps if incoming commits only touch `.github/`).
3. Executes `deploy/deploy.sh` to rebuild the Docker image, run migrations, and recreate the container.
4. Verifies the deployment healthcheck against `https://thereish.app/check`.

## Manual deploy fallback

When deploying manually from the Mac (e.g. if GitHub Actions is degraded or for immediate control):

```sh
bin/deploy
```

It fetches `master` on the VPS, rebuilds the image from the same `Dockerfile`
used on the Mac, runs migrations, restarts the container, and does not return
until `https://thereish.app/check` actually serves the check page. An unpushed
`master` stops it before it touches the server; a dirty working tree is only a
warning, since design docs are edited in this repo alongside the build and none
of that reaches the server anyway.

## What runs where

| | Mac | VPS |
|---|---|---|
| App | `mix phx.server` on `:4000` | the release image, container port 4000 published on `127.0.0.1:3530` |
| Postgres | `docker-compose.yml`, published on `127.0.0.1:5432` | the host's own Postgres 16 cluster, database `meaning_game` |
| TLS | none | Apache vhost + certbot, `deploy/thereish.app.conf` |

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

Already done for `thereish.app`. Re-running it is safe and is how you
repair a half-finished setup, or stand the whole thing up again after a rebuild:

```sh
bin/provision-server
```

It clones the repo to `/var/www/thereish.app`, then runs
`deploy/provision.sh` on the server, which creates the `meaning_game` Postgres
role and database, adds the `pg_hba.conf` rule for the docker bridge, writes
`/var/www/thereish.app/.env` with freshly generated secrets (mode 600,
never in git), installs and enables the Apache vhost, and obtains the
certificate with `certbot --apache --redirect` covering both `thereish.app` and `www.thereish.app`.

Every step checks before it acts, so it is idempotent. The one case it refuses
to guess at is a Postgres role that exists while `.env` does not — the password
is unrecoverable then, and it tells you how to reset it.

DNS for `thereish.app` points at `68.183.62.24`, the droplet.

### The websocket line

`deploy/thereish.app.conf` follows the proxy template in
`~/infra/ansible/roles/new_subdomain` on the server, with one addition that
template does not have:

```apache
ProxyPass / http://127.0.0.1:3530/ upgrade=websocket
```

Without `upgrade=websocket` the LiveView socket silently falls back to long
polling, which is exactly the latency the couch-night hosting decision exists to
measure honestly. It needs Apache 2.4.47+; the VPS runs 2.4.58. If that role
ever grows a websocket option, this vhost should move back onto it.

### The Assayer's key

The live Assayer is Gemini 3.8 Flash (ADR-0005), and it is reached with an API
key that `deploy/provision.sh` cannot generate. It lives in the same `.env` as
the other secrets, on one line:

```sh
ssh jacob@stephens.page
sudo -e /var/www/thereish.app/.env    # GEMINI_API_KEY=...
cd /var/www/thereish.app && docker compose -f docker-compose.app.yml up -d
```

On the Mac it goes in `.env.local` for the release image, and in the shell for
`mix phx.server`.

Without it the game runs and grades nothing: every Page reads "No verdict. This
one is yours to call," which is the honest failure and a miserable evening.
`bin/deploy` warns when the line is missing, and the container logs
`GEMINI_API_KEY is not set` on the first Bridge committed.

Nothing else about the Assayer is a secret. Which model, at what effort, hedged
how many ways, and how long it waits are all in `config/config.exs` under
`:steward`, so swapping the Assayer is a commit rather than a server visit.

### The Author's key

The live Author is Claude Fable 5.1 (design brief, "Model policy, v1"), reached
with an Anthropic API key that `deploy/provision.sh` cannot generate. It lives in
the same `.env` as the other secrets:

```sh
ssh jacob@stephens.page
sudo -e /var/www/thereish.app/.env    # ANTHROPIC_API_KEY=...
cd /var/www/thereish.app && docker compose -f docker-compose.app.yml up -d
```

On the Mac it goes in `.env.local` for the release image, and in the shell for
`mix phx.server`.

Without it the game plays on from the pre-authored pool: entering a Give at
the couch surfaces "The Author couldn't write for '<give>': no_api_key.
Playing on from the existing pool." `bin/deploy` warns when the line is missing,
and the container logs `ANTHROPIC_API_KEY is not set` when an Author run is
attempted.

When the Scribe is implemented to write Chronicle recaps post-play, it is
planned to use `claude-fable-5-1` as well and will share this key.

### Umami

Page views are counted first-party and cookieless through self-hosted Umami (ticket 11).
The instance already runs on the server; the website is created in its dashboard by hand.
Two values live in `/var/www/thereish.app/.env`:

```sh
ssh jacob@stephens.page
sudo -e /var/www/thereish.app/.env    # UMAMI_SCRIPT_URL=... UMAMI_WEBSITE_ID=...
cd /var/www/thereish.app && docker compose -f docker-compose.app.yml up -d
```

On the Mac they can be set in `.env.local` for the release image, or omitted so development and tests load nothing.

Without them, the game renders no analytics script tag at all. `bin/deploy` and the boot line warn when the pair is missing, and `bin/keys-to-server` can push them.

### The keys on the Mac: `va`


Every key the game reads — `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, and the Foley's `MUREKA_API_KEY`, `ELEVENLABS_API_KEY`, `HUME_API_KEY` / `HUME_SECRET_KEY` — is in the Bitwarden manifest of Jacob's `vaulted-agent` launcher. A shell or harness started through it has them in the environment and nothing else does:

```sh
va bash                  # a shell with the keys; then mix phx.server, or a live smoke test
va claude                # a coding session that can run them
```

Nothing is written to disk. `.env.local` is only for running the release image on the Mac.

### Measuring the round trip

The reveal is a fixed 2.5 second beat and the Assayer has to fit a p95 of four
seconds inside it (design law 10). That is a claim about this machine's distance
from Google, so it is measured from this machine, after any deploy that touches
the prompt, the schema, or the model:

```sh
ssh jacob@stephens.page 'cd /var/www/thereish.app && \
  docker compose -f docker-compose.app.yml exec app \
  /app/bin/meaning_game eval "MeaningGame.Steward.Latency.measure()"'
```

Twenty real grades, sequentially, on a fixed set of pairs spread across the
ladder; it prints each one as it lands and then p50, p95, max, and what it
spent. It costs cents.

## The URLs

| | |
|---|---|
| `https://thereish.app/` | the front page: a Code box, New Room, and this phone's Rooms |
| `https://thereish.app/new` | New Room: how many players, then a Code to read aloud |
| `https://thereish.app/r/couch` | a phone in the couch's Room, joined by typing a name |
| `https://thereish.app/r/couch/stage` | the laptop: the same Room as the stage |
| `https://thereish.app/check` | the deployment's proof of life |

Every Room lives under its Code, the couch included. The bare URL is the door a
friend at a table opens: they were told one word, and it asks for that word. A
Code that no Room has is a 404 — visiting a path has never created a Room since
Rooms became things people open on purpose.

`https://meld.stephens.page` 301-redirects to `https://thereish.app`, path preserved,
so older bookmarks and "Your Rooms" links continue to land in the right Room.

## Checking it

`https://thereish.app/check` is `MeaningGameWeb.CheckLive`, the
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
ssh jacob@stephens.page 'cd /var/www/thereish.app && docker compose -f docker-compose.app.yml logs --tail=100 app'

# restart
ssh jacob@stephens.page 'cd /var/www/thereish.app && docker compose -f docker-compose.app.yml restart app'

# a shell in the running release
ssh jacob@stephens.page 'cd /var/www/thereish.app && docker compose -f docker-compose.app.yml exec app /app/bin/meaning_game remote'
```

Secrets live only in `/var/www/thereish.app/.env` on the server. They are
not in git, not in the image, and not in any backup this repo controls.
