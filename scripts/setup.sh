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
    # Compose monta archivos; Odoo (no root) debe poder leerlos en el contenedor.
    # El directorio padre 0700 impide acceso de otros usuarios en el host.
    chmod 444 "secrets/$name"
done
printf '%s\n' 'Secretos preparados. Edita ODOO_DOMAIN y ACME_EMAIL en .env antes de desplegar.'
