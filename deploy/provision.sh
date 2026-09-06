#!/usr/bin/env bash
# One-time server provisioning for thereish.app. Runs ON the VPS, from the
# checkout at /var/www/thereish.app. Idempotent: every step checks first,
# so re-running it is safe and is the way to repair a half-finished setup.
#
# Invoked from the Mac by bin/provision-server. Routine redeploys are bin/deploy,
# which does not touch any of this.
set -euo pipefail

HOST="thereish.app"
APP_DIR="/var/www/${HOST}"
DB_NAME="meaning_game"
DB_USER="meaning_game"
ENV_FILE="${APP_DIR}/.env"
CERTBOT_EMAIL="jacob@stephens.page"
DOCKER_SUBNET="172.17.0.0/16"
PG_HBA="/etc/postgresql/16/main/pg_hba.conf"

say() { printf '\n== %s\n' "$1"; }

say "Postgres role and database"
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${DB_USER}'" | grep -q 1; then
  echo "role ${DB_USER} already exists"
  DB_PASSWORD=""
else
  DB_PASSWORD="$(openssl rand -hex 24)"
  sudo -u postgres psql -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}'"
  echo "created role ${DB_USER}"
fi

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | grep -q 1; then
  echo "database ${DB_NAME} already exists"
else
  sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
  echo "created database ${DB_NAME}"
fi

say "pg_hba rule for the docker bridge"
# The app runs in a container on docker0, so it reaches Postgres from
# 172.17.0.0/16 rather than from loopback. Same shape as the documenso and umami
# rules already in this file: one database, one role, one subnet.
HBA_RULE="host    ${DB_NAME}    ${DB_USER}    ${DOCKER_SUBNET}    scram-sha-256"
if sudo grep -qE "^host\s+${DB_NAME}\s+${DB_USER}\s" "${PG_HBA}"; then
  echo "pg_hba rule already present"
else
  echo "${HBA_RULE}" | sudo tee -a "${PG_HBA}" >/dev/null
  sudo systemctl reload postgresql
  echo "added pg_hba rule and reloaded postgres"
fi

say "Environment file"
if [ -f "${ENV_FILE}" ]; then
  echo "${ENV_FILE} already exists, leaving it alone"
else
  if [ -z "${DB_PASSWORD}" ]; then
    echo "ERROR: the ${DB_USER} role exists but ${ENV_FILE} does not, so its" >&2
    echo "password is unknown. Reset it with:" >&2
    echo "  sudo -u postgres psql -c \"ALTER ROLE ${DB_USER} PASSWORD '<new>'\"" >&2
    echo "then write ${ENV_FILE} by hand and re-run." >&2
    exit 1
  fi
  umask 077
  cat >"${ENV_FILE}" <<ENV
# Secrets. Not in git. Mode 600. Recreate with deploy/provision.sh.
SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n')
DATABASE_URL=ecto://${DB_USER}:${DB_PASSWORD}@host.docker.internal/${DB_NAME}
PHX_HOST=${HOST}
# The Assayer's key, which this script cannot generate. Paste it here: without
# one the game runs and grades nothing, saying "no verdict" on every Page.
GEMINI_API_KEY=
# The Author's key (Anthropic Claude Fable 5.1). Paste it here: without it
# the game plays from the static pool and the Author cannot write for Gives.
ANTHROPIC_API_KEY=
ENV
  chmod 600 "${ENV_FILE}"
  echo "wrote ${ENV_FILE}"
fi

say "Apache proxy fragment"
# Always synced, because this is the file that changes. Both the :80 vhost and
# certbot's :443 vhost include it, so one copy configures both.
sudo install -d -m 0755 "/etc/apache2/${HOST}.d"
sudo install -m 0644 "${APP_DIR}/deploy/apache/proxy.conf" "/etc/apache2/${HOST}.d/proxy.conf"
echo "synced /etc/apache2/${HOST}.d/proxy.conf"

say "Apache vhost"
if [ -f "/etc/apache2/sites-available/${HOST}.conf" ]; then
  echo "vhost already installed"
else
  sudo install -m 0644 "${APP_DIR}/deploy/${HOST}.conf" "/etc/apache2/sites-available/${HOST}.conf"
  sudo a2ensite "${HOST}.conf"
  echo "installed and enabled the vhost"
fi
sudo apache2ctl configtest
sudo systemctl reload apache2

say "TLS certificate"
# Guarded on the vhost certbot writes rather than on the certificate, so that a
# missing :443 vhost is repaired even when the certificate is already issued.
# --keep-until-expiring makes that repair a no-op for the certificate itself.
if [ -f "/etc/apache2/sites-available/${HOST}-le-ssl.conf" ]; then
  echo "TLS vhost already in place"
else
  sudo certbot --apache --non-interactive --agree-tos --keep-until-expiring \
    -m "${CERTBOT_EMAIL}" --redirect -d "${HOST}" -d "www.${HOST}"
  echo "issued the certificate and installed the TLS vhost"
fi

say "Done. Deploy with bin/deploy from the Mac."
