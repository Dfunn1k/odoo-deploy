# Odoo 20: servidor de producción

Stack de producción para una VPS: imagen propia de Odoo construida sobre la **imagen oficial**
(`odoo:20.0-<fecha>`), Enterprise opcional, addons de terceros, HTTPS automático, backups y despliegue
con rollback.

```
Internet ──:80/:443──► caddy ─── HTTPS automático (Let's Encrypt), HSTS, bloquea /web/database
                         │
                         ├─ /websocket* ──► odoo:8072   (worker gevent: chat, notificaciones)
                         └─ /*          ──► odoo:8069   (workers HTTP)
                                              │  red interna, sin salida a Internet
                                              ▼
                                           postgres:17 + pgvector  (rol "odoo" sin superusuario)
```

## Glosario

Palabras en inglés que aparecen en este proyecto (son nombres técnicos que no se traducen):

| Palabra | Significado |
|---|---|
| imagen (*image*) | "Molde" de Docker con Odoo y todo lo necesario ya instalado |
| contenedor (*container*) | Una imagen en ejecución |
| *build* / construir | Fabricar la imagen a partir del `Dockerfile` |
| *deploy* / desplegar | Poner en producción una versión nueva |
| *rollback* | Volver a la versión anterior |
| *backup* | Copia de seguridad |
| repo / repositorio | Proyecto de código guardado en GitHub |
| rama (*branch*) | Línea de versiones de un repo, p. ej. `20.0` |
| *commit* | Una versión exacta del código (un código largo como `046ebfe...`) |
| *nightly* | Versión de Odoo publicada cada noche |
| *token* / PAT | Contraseña especial de GitHub para que un programa descargue código en tu nombre |
| SSH | Otra forma de conectarse a GitHub o al servidor, con un par de llaves |
| proxy | Programa que recibe las visitas de Internet y se las pasa a Odoo |
| *workers* | Procesos de Odoo que atienden a los usuarios a la vez |
| *filestore* | Carpeta donde Odoo guarda los archivos adjuntos |
| DNS / registro A | Configuración del dominio que dice a qué IP apunta |

## Estructura

```
.
├── compose.yml              # caddy + odoo + postgres
├── .env.example             # plantilla de configuración (el .env real no va a git)
├── image/
│   ├── Dockerfile           # FROM odoo oficial + enterprise + addons + dependencias
│   ├── build/fetch-addons   # descarga de código en el build (usa el token)
│   └── bin/                 # scripts dentro del contenedor: odoo-init, odoo-update, odoo-install...
├── addons/
│   ├── repos.txt            # QUÉ repos de módulos se descargan (url, rama, commit)
│   ├── requirements.txt     # dependencias Python extra
│   └── custom/              # módulos locales sin repo (opcional)
├── caddy/Caddyfile          # dominio y proxy
├── postgres/initdb/         # crea el rol de Odoo la primera vez
├── server/fail2ban/         # bloqueo de IPs por logins fallidos
├── secrets/github_token     # token de GitHub (no va a git)
├── scripts/                 # bootstrap-vps, setup-env, deploy, backup, restore, rollback
└── docs/                    # referencia y decisiones
```

## Decisiones de diseño

| Tema | Decisión | Por qué |
|---|---|---|
| Imagen | Propia, `FROM odoo:20.0-<fecha>` oficial | Odoo S.A. mantiene el SO y Odoo; nosotros solo la capa de addons y scripts. Ver [docs/01](docs/01-referencia-imagen-mintsystem.md) |
| Dónde se construye | **En el propio servidor** | Con Enterprise dentro, la imagen es privada y no puede ir a un registro público. Construir en el servidor evita registros, CI y credenciales extra. El token solo vive en esa máquina |
| Cuándo se descargan los addons | **En el build**, no al arrancar | Si GitHub o PyPI fallan, Odoo igual arranca; dos arranques usan el mismo código; el rollback es cambiar de imagen |
| Compatibilidad Community/Enterprise | Enterprise = último commit **anterior** a la fecha de la imagen base | El nightly oficial sale de madrugada (UTC) de esa fecha: Enterprise queda a lo sumo unas horas detrás, nunca delante. Se puede fijar a mano con `ODOO_ENTERPRISE_REF` |
| Autenticación con GitHub | **Token clásico (PAT)** por HTTPS, como secreto de build | Ver la sección [Token de GitHub](#token-de-github) |
| Proxy | Caddy en un solo salto | Certificados automáticos y la IP real del cliente llega a Odoo (logs y fail2ban) |
| IA de Odoo (pgvector) | Imagen `pgvector/pgvector:<versión>-pg17` y la base se crea como superusuario con las extensiones `vector` y `pg_trgm` | La documentación oficial de Odoo 20 exige pgvector para las funciones de IA, y como `vector` no es una extensión "confiable", el usuario `odoo` (sin superusuario) no puede crearla |
| Workers | `WORKERS=auto` | Se calculan al arrancar según CPU y RAM: `min((CPU×2)+1, RAM×0.5 / 325 MB)` |

## Token de GitHub

El token es una **contraseña especial de GitHub** que permite que un programa descargue código en
tu nombre. En este proyecto se usa para tres cosas:

1. Descargar **este proyecto** en la VPS (si lo guardas en un repo privado de GitHub).
2. Descargar **Odoo Enterprise** (si `ODOO_ENTERPRISE=true`).
3. Descargar tus **repos privados de módulos** (los de `addons/repos.txt`).

**Un solo token sirve para las tres.** Si solo usas Community y repos públicos, no lo necesitas.

### ¿Por qué un token "clásico" y no SSH?

- Odoo te da acceso a Enterprise invitándote como "colaborador externo". Según la documentación de
  GitHub, el token de tipo nuevo (*fine-grained*) no sirve en ese caso. Por eso tiene que ser el **clásico**.
- Una llave SSH da el mismo acceso, pero nunca vence. El token se puede hacer vencer y anular en
  cualquier momento.
- El token solo se usa mientras se fabrica la imagen: **no queda guardado dentro de la imagen**.

### Paso 1: comprobar que tienes acceso a Enterprise

Solo si vas a usar Enterprise. Entra con tu usuario en https://github.com/odoo/enterprise.
Si ves el código, tienes acceso. Si ves "404", todavía no tienes acceso o no aceptaste la
invitación de Odoo: revisa tu correo o https://github.com/notifications.

### Paso 2: crear el token

GitHub está en inglés; entre paréntesis va la traducción.

1. Entra en https://github.com e inicia sesión.
2. Arriba a la derecha, haz clic en **tu foto** → **Settings** (Configuración).
3. En el menú de la izquierda, abajo del todo: **Developer settings** (Opciones de desarrollador).
4. **Personal access tokens** (Tokens de acceso personal) → **Tokens (classic)**.
5. Botón **Generate new token** (Generar nuevo token) → **Generate new token (classic)**.
   GitHub puede pedirte la contraseña o el código de verificación en dos pasos.
6. Completa el formulario:
   - **Note** (Nota): un nombre para reconocerlo, p. ej. `odoo-vps-cliente1`.
   - **Expiration** (Vencimiento): **90 days** (90 días). GitHub te avisa por correo antes de que venza.
   - **Select scopes** (Permisos): marca **solo `repo`**. Las casillas de debajo se marcan solas. No marques nada más.
7. Abajo del todo: **Generate token** (Generar token).
8. **Copia el token ahora.** Empieza por `ghp_...` y GitHub **no lo vuelve a mostrar**.
   Guárdalo en tu gestor de contraseñas (Bitwarden, 1Password, KeePass...).

> El token da acceso a todos tus repos: trátalo como una contraseña. No lo pegues en chats ni en
> archivos que se suban a GitHub. Para varios clientes, lo ideal es una cuenta de GitHub aparte
> (tipo "bot"), invitada a Enterprise y a tus repos solo con permiso de lectura.

### Paso 3: configurarlo en la VPS

Conéctate a la VPS (`ssh root@<IP>`) y sigue estos pasos.

**a) Para descargar este proyecto** (solo si está en un repo privado de GitHub):

```bash
git config --global credential.helper store
git clone https://github.com/<tu-usuario>/<este-repo>.git /opt/odoo
```

Git te pedirá dos datos:
- `Username:` tu usuario de GitHub.
- `Password:` **pega el token** (no tu contraseña de GitHub). Al pegarlo no se ve nada en pantalla: es normal.

Con `credential.helper store`, Git lo guarda en `/root/.git-credentials` y no lo vuelve a pedir en
cada `git pull`.

**b) Para Enterprise y tus módulos privados:**

```bash
cd /opt/odoo
scripts/setup-env.sh
```

Cuando pregunte `Token de GitHub`, pega el mismo token y pulsa Enter. Se guarda en
`secrets/github_token`, con permisos que solo deja leerlo a root, y no se sube a GitHub.

**c) Comprobar que funciona:**

```bash
scripts/check-token.sh
```

Muestra de quién es el token, cuándo vence y si tiene acceso a Enterprise y a cada repo de
`addons/repos.txt`. Si algo sale "SIN ACCESO", corrígelo antes de desplegar.

### Cuando el token vence (o si se filtró)

1. Crea uno nuevo (Paso 2). Si se filtró, en la misma página de GitHub pulsa **Delete**
   (Eliminar) sobre el token viejo para anularlo al instante.
2. En la VPS, actualiza los dos lugares donde está guardado:
   ```bash
   cd /opt/odoo
   scripts/setup-env.sh        # pega el token nuevo cuando lo pida (Enter en lo demás)
   rm /root/.git-credentials   # el próximo git pull pedirá usuario y token nuevo
   scripts/check-token.sh      # comprobar
   ```

Odoo sigue funcionando aunque el token venza: solo hace falta para descargar código (`git pull`
y `scripts/deploy.sh`).

## Puesta en marcha (VPS nueva)

**Antes de empezar**
1. VPS con Ubuntu 24.04 (o Debian 12). Mínimo 2 vCPU / 4 GB; con Enterprise y varios usuarios, 4 vCPU / 8 GB.
2. En el DNS del dominio, crea un **registro A** que apunte el dominio (p. ej. `erp.miempresa.pe`)
   a la **IP de la VPS**. La IP no se configura en ningún archivo del proyecto: solo en el DNS.
   Comprueba que ya resuelve con `dig +short erp.miempresa.pe`.
3. El token de GitHub, si lo necesitas (ver [Token de GitHub](#token-de-github), Pasos 1 y 2).

**1. Subir el proyecto al servidor** (repo privado: en `Password` va el token, ver [Paso 3a](#paso-3-configurarlo-en-la-vps))
```bash
ssh root@<IP>
git config --global credential.helper store
git clone https://github.com/<tu-usuario>/<este-repo>.git /opt/odoo
cd /opt/odoo
```

**2. Preparar el servidor** (Docker, firewall, swap, fail2ban, actualizaciones automáticas). Una sola vez:
```bash
scripts/bootstrap-vps.sh
```

**3. Configurar** (dominio, administrador, Enterprise, token; genera las contraseñas y ajusta Postgres a la RAM):
```bash
scripts/setup-env.sh
```

**4. Elegir los módulos:** edita `addons/repos.txt` (y `addons/requirements.txt` si hace falta).
Después comprueba que el token tiene acceso a todo:
```bash
scripts/check-token.sh
```

**5. Desplegar:**
```bash
scripts/deploy.sh
```
La primera vez tarda varios minutos (descarga la imagen base, Enterprise y los repos, y crea la base).
Al terminar, entra en `https://<dominio>` con el login y la contraseña que mostró `setup-env.sh`.

**6. Backups diarios** (`crontab -e` como root):
```
0 3 * * * /opt/odoo/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
```
Para copiarlos fuera del servidor (muy recomendado): configura un destino con `rclone config`
(S3, Backblaze B2, Google Drive, otro servidor por SFTP...) y ponlo en `BACKUP_RCLONE_REMOTE` del `.env`.

## Detrás de Cloudflare

Si el dominio pasa por Cloudflare (nube naranja):

- En Cloudflare, **SSL/TLS → modo Full (strict)**. Caddy obtiene su certificado por HTTP-01 (puerto 80),
  que sí atraviesa Cloudflare; el reto TLS-ALPN está desactivado en el `Caddyfile` porque no llega.
- El `Caddyfile` solo acepta la IP real del cliente (`CF-Connecting-IP`) cuando la conexión viene de
  una IP de Cloudflare. Si Cloudflare publica rangos nuevos, actualízalos en `trusted_proxies`.
- La jail `odoo-login` de fail2ban no sirve: las conexiones llegan desde IPs de Cloudflare y bloquear
  la IP real con iptables no tiene efecto. Usa el WAF / rate limiting de Cloudflare.

### Sitios extra en el mismo servidor

Caddy carga además `caddy/sites/*.caddy`. Para enrutar otro stack (p. ej. el QA de Odoo 19), crea
ahí su bloque, une Caddy a la red de ese stack con un override de compose (ver `compose.qa19.yml`)
y actívalo con `COMPOSE_FILE=compose.yml:compose.qa19.yml` en el `.env`.

## Operación

| Tarea | Comando |
|---|---|
| Ver logs | `docker compose logs -f odoo` |
| Estado de los servicios | `docker compose ps` |
| Ver la config generada | `docker compose exec odoo cat /etc/odoo/odoo.conf` |
| Qué código hay en la imagen | `docker compose exec odoo cat /opt/odoo-addons/MANIFEST` |
| Actualizar módulos (nuevos commits, repos nuevos) | edita `addons/repos.txt` → `scripts/deploy.sh` |
| Subir la versión de Odoo | cambia `ODOO_RELEASE` (tags en [Docker Hub](https://hub.docker.com/_/odoo/tags)) → `scripts/deploy.sh` |
| Instalar un módulo | desde *Aplicaciones* en Odoo, o `docker compose exec odoo odoo-install modulo` |
| Shell de Odoo | `docker compose exec odoo odoo shell -d <DB_NAME>` |
| Comprobar el token de GitHub | `scripts/check-token.sh` |
| Backup manual | `scripts/backup.sh` |
| Volver a la imagen anterior | `scripts/rollback.sh` |
| Restaurar un backup | `scripts/restore.sh /var/backups/odoo/<fecha>` |

`deploy.sh` siempre hace backup antes de tocar la base. Si algo falla a mitad de camino, la imagen en
servicio no cambia y el script indica cómo volver atrás.

## Problemas frecuentes

- **No sale el certificado HTTPS**: el registro A del dominio todavía no apunta a la IP, o los
  puertos 80/443 están cerrados en el firewall del proveedor (algunos tienen uno propio en su panel).
  Revisa con `docker compose logs caddy`.
- **502 al entrar**: Odoo todavía está arrancando o falló. Revisa `docker compose logs odoo`.
- **Falla el build al clonar**: la rama no existe en ese repo (muchos repos OCA aún no tienen 20.0)
  o el token no tiene acceso. El mensaje indica el repo.
- **Falta un módulo dependiente**: algún repo de `repos.txt` depende de módulos de otro repo que
  no está en la lista.
