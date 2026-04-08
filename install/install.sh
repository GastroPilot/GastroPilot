#!/bin/bash
# =========================================
#  GastroPilot — Server-Installation
# =========================================
#
# Vollständige Installation einer GastroPilot-Umgebung.
# Installiert bei Bedarf den Shared Proxy, konfiguriert externe
# PostgreSQL (Primary + Replica), erzeugt docker-compose.yml,
# .env, Proxy-Configs, SSL-Zertifikate und Hilfs-Skripte.
#
# Environments: test, staging, demo, production
#
# Voraussetzungen:
#   - Docker + Docker Compose v2
#   - Externe PostgreSQL-Datenbank (Primary + optional Replica)
#
# Verwendung:
#   Remote (curl):
#     curl -fsSL http://intranet.corp.servcta.local/install.sh | bash
#
#   Lokal:
#     cp -r install/* /opt/<environment>/ && cd /opt/<environment> && ./install.sh
#
set -e

DOWNLOAD_BASE_URL="http://intranet.corp.servcta.local/install"
SHARED_PROXY_DIR="/opt/shared-proxy"
ENV_FILE=".env"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd 2>/dev/null)" || SCRIPT_DIR=""

# -------------------------------------------
# Pipe-Erkennung: curl ... | bash
# -------------------------------------------
# Wenn stdin kein Terminal ist (Pipe von curl), stdin auf /dev/tty
# umleiten, damit read-Befehle interaktiv funktionieren.
if [ ! -t 0 ]; then
    if [ ! -e /dev/tty ]; then
        echo "Fehler: Kein Terminal verfügbar. Bitte interaktiv ausführen."
        exit 1
    fi
    exec < /dev/tty
    PIPED_MODE="true"
else
    PIPED_MODE="false"
fi

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
header "GastroPilot — Server-Installation"
# -------------------------------------------

# ============================================
# 1. Voraussetzungen
# ============================================
step "1/11 — Voraussetzungen prüfen"

for cmd in docker openssl curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Fehler: '$cmd' ist nicht installiert."; exit 1
    fi
done

if ! docker compose version &> /dev/null; then
    echo "Fehler: Docker Compose (v2) ist nicht installiert."; exit 1
fi

echo "  Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo "  Docker Compose $(docker compose version --short)"
echo

# ============================================
# 2. Shared Proxy prüfen / installieren
# ============================================
step "2/11 — Shared Proxy"

if [ -d "$SHARED_PROXY_DIR" ] && [ -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" ]; then
    echo "  Shared Proxy vorhanden: $SHARED_PROXY_DIR"
    if docker ps --format '{{.Names}}' | grep -q "gastropilot-shared-proxy"; then
        echo "  Shared Proxy läuft."
    else
        echo "  Shared Proxy existiert aber läuft nicht. Starte..."
        docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
        echo "  Shared Proxy gestartet."
    fi
else
    echo "  Shared Proxy nicht gefunden unter $SHARED_PROXY_DIR"
    echo "  Installiere Shared Proxy..."
    echo

    mkdir -p "$SHARED_PROXY_DIR/conf.d"
    mkdir -p "$SHARED_PROXY_DIR/ssl"

    # --- Shared-Proxy nginx.conf ---
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

    # HTTP -> HTTPS Redirect
    server {
        listen 80 default_server;
        server_name _;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 301 https://$host$request_uri;
        }
    }

    include /etc/nginx/conf.d/*.conf;
}
PROXYNGINXEOF

    # --- docker-compose.proxy.yml ---
    cat > "$SHARED_PROXY_DIR/docker-compose.proxy.yml" << 'PROXYCOMPOSEEOF'
# GastroPilot Shared Proxy
# TLS-Terminierung + Routing zu allen GastroPilot-Stacks

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

    # --- Default-Config ---
    cat > "$SHARED_PROXY_DIR/conf.d/default.conf" << 'DEFAULTCONFEOF'
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate /etc/nginx/ssl/default/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/default/privkey.pem;
    return 444;
}
DEFAULTCONFEOF

    # --- Self-signed Default-Zertifikat ---
    mkdir -p "$SHARED_PROXY_DIR/ssl/default"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$SHARED_PROXY_DIR/ssl/default/privkey.pem" \
        -out "$SHARED_PROXY_DIR/ssl/default/fullchain.pem" \
        -subj "/CN=localhost" 2>/dev/null

    # --- Docker-Netzwerk ---
    if ! docker network ls --format '{{.Name}}' | grep -q "gastropilot-shared-proxy"; then
        docker network create gastropilot-shared-proxy
        echo "  Docker-Netzwerk 'gastropilot-shared-proxy' erstellt."
    fi

    docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
    echo "  Shared Proxy installiert und gestartet."
fi
echo

# ============================================
# 3. Environment & Domain-Konfiguration
# ============================================
step "3/11 — Environment & Konfiguration"

echo "  Verfügbare Environments:"
echo "    1) test"
echo "    2) staging"
echo "    3) demo"
echo "    4) production"
echo
read -rp "  Environment [1/2/3/4]: " ENV_CHOICE

case "$ENV_CHOICE" in
    1) ENVIRONMENT="test" ;;
    2) ENVIRONMENT="staging" ;;
    3) ENVIRONMENT="demo" ;;
    4) ENVIRONMENT="production" ;;
    *) echo "Fehler: Ungültige Auswahl."; exit 1 ;;
esac

STACK_NAME="gastropilot-${ENVIRONMENT}"

if [ "$ENVIRONMENT" = "production" ]; then
    IMAGE_TAG="latest"
else
    IMAGE_TAG="${ENVIRONMENT}"
fi

echo "  Environment: $ENVIRONMENT"
echo "  Stack-Name:  $STACK_NAME"
echo "  Image-Tag:   $IMAGE_TAG"
echo

# Domain-Konfiguration
if [ "$ENVIRONMENT" = "production" ]; then
    echo "  Production-Modus: Domains ohne Prefix."
    read -rp "  Base-Domain [gpilot.app]: " BASE_DOMAIN
    BASE_DOMAIN=${BASE_DOMAIN:-gpilot.app}
    DOMAIN="${BASE_DOMAIN}"
    WEB_DOMAIN_ALT="gastropilot.org"
    APP_DOMAIN="dashboard.${BASE_DOMAIN}"
    API_DOMAIN="api.${BASE_DOMAIN}"
    ORDER_DOMAIN="order.${BASE_DOMAIN}"
    KDS_DOMAIN="kds.${BASE_DOMAIN}"
else
    read -rp "  Domain-Prefix (z.B. stage, demo, test): " DOMAIN_PREFIX
    DOMAIN="${DOMAIN_PREFIX}.gpilot.app"
    WEB_DOMAIN_ALT="${DOMAIN_PREFIX}.gastropilot.org"
    APP_DOMAIN="${DOMAIN_PREFIX}-dashboard.gpilot.app"
    API_DOMAIN="${DOMAIN_PREFIX}-api.gpilot.app"
    ORDER_DOMAIN="${DOMAIN_PREFIX}-order.gpilot.app"
    KDS_DOMAIN="${DOMAIN_PREFIX}-kds.gpilot.app"
fi

ALL_DOMAINS=("$DOMAIN" "$WEB_DOMAIN_ALT" "$APP_DOMAIN" "$API_DOMAIN" "$ORDER_DOMAIN" "$KDS_DOMAIN")

echo
echo "  Konfigurierte Domains:"
echo "    ${DOMAIN}             — Webseite + Gästeportal"
echo "    ${WEB_DOMAIN_ALT}     — Webseite + Gästeportal (Alt)"
echo "    ${APP_DOMAIN}         — Restaurant-Dashboard"
echo "    ${API_DOMAIN}         — API (Backend)"
echo "    ${ORDER_DOMAIN}       — Tischbestellung"
echo "    ${KDS_DOMAIN}         — Kitchen Display"
echo
confirm_or_exit
echo

# ============================================
# 4. Externe PostgreSQL-Datenbank
# ============================================
step "4/11 — PostgreSQL-Datenbank (extern)"

echo
echo "  GastroPilot nutzt eine externe PostgreSQL-Datenbank."
echo "  Die Datenbank läuft auf einem separaten Server (Docker-Container)."
echo
echo "  --- Primary (Lesen + Schreiben) ---"
read -rp "  DB Host (IP/Hostname): " DB_HOST
read -rp "  DB Port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -rp "  DB Name [gastropilot_${ENVIRONMENT}]: " DB_NAME
DB_NAME=${DB_NAME:-gastropilot_${ENVIRONMENT}}
read -rp "  DB User [gastropilot_${ENVIRONMENT}]: " DB_USER
DB_USER=${DB_USER:-gastropilot_${ENVIRONMENT}}
read -rsp "  DB Passwort: " DB_PASSWORD
echo

if [ -z "$DB_PASSWORD" ]; then
    echo "  Fehler: DB-Passwort darf nicht leer sein."; exit 1
fi

read -rp "  SSL erzwingen? (J/n): " DB_SSL_CHOICE
if [[ "$DB_SSL_CHOICE" =~ ^[nN]$ ]]; then
    DB_SSL_MODE="disable"; DB_SSL_QUERY=""
else
    DB_SSL_MODE="require"; DB_SSL_QUERY="?ssl=require"
fi

DATABASE_URL="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}${DB_SSL_QUERY}"
DATABASE_ADMIN_URL="${DATABASE_URL}"

echo
echo "  --- Replica (nur Lesen, optional) ---"
read -rp "  Replica konfigurieren? (j/N): " REPLICA_CHOICE

if [[ "$REPLICA_CHOICE" =~ ^[jJ]$ ]]; then
    read -rp "  Replica Host (IP/Hostname): " REPLICA_HOST
    read -rp "  Replica Port [5432]: " REPLICA_PORT
    REPLICA_PORT=${REPLICA_PORT:-5432}
    read -rp "  Replica DB User [${DB_USER}]: " REPLICA_USER
    REPLICA_USER=${REPLICA_USER:-${DB_USER}}
    read -rsp "  Replica DB Passwort [gleich wie Primary]: " REPLICA_PASSWORD
    echo
    REPLICA_PASSWORD=${REPLICA_PASSWORD:-${DB_PASSWORD}}
    DATABASE_REPLICA_URL="postgresql+asyncpg://${REPLICA_USER}:${REPLICA_PASSWORD}@${REPLICA_HOST}:${REPLICA_PORT}/${DB_NAME}${DB_SSL_QUERY}"
    HAS_REPLICA="true"
    echo "  Replica konfiguriert: ${REPLICA_HOST}:${REPLICA_PORT}"
else
    DATABASE_REPLICA_URL=""
    HAS_REPLICA="false"
    echo "  Keine Replica — Primary wird für alle Abfragen genutzt."
fi

echo
echo "  Primary:  ${DB_HOST}:${DB_PORT}/${DB_NAME}"
if [ "$HAS_REPLICA" = "true" ]; then
    echo "  Replica:  ${REPLICA_HOST}:${REPLICA_PORT}/${DB_NAME}"
fi
echo "  SSL:      ${DB_SSL_MODE}"
echo

# Verbindung testen
echo "  Teste Datenbankverbindung..."
if docker run --rm --network host postgres:16-alpine \
    pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
    echo "  Primary erreichbar."
else
    echo "  WARNUNG: Primary nicht erreichbar (${DB_HOST}:${DB_PORT})."
    read -rp "  Trotzdem fortfahren? (j/N): " DB_CONTINUE
    if [[ ! "$DB_CONTINUE" =~ ^[jJ]$ ]]; then exit 1; fi
fi

if [ "$HAS_REPLICA" = "true" ]; then
    if docker run --rm --network host postgres:16-alpine \
        pg_isready -h "$REPLICA_HOST" -p "$REPLICA_PORT" -U "$REPLICA_USER" -d "$DB_NAME" > /dev/null 2>&1; then
        echo "  Replica erreichbar."
    else
        echo "  WARNUNG: Replica nicht erreichbar (${REPLICA_HOST}:${REPLICA_PORT})."
    fi
fi
echo

# ============================================
# 5. Weitere Konfiguration (SMTP, Secrets)
# ============================================
step "5/11 — Secrets & SMTP"

REDIS_PASSWORD=$(generate_secret)
JWT_SECRET=$(generate_hex)
AUTH_SECRET=$(generate_secret)

echo
read -rp "  SMTP konfigurieren für E-Mail-Versand? (j/N): " SMTP_CHOICE
if [[ "$SMTP_CHOICE" =~ ^[jJ]$ ]]; then
    read -rp "    SMTP Host: " SMTP_HOST
    read -rp "    SMTP Port [587]: " SMTP_PORT; SMTP_PORT=${SMTP_PORT:-587}
    read -rp "    SMTP User: " SMTP_USER
    read -rsp "    SMTP Passwort: " SMTP_PASSWORD; echo
    read -rp "    Absender-E-Mail [noreply@gpilot.app]: " SMTP_FROM_EMAIL
    SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-noreply@gpilot.app}
else
    SMTP_HOST="localhost"; SMTP_PORT="587"; SMTP_USER=""; SMTP_PASSWORD=""
    SMTP_FROM_EMAIL="noreply@gpilot.app"
fi

case "$ENVIRONMENT" in
    production)
        LOG_LEVEL="WARNING"; BCRYPT_ROUNDS="14"
        ACCESS_TOKEN_EXPIRE_MINUTES="15"; REFRESH_TOKEN_EXPIRE_DAYS="7"
        REDIS_MAXMEMORY="1024mb"
        ;;
    staging)
        LOG_LEVEL="INFO"; BCRYPT_ROUNDS="12"
        ACCESS_TOKEN_EXPIRE_MINUTES="30"; REFRESH_TOKEN_EXPIRE_DAYS="30"
        REDIS_MAXMEMORY="512mb"
        ;;
    *)
        LOG_LEVEL="DEBUG"; BCRYPT_ROUNDS="10"
        ACCESS_TOKEN_EXPIRE_MINUTES="60"; REFRESH_TOKEN_EXPIRE_DAYS="90"
        REDIS_MAXMEMORY="256mb"
        ;;
esac

# .env schreiben
cat > "$ENV_FILE" << ENVEOF
# GastroPilot ${ENVIRONMENT^} Environment
# Generiert am $(date +%Y-%m-%d)

# ==================== STACK ====================
STACK_NAME=${STACK_NAME}
IMAGE_TAG=${IMAGE_TAG}
ENVIRONMENT=${ENVIRONMENT}

# ==================== DOCKER HUB ====================
DOCKERHUB_ORG=servecta

# ==================== POSTGRESQL (extern) ====================
DATABASE_URL=${DATABASE_URL}
DATABASE_ADMIN_URL=${DATABASE_ADMIN_URL}
DATABASE_REPLICA_URL=${DATABASE_REPLICA_URL}
HAS_REPLICA=${HAS_REPLICA}
DATABASE_SSL_MODE=${DB_SSL_MODE}

# ==================== AUTH & SECURITY ====================
JWT_SECRET=${JWT_SECRET}
JWT_ALGORITHM=HS256
JWT_ISSUER=gastropilot_${ENVIRONMENT}
JWT_AUDIENCE=gastropilot_${ENVIRONMENT}-api
JWT_LEEWAY_SECONDS=10
ACCESS_TOKEN_EXPIRE_MINUTES=${ACCESS_TOKEN_EXPIRE_MINUTES}
REFRESH_TOKEN_EXPIRE_DAYS=${REFRESH_TOKEN_EXPIRE_DAYS}
BCRYPT_ROUNDS=${BCRYPT_ROUNDS}

# CORS & Security
CORS_ORIGINS=https://${DOMAIN},https://${WEB_DOMAIN_ALT},https://${APP_DOMAIN},https://${API_DOMAIN},https://${ORDER_DOMAIN},https://${KDS_DOMAIN}
CORS_ALLOW_CREDENTIALS=true
ALLOWED_HOSTS=${DOMAIN},${WEB_DOMAIN_ALT},${APP_DOMAIN},${API_DOMAIN},${ORDER_DOMAIN},${KDS_DOMAIN}

# Logging
LOG_LEVEL=${LOG_LEVEL}

# ==================== REDIS ====================
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_MAXMEMORY=${REDIS_MAXMEMORY}

# ==================== E-MAIL (SMTP) ====================
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_USE_TLS=true
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}
SMTP_FROM_NAME=GastroPilot ${ENVIRONMENT^}

# ==================== WEB (Webseite + Gästeportal) ====================
WEB_BASE_URL=https://${DOMAIN}

# ==================== DASHBOARD (Restaurant) ====================
BASE_URL=https://${APP_DOMAIN}
NEXT_PUBLIC_API_BASE_URL=https://${API_DOMAIN}
NEXT_PUBLIC_API_PREFIX=api/v1
AUTH_SECRET=${AUTH_SECRET}

# ==================== DOMAINS ====================
WEB_DOMAIN=${DOMAIN}
WEB_DOMAIN_ALT=${WEB_DOMAIN_ALT}
APP_DOMAIN_HOST=${APP_DOMAIN}
API_DOMAIN_HOST=${API_DOMAIN}
ORDER_DOMAIN_HOST=${ORDER_DOMAIN}
KDS_DOMAIN_HOST=${KDS_DOMAIN}

# ==================== TABLE ORDER ====================
TABLE_ORDER_BASE_URL=https://${ORDER_DOMAIN}

# ==================== KDS ====================
KDS_BASE_URL=https://${KDS_DOMAIN}

# ==================== OPTIONAL ====================
# OPENAI_API_KEY=
# SUMUP_API_KEY=
# SUMUP_MERCHANT_CODE=
# SENTRY_DSN=
# TWILIO_ACCOUNT_SID=
# TWILIO_AUTH_TOKEN=
# TWILIO_PHONE_NUMBER=
# TWILIO_WHATSAPP_NUMBER=
# WHATSAPP_ENABLED=false
ENVEOF

echo "  $ENV_FILE erstellt."
echo

# ============================================
# 6. docker-compose.yml generieren
# ============================================
step "6/11 — docker-compose.yml generieren"

cat > docker-compose.yml << 'COMPOSEEOF'
# GastroPilot — Server Stack (externe Datenbank)
# Generiert von install.sh

services:
  # ---------------------------------------------------------------------------
  # Redis (lokaler Cache + Message Broker)
  # ---------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: ${STACK_NAME}-redis
    restart: always
    command: >
      redis-server
      --appendonly yes
      --maxmemory ${REDIS_MAXMEMORY}
      --maxmemory-policy allkeys-lru
      --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 512M
    networks:
      - internal

  # ---------------------------------------------------------------------------
  # Backend Microservices
  # ---------------------------------------------------------------------------
  core:
    image: ${DOCKERHUB_ORG}/gastropilot-core:${IMAGE_TAG}
    container_name: ${STACK_NAME}-core
    restart: always
    environment:
      DATABASE_URL: ${DATABASE_URL}
      DATABASE_ADMIN_URL: ${DATABASE_ADMIN_URL}
      DATABASE_REPLICA_URL: ${DATABASE_REPLICA_URL}
      HAS_REPLICA: ${HAS_REPLICA}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
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
      UPLOAD_DIR: /data/uploads
      UPLOAD_PUBLIC_URL: https://${API_DOMAIN_HOST}/uploads
    volumes:
      - upload_data:/data/uploads
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
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
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      JWT_SECRET: ${JWT_SECRET}
      JWT_ALGORITHM: ${JWT_ALGORITHM}
      JWT_ISSUER: ${JWT_ISSUER}
      JWT_AUDIENCE: ${JWT_AUDIENCE}
      JWT_LEEWAY_SECONDS: ${JWT_LEEWAY_SECONDS}
      CORS_ORIGINS: ${CORS_ORIGINS}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    depends_on:
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8001/api/v1/orders/health')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
    labels:
      - "com.centurylinklabs.watchtower.enable=false"
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
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    depends_on:
      redis:
        condition: service_healthy
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
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      CELERY_RESULT_BACKEND: redis://:${REDIS_PASSWORD}@redis:6379/2
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_USE_TLS: ${SMTP_USE_TLS}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_FROM_NAME: ${SMTP_FROM_NAME}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    depends_on:
      redis:
        condition: service_healthy
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
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/1
      CELERY_RESULT_BACKEND: redis://:${REDIS_PASSWORD}@redis:6379/2
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USER: ${SMTP_USER}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_USE_TLS: ${SMTP_USE_TLS}
      SMTP_FROM_EMAIL: ${SMTP_FROM_EMAIL}
      SMTP_FROM_NAME: ${SMTP_FROM_NAME}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    depends_on:
      redis:
        condition: service_healthy
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    networks:
      - internal

  # ---------------------------------------------------------------------------
  # Internal nginx (API Gateway — routet an Microservices)
  # ---------------------------------------------------------------------------
  nginx:
    image: nginx:alpine
    container_name: ${STACK_NAME}-nginx
    restart: always
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./html:/usr/share/nginx/html:ro
      - upload_data:/data/uploads:ro
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

  # ---------------------------------------------------------------------------
  # Frontend Apps
  # ---------------------------------------------------------------------------
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

networks:
  internal:
    driver: bridge
  gastropilot-shared-proxy:
    external: true

volumes:
  redis_data:
  upload_data:
COMPOSEEOF

echo "  docker-compose.yml generiert."
echo

# ============================================
# 7. nginx.conf generieren (mit Maintenance + Coming-Soon)
# ============================================
step "7/11 — nginx.conf (interner API-Gateway)"

cat > nginx.conf << NGINXEOF
# nginx für ${STACK_NAME} (Microservices API-Gateway)
# Generiert von install.sh
#
# Unterstützt Maintenance-Modus und Coming-Soon-Seite:
#   touch /etc/nginx/maintenance.on   → Wartungsmodus
#   touch /etc/nginx/coming-soon.on   → Coming-Soon-Seite
#   rm -f /etc/nginx/<file>.on        → Deaktivieren
#   nginx -s reload                   → Anwenden
#
events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

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

    limit_req_zone \$binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=auth_limit:10m rate=10r/m;
    limit_req_zone \$binary_remote_addr zone=web_limit:10m rate=30r/s;

    set_real_ip_from 172.16.0.0/12;
    real_ip_header X-Real-IP;

    upstream core {
        server ${STACK_NAME}-core:8000 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    upstream orders {
        server ${STACK_NAME}-orders:8001 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    upstream ai {
        server ${STACK_NAME}-ai:8002 max_fails=3 fail_timeout=30s;
        keepalive 16;
    }

    upstream notifications {
        server ${STACK_NAME}-notifications:8003 max_fails=3 fail_timeout=30s;
        keepalive 16;
    }

    upstream web {
        server ${STACK_NAME}-web:3000 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    upstream dashboard {
        server ${STACK_NAME}-dashboard:3001 max_fails=3 fail_timeout=30s;
        keepalive 16;
    }

    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      '';
    }

    server {
        listen 80;
        server_name _;

        # Security-Header
        add_header X-Frame-Options SAMEORIGIN always;
        add_header X-Content-Type-Options nosniff always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # Statische HTML-Seiten (Maintenance, Coming-Soon)
        root /usr/share/nginx/html;

        # --- Health check (immer erreichbar, auch bei Maintenance) ---
        location /health {
            proxy_pass http://core/api/v1/health;
            access_log off;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }

        # --- Coming-Soon-Modus (Prio 1 — alles blockieren) ---
        # Aktivierung: touch /etc/nginx/coming-soon.on && nginx -s reload
        set \$coming_soon 0;
        if (-f /etc/nginx/coming-soon.on) {
            set \$coming_soon 1;
        }

        # --- Maintenance-Modus (Prio 2 — alles blockieren) ---
        # Aktivierung: touch /etc/nginx/maintenance.on && nginx -s reload
        set \$maintenance 0;
        if (-f /etc/nginx/maintenance.on) {
            set \$maintenance 1;
        }

        # API gibt bei Maintenance/Coming-Soon JSON zurück
        location ~ ^/(api/v1|v1)/(?!health) {
            if (\$coming_soon = 1) {
                return 503 '{"detail":"Coming soon","code":"COMING_SOON"}';
            }
            if (\$maintenance = 1) {
                return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}';
            }

            # --- Auth (strengeres Rate-Limit) ---
            # Wird per nested location unten gehandhabt
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://core;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header Connection "";
            proxy_buffering off;
        }

        # --- WebSocket (immer erreichbar, auch bei Maintenance) ---
        location /ws/ {
            proxy_pass http://orders;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_read_timeout 86400s;
            proxy_send_timeout 86400s;
        }

        # --- Webhooks (SumUp) ---
        location ~ ^/(api/v1|v1)/webhooks/sumup {
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://orders;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Webhooks (WhatsApp) ---
        location ~ ^/(api/v1|v1)/webhooks/whatsapp {
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://notifications;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Auth /me (kein Rate-Limit) ---
        location ~ ^/(api/v1|v1)/auth/me {
            if (\$coming_soon = 1) {
                return 503 '{"detail":"Coming soon","code":"COMING_SOON"}';
            }
            if (\$maintenance = 1) {
                return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}';
            }
            proxy_pass http://core;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Auth (strengeres Rate-Limit) ---
        location ~ ^/(api/v1|v1)/auth/ {
            if (\$coming_soon = 1) {
                return 503 '{"detail":"Coming soon","code":"COMING_SOON"}';
            }
            if (\$maintenance = 1) {
                return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}';
            }
            limit_req zone=auth_limit burst=20 nodelay;
            proxy_pass http://core;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Orders Service ---
        location ~ ^/(api/v1|v1)/(orders|kitchen|order-statistics|sumup|invoices|waitlist)(/|$) {
            if (\$coming_soon = 1) {
                return 503 '{"detail":"Coming soon","code":"COMING_SOON"}';
            }
            if (\$maintenance = 1) {
                return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}';
            }
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://orders;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header Connection "";
            proxy_buffering off;
        }

        # --- AI Service ---
        location ~ ^/(api/v1|v1)/ai(/|$) {
            if (\$coming_soon = 1) {
                return 503 '{"detail":"Coming soon","code":"COMING_SOON"}';
            }
            if (\$maintenance = 1) {
                return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}';
            }
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://ai;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Notifications Service ---
        location ~ ^/(api/v1|v1)/notifications(/|$) {
            if (\$coming_soon = 1) {
                return 503 '{"detail":"Coming soon","code":"COMING_SOON"}';
            }
            if (\$maintenance = 1) {
                return 503 '{"detail":"Wartungsarbeiten","code":"MAINTENANCE"}';
            }
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://notifications;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Uploads (Bilder, lokal gespeichert) ---
        location /uploads/ {
            alias /data/uploads/;
            expires 30d;
            add_header Cache-Control "public, max-age=2592000, immutable";
            add_header X-Content-Type-Options nosniff always;
            try_files \$uri =404;
        }

        # --- Next.js static assets (immer erreichbar) ---
        location /_next/static/ {
            proxy_pass http://web;
            proxy_http_version 1.1;
            expires 365d;
            add_header Cache-Control "public, immutable";
            proxy_set_header Host \$host;
        }

        # --- Web (catch-all, mit Coming-Soon / Maintenance) ---
        location / {
            if (\$coming_soon = 1) {
                rewrite ^ /coming-soon.html break;
            }
            if (\$maintenance = 1) {
                rewrite ^ /maintenance.html break;
            }
            limit_req zone=web_limit burst=50 nodelay;
            proxy_pass http://web;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
NGINXEOF

echo "  nginx.conf generiert."
echo

# ============================================
# 8. HTML-Seiten (Maintenance + Coming-Soon)
# ============================================
step "8/11 — Maintenance & Coming-Soon Seiten"

mkdir -p html

cat > html/maintenance.html << 'MAINTHTML'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Wartungsarbeiten — GastroPilot</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
            color: #e2e8f0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            text-align: center;
            max-width: 520px;
            padding: 2rem;
        }
        .icon {
            font-size: 4rem;
            margin-bottom: 1.5rem;
            animation: spin 3s linear infinite;
        }
        @keyframes spin {
            0%, 100% { transform: rotate(0deg); }
            50% { transform: rotate(180deg); }
        }
        h1 {
            font-size: 1.75rem;
            font-weight: 700;
            margin-bottom: 0.75rem;
            color: #f8fafc;
        }
        p {
            font-size: 1.05rem;
            line-height: 1.6;
            color: #94a3b8;
            margin-bottom: 0.5rem;
        }
        .brand {
            margin-top: 2.5rem;
            font-size: 0.85rem;
            color: #475569;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">&#9881;</div>
        <h1>Wartungsarbeiten</h1>
        <p>Wir führen gerade Wartungsarbeiten durch und sind in Kürze wieder erreichbar.</p>
        <p>Vielen Dank für Ihre Geduld.</p>
        <div class="brand">GastroPilot</div>
    </div>
</body>
</html>
MAINTHTML

cat > html/coming-soon.html << 'CSHTML'
<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Coming Soon — GastroPilot</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
            color: #e2e8f0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            text-align: center;
            max-width: 520px;
            padding: 2rem;
        }
        .icon {
            font-size: 4rem;
            margin-bottom: 1.5rem;
        }
        h1 {
            font-size: 2rem;
            font-weight: 700;
            margin-bottom: 0.75rem;
            color: #f8fafc;
        }
        p {
            font-size: 1.05rem;
            line-height: 1.6;
            color: #94a3b8;
            margin-bottom: 0.5rem;
        }
        .highlight {
            color: #38bdf8;
            font-weight: 600;
        }
        .brand {
            margin-top: 2.5rem;
            font-size: 0.85rem;
            color: #475569;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="icon">&#127860;</div>
        <h1>Bald verfügbar</h1>
        <p>Wir arbeiten mit Hochdruck an <span class="highlight">GastroPilot</span> &mdash; der intelligenten Lösung für Ihr Restaurant.</p>
        <p>Bleiben Sie gespannt!</p>
        <div class="brand">GastroPilot</div>
    </div>
</body>
</html>
CSHTML

echo "  html/maintenance.html erstellt."
echo "  html/coming-soon.html erstellt."
echo

# ============================================
# 9. Hilfs-Skripte generieren
# ============================================
step "9/11 — Hilfs-Skripte"

# --- coming-soon.sh ---
cat > coming-soon.sh << 'CSEOF'
#!/bin/bash
# Coming-Soon-Seite aktivieren/deaktivieren
STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot}-nginx"

case "$1" in
  on)
    docker exec "$CONTAINER" touch /etc/nginx/coming-soon.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Coming-Soon-Seite aktiviert."
    ;;
  off)
    docker exec "$CONTAINER" rm -f /etc/nginx/coming-soon.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Coming-Soon-Seite deaktiviert."
    ;;
  status)
    if docker exec "$CONTAINER" test -f /etc/nginx/coming-soon.on 2>/dev/null; then
        echo "Coming-Soon-Seite: AKTIV"
    else
        echo "Coming-Soon-Seite: INAKTIV"
    fi
    ;;
  *)
    echo "Verwendung: $0 {on|off|status}"
    exit 1
    ;;
esac
CSEOF
chmod +x coming-soon.sh
echo "  coming-soon.sh erstellt."

# --- maintenance.sh ---
cat > maintenance.sh << 'MAINTEOF'
#!/bin/bash
# Wartungsmodus aktivieren/deaktivieren
STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot}-nginx"

case "$1" in
  on)
    docker exec "$CONTAINER" touch /etc/nginx/maintenance.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Wartungsmodus aktiviert."
    ;;
  off)
    docker exec "$CONTAINER" rm -f /etc/nginx/maintenance.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Wartungsmodus deaktiviert."
    ;;
  status)
    if docker exec "$CONTAINER" test -f /etc/nginx/maintenance.on 2>/dev/null; then
        echo "Wartungsmodus: AKTIV"
    else
        echo "Wartungsmodus: INAKTIV"
    fi
    ;;
  *)
    echo "Verwendung: $0 {on|off|status}"
    exit 1
    ;;
esac
MAINTEOF
chmod +x maintenance.sh
echo "  maintenance.sh erstellt."

# --- update.sh ---
if [ ! -f "update.sh" ]; then
    cat > update.sh << 'UPDATEEOF'
#!/bin/bash
set -e
STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
STACK_NAME="${STACK_NAME:-gastropilot}"

echo "== GastroPilot Update ($STACK_NAME) =="

echo "== 1/4 Images pullen =="
docker compose pull

echo "== 2/4 DB-Migration =="
docker compose run --rm core alembic -c alembic.ini upgrade head 2>/dev/null || echo "  Migration übersprungen."

echo "== 3/4 Container starten =="
docker compose up -d

echo "== 4/4 nginx neu laden =="
sleep 3
docker restart "${STACK_NAME}-nginx"
docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || true

echo
echo "== Update abgeschlossen =="
docker compose ps
UPDATEEOF
    chmod +x update.sh
    echo "  update.sh erstellt."
fi
echo

# ============================================
# 10. SSL-Zertifikate & Proxy-Configs
# ============================================
step "10/11 — SSL-Zertifikate & Proxy-Configs"

SSL_BASE_DIR="$SHARED_PROXY_DIR/ssl"
PROXY_CONF_DIR="$SHARED_PROXY_DIR/conf.d"

# --- SSL ---
echo "  Prüfe SSL-Zertifikate..."
DOMAINS_NEEDING_CERT=()
for D in "${ALL_DOMAINS[@]}"; do
    if [ -f "$SSL_BASE_DIR/$D/fullchain.pem" ] && [ -f "$SSL_BASE_DIR/$D/privkey.pem" ]; then
        echo "    $D — vorhanden"
    else
        echo "    $D — fehlt"
        DOMAINS_NEEDING_CERT+=("$D")
    fi
done

if [ ${#DOMAINS_NEEDING_CERT[@]} -gt 0 ]; then
    echo
    echo "  ${#DOMAINS_NEEDING_CERT[@]} Domain(s) benötigen SSL-Zertifikate:"
    printf "    %s\n" "${DOMAINS_NEEDING_CERT[@]}"
    echo
    echo "  1) Let's Encrypt (certbot)"
    echo "  2) Selbstsignierte Zertifikate"
    echo "  3) überspringen"
    echo
    read -rp "  Auswahl [1/2/3]: " SSL_CHOICE

    if [ "$SSL_CHOICE" = "1" ]; then
        read -rp "  E-Mail für Let's Encrypt: " CERT_EMAIL
        echo "  Stoppe Shared Proxy für Zertifikat-Erstellung..."
        docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" stop proxy 2>/dev/null || trü

        for D in "${DOMAINS_NEEDING_CERT[@]}"; do
            echo "  Hole Zertifikat für $D..."
            mkdir -p "$SSL_BASE_DIR/$D"
            mkdir -p certbot
            docker run --rm -p 80:80 \
                -v "$(pwd)/certbot:/etc/letsencrypt" \
                certbot/certbot certonly --standalone \
                -d "$D" --non-interactive --agree-tos -m "$CERT_EMAIL"
            cp "certbot/live/$D/fullchain.pem" "$SSL_BASE_DIR/$D/"
            cp "certbot/live/$D/privkey.pem" "$SSL_BASE_DIR/$D/"
            echo "    $D — Zertifikat installiert."
        done

        docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
    elif [ "$SSL_CHOICE" = "2" ]; then
        if [ "$ENVIRONMENT" = "production" ]; then
            echo "  WARNUNG: Selbstsignierte Zertifikate für Production nicht empfohlen!"
            read -rp "  Trotzdem fortfahren? (j/N): " SSL_PROD_CONFIRM
            if [[ ! "$SSL_PROD_CONFIRM" =~ ^[jJ]$ ]]; then exit 1; fi
        fi
        for D in "${DOMAINS_NEEDING_CERT[@]}"; do
            mkdir -p "$SSL_BASE_DIR/$D"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$SSL_BASE_DIR/$D/privkey.pem" \
                -out "$SSL_BASE_DIR/$D/fullchain.pem" \
                -subj "/CN=$D" 2>/dev/null
            echo "    $D — selbstsigniert erstellt."
        done
        docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || true
    else
        echo "  Kopiere Zertifikate manuell nach $SSL_BASE_DIR/<domain>/"
    fi
fi
echo

# --- Proxy-Configs ---
echo "  Generiere Proxy-Configs..."

write_proxy_conf() {
    local CONF_FILE="$1" SERVER_NAME="$2" BACKEND_VAR="$3" BACKEND_TARGET="$4" DESCRIPTION="$5"

    cat > "$CONF_FILE" << PROXYEOF
# ${DESCRIPTION}
server {
    listen 443 ssl;
    http2 on;
    server_name ${SERVER_NAME};

    resolver 127.0.0.11 valid=10s ipv6=off;
    set \${BACKEND_VAR} ${BACKEND_TARGET};

    ssl_certificate /etc/nginx/ssl/${SERVER_NAME}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${SERVER_NAME}/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://\${BACKEND_VAR};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_buffering off;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
PROXYEOF
    echo "    $(basename "$CONF_FILE")"
}

write_proxy_conf "$PROXY_CONF_DIR/${DOMAIN}.conf" "$DOMAIN" \
    "backend" "${STACK_NAME}-nginx:80" "Web — Webseite + Gästeportal (gpilot.app)"

write_proxy_conf "$PROXY_CONF_DIR/${WEB_DOMAIN_ALT}.conf" "$WEB_DOMAIN_ALT" \
    "backend_alt" "${STACK_NAME}-nginx:80" "Web — Webseite + Gästeportal (gastropilot.org)"

write_proxy_conf "$PROXY_CONF_DIR/${APP_DOMAIN}.conf" "$APP_DOMAIN" \
    "dashboard_backend" "${STACK_NAME}-dashboard:3001" "Dashboard — Restaurant-Dashboard"

write_proxy_conf "$PROXY_CONF_DIR/${API_DOMAIN}.conf" "$API_DOMAIN" \
    "api_backend" "${STACK_NAME}-nginx:80" "API — Backend Microservices"

write_proxy_conf "$PROXY_CONF_DIR/${ORDER_DOMAIN}.conf" "$ORDER_DOMAIN" \
    "order_backend" "${STACK_NAME}-table-order:3003" "Table Order — QR-Tischbestellung"

write_proxy_conf "$PROXY_CONF_DIR/${KDS_DOMAIN}.conf" "$KDS_DOMAIN" \
    "kds_backend" "${STACK_NAME}-kds:3004" "KDS — Kitchen Display System"

echo "  Lade Shared Proxy neu..."
docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || \
    docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" restart
echo

# ============================================
# 11. SQL-Init & Container starten
# ============================================
step "11/11 — Container starten"

# SQL-Dateien kopieren oder herunterladen
echo "  SQL-Init-Dateien (Referenz für DB-Server)..."
for SQL_FILE in init.sql rls.sql; do
    [ -d "$SQL_FILE" ] && rm -rf "$SQL_FILE"
    if [ ! -f "$SQL_FILE" ]; then
        # 1. Lokal aus sql/ Unterverzeichnis
        if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/sql/$SQL_FILE" ]; then
            cp "$SCRIPT_DIR/sql/$SQL_FILE" "./$SQL_FILE"
            echo "    $SQL_FILE aus sql/ kopiert."
        # 2. Lokal aus infra/sql/
        elif [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/../infra/sql/$SQL_FILE" ]; then
            cp "$SCRIPT_DIR/../infra/sql/$SQL_FILE" "./$SQL_FILE"
            echo "    $SQL_FILE aus infra/sql/ kopiert."
        # 3. Remote herunterladen (curl | bash Modus)
        elif curl -fsSL "${DOWNLOAD_BASE_URL}/sql/${SQL_FILE}" -o "./$SQL_FILE" 2>/dev/null; then
            echo "    $SQL_FILE heruntergeladen."
        else
            echo "    HINWEIS: $SQL_FILE nicht gefunden — manuell auf DB-Server ausführen."
        fi
    else
        echo "    $SQL_FILE vorhanden."
    fi
done
echo

echo "  Pullen der Images..."
docker compose pull
echo
echo "  Starte Container..."
docker compose up -d

echo
echo "  Warte auf Core-Service..."
for i in $(seq 1 30); do
    if docker exec "${STACK_NAME}-core" python -c \
        "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')" > /dev/null 2>&1; then
        echo "  Core-Service bereit."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  Warnung: Core-Service antwortet noch nicht."
        echo "  Prüfe: docker compose logs core"
    fi
    sleep 2
done

echo
echo "  Führe DB-Migration aus..."
docker compose exec core alembic -c alembic.ini upgrade head 2>/dev/null || \
    echo "  Migration übersprungen (ggf. init.sql auf DB-Server ausführen)."

echo
echo "  Service-Status:"
for svc in core orders ai notifications notifications-worker web dashboard table-order kds nginx redis; do
    CONTAINER="${STACK_NAME}-${svc}"
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "nicht gefunden")
    HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$CONTAINER" 2>/dev/null || echo "-")
    printf "    %-25s %-10s %s\n" "$svc" "$STATUS" "$HEALTH"
done
echo

# Admin-Account
read -rp "  Platform-Admin erstellen? (J/n): " ADMIN_CHOICE
if [[ ! "$ADMIN_CHOICE" =~ ^[nN]$ ]]; then
    echo
    read -rp "  E-Mail: " ADMIN_EMAIL
    read -rp "  Vorname: " ADMIN_FIRST_NAME
    read -rp "  Nachname: " ADMIN_LAST_NAME
    read -rsp "  Passwort (min. 8 Zeichen): " ADMIN_PASSWORD
    echo

    if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
        echo "  Fehler: Passwort muss mindestens 8 Zeichen lang sein."
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
    print(f'  Platform-Admin erstellt: {user.first_name} {user.last_name} ({user.email})')

asyncio.run(create_admin())
"
    fi
fi

# ============================================
header "Installation abgeschlossen!"
# ============================================

echo "Environment:  $ENVIRONMENT"
echo "Stack:        $STACK_NAME"
echo "Image-Tag:    $IMAGE_TAG"
echo
echo "Datenbank (extern):"
echo "  Primary:    ${DB_HOST}:${DB_PORT}/${DB_NAME}"
if [ "$HAS_REPLICA" = "true" ]; then
    echo "  Replica:    ${REPLICA_HOST}:${REPLICA_PORT}/${DB_NAME}"
fi
echo "  SSL:        ${DB_SSL_MODE}"
echo
echo "Domains:"
echo "  Webseite:     https://$DOMAIN"
echo "  Webseite:     https://$WEB_DOMAIN_ALT (Alt)"
echo "  Dashboard:    https://$APP_DOMAIN"
echo "  API:          https://$API_DOMAIN"
echo "  Table Order:  https://$ORDER_DOMAIN"
echo "  KDS:          https://$KDS_DOMAIN"
echo
echo "Dateien:"
echo "  .env                — Konfiguration & Secrets"
echo "  docker-compose.yml  — Service-Definition"
echo "  nginx.conf          — Interner API-Gateway"
echo "  html/               — Maintenance & Coming-Soon Seiten"
echo "  update.sh           — Update (Pull + Migration + Restart)"
echo "  maintenance.sh      — Wartungsmodus {on|off|status}"
echo "  coming-soon.sh      — Coming-Soon-Seite {on|off|status}"
echo "  init.sql / rls.sql  — DB-Schema (Referenz)"
echo
echo "Befehle:"
echo "  ./update.sh                — Update ausführen"
echo "  ./maintenance.sh on|off    — Wartungsmodus"
echo "  ./coming-soon.sh on|off    — Coming-Soon-Seite"
echo "  docker compose logs -f     — Alle Logs"
echo "  docker compose ps          — Service-Status"
echo
