# Odoo Community 19 for a small server

Odoo 19 Community, PostgreSQL 16, and Caddy with automatic HTTPS. The starting configuration targets **2 vCPUs, 4 GB of RAM, and an SSD**, with a small number of concurrent users. It uses the standard Community interface. Enterprise requires a license and additional add-ons.

There is no universally fastest Odoo version: performance depends on your modules, data, and workload. This setup uses a pinned official Odoo image, two HTTP workers, one cron process, and a websocket worker. A 2 GB server may need one HTTP worker and fewer modules; large reports and imports can exhaust memory. A 1 GB server is not recommended for this production setup.

## First deployment

Requirements: Docker Engine with Compose v2.24 or later, a domain whose DNS A/AAAA record points to the server, and reachable TCP ports 80 and 443. Publish only those ports. Restrict SSH with a firewall. Do not expose ports 5432, 8069, or 8072.

```sh
sh scripts/setup.sh
# Edit .env: set ODOO_DOMAIN=erp.example.com and ACME_EMAIL=you@example.com.
docker compose build --pull
docker compose up -d db
docker compose run --rm odoo bootstrap
docker compose up -d
docker compose ps
```

Open `https://erp.example.com`. The initial username is `admin`. Read its generated password locally from `secrets/odoo_admin_password`, store it in a password manager, and change it in Odoo after signing in. The database master password is separate (`secrets/odoo_master_password`). Bootstrap sets the administrator password before the site is exposed and does not reset it on later runs.

`setup.sh` preserves existing secrets. Bootstrap runs once against an empty database. If it fails after creating tables, startup is blocked. Inspect the logs and finish initialization manually. Do not delete volumes containing real data to resolve the failure.

## Security and resource limits

- PostgreSQL uses an internal network with no published port. Odoo connects through a role that cannot create roles or databases and is not a superuser.
- Only Caddy accepts public traffic and handles certificates and HTTPS redirects. Database management routes are blocked; Odoo also uses `list_db=False` and a fixed database filter.
- Odoo runs as a non-root user without Linux capabilities and with a read-only root filesystem. Data files and sessions persist in a volume. Credentials are written to a private file in tmpfs rather than passed as process arguments.
- Memory limits: 2304 MiB for Odoo, 768 MiB for PostgreSQL, and 128 MiB for Caddy. This leaves some headroom on a 4 GB server. Per-worker memory limits are separate from the container limit; concurrent memory peaks can still trigger the OOM killer.
- Logs are rotated. HTTP compression and dedicated websocket routing are enabled. Each Odoo process has a maximum of eight SQL connections.
- Compose secrets are files on the host, **not an encrypted vault**. The `secrets/` directory has mode 0700; its files are readable by Odoo inside the container. Do not commit or bake them into images. Host and Docker administrators can read them.

The Odoo image uses a fixed release date; PostgreSQL and Caddy use maintained version branches. For fully reproducible deployments, pin all three images to tested digests in `.env` (`image@sha256:...`). Schedule updates and testing: pinning does not install security patches. Regenerating secret files does not rotate existing PostgreSQL or Odoo accounts.

## Custom add-ons

Place Odoo 19 add-ons in `custom-addons/my_module/` with `__manifest__.py` and `__init__.py`. Put any Python dependencies in `requirements.txt` with exact versions. The Dockerfile creates a virtual environment that can also access Odoo's official dependencies.

Git ignores add-ons under `custom-addons/`. They remain on your machine and are copied into the production image when you build it. If you deploy from another machine, transfer your custom add-ons separately.

After reviewing and testing an add-on change, deploy it as follows:

```sh
sh scripts/backup.sh
docker compose build --pull odoo
docker compose stop odoo
# For a first installation, replace -u with -i.
docker compose run --rm odoo -u my_module --stop-after-init --no-http --workers=0 --max-cron-threads=0
docker compose up -d odoo
```

If the update fails, keep Odoo stopped and inspect the error before restarting. Do not update every add-on automatically at startup. Major Odoo upgrades require a database migration.

### Isolated local development

Use this configuration on a development machine. The **odoo-dev** project name separates its volumes and networks from production. The override mounts local add-ons, enables reload, disables cron, and exposes HTTP only on loopback. It does not start Caddy.

```sh
sh scripts/setup.sh
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml build
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml up -d db
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml run --rm odoo bootstrap
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml up -d odoo
```

Open `http://localhost:8069`. Python reload does not install add-ons or apply schema changes. With Odoo stopped, use the maintenance command above with `-i my_module` or `-u my_module`. To generate a new add-on skeleton:

```sh
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml run --rm \
  -v "$PWD/custom-addons:/opt/custom-addons:rw" odoo scaffold my_module /opt/custom-addons
```

On Linux, the container UID needs write permission for scaffolding. Set ownership of the directory for that user; avoid `chmod 777`. In development mode with zero workers, websockets use the HTTP port.

## Backup and restore

```sh
sh scripts/backup.sh
```

The script stops Odoo briefly to keep PostgreSQL and the filestore consistent, then restarts it whether the copy succeeds or fails. It creates a PostgreSQL dump and an attachment archive; sessions are not restored. Run it during a maintenance window, set a schedule and external retention, and copy encrypted backups off the server. A directory left by a failed run is not a valid backup. Keep encrypted copies of the secrets and the Git revision/image plus the custom add-ons used to create the backup.

Test restoration in another project or server with the same Odoo version and add-ons. The following commands **replace the target database's data**. Do not run them against production by mistake:

```sh
# Configure the TARGET project/host and its secrets first.
docker compose up -d db
docker compose stop odoo
docker compose exec -T db dropdb -U postgres --if-exists --force odoo
docker compose exec -T db createdb -U postgres -O odoo -T template0 odoo
docker compose exec -T db psql -U postgres -d postgres -c 'REVOKE ALL ON DATABASE odoo FROM PUBLIC'
docker compose exec -T db pg_restore -U postgres -d odoo --exit-on-error < backups/TIMESTAMP/database.dump
# Use an empty odoo_data volume on the target to avoid mixing old attachments.
docker compose run --rm --no-deps -T --entrypoint tar odoo \
  -C /var/lib/odoo -xzf - < backups/TIMESTAMP/filestore.tar.gz
docker compose up -d
```

Check login, attachments, reports, and permissions. Never run `docker compose down -v` on a deployment whose data you need to keep.

## Local validation

The production and development Compose configurations were parsed, Python and shell syntax were checked, and five startup security tests passed (`python3 -m unittest discover -s tests -v`). The tests use database and process mocks. A development integration check also confirmed role and database creation in a fresh container, the health endpoint, HTTP 200 on the login page, and administrator authentication. The PostgreSQL initialization script is baked into its image to avoid host mount execution problems; its healthcheck verifies a real connection as the Odoo user. Before using real data, test HTTPS, websockets, backup, and restore on the target server.

## References

- [Odoo deployment and worker sizing](https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html).
- [Official Odoo image](https://hub.docker.com/_/odoo) and [official Odoo 19 Dockerfile](https://github.com/odoo/docker/blob/master/19.0/Dockerfile).
- [Official PostgreSQL image](https://hub.docker.com/_/postgres).
- [Caddy reverse proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).
