#!/bin/sh
set -eu
# Rol de aplicación independiente: nunca superusuario ni creador de bases.
app_password="$(cat /run/secrets/odoo_db_password)"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    --set=app_password="$app_password" <<'SQL'
CREATE ROLE odoo LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'app_password';
CREATE DATABASE odoo OWNER odoo TEMPLATE template0 ENCODING 'UTF8';
REVOKE ALL ON DATABASE odoo FROM PUBLIC;
SQL
