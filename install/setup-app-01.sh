#!/bin/bash
# =========================================
#  GastroPilot — APP-01 Server-Setup
#  (Production Application Server)
# =========================================
#
# Richtet den Production-Server ein:
#   - SSH-Härtung (Port 2222, Ed25519, Fail2Ban)
#   - Shared Proxy (nginx TLS-Terminierung)
#   - Production-Stack deployen (alle Services)
#   - Let's Encrypt SSL-Zertifikate
#   - Watchtower für automatische Updates
#   - UFW-Firewall (HTTP/HTTPS + SSH via INFRA)
#   - Netplan DNS (CoreDNS auf INFRA-SRV)
#
# Voraussetzung:
#   - INFRA-SRV läuft (WireGuard + CoreDNS)
#   - DB-01 läuft (PostgreSQL + Redis)
#   - Server ist im gastropilot-net (10.0.0.0/16)
#   - DNS A-Records zeigen auf diesen Server / Hetzner LB
#
# Verwendung:
#   ssh app-01        # via WireGuard + INFRA-SRV
#   sudo ./setup-app-01.sh
#
set -euo pipefail

# ============================================
# Netzwerk-Konstanten
# ============================================
PRIVATE_IP="10.0.1.1"              # APP-01
INFRA_IP="10.0.0.2"                # INFRA-SRV
DB01_IP="10.0.2.1"                 # DB-01 (Primary + Redis)
DB02_IP="10.0.2.2"                 # DB-02 (Replica)
WG_SUBNET="10.8.0.0/24"           # WireGuard VPN

SSH_PORT=2222
SSH_USERS=("lucakohls" "saschadolgow")

# ============================================
# Stack-Konstanten
# ============================================
ENVIRONMENT="production"
STACK_NAME="gastropilot-production"
IMAGE_TAG="latest"
SHARED_PROXY_DIR="/opt/shared-proxy"
INSTALL_DIR="/opt/production"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# -------------------------------------------
# Hilfsfunktionen
# -------------------------------------------
generate_secret() { openssl rand -base64 32 | tr -d '/+=' | head -c 44; }
generate_hex()    { openssl rand -hex 32; }

header() {
    echo
    echo "==========================================="
    echo "  $1"
    echo "==========================================="
    echo
}

step() { echo "== $1 =="; }

confirm_or_exit() {
    read -rp "  Korrekt? (J/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[nN]$ ]]; then echo "  Abgebrochen."; exit 0; fi
}

# -------------------------------------------
header "GastroPilot — APP-01 Production Setup"
# -------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "Fehler: Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

# ============================================
# 1. Voraussetzungen + Docker
# ============================================
step "1/12 — Voraussetzungen prüfen"

if ! command -v docker &> /dev/null; then
    echo "  Docker nicht gefunden. Installiere..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
        $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker
    systemctl start docker
fi

for pkg in fail2ban ufw unattended-upgrades apt-listchanges openssl; do
    dpkg -s "$pkg" &> /dev/null 2>&1 || apt-get install -y -qq "$pkg"
done

echo "  Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo "  Docker Compose $(docker compose version --short)"
echo

# ============================================
# 2. SSH-Härtung
# ============================================
step "2/12 — SSH-Härtung"

for USER in "${SSH_USERS[@]}"; do
    if ! id "$USER" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo,docker "$USER"
        echo "$USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER"
        chmod 440 "/etc/sudoers.d/$USER"
        echo "  User '$USER' erstellt — SSH-Key muss noch hinterlegt werden!"
    else
        usermod -aG docker "$USER" 2>/dev/null || true
        echo "  User '$USER' vorhanden."
    fi
done

cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"

cat > /etc/ssh/sshd_config << SSHEOF
# Servecta SSH — APP-01 (generiert von setup-app-01.sh)
Port ${SSH_PORT}
AddressFamily inet
Protocol 2

PermitRootLogin no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
UsePAM yes

KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,ssh-ed25519-cert-v01@openssh.com

LoginGraceTime 30
MaxAuthTries 3
MaxSessions 5
MaxStartups 3:50:10
ClientAliveInterval 300
ClientAliveCountMax 2

AllowUsers ${SSH_USERS[*]}
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
# Forwarding einzeln deaktivieren (SFTP muss funktionieren)
AllowStreamLocalForwarding no

# SFTP (benötigt für scp)
Subsystem sftp /usr/lib/openssh/sftp-server

SyslogFacility AUTH
LogLevel VERBOSE
PrintMotd no
PrintLastLog yes
TCPKeepAlive no
Compression no
UseDNS no
Banner /etc/ssh/banner
SSHEOF

cat > /etc/ssh/banner << 'EOF'
======================================================
  SERVECTA INFRASTRUCTURE — APP-01 (Production)
  Unauthorized access is prohibited.
  All connections are monitored and logged.
======================================================
EOF

rm -f /etc/ssh/ssh_host_dsa_key* /etc/ssh/ssh_host_ecdsa_key* /etc/ssh/ssh_host_rsa_key*
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

cat > /etc/fail2ban/jail.local << F2BEOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd
banaction = ufw

[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 86400
findtime = 600
F2BEOF
systemctl enable fail2ban
systemctl restart fail2ban

cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UUEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUEOF

if sshd -t 2>/dev/null; then
    systemctl restart ssh
    echo "  SSH gehärtet: Port $SSH_PORT, nur Ed25519, nur ${SSH_USERS[*]}"
else
    echo "  FEHLER: SSHD-Config ungültig!"
    cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config 2>/dev/null
    systemctl restart ssh
    exit 1
fi
echo

# ============================================
# 3. Netplan DNS
# ============================================
step "3/12 — DNS-Konfiguration (CoreDNS)"

PRIV_IF=$(ip -o addr show | grep "10\.0\." | awk '{print $2}' | head -1)
PRIV_IF=${PRIV_IF:-ens10}

cat > /etc/netplan/99-dns.yaml << DNSEOF
network:
  version: 2
  ethernets:
    ${PRIV_IF}:
      nameservers:
        addresses: [${INFRA_IP}]
        search: [servecta.local, corp.servecta.local]
DNSEOF

netplan apply 2>/dev/null || echo "  WARNUNG: netplan apply fehlgeschlagen."
echo "  DNS: ${INFRA_IP} (INFRA-SRV CoreDNS)"
echo

# ============================================
# 4. UFW-Firewall (APP-01 spezifisch)
# ============================================
step "4/12 — Firewall (UFW)"

ufw --force reset > /dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing

# SSH nur von INFRA-SRV + WireGuard
ufw allow in from "$INFRA_IP" to any port "$SSH_PORT" proto tcp comment "SSH from INFRA-SRV"
ufw allow in from "$WG_SUBNET" to any port "$SSH_PORT" proto tcp comment "SSH via WireGuard"

# HTTP/HTTPS (vom Hetzner LB oder direkt)
ufw allow in from 10.0.0.0/16 to any port 80 proto tcp comment "HTTP from LB / Private Net"
ufw allow in from 10.0.0.0/16 to any port 443 proto tcp comment "HTTPS from LB / Private Net"

# Port 22 sperren
ufw deny 22/tcp

ufw --force enable
echo "  UFW aktiv: SSH($SSH_PORT) von INFRA+WG, HTTP(80), HTTPS(443)"
echo

# ============================================
# 5. Shared Proxy installieren
# ============================================
step "5/12 — Shared Proxy"

if [ -d "$SHARED_PROXY_DIR" ] && [ -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" ]; then
    echo "  Shared Proxy vorhanden."
    if ! docker ps --format '{{.Names}}' | grep -q "gastropilot-shared-proxy"; then
        echo "  Starte Shared Proxy..."
        docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
    else
        echo "  Shared Proxy läuft."
    fi
else
    echo "  Installiere Shared Proxy..."
    mkdir -p "$SHARED_PROXY_DIR/conf.d" "$SHARED_PROXY_DIR/ssl"

    cat > "$SHARED_PROXY_DIR/nginx.conf" << 'PROXYNGINXEOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 2048;
    use epoll;
    multi_accept on;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 100M;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss
               application/rss+xml font/truetype font/opentype
               application/vnd.ms-fontobject image/svg+xml;

    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      '';
    }

    server {
        listen 80 default_server;
        server_name _;
        location /.well-known/acme-challenge/ { root /var/www/certbot; }
        location / { return 301 https://$host$request_uri; }
    }

    include /etc/nginx/conf.d/*.conf;
}
PROXYNGINXEOF

    cat > "$SHARED_PROXY_DIR/docker-compose.proxy.yml" << 'PROXYCOMPOSEEOF'
services:
  proxy:
    image: nginx:alpine
    container_name: gastropilot-shared-proxy
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./conf.d:/etc/nginx/conf.d:ro
      - ./ssl:/etc/nginx/ssl:ro
      - certbot_webroot:/var/www/certbot:ro
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:80/"]
      interval: 30s
      timeout: 10s
      retries: 3
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 256M
    networks:
      - gastropilot-shared-proxy

networks:
  gastropilot-shared-proxy:
    name: gastropilot-shared-proxy
    driver: bridge

volumes:
  certbot_webroot:
PROXYCOMPOSEEOF

    cat > "$SHARED_PROXY_DIR/conf.d/default.conf" << 'DEFAULTCONFEOF'
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/default/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/default/privkey.pem;
    return 444;
}
DEFAULTCONFEOF

    mkdir -p "$SHARED_PROXY_DIR/ssl/default"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$SHARED_PROXY_DIR/ssl/default/privkey.pem" \
        -out "$SHARED_PROXY_DIR/ssl/default/fullchain.pem" \
        -subj "/CN=localhost" 2>/dev/null


    docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
    echo "  Shared Proxy installiert."
fi
echo

# ============================================
# 6. Domain-Konfiguration
# ============================================
step "6/12 — Domain-Konfiguration"

echo "  Production-Domains (ohne Prefix):"
echo
read -rp "  Base-Domain [gpilot.app]: " BASE_DOMAIN
BASE_DOMAIN=${BASE_DOMAIN:-gpilot.app}

DOMAIN="${BASE_DOMAIN}"
WEB_DOMAIN_ALT="gastropilot.org"
APP_DOMAIN="dashboard.${BASE_DOMAIN}"
API_DOMAIN="api.${BASE_DOMAIN}"
ORDER_DOMAIN="order.${BASE_DOMAIN}"
KDS_DOMAIN="kds.${BASE_DOMAIN}"
ALL_DOMAINS=("$DOMAIN" "$WEB_DOMAIN_ALT" "$APP_DOMAIN" "$API_DOMAIN" "$ORDER_DOMAIN" "$KDS_DOMAIN")

echo
echo "  Domains:"
for D in "${ALL_DOMAINS[@]}"; do echo "    $D"; done
echo
confirm_or_exit
echo

# ============================================
# 7. Datenbank-Verbindung (DB-01)
# ============================================
step "7/12 — PostgreSQL + Redis (DB-01)"

echo "  DB-01: ${DB01_IP} (db-primary.servecta.local)"
echo
read -rp "  DB Name [gastropilot_production]: " DB_NAME
DB_NAME=${DB_NAME:-gastropilot_production}
read -rp "  DB User [gastropilot_production]: " DB_USER
DB_USER=${DB_USER:-gastropilot_production}
read -rsp "  DB Passwort: " DB_PASSWORD; echo

if [ -z "$DB_PASSWORD" ]; then echo "  Fehler: Passwort leer."; exit 1; fi

DATABASE_URL="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB01_IP}:5432/${DB_NAME}"
DATABASE_ADMIN_URL="${DATABASE_URL}"

read -rp "  Replica (DB-02) nutzen? (j/N): " REPLICA_CHOICE
if [[ "$REPLICA_CHOICE" =~ ^[jJ]$ ]]; then
    DATABASE_REPLICA_URL="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB02_IP}:5432/${DB_NAME}"
    HAS_REPLICA="true"
else
    DATABASE_REPLICA_URL=""
    HAS_REPLICA="false"
fi

echo
read -rsp "  Redis-Passwort (von DB-01 Setup): " REDIS_PASSWORD; echo

echo "  Teste DB-Verbindung..."
if docker run --rm --network host postgres:16-alpine \
    pg_isready -h "$DB01_IP" -p 5432 -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
    echo "  DB erreichbar."
else
    echo "  WARNUNG: DB nicht erreichbar."
    read -rp "  Fortfahren? (j/N): " C; [[ "$C" =~ ^[jJ]$ ]] || exit 1
fi
echo

# ============================================
# 8. Secrets & SMTP
# ============================================
step "8/12 — Secrets & SMTP"

JWT_SECRET=$(generate_hex)
AUTH_SECRET=$(generate_secret)

LOG_LEVEL="WARNING"; BCRYPT_ROUNDS="14"
ACCESS_TOKEN_EXPIRE_MINUTES="15"; REFRESH_TOKEN_EXPIRE_DAYS="7"
REDIS_MAXMEMORY="1024mb"

read -rp "  SMTP konfigurieren? (j/N): " SMTP_CHOICE
if [[ "$SMTP_CHOICE" =~ ^[jJ]$ ]]; then
    read -rp "    SMTP Host: " SMTP_HOST
    read -rp "    SMTP Port [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
    read -rp "    SMTP User: " SMTP_USER
    read -rsp "    SMTP Passwort: " SMTP_PASSWORD; echo
    read -rp "    Absender [noreply@gpilot.app]: " SMTP_FROM_EMAIL
    SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-noreply@gpilot.app}
else
    SMTP_HOST="localhost"; SMTP_PORT="587"; SMTP_USER=""; SMTP_PASSWORD=""
    SMTP_FROM_EMAIL="noreply@gpilot.app"
fi
echo

# ============================================
# 9. .env + docker-compose.yml
# ============================================
step "9/12 — Konfiguration generieren"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

cat > .env << ENVEOF
# GastroPilot Production — APP-01 (${PRIVATE_IP})
# Generiert am $(date +%Y-%m-%d) von setup-app-01.sh

STACK_NAME=${STACK_NAME}
IMAGE_TAG=${IMAGE_TAG}
ENVIRONMENT=${ENVIRONMENT}
DOCKERHUB_ORG=servecta

# PostgreSQL (DB-01: ${DB01_IP})
DATABASE_URL=${DATABASE_URL}
DATABASE_ADMIN_URL=${DATABASE_ADMIN_URL}
DATABASE_REPLICA_URL=${DATABASE_REPLICA_URL}
HAS_REPLICA=${HAS_REPLICA}

# Redis (DB-01: ${DB01_IP})
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_MAXMEMORY=${REDIS_MAXMEMORY}

# Auth
JWT_SECRET=${JWT_SECRET}
JWT_ALGORITHM=HS256
JWT_ISSUER=gastropilot_production
JWT_AUDIENCE=gastropilot_production-api
JWT_LEEWAY_SECONDS=10
ACCESS_TOKEN_EXPIRE_MINUTES=${ACCESS_TOKEN_EXPIRE_MINUTES}
REFRESH_TOKEN_EXPIRE_DAYS=${REFRESH_TOKEN_EXPIRE_DAYS}
BCRYPT_ROUNDS=${BCRYPT_ROUNDS}

# CORS
CORS_ORIGINS=https://${DOMAIN},https://${WEB_DOMAIN_ALT},https://${APP_DOMAIN},https://${API_DOMAIN},https://${ORDER_DOMAIN},https://${KDS_DOMAIN}
CORS_ALLOW_CREDENTIALS=true
ALLOWED_HOSTS=${DOMAIN},${WEB_DOMAIN_ALT},${APP_DOMAIN},${API_DOMAIN},${ORDER_DOMAIN},${KDS_DOMAIN}

LOG_LEVEL=${LOG_LEVEL}

# E-Mail
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_USE_TLS=true
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}
SMTP_FROM_NAME=GastroPilot

# Domains
WEB_BASE_URL=https://${DOMAIN}
WEB_DOMAIN=${DOMAIN}
WEB_DOMAIN_ALT=${WEB_DOMAIN_ALT}
APP_DOMAIN_HOST=${APP_DOMAIN}
API_DOMAIN_HOST=${API_DOMAIN}
ORDER_DOMAIN_HOST=${ORDER_DOMAIN}
KDS_DOMAIN_HOST=${KDS_DOMAIN}

# Dashboard
BASE_URL=https://${APP_DOMAIN}
NEXT_PUBLIC_API_BASE_URL=https://${API_DOMAIN}
NEXT_PUBLIC_API_PREFIX=api/v1
AUTH_SECRET=${AUTH_SECRET}

TABLE_ORDER_BASE_URL=https://${ORDER_DOMAIN}
KDS_BASE_URL=https://${KDS_DOMAIN}
ENVEOF

chmod 600 .env
echo "  .env erstellt."

# docker-compose.yml — Redis zeigt auf DB-01 (extern)
cat > docker-compose.yml << 'COMPOSEEOF'
# GastroPilot Production Stack — APP-01
# Redis + PostgreSQL extern auf DB-01

services:
  core:
    image: ${DOCKERHUB_ORG}/gastropilot-core:${IMAGE_TAG}
    container_name: ${STACK_NAME}-core
    restart: always
    environment:
      DATABASE_URL: ${DATABASE_URL}
      DATABASE_ADMIN_URL: ${DATABASE_ADMIN_URL}
      DATABASE_REPLICA_URL: ${DATABASE_REPLICA_URL}
      HAS_REPLICA: ${HAS_REPLICA}
      REDIS_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/0
      JWT_SECRET: ${JWT_SECRET}
      JWT_ALGORITHM: ${JWT_ALGORITHM}
      JWT_ISSUER: ${JWT_ISSUER}
      JWT_AUDIENCE: ${JWT_AUDIENCE}
      JWT_LEEWAY_SECONDS: ${JWT_LEEWAY_SECONDS}
      ACCESS_TOKEN_EXPIRE_MINUTES: ${ACCESS_TOKEN_EXPIRE_MINUTES}
      REFRESH_TOKEN_EXPIRE_DAYS: ${REFRESH_TOKEN_EXPIRE_DAYS}
      BCRYPT_ROUNDS: ${BCRYPT_ROUNDS}
      CORS_ORIGINS: ${CORS_ORIGINS}
      CORS_ALLOW_CREDENTIALS: ${CORS_ALLOW_CREDENTIALS}
      ALLOWED_HOSTS: ${ALLOWED_HOSTS}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_USE_TLS: ${SMTP_USE_TLS}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_FROM_NAME: ${SMTP_FROM_NAME}
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 512M
    networks:
      - internal

  orders:
    image: ${DOCKERHUB_ORG}/gastropilot-orders:${IMAGE_TAG}
    container_name: ${STACK_NAME}-orders
    restart: always
    environment:
      DATABASE_URL: ${DATABASE_URL}
      DATABASE_ADMIN_URL: ${DATABASE_ADMIN_URL}
      DATABASE_REPLICA_URL: ${DATABASE_REPLICA_URL}
      HAS_REPLICA: ${HAS_REPLICA}
      REDIS_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/0
      JWT_SECRET: ${JWT_SECRET}
      JWT_ALGORITHM: ${JWT_ALGORITHM}
      JWT_ISSUER: ${JWT_ISSUER}
      JWT_AUDIENCE: ${JWT_AUDIENCE}
      JWT_LEEWAY_SECONDS: ${JWT_LEEWAY_SECONDS}
      CORS_ORIGINS: ${CORS_ORIGINS}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8001/api/v1/orders/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "1"
          memory: 512M
    networks:
      - internal

  ai:
    image: ${DOCKERHUB_ORG}/gastropilot-ai:${IMAGE_TAG}
    container_name: ${STACK_NAME}-ai
    restart: always
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/0
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8002/api/v1/ai/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
    networks:
      - internal

  notifications:
    image: ${DOCKERHUB_ORG}/gastropilot-notifications:${IMAGE_TAG}
    container_name: ${STACK_NAME}-notifications
    restart: always
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/1
      CELERY_RESULT_BACKEND: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/2
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_USE_TLS: ${SMTP_USE_TLS}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_FROM_NAME: ${SMTP_FROM_NAME}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8003/api/v1/notifications/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - internal

  notifications-worker:
    image: ${DOCKERHUB_ORG}/gastropilot-notifications:${IMAGE_TAG}
    container_name: ${STACK_NAME}-notifications-worker
    restart: always
    command: celery -A app.worker.celery_app worker --loglevel=info --concurrency=2
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/1
      CELERY_RESULT_BACKEND: redis://:${REDIS_PASSWORD}@REDIS_HOST:6379/2
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_USE_TLS: ${SMTP_USE_TLS}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_FROM_NAME: ${SMTP_FROM_NAME}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - internal

  nginx:
    image: nginx:alpine
    container_name: ${STACK_NAME}-nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./html:/usr/share/nginx/html:ro
    depends_on:
      - core
      - orders
      - ai
      - notifications
      - web
      - dashboard
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    networks:
      - internal
      - gastropilot-shared-proxy

  web:
    image: ${DOCKERHUB_ORG}/gastropilot-web:${IMAGE_TAG}
    container_name: ${STACK_NAME}-web
    restart: always
    environment:
      NODE_ENV: production
      NEXT_PUBLIC_API_BASE_URL: https://${API_DOMAIN_HOST}
      NEXT_PUBLIC_API_PREFIX: api/v1
      SSR_API_BASE_URL: http://nginx:80
      NEXT_TELEMETRY_DISABLED: 1
    expose:
      - "3000"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:3000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
    networks:
      - internal
      - gastropilot-shared-proxy

  dashboard:
    image: ${DOCKERHUB_ORG}/gastropilot-dashboard:${IMAGE_TAG}
    container_name: ${STACK_NAME}-dashboard
    restart: always
    environment:
      NODE_ENV: production
      NEXT_PUBLIC_API_BASE_URL: https://${API_DOMAIN_HOST}
      NEXT_PUBLIC_API_PREFIX: ${NEXT_PUBLIC_API_PREFIX}
      SSR_API_BASE_URL: http://nginx:80
      AUTH_SECRET: ${AUTH_SECRET}
      NEXT_TELEMETRY_DISABLED: 1
    expose:
      - "3001"
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://127.0.0.1:3001/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
    networks:
      - internal
      - gastropilot-shared-proxy

  table-order:
    image: ${DOCKERHUB_ORG}/gastropilot-table-order:${IMAGE_TAG}
    container_name: ${STACK_NAME}-table-order
    restart: always
    environment:
      NEXT_PUBLIC_API_BASE_URL: https://${API_DOMAIN_HOST}
      NEXT_PUBLIC_API_PREFIX: api/v1
      SSR_API_BASE_URL: http://nginx:80
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3003/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - internal
      - gastropilot-shared-proxy

  kds:
    image: ${DOCKERHUB_ORG}/gastropilot-kds:${IMAGE_TAG}
    container_name: ${STACK_NAME}-kds
    restart: always
    environment:
      NEXT_PUBLIC_API_BASE_URL: https://${API_DOMAIN_HOST}
      NEXT_PUBLIC_API_PREFIX: api/v1
      SSR_API_BASE_URL: http://nginx:80
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3004/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - internal
      - gastropilot-shared-proxy

  watchtower:
    image: containrrr/watchtower
    container_name: ${STACK_NAME}-watchtower
    restart: always
    environment:
      WATCHTOWER_CLEANUP: "true"
      WATCHTOWER_POLL_INTERVAL: "300"
      WATCHTOWER_LABEL_ENABLE: "false"
      WATCHTOWER_SCOPE: "${STACK_NAME}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      resources:
        limits:
          cpus: "0.25"
          memory: 128M
    networks:
      - internal

networks:
  internal:
    driver: bridge
  gastropilot-shared-proxy:
    external: true
COMPOSEEOF

# REDIS_HOST Platzhalter in docker-compose.yml ersetzen
sed -i "s|REDIS_HOST|${DB01_IP}|g" docker-compose.yml

echo "  docker-compose.yml erstellt (Redis → ${DB01_IP}:6379)."
echo

# ============================================
# 10. nginx.conf + HTML + Hilfs-Skripte
# ============================================
step "10/12 — nginx.conf & Hilfs-Skripte"

# nginx.conf (identisch mit install.sh Logik)
cat > nginx.conf << NGINXEOF
events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" "\$http_user_agent"';
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    sendfile on; tcp_nopush on; tcp_nodelay on;
    keepalive_timeout 65; client_max_body_size 100M;

    gzip on; gzip_vary on; gzip_proxied any; gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/json application/javascript application/xml+rss;

    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=auth_limit:10m rate=10r/m;
    limit_req_zone \$binary_remote_addr zone=web_limit:10m rate=30r/s;

    set_real_ip_from 172.16.0.0/12;
    real_ip_header X-Real-IP;

    # Docker-interner DNS — löst Container-Namen dynamisch auf
    resolver 127.0.0.11 valid=10s ipv6=off;

    map \$http_upgrade \$connection_upgrade { default upgrade; '' ''; }

    server {
        listen 80;
        server_name _;

        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;

        root /usr/share/nginx/html;

        # Upstream-Variablen (dynamisch aufgelöst bei jedem Request)
        set \$up_core        ${STACK_NAME}-core:8000;
        set \$up_orders      ${STACK_NAME}-orders:8001;
        set \$up_ai          ${STACK_NAME}-ai:8002;
        set \$up_notif       ${STACK_NAME}-notifications:8003;
        set \$up_web         ${STACK_NAME}-web:3000;
        set \$up_dashboard   ${STACK_NAME}-dashboard:3001;

        set \$coming_soon 0;
        if (-f /etc/nginx/coming-soon.on) { set \$coming_soon 1; }
        set \$maintenance 0;
        if (-f /etc/nginx/maintenance.on) { set \$maintenance 1; }

        location /health { proxy_pass http://\$up_core/api/v1/health; access_log off; }

        location /ws/ {
            proxy_pass http://\$up_orders;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }

        location ~ ^/(api/v1|v1)/webhooks/sumup { proxy_pass http://\$up_orders; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; }
        location ~ ^/(api/v1|v1)/webhooks/whatsapp { proxy_pass http://\$up_notif; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; }

        location ~ ^/(api/v1|v1)/auth/me {
            if (\$maintenance = 1) { return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}'; }
            proxy_pass http://\$up_core; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        }

        location ~ ^/(api/v1|v1)/auth/ {
            if (\$maintenance = 1) { return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}'; }
            limit_req zone=auth_limit burst=20 nodelay;
            proxy_pass http://\$up_core; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
        }

        location ~ ^/(api/v1|v1)/(orders|kitchen|order-statistics|sumup|invoices|waitlist)(/|\$) {
            if (\$maintenance = 1) { return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}'; }
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://\$up_orders; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_buffering off;
        }

        location ~ ^/(api/v1|v1)/ai(/|\$) {
            if (\$maintenance = 1) { return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}'; }
            proxy_pass http://\$up_ai; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        }

        location ~ ^/(api/v1|v1)/notifications(/|\$) {
            if (\$maintenance = 1) { return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}'; }
            proxy_pass http://\$up_notif; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
        }

        location ~ ^/(api/v1|v1)/ {
            if (\$maintenance = 1) { return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}'; }
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://\$up_core; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_buffering off;
        }

        location /_next/static/ { proxy_pass http://\$up_web; expires 365d; add_header Cache-Control "public, immutable"; }

        location / {
            if (\$coming_soon = 1) { rewrite ^ /coming-soon.html break; }
            if (\$maintenance = 1) { rewrite ^ /maintenance.html break; }
            limit_req zone=web_limit burst=50 nodelay;
            proxy_pass http://\$up_web; proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header Upgrade \$http_upgrade; proxy_set_header Connection "upgrade";
        }
    }
}
NGINXEOF

# HTML-Seiten
mkdir -p html
cat > html/maintenance.html << 'MAINTHTML'
<!DOCTYPE html><html lang="de"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Wartungsarbeiten — GastroPilot</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:linear-gradient(135deg,#0f172a,#1e293b);color:#e2e8f0;min-height:100vh;display:flex;align-items:center;justify-content:center}.c{text-align:center;max-width:520px;padding:2rem}h1{font-size:1.75rem;margin-bottom:.75rem;color:#f8fafc}p{font-size:1.05rem;color:#94a3b8;line-height:1.6}.b{margin-top:2.5rem;font-size:.85rem;color:#475569}</style>
</head><body><div class="c"><h1>Wartungsarbeiten</h1><p>Wir sind in Kürze wieder erreichbar.</p><div class="b">GastroPilot</div></div></body></html>
MAINTHTML

cat > html/coming-soon.html << 'CSHTML'
<!DOCTYPE html><html lang="de"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Coming Soon — GastroPilot</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:linear-gradient(135deg,#0f172a,#1e293b);color:#e2e8f0;min-height:100vh;display:flex;align-items:center;justify-content:center}.c{text-align:center;max-width:520px;padding:2rem}h1{font-size:2rem;margin-bottom:.75rem;color:#f8fafc}p{font-size:1.05rem;color:#94a3b8}.hl{color:#38bdf8;font-weight:600}.b{margin-top:2.5rem;font-size:.85rem;color:#475569}</style>
</head><body><div class="c"><h1>Bald verfügbar</h1><p><span class="hl">GastroPilot</span> — die intelligente Lösung für Ihr Restaurant.</p><div class="b">GastroPilot</div></div></body></html>
CSHTML

# Hilfs-Skripte
for SCRIPT_NAME in maintenance coming-soon; do
    FLAG_NAME="$SCRIPT_NAME"
    [ "$SCRIPT_NAME" = "coming-soon" ] && LABEL="Coming-Soon" || LABEL="Wartungsmodus"
    cat > "${SCRIPT_NAME}.sh" << HELPEREOF
#!/bin/bash
STACK_NAME=\$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
CONTAINER="\${STACK_NAME:-gastropilot}-nginx"
case "\$1" in
  on)  docker exec "\$CONTAINER" touch /etc/nginx/${FLAG_NAME}.on && docker exec "\$CONTAINER" nginx -s reload && echo "${LABEL} aktiviert." ;;
  off) docker exec "\$CONTAINER" rm -f /etc/nginx/${FLAG_NAME}.on && docker exec "\$CONTAINER" nginx -s reload && echo "${LABEL} deaktiviert." ;;
  status) docker exec "\$CONTAINER" test -f /etc/nginx/${FLAG_NAME}.on 2>/dev/null && echo "${LABEL}: AKTIV" || echo "${LABEL}: INAKTIV" ;;
  *) echo "Verwendung: \$0 {on|off|status}"; exit 1 ;;
esac
HELPEREOF
    chmod +x "${SCRIPT_NAME}.sh"
done

cat > update.sh << 'UPDATEEOF'
#!/bin/bash
set -e
STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
echo "== GastroPilot Update ($STACK_NAME) =="
echo "== 1/4 Images pullen =="
docker compose pull
echo "== 2/4 DB-Migration =="
docker compose run --rm core alembic -c alembic.ini upgrade head 2>/dev/null || echo "  Übersprungen."
echo "== 3/4 Container starten =="
docker compose up -d
echo "== 4/4 Proxy neu laden =="
sleep 3
docker restart "${STACK_NAME}-nginx"
docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || true
echo "== Fertig =="
docker compose ps
UPDATEEOF
chmod +x update.sh

echo "  nginx.conf, HTML-Seiten, Hilfs-Skripte erstellt."
echo

# ============================================
# 11. SSL-Zertifikate & Proxy-Configs
# ============================================
step "11/12 — SSL & Proxy-Configs"

SSL_BASE_DIR="$SHARED_PROXY_DIR/ssl"
PROXY_CONF_DIR="$SHARED_PROXY_DIR/conf.d"

DOMAINS_NEEDING_CERT=()
for D in "${ALL_DOMAINS[@]}"; do
    if [ -f "$SSL_BASE_DIR/$D/fullchain.pem" ] && [ -f "$SSL_BASE_DIR/$D/privkey.pem" ]; then
        echo "  $D — vorhanden"
    else
        DOMAINS_NEEDING_CERT+=("$D")
    fi
done

if [ ${#DOMAINS_NEEDING_CERT[@]} -gt 0 ]; then
    echo "  ${#DOMAINS_NEEDING_CERT[@]} Domain(s) benötigen SSL."
    echo "  1) Let's Encrypt (empfohlen)   2) Selbstsigniert   3) Überspringen"
    read -rp "  Auswahl [1/2/3]: " SSL_CHOICE

    if [ "$SSL_CHOICE" = "1" ]; then
        read -rp "  E-Mail für Let's Encrypt: " CERT_EMAIL
        docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" stop proxy 2>/dev/null || true
        for D in "${DOMAINS_NEEDING_CERT[@]}"; do
            mkdir -p "$SSL_BASE_DIR/$D" certbot
            if docker run --rm -p 80:80 -v "$(pwd)/certbot:/etc/letsencrypt" \
                certbot/certbot certonly --standalone -d "$D" --non-interactive --agree-tos -m "$CERT_EMAIL"; then
                cp "certbot/live/$D/fullchain.pem" "$SSL_BASE_DIR/$D/"
                cp "certbot/live/$D/privkey.pem" "$SSL_BASE_DIR/$D/"
                echo "    $D — Let's Encrypt installiert"
            else
                echo "    $D — Let's Encrypt fehlgeschlagen, erstelle selbstsigniertes Zertifikat"
                openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                    -keyout "$SSL_BASE_DIR/$D/privkey.pem" \
                    -out "$SSL_BASE_DIR/$D/fullchain.pem" \
                    -subj "/CN=$D" 2>/dev/null
            fi
        done
        docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
    elif [ "$SSL_CHOICE" = "2" ]; then
        for D in "${DOMAINS_NEEDING_CERT[@]}"; do
            mkdir -p "$SSL_BASE_DIR/$D"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$SSL_BASE_DIR/$D/privkey.pem" -out "$SSL_BASE_DIR/$D/fullchain.pem" \
                -subj "/CN=$D" 2>/dev/null
            echo "    $D — selbstsigniert"
        done
    fi
fi

# Proxy-Configs
write_proxy_conf() {
    local CONF_FILE="$1" SERVER_NAME="$2" BACKEND_VAR="$3" BACKEND_TARGET="$4"
    cat > "$CONF_FILE" << PROXYEOF
server {
    listen 443 ssl; http2 on;
    server_name ${SERVER_NAME};
    resolver 127.0.0.11 valid=10s ipv6=off;
    set \$${BACKEND_VAR} ${BACKEND_TARGET};
    ssl_certificate /etc/nginx/ssl/${SERVER_NAME}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${SERVER_NAME}/privkey.pem;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    location / {
        proxy_pass http://\$${BACKEND_VAR};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_buffering off;
    }
}
PROXYEOF
}

write_proxy_conf "$PROXY_CONF_DIR/${DOMAIN}.conf" "$DOMAIN" "backend" "${STACK_NAME}-nginx:80"
write_proxy_conf "$PROXY_CONF_DIR/${WEB_DOMAIN_ALT}.conf" "$WEB_DOMAIN_ALT" "backend_alt" "${STACK_NAME}-nginx:80"
write_proxy_conf "$PROXY_CONF_DIR/${APP_DOMAIN}.conf" "$APP_DOMAIN" "dashboard_be" "${STACK_NAME}-dashboard:3001"
write_proxy_conf "$PROXY_CONF_DIR/${API_DOMAIN}.conf" "$API_DOMAIN" "api_be" "${STACK_NAME}-nginx:80"
write_proxy_conf "$PROXY_CONF_DIR/${ORDER_DOMAIN}.conf" "$ORDER_DOMAIN" "order_be" "${STACK_NAME}-table-order:3003"
write_proxy_conf "$PROXY_CONF_DIR/${KDS_DOMAIN}.conf" "$KDS_DOMAIN" "kds_be" "${STACK_NAME}-kds:3004"

docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || \
    docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" restart
echo "  Proxy-Configs generiert."
echo

# ============================================
# 12. Container starten
# ============================================
step "12/12 — Container starten"

docker compose pull
docker compose up -d

echo "  Warte auf Core..."
for i in $(seq 1 30); do
    if docker exec "${STACK_NAME}-core" python -c \
        "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')" > /dev/null 2>&1; then
        echo "  Core bereit."
        break
    fi
    [ "$i" -eq 30 ] && echo "  WARNUNG: Core antwortet noch nicht."
    sleep 2
done

echo "  DB-Migration..."
docker compose exec core alembic -c alembic.ini upgrade head 2>/dev/null || \
    echo "  Migration übersprungen."

# Platform-Admin
echo
read -rp "  Platform-Admin erstellen? (J/n): " ADMIN_CHOICE
if [[ ! "$ADMIN_CHOICE" =~ ^[nN]$ ]]; then
    read -rp "  E-Mail: " ADMIN_EMAIL
    read -rp "  Vorname: " ADMIN_FIRST_NAME
    read -rp "  Nachname: " ADMIN_LAST_NAME
    read -rsp "  Passwort (min. 8 Zeichen): " ADMIN_PASSWORD; echo
    if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
        echo "  Fehler: Passwort zu kurz."
    else
        docker exec \
            -e ADMIN_EMAIL="$ADMIN_EMAIL" \
            -e ADMIN_FIRST_NAME="$ADMIN_FIRST_NAME" \
            -e ADMIN_LAST_NAME="$ADMIN_LAST_NAME" \
            -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
            "${STACK_NAME}-core" python -c "
import asyncio, os
from app.core.database import get_session_factories
from app.models.user import User
from app.core.security import hash_password

async def create_admin():
    factory, _ = get_session_factories()
    async with factory() as session:
        async with session.begin():
            user = User(
                email=os.environ['ADMIN_EMAIL'],
                password_hash=hash_password(os.environ['ADMIN_PASSWORD']),
                first_name=os.environ['ADMIN_FIRST_NAME'].strip(),
                last_name=os.environ['ADMIN_LAST_NAME'].strip(),
                role='platform_admin',
                auth_method='password',
                is_active=True,
            )
            session.add(user)
    print(f'  Admin: {user.first_name} {user.last_name} ({user.email})')

asyncio.run(create_admin())
"
    fi
fi
echo

# ============================================
header "APP-01 Production Setup abgeschlossen!"
# ============================================

echo "Server:       APP-01 (${PRIVATE_IP})"
echo "Environment:  production"
echo "Stack:        $STACK_NAME"
echo "SSH:          Port ${SSH_PORT} (nur via INFRA-SRV / WireGuard)"
echo "DB:           ${DB01_IP}:5432 (db-primary.servecta.local)"
echo "Redis:        ${DB01_IP}:6379 (db-primary.servecta.local)"
echo
echo "Domains:"
for D in "${ALL_DOMAINS[@]}"; do echo "  https://$D"; done
echo
echo "DNS (via CoreDNS):"
echo "  app.servecta.local  →  ${PRIVATE_IP}"
echo
echo "Befehle:"
echo "  ./update.sh                — Update (Pull + Migration + Restart)"
echo "  ./maintenance.sh on|off    — Wartungsmodus"
echo "  ./coming-soon.sh on|off    — Coming-Soon"
echo "  docker compose logs -f     — Logs"
echo "  docker compose ps          — Status"
echo
echo "Service-Status:"
for svc in core orders ai notifications notifications-worker web dashboard table-order kds nginx watchtower; do
    CONTAINER="${STACK_NAME}-${svc}"
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "nicht gefunden")
    printf "  %-25s %s\n" "$svc" "$STATUS"
done
echo
