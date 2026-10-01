#!/bin/sh
# Copia consistente con una breve parada de Odoo; no elimina backups anteriores.
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
printf '%s\n' "Backup completo: $destination. Cópialo cifrado fuera del servidor."
