# Odoo Community 19 para un servidor pequeño

Odoo 19 Community, PostgreSQL 16 y Caddy con HTTPS automático. Base inicial para **2 vCPU, 4 GB de RAM y SSD**, con pocos usuarios concurrentes. Incluye la interfaz estándar de Community; Enterprise necesita licencia y addons adicionales. No incluye un tema externo que pueda afectar compatibilidad o rendimiento.

No existe una versión universalmente «más rápida»: hay que medir con los módulos, datos y usuarios reales. Se elige una versión actual disponible en la imagen oficial, con dos workers HTTP, un proceso cron y websocket. En 2 GB puede ser necesario un solo worker y menos módulos; informes grandes e importaciones pueden agotar memoria. Para 1 GB no recomiendo esta configuración de producción.

## Primer arranque

Requisitos: Docker Engine con Compose v2.24 o posterior, un dominio con DNS A/AAAA apuntando al servidor y puertos TCP 80/443 accesibles. Solo publica esos puertos; restringe SSH por firewall. No abras 5432, 8069 ni 8072.

```sh
sh scripts/setup.sh
# Edita .env: ODOO_DOMAIN=erp.tudominio.com y ACME_EMAIL=tu@email.com
docker compose build --pull
docker compose up -d db
docker compose run --rm odoo bootstrap
docker compose up -d
docker compose ps
```

Abre `https://erp.tudominio.com`. Usuario inicial: `admin`. La contraseña aleatoria está en `secrets/odoo_admin_password`; consúltala localmente y guárdala en tu gestor de contraseñas. Cámbiala desde Odoo tras acceder. La clave maestra de bases de datos es distinta (`secrets/odoo_master_password`). El bootstrap evita publicar la contraseña predeterminada y no cambia credenciales si ya se completó.

`setup.sh` no sobrescribe secretos existentes. El bootstrap se ejecuta una sola vez sobre una base vacía. Si falla después de crear las tablas, el arranque queda bloqueado: revisa los logs y completa manualmente la inicialización. No borres volúmenes que contengan datos reales para resolverlo.

## Seguridad y recursos

- PostgreSQL está en una red interna, sin puertos publicados; Odoo usa un rol sin superusuario, creación de roles o bases.
- Solo Caddy recibe tráfico público y gestiona certificados y redirección a HTTPS. Las rutas de gestión de bases están bloqueadas, con `list_db=False` y filtro de base fijo.
- Odoo ejecuta como usuario no root, sin capacidades Linux, con raíz de solo lectura. Archivos de datos y sesiones persisten en un volumen. Las credenciales se escriben en un archivo privado en tmpfs, no en argumentos del proceso.
- Límites de RAM: Odoo 2304 MiB, PostgreSQL 768 MiB y Caddy 128 MiB. Se deja margen al sistema en un servidor de 4 GB. Los límites por worker son distintos del límite total del contenedor; si todos consumen su máximo simultáneamente puede actuar el OOM killer.
- Logs rotados, compresión HTTP, conexión websocket dedicada y un máximo de ocho conexiones SQL por proceso. Sin workers de desarrollo en producción.
- Los secretos de Compose son archivos del host, **no una bóveda cifrada**. El directorio `secrets/` usa permiso 0700; sus archivos son legibles dentro del contenedor por Odoo. No los añadas a Git ni los copies en imágenes. El administrador del host y Docker puede leerlos.

La imagen de Odoo tiene una fecha fija; PostgreSQL y Caddy siguen ramas mantenidas. Para despliegues reproducibles, fija las tres imágenes por digest en `.env` tras validarlas (`imagen@sha256:...`). Planifica actualizaciones y pruebas periódicas; fijar una imagen no aplica parches automáticamente. Regenerar archivos de secretos no rota usuarios ya creados en PostgreSQL/Odoo.

## Módulos personalizados

Añade módulos Odoo 19 en `custom-addons/mi_modulo/` con su `__manifest__.py` y `__init__.py`. Las dependencias Python van en `requirements.txt`, con versiones fijadas. El Dockerfile utiliza un entorno virtual que también ve las dependencias oficiales de Odoo.

Git ignora los módulos de `custom-addons/`. Permanecen en tu equipo y se incluyen en la imagen de producción al construirla; si despliegas desde otro equipo o servidor, copia allí esos módulos por separado.

En producción los módulos se copian durante la construcción. Después de revisar y probar un cambio:

```sh
sh scripts/backup.sh
docker compose build --pull odoo
docker compose stop odoo
# Primera instalación: sustituye -u por -i.
docker compose run --rm odoo -u mi_modulo --stop-after-init --no-http --workers=0 --max-cron-threads=0
docker compose up -d odoo
```

Si falla la actualización, mantén Odoo detenido y revisa el error antes de arrancar. No actualices todos los módulos automáticamente al iniciar. Una versión mayor de Odoo requiere migración de base de datos.

### Desarrollo local aislado

No uses esta variante en el servidor de producción. El nombre de proyecto **odoo-dev** separa volúmenes y redes. El override monta los módulos locales, activa recarga, desactiva cron y expone HTTP únicamente en loopback. No inicia Caddy.

```sh
sh scripts/setup.sh
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml build
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml up -d db
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml run --rm odoo bootstrap
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml up -d odoo
```

Visita `http://localhost:8069`. La recarga de Python no instala módulos ni aplica cambios de esquema: utiliza `-i mi_modulo` o `-u mi_modulo` con los mismos flags de mantenimiento anteriores y con Odoo detenido. Para crear un esqueleto:

```sh
docker compose -p odoo-dev -f compose.yaml -f compose.dev.yaml run --rm \
  -v "$PWD/custom-addons:/opt/custom-addons:rw" odoo scaffold mi_modulo /opt/custom-addons
```

En Linux el UID del contenedor debe tener permiso de escritura para el scaffold; ajusta el propietario del directorio para ese usuario. Evita `chmod 777`. En desarrollo el websocket se sirve por el puerto HTTP al usar cero workers.

## Copias de seguridad y restauración

```sh
sh scripts/backup.sh
```

El script detiene Odoo durante la copia para mantener coherencia entre PostgreSQL y el filestore, y vuelve a iniciarlo al terminar o fallar. Produce un dump PostgreSQL y un archivo de adjuntos; las sesiones no se restauran. Ejecuta durante una ventana de mantenimiento, configura periodicidad/retención externa y copia los resultados cifrados fuera del servidor. Un directorio incompleto tras un error no es un backup válido. Conserva también los secretos de forma cifrada y la revisión Git/imagen con los módulos que generaron la copia.

Prueba la restauración en otro proyecto o servidor con la misma versión y módulos. Los siguientes comandos **reemplazan los datos de la base destino**; no los ejecutes sobre producción por accidente:

```sh
# Configura primero el proyecto/host DESTINO y sus secretos.
docker compose up -d db
docker compose stop odoo
docker compose exec -T db dropdb -U postgres --if-exists --force odoo
docker compose exec -T db createdb -U postgres -O odoo -T template0 odoo
docker compose exec -T db psql -U postgres -d postgres -c 'REVOKE ALL ON DATABASE odoo FROM PUBLIC'
docker compose exec -T db pg_restore -U postgres -d odoo --exit-on-error < backups/FECHA/database.dump
# Usa un volumen odoo_data vacío en el destino, para no mezclar adjuntos viejos.
docker compose run --rm --no-deps -T --entrypoint tar odoo \
  -C /var/lib/odoo -xzf - < backups/FECHA/filestore.tar.gz
docker compose up -d
```

Comprueba acceso, adjuntos, informes y permisos. Nunca ejecutes `docker compose down -v` sobre un despliegue con datos que quieras conservar.

## Validación local

Comprobados: `docker compose config` para producción y desarrollo, sintaxis Python/shell y cinco pruebas de seguridad del arranque (`python3 -m unittest discover -s tests -v`). Las pruebas usan dobles de PostgreSQL/procesos; no sustituyen una prueba de integración. También se verificó el arranque real en desarrollo: creación del rol y base en un contenedor nuevo, endpoint de salud, página de login HTTP 200 y autenticación del administrador. PostgreSQL incorpora el script de inicialización en su imagen para evitar problemas al ejecutar archivos montados desde el host; su healthcheck comprueba la conexión real del usuario de Odoo. Antes de usar datos reales, verifica HTTPS, websocket, backup y restauración en el servidor destino.

## Fuentes

- [Despliegue y cálculo de workers de Odoo](https://www.odoo.com/documentation/19.0/administration/on_premise/deploy.html).
- [Imagen oficial Odoo](https://hub.docker.com/_/odoo) y [Dockerfile oficial 19](https://github.com/odoo/docker/blob/master/19.0/Dockerfile).
- [Imagen oficial PostgreSQL](https://hub.docker.com/_/postgres).
- [Proxy inverso Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).
