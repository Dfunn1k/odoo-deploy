# shellcheck shell=bash
# Funciones comunes de los scripts del host. Se carga con: source scripts/lib.sh

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

log() {
    printf '\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
    printf '\033[1;33mAVISO:\033[0m %s\n' "$*" >&2
}

die() {
    printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2
    exit 1
}

# env-get <VAR>: lee una variable del .env sin ejecutarlo como script.
env-get() {
    local line
    line=$(grep -E "^$1=" .env 2>/dev/null | tail -n 1) || true
    line=${line#*=}
    line=${line%\"}
    line=${line#\"}
    printf '%s' "$line"
}

# env-set <VAR> <valor>: crea o reemplaza una variable en el .env.
env-set() {
    local key=$1
    local value=$2
    local tmp line found=0
    tmp=$(mktemp)
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == "$key="* ]]; then
            printf '%s=%s\n' "$key" "$value"
            found=1
        else
            printf '%s\n' "$line"
        fi
    done < .env > "$tmp"
    (( found )) || printf '%s=%s\n' "$key" "$value" >> "$tmp"
    cat "$tmp" > .env
    rm -f "$tmp"
}

require-env() {
    [[ -f .env ]] || die 'Falta el archivo .env. Ejecuta primero: scripts/setup-env.sh'
    [[ -f secrets/github_token ]] || { mkdir -p secrets && install -m 600 /dev/null secrets/github_token; }
}

# db-exists: éxito si la base de producción ya existe en Postgres.
db-exists() {
    local db
    db=$(env-get DB_NAME)
    [[ "$(docker compose exec -T db psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$db'" 2>/dev/null)" == '1' ]]
}

# ensure-db: crea la base de producción como superusuario y le agrega las extensiones.
# El usuario "odoo" no es superusuario, así que no puede crear extensiones no confiables
# como "vector" (pgvector, para la IA de Odoo). Se crea la base igual que lo haría Odoo
# (UTF8, collate C, template0) y, como Odoo ya no la crea, también se crea pg_trgm.
# Es idempotente: se puede ejecutar en cada despliegue.
ensure-db() {
    local db owner
    db=$(env-get DB_NAME)
    owner=$(env-get ODOO_DB_USER)
    owner=${owner:-odoo}

    if ! db-exists; then
        log "Creando la base '$db'..."
        docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -v db="$db" -v owner="$owner" <<'SQL'
CREATE DATABASE :"db" OWNER :"owner" ENCODING 'unicode' LC_COLLATE 'C' TEMPLATE template0;
SQL
    fi

    docker compose exec -T db psql -U postgres -v ON_ERROR_STOP=1 -q -d "$db" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
SQL
}
