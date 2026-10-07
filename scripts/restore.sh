#!/usr/bin/env bash
# Restaura un backup hecho con backup.sh. REEMPLAZA la base y el filestore actuales.
# Uso: scripts/restore.sh /var/backups/odoo/<fecha>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require-env
src=${1:?Uso: scripts/restore.sh <directorio-de-backup>}
[[ -f "$src/db.dump" ]] || die "No existe $src/db.dump"
db=$(env-get DB_NAME)
odoo_user=$(env-get ODOO_DB_USER)
odoo_user=${odoo_user:-odoo}

warn "Se va a REEMPLAZAR la base '$db' y su filestore con el backup $src."
read -r -p "Escribe el nombre de la base para confirmar: " confirm
[[ "$confirm" == "$db" ]] || die 'Confirmación incorrecta. No se hizo nada.'

log 'Deteniendo Odoo...'
docker compose stop odoo
docker compose up -d --wait db

log 'Restaurando la base...'
docker compose exec -T db dropdb -U postgres --if-exists "$db"
ensure-db
docker compose exec -T db pg_restore -U postgres -d "$db" --no-owner --role="$odoo_user" < "$src/db.dump"

log 'Restaurando el filestore...'
docker compose run --rm --no-deps -T --entrypoint bash odoo -c \
    "rm -rf '/var/lib/odoo/filestore/$db' && mkdir -p /var/lib/odoo/filestore"
if [[ -s "$src/filestore.tar.gz" ]]; then
    docker compose run --rm --no-deps -T --entrypoint tar odoo -C /var/lib/odoo/filestore -xzf - \
        < "$src/filestore.tar.gz"
fi

log 'Levantando Odoo...'
docker compose up -d --wait
log 'Restauración completa.'
