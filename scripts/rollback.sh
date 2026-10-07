#!/usr/bin/env bash
# Vuelve a la imagen anterior (odoo-prod:previous).
# Si el despliegue fallido ya había actualizado módulos, restaura también la base:
#   scripts/restore.sh <backup previo al despliegue>
set -euo pipefail
source "$(dirname "$0")/lib.sh"

docker image inspect odoo-prod:previous >/dev/null 2>&1 || die 'No hay imagen previa (odoo-prod:previous).'

log 'Activando odoo-prod:previous...'
docker tag odoo-prod:current odoo-prod:rollback-from 2>/dev/null || true
docker tag odoo-prod:previous odoo-prod:current
docker compose up -d --wait odoo
log 'Rollback completo. La imagen descartada quedó como odoo-prod:rollback-from.'
