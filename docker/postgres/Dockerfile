ARG POSTGRES_IMAGE=postgres:16-bookworm
FROM ${POSTGRES_IMAGE}
# Source the script during init; do not execute a host bind mount.
COPY --chmod=0644 init.sh /docker-entrypoint-initdb.d/10-odoo.sh
