#!/usr/bin/env bash
# Build-is-deploy hook for thereish.app.
# Rebuilds the Docker release image, runs migrations, and starts the container.
#
# Usage: deploy/deploy.sh (invoked by /usr/local/bin/site-deploy meld)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE="docker compose -f docker-compose.app.yml"

echo "==> Ensuring media volume is owned by the release user"
# Ticket 73 mounts ./media into the container so Tracks and Masks survive
# deploys. The release runs as nobody. On every run, including when the
# directory already exists, own it as nobody at 0755. install -d tries to
# chmod an existing directory and aborts when it cannot, so a missing
# directory is created first and the chown and chmod always run. Left
# owned by root at 0755, TrackCache.store raises eacces and the Page stays
# on the Repertoire.
if [ ! -d "${ROOT}/media" ]; then
  sudo install -d -m 0755 "${ROOT}/media"
fi
sudo chown nobody:nogroup "${ROOT}/media"
sudo chmod 0755 "${ROOT}/media"

echo "==> Building release image"
${COMPOSE} build

echo "==> Running database migrations"
# -T and </dev/null: ensure non-interactive execution over ssh / site-deploy
${COMPOSE} run --rm -T app /app/bin/migrate </dev/null

echo "==> Starting application container"
${COMPOSE} up -d

echo "==> Deployed container status:"
${COMPOSE} ps app
