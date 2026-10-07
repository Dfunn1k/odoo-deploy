#!/usr/bin/env bash
# Comprueba el token de GitHub guardado en secrets/github_token:
#   - que es válido, de qué usuario es, qué permisos tiene y cuándo vence
#   - que tiene acceso a odoo/enterprise (si ODOO_ENTERPRISE=true)
#   - que tiene acceso a cada repo de GitHub listado en addons/repos.txt
set -euo pipefail
source "$(dirname "$0")/lib.sh"

require-env
[[ -s secrets/github_token ]] || die 'No hay token en secrets/github_token. Cárgalo con: scripts/setup-env.sh'
token=$(tr -d '[:space:]' < secrets/github_token)

# github-get <ruta> <archivo-cabeceras>: imprime el cuerpo; el token no aparece en la lista de procesos.
github-get() {
    curl -s -D "$2" -H @<(printf 'Authorization: token %s\n' "$token") \
        -H 'Accept: application/vnd.github+json' "https://api.github.com/$1"
}

headers=$(mktemp)
trap 'rm -f "$headers"' EXIT

body=$(github-get user "$headers")
status=$(awk 'NR == 1 {print $2}' "$headers")
case "$status" in
    200) ;;
    401) die 'El token no es válido o ya venció. Crea uno nuevo (ver README, "Token de GitHub").' ;;
    *) die "GitHub respondió $status al validar el token." ;;
esac

login=$(sed -n 's/.*"login": *"\([^"]*\)".*/\1/p' <<< "$body" | head -n 1)
scopes=$(awk -F': ' 'tolower($1) == "x-oauth-scopes" {print $2}' "$headers" | tr -d '\r')
expires=$(awk -F': ' 'tolower($1) == "github-authentication-token-expiration" {print $2}' "$headers" | tr -d '\r')
log "Token válido del usuario: $login"
log "Permisos: ${scopes:-(ninguno)}"
log "Vence: ${expires:-nunca}"
[[ ",${scopes// /}," == *,repo,* ]] || warn 'El token no tiene el permiso "repo": no podrá leer repos privados.'

failed=0
check-repo() {
    local repo=$1
    local code
    code=$(github-get "repos/$repo" "$headers" >/dev/null; awk 'NR == 1 {print $2}' "$headers")
    if [[ "$code" == '200' ]]; then
        log "  OK     $repo"
    else
        warn "  SIN ACCESO ($code)  $repo"
        failed=1
    fi
}

log 'Acceso a los repositorios:'
if [[ "$(env-get ODOO_ENTERPRISE)" == 'true' ]]; then
    check-repo odoo/enterprise
fi
while read -r url _; do
    [[ -z "$url" || "$url" == \#* ]] && continue
    [[ "$url" == https://github.com/* ]] || continue
    repo=${url#https://github.com/}
    repo=${repo%.git}
    check-repo "${repo%/}"
done < addons/repos.txt

if (( failed )); then
    die 'El token no tiene acceso a todos los repos. Si es odoo/enterprise, revisa que aceptaste la invitación de Odoo en GitHub.'
fi
log 'Todo correcto.'
