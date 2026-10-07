# syntax=docker/dockerfile:1.7
#
# Imagen de producción: Odoo oficial + Enterprise (opcional) + addons de terceros.
# Todo el código y las dependencias se resuelven en el build, así que el contenedor
# arranca sin depender de GitHub ni de PyPI.

ARG ODOO_VERSION=20.0
ARG ODOO_RELEASE=20260926

# -----------------------------------------------------------------------------
# Etapa 1: descarga de código. El token de GitHub solo existe en esta etapa
# (como secreto de BuildKit) y nunca llega a la imagen final.
# -----------------------------------------------------------------------------
FROM debian:trixie-slim AS fetch

ARG ODOO_VERSION
ARG ODOO_RELEASE
ARG ODOO_ENTERPRISE=false
ARG ODOO_ENTERPRISE_REF=

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 image/build/fetch-addons /usr/local/bin/fetch-addons
COPY addons/repos.txt /build/repos.txt
COPY addons/custom/ /opt/odoo-addons/custom/

RUN --mount=type=secret,id=github_token \
    fetch-addons /build/repos.txt /opt/odoo-addons

# -----------------------------------------------------------------------------
# Etapa 2: imagen final sobre la oficial de Odoo (odoo:<versión>-<fecha>).
# -----------------------------------------------------------------------------
FROM odoo:${ODOO_VERSION}-${ODOO_RELEASE}

ARG ODOO_VERSION
ARG ODOO_RELEASE
ARG ODOO_ENTERPRISE=false

USER root
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

COPY --from=fetch /opt/odoo-addons /opt/odoo-addons
COPY addons/requirements.txt /opt/odoo-addons/requirements.extra.txt

# Dependencias Python: herramientas de despliegue + requirements.txt de cada repo
# + los requirements propios del proyecto. Ubuntu 24.04 (base oficial) exige
# --break-system-packages para pip a nivel de sistema.
RUN pip install --no-cache-dir --break-system-packages click-odoo-contrib \
    && for req in /opt/odoo-addons/repos/*/requirements.txt /opt/odoo-addons/requirements.extra.txt; do \
         if [[ -f "$req" ]]; then \
           echo "pip install -r $req"; \
           pip install --no-cache-dir --break-system-packages -r "$req"; \
         fi; \
       done

COPY --chmod=0755 image/bin/ /usr/local/bin/

LABEL org.opencontainers.image.title="odoo-prod" \
      org.opencontainers.image.version="${ODOO_VERSION}-${ODOO_RELEASE}" \
      org.opencontainers.image.description="Odoo ${ODOO_VERSION} (nightly ${ODOO_RELEASE}), enterprise=${ODOO_ENTERPRISE}"

ENV ODOO_ADDONS_ROOT=/opt/odoo-addons

USER odoo

EXPOSE 8069 8072

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8069/web/health || exit 1

ENTRYPOINT ["odoo-entrypoint"]
CMD ["odoo"]
