#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
umask 077
mkdir -p secrets backups
chmod 700 secrets backups
if [ ! -f .env ]; then
    cp .env.example .env
fi
for name in postgres_password odoo_db_password odoo_master_password odoo_admin_password; do
    if [ ! -e "secrets/$name" ]; then
        openssl rand -hex 32 > "secrets/$name"
    fi
    # Compose mounts files; non-root Odoo must be able to read them in the container.
    # The parent directory's 0700 mode blocks other host users.
    chmod 444 "secrets/$name"
done
printf '%s\n' 'Secrets prepared. Set ODOO_DOMAIN and ACME_EMAIL in .env before deployment.'
