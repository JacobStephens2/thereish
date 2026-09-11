#!/usr/bin/env bash
# Build-is-deploy hook for thereish.app.
# Rebuilds the Docker release image, runs migrations, and starts the container.
#
# Usage: deploy/deploy.sh (invoked by /usr/local/bin/site-deploy meld)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE="docker compose -f docker-compose.app.yml"

echo "==> Ensuring media volume is writable"
# Ticket 73 mounts ./media into the container so Tracks and Masks survive
# deploys. The app runs as nobody; a root-owned 0755 directory makes
# TrackCache.store raise eacces and every Page stays on the Repertoire.
install -d -m 0777 "${ROOT}/media"
chmod 0777 "${ROOT}/media" || sudo chmod 0777 "${ROOT}/media"

echo "==> Building release image"
${COMPOSE} build

echo "==> Running database migrations"
# -T and </dev/null: ensure non-interactive execution over ssh / site-deploy
${COMPOSE} run --rm -T app /app/bin/migrate </dev/null

echo "==> Starting application container"
${COMPOSE} up -d

echo "==> Deployed container status:"
${COMPOSE} ps app
