# Referencia: imagen `mintsystem/odoo` para Odoo 20

Documento de referencia para el despliegue de producción de este proyecto.
Recoge la documentación oficial de Mint System **contrastada con el código fuente real** de la imagen
y con la documentación oficial de despliegue de Odoo 20.

| Fuente | Versión revisada |
|---|---|
| Repo [Mint-System/Odoo-Build](https://github.com/Mint-System/Odoo-Build) (`images/odoo/`) | commit `866f8a6` (2026-10-06) |
| Docs imagen: <https://odoo.build/images/odoo/> | ídem |
| Docker Hub `mintsystem/odoo` | tags `20.0`, `20.0.20260926` (Python 3.13) |
| Odoo 20 `deploy.rst` ([odoo/documentation@20.0](https://github.com/odoo/documentation/blob/20.0/content/administration/on_premise/deploy.rst)) | rama 20.0 |
| Odoo 20 código (`odoo/tools/config.py`, `odoo/http/router.py`, `odoo/release.py`) | commit `dd5defe` (el que usa la revisión de la imagen) |

---

## 1. Qué es la imagen

"A better Odoo image": reemplazo de la imagen oficial `odoo` con estas diferencias:

- Python gestionado con **uv** en un venv (`/opt/odoo/venv`); Odoo instalado desde fuente en `/opt/odoo`.
- Odoo fijado a una **revisión** (snapshot por fecha): el tag `20.0.20260926` es reproducible; `20.0` es flotante.
- `odoo.conf` **generado en cada arranque** desde variables de entorno (`envsubst` sobre `/etc/odoo/odoo.conf.template`).
- Clona addons desde git (GitHub/GitLab/Forgejo, https o ssh), soporta `git-aggregator` (`repos.yml`).
- Instala paquetes Python en runtime (`PYTHON_INSTALL`, `requirements.txt`, `pyproject.toml`).
- Detecta módulos en **carpetas anidadas** y arma el `addons_path` solo.
- Scripts para `init-db`, `init-module`, `update-module`, `update-modules` (click-odoo-update con checksums).
- Incluye **manifestoo**, **click-odoo-contrib**, **git-aggregator**, **openupgradelib**, **upgrade-util**, wkhtmltopdf 0.12.6.1, `postgresql-client` (última), Node + rtlcss.
- **Nginx embebido** (reverse proxy en el puerto 8080).
- Healthcheck integrado: `curl http://localhost:8069/web/health` cada 10 s.
- Compatible con UID arbitrario (permisos estilo OpenShift, grupo 0). **Ojo:** el Dockerfile no declara `USER`, así que por defecto corre como root; hay que fijar el usuario nosotros (ver §8).

Puertos expuestos: `8069` (HTTP Odoo), `8072` (gevent/websocket), `8080` (nginx), `8068`/`8071` (tests).

## 2. Secuencia del entrypoint (`/entrypoint.sh`)

1. `template-odoo-rc`: aplica los valores por defecto, arma `ADDONS_PATH` (`set-addons-path`) y genera `/etc/odoo/odoo.conf`.
2. `install-python-packages`: `PYTHON_INSTALL` y `/var/lib/odoo/requirements.txt` (si existe).
3. Construye los argumentos de BD (`--db_host`, `--db_port`, `--db_user`, `--db_password`, `--db_sslmode`) desde `PG*`.
4. `wait-for-pg` (30 intentos × 5 s), solo si el hostname de `PGHOST` resuelve.
5. Si `AUTO_UPDATE_MODULES_LIST=True`, ejecuta `update-modules-list`.
6. Si `AUTO_UPDATE_TRANSLATIONS=True`, ejecuta `update-translations`.
7. Según el `command`:
   - `odoo` (por defecto): `exec odoo ...`
   - `odoo-nginx`: lanza `nginx` en segundo plano y luego `exec odoo ...`. **Este es el modo que usaremos.**
   - `-algo`: lo pasa como flags a odoo.
   - cualquier otra cosa: `exec "$@"`.

No clona repos ni descarga Enterprise al arrancar: eso se hace a mano con `clone-git-addons`, `aggregate-git-repos` y `download-odoo-enterprise`. Lo persistido queda en el volumen `/var/lib/odoo`.

## 3. Variables de entorno (valores por defecto REALES del código)

> Donde la documentación y el código discrepan, manda el código. Las discrepancias se marcan con ⚠️.

### Base de datos
| Variable | Defecto | Nota |
|---|---|---|
| `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` | `db` / `5432` / `odoo` / `odoo` | Odoo 20 también las lee nativamente (`env_name`) |
| `DB_NAME` | `""` | → `db_name`. **En producción: fijarla.** |
| `DB_SYSTEM` | `postgres` | Odoo 20: BD para operaciones de sistema |
| `DB_MAXCONN` | `64` | |
| `PGSSLMODE` / `PGSSLROOTCERT` | `prefer` / – | `verify-ca` exige el certificado |
| `db_user_FILE`, `db_password_FILE` | – | ⚠️ **No funciona** (ver §7.1) |

### Servidor
| Variable | Defecto real | Nota |
|---|---|---|
| `WORKERS` | `0` | ⚠️ 0 = modo multihilo. **El nginx embebido exige ≥1** (websocket en 8072) |
| `GEVENT_WORKERS` | `1` | Opción nueva de Odoo 19+/20 (necesita `SO_REUSEPORT`) |
| `ODOO_MAX_HTTP_THREADS` | (Odoo: `2*CPU+1`) | Solo aplica en modo multihilo |
| `MAX_CRON_THREADS` | `2` | |
| `LIMIT_REQUEST` | `8192` | ⚠️ la doc dice 65536 |
| `LIMIT_TIME_CPU` / `LIMIT_TIME_REAL` | `60` / `120` | |
| `LIMIT_MEMORY_SOFT` / `LIMIT_MEMORY_HARD` | 2 GiB / 2.5 GiB | por worker |
| `LIMIT_MEMORY_*_GEVENT` | `False` | Odoo 20 ignora "False" en opciones int (solo avisa) → hereda el límite normal |
| `PROXY_MODE` | `True` | correcto detrás de un proxy |
| `LIST_DB` | `False` | gestor de BD deshabilitado ✅ |
| `ADMIN_PASSWD` | `odoo` | ⚠️ **cambiar siempre** |
| `DB_FILTER` | `""` | ⚠️ la doc dice `.*`. Producción: `^<db>$` |
| `WITHOUT_DEMO` | `True` | ⚠️ la doc lo describe al revés; `True` = **sin** demo ✅ |
| `RUNNING_ENV` | `development` | ⚠️ poner `production` |
| `LOG_LEVEL` / `LOG_HANDLER` / `LOG_DB` / `LOGFILE` | `info` / `:INFO` / – / `None` | Dejar log a stdout (Docker lo recoge) |
| `SERVER_WIDE_MODULES` | `base,web,` + valor | |
| `MODULE_AUTO_INSTALL_DISABLED` | – | requiere `module_change_auto_install` |
| `AUTO_UPDATE_MODULES_LIST` / `AUTO_UPDATE_TRANSLATIONS` | `False` | Se ejecutan en **cada** arranque |
| `ADDITIONAL_ODOO_RC` | – | Texto libre añadido a `[options]` (para `x_sendfile`, `limit_time_real_cron`, etc.) |
| `IR_CONFIG_PARAMETER` | – | Sección `[ir.config_parameter]` (p. ej. `web.base.url = https://...`) |

### Correo
- **Config de servidor** (`odoo.conf`): `SMTP_SERVER`, `SMTP_PORT`, `SMTP_SSL`, `SMTP_USER`, `SMTP_PASSWORD`, `EMAIL_FROM`.
- **Registros en la BD** (los crea `init-db` vía `setup-mail`): `ODOO_MAIL_SMTP_HOST|PORT|ENCRYPTION|FROM_FILTER`, `ODOO_MAIL_IMAP_HOST|PORT|SSL`, `ODOO_MAIL_PASSWORD`.
  - ⚠️ El usuario se lee de **`ODOO_MAIL_USER`**, no de `ODOO_MAIL_USERNAME` como dice la doc.
- **Parámetros/alias**: `MAIL_BOUNCE_ALIAS`, `MAIL_CATCHALL_ALIAS`, `MAIL_CATCHALL_DOMAIN`, `MAIL_DEFAULT_FROM`, `MAIL_ALIAS_DOMAIN` (crea `mail.alias.domain`).

### Addons y git
| Variable | Uso |
|---|---|
| `ADDONS_GIT_REPOS` | Lista (coma o salto de línea): `url#rama#commit`. La rama por defecto es la versión de Odoo. Se clona en `/var/lib/odoo/git/<host>/<path>` |
| `GITHUB_USERNAME`/`GITHUB_PAT`, `GITLAB_*`, `FORGEJO_*` | Credenciales https (repos privados, descarga de Enterprise) |
| `GIT_SSH_PRIVATE_KEY` (base64), `GIT_SSH_PUBLIC_KEY`, `SSH_ID_ALGORITHM`, `GIT_SSH_CONFIG` | Clonado por ssh. La clave se borra después de clonar |
| `GIT_CLONE_DEPTH` | por defecto `999` |
| `ODOO_ENTERPRISE_URL` / `ODOO_ENTERPRISE_REF` / `ODOO_ENTERPRISE_PATH` | Enterprise fijado al commit de la revisión; por defecto en `/var/lib/odoo/enterprise` |
| `ODOO_ADDONS_PATH` | Rutas extra a escanear |

`addons_path` final = `/opt/odoo/addons` + enterprise + `/var/lib/odoo/git` + `/mnt/extra-addons` + `ODOO_ADDONS_PATH`, incluyendo solo las carpetas cuyos manifiestos tienen una versión compatible (`20.0.x.y.z` o `x.y[.z]`).

### Inicialización (`init-db`)
`ODOO_INIT_LOGIN` (`admin`), `ODOO_INIT_PASSWORD` (`admin`), `ODOO_INIT_LANG` (`en_US`), `ODOO_INIT_ADDONS` (`web`).
Es idempotente: crea la BD si no existe, la inicializa si falta `ir_module_module`, cambia el login y la contraseña del usuario id 2 y configura el correo.

## 4. Scripts del contenedor (`docker compose exec odoo <script>`)

| Script | Qué hace |
|---|---|
| `config` | Muestra el `odoo.conf` generado |
| `init-db [db]` | Crea e inicializa la BD (ver arriba) |
| `init-module <mods> [db]` | `odoo -i mods --stop-after-init --no-http` |
| `update-module <mods> [db]` | `odoo -u mods --stop-after-init --no-http` |
| `update-modules [db]` | `click-odoo-update`: actualiza **solo los módulos cuyo checksum cambió** |
| `update-modules-list [db]` / `update-translations [db]` | Lo que indican sus nombres |
| `clone-git-addons` | Clona o hace pull de `ADDONS_GIT_REPOS` (y sus submódulos) |
| `aggregate-git-repos` | `gitaggregate` sobre `/var/lib/odoo/git/repos.yml` |
| `download-odoo-enterprise` | Descarga Enterprise (tarball con PAT, o git con ssh) solo si cambió el ref |
| `download-odoo-openupgrade` | OpenUpgrade de la versión en curso |
| `list-databases`, `check-database-initialized`, `wait-for-pg` | Utilidades |
| `manifestoo ...` | Consultas de dependencias |
| `setup-tests` / `run-tests` | ⚠️ Rotos: apuntan a `/opt/odoo-venv/bin/odoo`, que ya no existe |

## 5. Nginx embebido: qué hace y qué NO hace

Se activa con `command: odoo-nginx`. Usa `/etc/nginx/nginx.conf` (se puede reemplazar montando un archivo propio).

**Hace:**
- Escucha en `:8080` (todas las interfaces del contenedor).
- `/` → `127.0.0.1:8069`; `/websocket` → `127.0.0.1:8072`, con Upgrade/Connection.
- Cachea los estáticos (`jpg|css|js|woff…`) 60 min en `/var/cache/nginx/odoo`, con `expires 30d`.
- gzip, `client_max_body_size 4G`, timeouts de 720 s, `large_client_header_buffers 4 12k` (evita un 414 en el login con muchos módulos).

**NO hace (importante para producción):**
- ❌ **No hay TLS/HTTPS**, ni puerto 443, ni Let's Encrypt.
- ❌ No hay `server_name`: no sabe nada de tu dominio.
- ❌ Fija `X-Forwarded-Proto "https"` siempre, es decir, **da por hecho que delante hay un terminador TLS**.
- ❌ Usa `$proxy_add_x_forwarded_for` y `X-Real-IP $remote_addr`. Odoo 20 aplica `ProxyFix(x_for=1)`, que se queda con el **último** salto, así que detrás de otro proxy Odoo vería la IP del proxy y no la del cliente: los logs de login y fail2ban quedarían inútiles. Se arregla con `real_ip` en un `nginx.conf` propio.
- ❌ No tiene HSTS, `proxy_cookie_flags`, rate limiting ni bloqueo de `/web/database`.
- ❌ Escribe logs en `/var/log/nginx/odoo.*.log` dentro del contenedor (además de stdout).

**Conclusión de diseño:** el nginx embebido es un *sidecar* para enrutar el websocket y cachear estáticos, **no un borde de Internet**. Hace falta un terminador TLS delante (Caddy o Traefik) que reciba el dominio y la IP. Ventaja extra: al compartir contenedor con Odoo, puede servir el filestore por **X-Accel** (`x_sendfile`), cosa imposible con un proxy en otro contenedor.

## 6. Requisitos de Odoo 20 relevantes (código y documentación oficial)

- **PostgreSQL ≥ 16** (`MIN_PG_VERSION = 16`). Python 3.12–3.14.
- **`http_interface` por defecto `127.0.0.1`** (nuevo): dentro del contenedor Odoo solo escucha en loopback. Con `odoo-nginx` eso es justo lo que queremos (solo se expone el 8080). Si se publica el 8069 directamente, hay que pasar `--http-interface=0.0.0.0`; el compose "Minimal" de la doc de Mint no lo hace y **no funcionaría** en 20.
- Demo desactivada por defecto (`--with-demo` / `--without-demo`).
- Workers: regla `(CPU × 2) + 1`; 1 worker ≈ 6 usuarios concurrentes. RAM ≈ `workers × (0.8×150 MB + 0.2×1 GB)`.
- Ejemplo oficial (4 CPU, 60 usuarios): `workers = 8`, `max_cron_threads = 1`, `limit_memory_soft = 629145600`, `limit_memory_hard = 1677721600`, `limit_time_cpu = 600`, `limit_time_real = 1200`, `limit_request = 8192`.
- Websocket: en modo multiproceso hay que enrutar `/websocket` al `gevent_port` (8072) y activar `proxy_mode`.
- HTTPS obligatorio, redirección http→https, **HSTS** y `proxy_cookie_flags session_id samesite=lax secure`.
- Estáticos y adjuntos: servirlos desde el proxy (`/<mod>/static/`) y X-Accel para `/web/filestore` con `--x-sendfile`.
- Seguridad: `list_db = False`, `admin_passwd` aleatorio, `dbfilter` que resuelva una sola BD, usuario PG **sin superusuario**, sin datos demo, login distinto de `admin`, fail2ban sobre `Login failed for db:... from <HOST>`, backups diarios de la BD y del filestore **fuera del servidor**.
- Opciones solo de archivo nuevas: `websocket_keep_alive_timeout` (3600), `websocket_rate_limit_burst` (10), `websocket_rate_limit_delay` (0.2); `limit_time_real_cron`, `limit_time_worker_cron`, `db_replica_host`.

## 7. Defectos y trampas detectados en la imagen

1. **Los secretos `_FILE` no funcionan.** `check_config` evalúa `[[ -f "$file_var" ]]` sobre el *nombre* de la variable (`"db_password_FILE"`), no sobre su valor. Además, los scripts (`init-db`, `psql`) usan `PGPASSWORD` del entorno. → Usar `.env` con permisos `600`.
2. **`ODOO_MAIL_USERNAME` no se lee**: hay que usar `ODOO_MAIL_USER`.
3. **Fallos silenciosos**: `init-db`, `init-module`, `update-module`, `update-modules` y demás terminan con `|| true`, así que **devuelven 0 aunque Odoo falle**. En los despliegues hay que validar el log (buscar `ERROR`/`CRITICAL`), no el código de salida.
4. **`init-db` mete la contraseña dentro de un heredoc de Python** entre comillas simples: una contraseña con `'` lo rompe. Evitar `'`, `"` y `\` en `ODOO_INIT_PASSWORD`, o cambiarla después desde la UI.
5. `setup-tests`/`run-tests` apuntan a una ruta de venv antigua (no afecta a producción).
6. El valor por defecto `WORKERS=0` es incompatible con el nginx embebido.
7. `ADMIN_PASSWD=odoo` y `RUNNING_ENV=development` por defecto.
8. Las variables sensibles (`PGPASSWORD`, PAT, claves ssh) quedan visibles en `docker inspect`. Aceptable en un host propio con acceso restringido a Docker; documentarlo.
9. `AUTO_UPDATE_*` se ejecuta contra la BD en **cada** reinicio: mejor dejarlo en `False` en producción y actualizar de forma explícita en cada despliegue.
10. `limit_time_real` de Odoo (120 s) frente a los 720 s del nginx: el límite efectivo de una petición es el de Odoo.

## 8. Rutas internas

| Ruta | Contenido | Persistir |
|---|---|---|
| `/etc/odoo/odoo.conf` | Generado en cada arranque | no |
| `/var/lib/odoo` | `filestore/`, `sessions/`, `git/`, `enterprise/`, `requirements.txt` | **sí (volumen)** |
| `/mnt/extra-addons` | Módulos propios (se escanean anidados) | bind mount / imagen |
| `/opt/odoo`, `/opt/odoo/addons`, `/opt/odoo/venv` | Fuente de Odoo, módulos community, venv | no (imagen) |
| `/home/odoo` | HOME (`.ssh`, `.gitconfig`) | no |
| `/var/cache/nginx/odoo` | Caché de estáticos | opcional (tmpfs) |

## 9. Imágenes auxiliares de Mint System

- `mintsystem/odoo-mailgate`: Postfix + `odoo-mailgate` para recibir correo entrante por SMTP (25/587) y reenviarlo a Odoo. Es una alternativa a IMAP (`fetchmail`).
- `mintsystem/odoo-upgrade`: ejecuta el script oficial `upgrade.odoo.com` (migraciones Enterprise).
- `mintsystem/odoo-cli` / `odoo-mcp`: clientes XML-RPC y MCP.
