#!/usr/bin/env bash
# Despliegue completo (sirve igual para la primera vez y para actualizaciones):
#   1. Construye una imagen nueva (odoo-prod:<fecha>) sin tocar la que está en servicio.
#   2. Levanta Postgres.
#   3. Backup de la base y del filestore (si la base ya existe).
#   4. Detiene Odoo (ventana de mantenimiento: de segundos a pocos minutos).
#   5. odoo-init (crea la base la primera vez) + odoo-update (módulos que cambiaron).
#   6. Activa la imagen nueva (current) y guarda la anterior (previous) para rollback.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require-env
tag=$(date +%Y%m%d-%H%M%S)
backup_hint='(no se hizo backup: la base era nueva)'

on-error() {
    warn "El despliegue falló. La imagen en servicio NO se cambió (odoo-prod:current)."
    warn "Para volver a levantar Odoo como estaba: docker compose up -d"
    warn "Si la base quedó a medio actualizar, restaura el backup: scripts/restore.sh <dir> $backup_hint"
}
trap on-error ERR

log "1/6 Construyendo la imagen odoo-prod:$tag ..."
IMAGE_TAG=$tag docker compose build --pull odoo

log '2/6 Levantando Postgres...'
docker compose up -d --wait db

if db-exists; then
    log '3/6 Backup previo al despliegue...'
    backup_dir=$(scripts/backup.sh | tail -n 1)
    backup_hint="(backup previo: $backup_dir)"
else
    log '3/6 La base aún no existe: se omite el backup.'
fi
ensure-db

log '4/6 Deteniendo Odoo...'
docker compose stop odoo

log '5/6 Inicializando / actualizando la base...'
IMAGE_TAG=$tag docker compose run --rm --no-deps odoo odoo-init
IMAGE_TAG=$tag docker compose run --rm --no-deps odoo odoo-update

log '6/6 Activando la imagen nueva...'
if docker image inspect odoo-prod:current >/dev/null 2>&1; then
    docker tag odoo-prod:current odoo-prod:previous
fi
docker tag "odoo-prod:$tag" odoo-prod:current
docker compose up -d --wait

# Conserva las 3 imágenes más recientes (además de current y previous).
docker image ls odoo-prod --format '{{.Tag}}' \
    | grep -E '^[0-9]{8}-[0-9]{6}$' | sort -r | tail -n +4 \
    | xargs -r -I{} docker rmi "odoo-prod:{}" >/dev/null

trap - ERR
log "Desplegado: odoo-prod:$tag -> https://$(env-get DOMAIN)"
