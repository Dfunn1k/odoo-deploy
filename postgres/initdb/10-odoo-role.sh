#!/usr/bin/env bash
# Se ejecuta UNA sola vez, cuando se crea el volumen de datos de Postgres.
# Crea el rol de Odoo SIN superusuario (recomendación oficial de Odoo).
# CREATEDB es necesario para que odoo-init cree la base de producción.
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -v odoo_user="$ODOO_DB_USER" -v odoo_password="$ODOO_DB_PASSWORD" <<'SQL'
CREATE ROLE :"odoo_user" LOGIN CREATEDB NOSUPERUSER NOCREATEROLE PASSWORD :'odoo_password';
SQL
