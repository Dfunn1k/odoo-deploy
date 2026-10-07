#!/usr/bin/env bash
# Backup de la base (pg_dump en formato custom) y del filestore.
# Deja todo en $BACKUP_DIR/<fecha>/ y, si BACKUP_RCLONE_REMOTE está definido, lo copia fuera del servidor.
# La última línea de la salida es la ruta del backup (la usa deploy.sh).
#
# Cron diario sugerido (crontab -e como root):
#   0 3 * * * /ruta/al/proyecto/scripts/backup.sh >> /var/log/odoo-backup.log 2>&1
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require-env
db=$(env-get DB_NAME)
backup_root=$(env-get BACKUP_DIR)
backup_root=${backup_root:-/var/backups/odoo}
retention=$(env-get BACKUP_RETENTION_DAYS)
remote=$(env-get BACKUP_RCLONE_REMOTE)
dest="$backup_root/$(date +%Y%m%d-%H%M%S)"

mkdir -p "$dest"
chmod 700 "$backup_root" "$dest"

log "Backup de la base '$db'..." >&2
docker compose exec -T db pg_dump -U postgres -Fc -d "$db" > "$dest/db.dump"

log 'Backup del filestore...' >&2
docker compose run --rm --no-deps -T --entrypoint bash odoo -c \
    "if [[ -d /var/lib/odoo/filestore/$db ]]; then tar -C /var/lib/odoo/filestore -czf - '$db'; fi" \
    > "$dest/filestore.tar.gz"

# Qué código estaba en producción al momento del backup.
docker compose run --rm --no-deps -T --entrypoint cat odoo /opt/odoo-addons/MANIFEST > "$dest/MANIFEST" || true

if [[ -n "$remote" ]]; then
    log "Copiando a $remote ..." >&2
    rclone copy "$dest" "$remote/$(basename "$dest")"
fi

if [[ -n "$retention" ]]; then
    find "$backup_root" -mindepth 1 -maxdepth 1 -type d -mtime +"$retention" -exec rm -rf {} +
fi

log "Backup completo ($(du -sh "$dest" | cut -f1))" >&2
echo "$dest"
