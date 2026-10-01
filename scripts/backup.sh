#!/bin/sh
# Consistent backup with a brief Odoo stop; previous backups remain untouched.
set -eu
cd "$(dirname "$0")/.."
umask 077
destination="backups/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$destination"
docker compose stop odoo
trap 'docker compose start odoo >/dev/null' EXIT
docker compose exec -T db pg_dump -U postgres -d odoo -Fc > "$destination/database.dump"
docker compose run --rm --no-deps -T --entrypoint tar odoo \
    -C /var/lib/odoo -czf - filestore > "$destination/filestore.tar.gz"
cp .env "$destination/deployment.env"
docker compose images > "$destination/images.txt"
printf '%s\n' "Backup complete: $destination. Copy it off the server in encrypted form."
