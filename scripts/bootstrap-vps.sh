#!/usr/bin/env bash
# Prepara una VPS recién creada (Ubuntu 24.04 / Debian 12) para correr el stack.
# Ejecutar como root, UNA vez:  sudo scripts/bootstrap-vps.sh
#
# Hace: actualizaciones automáticas de seguridad, Docker, swap, firewall (22/80/443)
# y fail2ban para SSH y para los logins de Odoo.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ $EUID -eq 0 ]] || die 'Ejecuta este script como root (sudo).'

export DEBIAN_FRONTEND=noninteractive

log 'Actualizando el sistema...'
apt-get update
apt-get -y upgrade
apt-get install -y ca-certificates curl git ufw fail2ban unattended-upgrades rclone
dpkg-reconfigure -f noninteractive unattended-upgrades

if ! command -v docker >/dev/null; then
    log 'Instalando Docker (repositorio oficial)...'
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

if ! swapon --show | grep -q .; then
    log 'Creando swap de 2 GB (evita que el kernel mate procesos en picos de memoria)...'
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo 'vm.swappiness=10' > /etc/sysctl.d/99-swappiness.conf
    sysctl --system >/dev/null
fi

log 'Configurando el firewall (SSH, HTTP, HTTPS)...'
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

log 'Configurando fail2ban...'
install -m 644 server/fail2ban/filter.d/odoo-login.conf /etc/fail2ban/filter.d/odoo-login.conf
install -m 644 server/fail2ban/jail.d/odoo.local /etc/fail2ban/jail.d/odoo.local
systemctl enable fail2ban
systemctl restart fail2ban

log 'Servidor listo. Siguiente paso: scripts/setup-env.sh'
warn 'Recomendado: entra por SSH con clave y desactiva el login por contraseña (PasswordAuthentication no).'
