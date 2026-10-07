#!/usr/bin/env bash
# Crea o completa el .env de forma interactiva:
#   - pregunta el dominio, el email y los datos del administrador
#   - genera las contraseñas que falten (hex: sin caracteres problemáticos)
#   - guarda el token de GitHub en secrets/github_token
#   - calcula el tuning de Postgres según la RAM de ESTE servidor
# Se puede volver a ejecutar: no pisa los valores existentes salvo los que confirmes.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ask() {
    local var=$1
    local prompt=$2
    local current answer
    current=$(env-get "$var")
    read -r -p "$prompt [${current}]: " answer
    if [[ -n "$answer" ]]; then
        env-set "$var" "$answer"
    fi
}

ensure-secret() {
    if [[ -z "$(env-get "$1")" ]]; then
        env-set "$1" "$(openssl rand -hex 24)"
        log "Generada $1"
    fi
}

if [[ ! -f .env ]]; then
    install -m 600 .env.example .env
    log 'Creado .env a partir de .env.example'
fi
chmod 600 .env

ask DOMAIN 'Dominio (el registro DNS A debe apuntar a la IP de este servidor)'
ask ACME_EMAIL 'Email para Let'"'"'s Encrypt'
ask DB_NAME 'Nombre de la base de datos'
[[ "$(env-get DB_NAME)" =~ ^[a-zA-Z0-9_-]+$ ]] || die 'DB_NAME solo admite letras, números, _ y -'
ask ODOO_ADMIN_LOGIN 'Login del administrador de Odoo (email)'
ask ODOO_INIT_LANG 'Idioma inicial'
ask ODOO_ENTERPRISE '¿Enterprise? (true/false)'

for var in POSTGRES_PASSWORD ODOO_DB_PASSWORD ADMIN_PASSWD ODOO_ADMIN_PASSWORD; do
    ensure-secret "$var"
done

mkdir -p secrets
chmod 700 secrets
[[ -f secrets/github_token ]] || install -m 600 /dev/null secrets/github_token
read -r -s -p 'Token de GitHub (Enter para mantener el actual / no usar): ' token
echo
if [[ -n "$token" ]]; then
    printf '%s' "$token" > secrets/github_token
    chmod 600 secrets/github_token
    log 'Token guardado en secrets/github_token'
fi
if [[ "$(env-get ODOO_ENTERPRISE)" == 'true' && ! -s secrets/github_token ]]; then
    warn 'ODOO_ENTERPRISE=true necesita un token con acceso a github.com/odoo/enterprise.'
fi

# Tuning de Postgres: ~20 % de la RAM a shared_buffers y ~50 % como caché estimada.
mem_mb=$(awk '/^MemTotal:/ {print int($2 / 1024)}' /proc/meminfo)
maintenance=$(( mem_mb / 20 ))
(( maintenance <= 1024 )) || maintenance=1024
env-set PG_SHARED_BUFFERS "$(( mem_mb / 5 ))MB"
env-set PG_EFFECTIVE_CACHE_SIZE "$(( mem_mb / 2 ))MB"
env-set PG_MAINTENANCE_WORK_MEM "${maintenance}MB"
env-set PG_WORK_MEM "$( (( mem_mb >= 8192 )) && echo 32MB || echo 16MB )"
log "Postgres ajustado para ${mem_mb} MB de RAM y $(nproc) CPU. Los workers de Odoo se calculan al arrancar (WORKERS=auto)."

log ".env listo. Credenciales del administrador de Odoo:"
echo "    login:      $(env-get ODOO_ADMIN_LOGIN)"
echo "    contraseña: $(env-get ODOO_ADMIN_PASSWORD)"
warn 'Guarda esa contraseña en tu gestor de contraseñas. Siguiente paso: scripts/deploy.sh'
