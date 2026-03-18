#!/bin/bash
# =========================================
#  GastroPilot — Server-Installation
# =========================================
#
# Installiert eine GastroPilot-Umgebung (Test/Staging/Demo).
# Erzeugt docker-compose.yml, .env, Proxy-Configs und SSL-Zertifikate.
#
# Voraussetzungen:
#   - Docker + Docker Compose v2
#   - Shared Proxy unter /opt/shared-proxy
#
# Verwendung:
#   Ins Zielverzeichnis kopieren und ausfuehren:
#   cp install.sh /opt/staging/ && cd /opt/staging && ./install.sh
#
# Microservices:
#   core (8000)          — Auth, Users, Restaurants, Reservierungen, Menue
#   orders (8001)        — Bestellungen, Kitchen, Payments, WebSocket
#   ai (8002)            — Sitzplatz-Optimierung, Prognosen
#   notifications (8003) — E-Mail, SMS, Push, WhatsApp
#   web (3000)           — Webseite + Gaesteportal
#   dashboard (3001)     — Restaurant-Dashboard
#   table-order (3003)   — QR-Tischbestellung
#   kds (3004)           — Kitchen Display System
#
set -e

SHARED_PROXY_DIR="/opt/shared-proxy"
ENV_FILE=".env"

# -------------------------------------------
# Hilfsfunktionen
# -------------------------------------------
generate_secret() {
    openssl rand -base64 32 | tr -d '/+=' | head -c 44
}

generate_hex() {
    openssl rand -hex 32
}

header() {
    echo
    echo "==========================================="
    echo "  $1"
    echo "==========================================="
    echo
}

step() {
    echo "== $1 =="
}

# -------------------------------------------
header "GastroPilot — Server-Installation"
# -------------------------------------------

# ============================================
# 1. Voraussetzungen
# ============================================
step "1/9 — Voraussetzungen pruefen"

for cmd in docker openssl curl; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Fehler: '$cmd' ist nicht installiert."
        exit 1
    fi
done

if ! docker compose version &> /dev/null; then
    echo "Fehler: Docker Compose (v2) ist nicht installiert."
    exit 1
fi

echo "  Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo "  Docker Compose $(docker compose version --short)"

if [ ! -d "$SHARED_PROXY_DIR" ]; then
    echo "Fehler: Shared Proxy nicht gefunden unter $SHARED_PROXY_DIR"
    exit 1
fi
echo "  Shared Proxy: $SHARED_PROXY_DIR"
echo

# ============================================
# 2. Environment & Domain-Konfiguration
# ============================================
step "2/9 — Environment & Konfiguration"

echo "  Verfuegbare Environments:"
echo "    1) test"
echo "    2) staging"
echo "    3) demo"
echo
read -rp "  Environment [1/2/3]: " ENV_CHOICE

case "$ENV_CHOICE" in
    1) ENVIRONMENT="test" ;;
    2) ENVIRONMENT="staging" ;;
    3) ENVIRONMENT="demo" ;;
    *) echo "Fehler: Ungueltige Auswahl."; exit 1 ;;
esac

STACK_NAME="gastropilot-${ENVIRONMENT}"
IMAGE_TAG="${ENVIRONMENT}"

echo "  Environment: $ENVIRONMENT"
echo "  Stack-Name:  $STACK_NAME"
echo "  Image-Tag:   $IMAGE_TAG"
echo

# Secrets generieren
POSTGRES_PASSWORD=$(generate_secret)
REDIS_PASSWORD=$(generate_secret)
JWT_SECRET=$(generate_hex)
AUTH_SECRET=$(generate_secret)

# Domain-Prefix (z.B. "stage" fuer stage.gpilot.app)
read -rp "  Domain-Prefix (z.B. stage, demo, test): " DOMAIN_PREFIX
echo
echo "  Folgende Subdomains werden konfiguriert:"
echo "    ${DOMAIN_PREFIX}.gpilot.app             — Webseite + Gaesteportal"
echo "    ${DOMAIN_PREFIX}-dashboard.gpilot.app         — Restaurant-Dashboard"
echo "    ${DOMAIN_PREFIX}-api.gpilot.app         — API (Backend)"
echo "    ${DOMAIN_PREFIX}-order.gpilot.app       — Tischbestellung"
echo "    ${DOMAIN_PREFIX}-kds.gpilot.app         — Kitchen Display"
echo
read -rp "  Korrekt? (J/n): " DOMAIN_CONFIRM
if [[ "$DOMAIN_CONFIRM" =~ ^[nN]$ ]]; then
    echo "  Abgebrochen."
    exit 0
fi

DOMAIN="${DOMAIN_PREFIX}.gpilot.app"
APP_DOMAIN="${DOMAIN_PREFIX}-dashboard.gpilot.app"
API_DOMAIN="${DOMAIN_PREFIX}-api.gpilot.app"
ORDER_DOMAIN="${DOMAIN_PREFIX}-order.gpilot.app"
KDS_DOMAIN="${DOMAIN_PREFIX}-kds.gpilot.app"

ALL_DOMAINS=("$DOMAIN" "$APP_DOMAIN" "$API_DOMAIN" "$ORDER_DOMAIN" "$KDS_DOMAIN")

# SMTP (optional)
echo
read -rp "  SMTP konfigurieren fuer E-Mail-Versand? (j/N): " SMTP_CHOICE
if [[ "$SMTP_CHOICE" =~ ^[jJ]$ ]]; then
    read -rp "    SMTP Host: " SMTP_HOST
    read -rp "    SMTP Port [587]: " SMTP_PORT
    SMTP_PORT=${SMTP_PORT:-587}
    read -rp "    SMTP User: " SMTP_USER
    read -rsp "    SMTP Passwort: " SMTP_PASSWORD
    echo
    read -rp "    Absender-E-Mail [noreply@gpilot.app]: " SMTP_FROM_EMAIL
    SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-noreply@gpilot.app}
else
    SMTP_HOST="localhost"
    SMTP_PORT="587"
    SMTP_USER=""
    SMTP_PASSWORD=""
    SMTP_FROM_EMAIL="noreply@gpilot.app"
fi

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

# ==================== POSTGRESQL ====================
POSTGRES_DB=gastropilot_${ENVIRONMENT}
POSTGRES_USER=gastropilot_${ENVIRONMENT}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_SSL_VERIFY=false

# ==================== AUTH & SECURITY ====================
JWT_SECRET=${JWT_SECRET}
JWT_ALGORITHM=HS256
JWT_ISSUER=gastropilot_${ENVIRONMENT}
JWT_AUDIENCE=gastropilot_${ENVIRONMENT}-api
JWT_LEEWAY_SECONDS=10
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
BCRYPT_ROUNDS=12

# CORS & Security
CORS_ORIGINS=https://${DOMAIN},https://${APP_DOMAIN},https://${API_DOMAIN},https://${ORDER_DOMAIN},https://${KDS_DOMAIN}
CORS_ALLOW_CREDENTIALS=true
ALLOWED_HOSTS=${DOMAIN},${APP_DOMAIN},${API_DOMAIN},${ORDER_DOMAIN},${KDS_DOMAIN}

# Logging
LOG_LEVEL=INFO

# ==================== REDIS ====================
REDIS_PASSWORD=${REDIS_PASSWORD}

# ==================== E-MAIL (SMTP) ====================
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_USE_TLS=true
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}
SMTP_FROM_NAME=GastroPilot ${ENVIRONMENT^}

# ==================== WEB (Webseite + Gaesteportal) ====================
WEB_BASE_URL=https://${DOMAIN}

# ==================== DASHBOARD (Restaurant) ====================
BASE_URL=https://${APP_DOMAIN}
NEXT_PUBLIC_API_BASE_URL=https://${API_DOMAIN}
NEXT_PUBLIC_API_PREFIX=api/v1
AUTH_SECRET=${AUTH_SECRET}

# ==================== DOMAINS (fuer docker-compose) ====================
WEB_DOMAIN=${DOMAIN}
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

# ============================================
# 3. docker-compose.yml generieren
# ============================================
step "3/9 — docker-compose.yml generieren"

cat > docker-compose.yml << 'COMPOSEEOF'
# GastroPilot — Server Stack
# Generiert von install.sh

services:
  # ---------------------------------------------------------------------------
  # Infrastruktur
  # ---------------------------------------------------------------------------
  postgres:
    image: postgres:16-alpine
    container_name: ${STACK_NAME}-postgres
    restart: always
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/01_init.sql
      - ./rls.sql:/docker-entrypoint-initdb.d/02_rls.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    deploy:
      resources:
        limits:
          cpus: "2"
          memory: 1G
    networks:
      - internal

  redis:
    image: redis:7-alpine
    container_name: ${STACK_NAME}-redis
    restart: always
    command: >
      redis-server
      --appendonly yes
      --maxmemory 512mb
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
      DATABASE_URL: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      DATABASE_ADMIN_URL: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
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
    depends_on:
      postgres:
        condition: service_healthy
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
      DATABASE_URL: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      DATABASE_ADMIN_URL: postgresql+asyncpg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379/0
      JWT_SECRET: ${JWT_SECRET}
      JWT_ALGORITHM: ${JWT_ALGORITHM}
      CORS_ORIGINS: ${CORS_ORIGINS}
      LOG_LEVEL: ${LOG_LEVEL}
      ENVIRONMENT: ${ENVIRONMENT}
    depends_on:
      postgres:
        condition: service_healthy
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
  postgres_data:
  redis_data:
COMPOSEEOF

echo "  docker-compose.yml generiert."

# ============================================
# 4. nginx-Configs kopieren
# ============================================
step "4/9 — nginx-Configs"

# Generiere nginx.conf (vollstaendige Config wie Staging-Setup)
if [ ! -f "nginx.conf" ]; then
    cat > nginx.conf << NGINXEOF
# nginx fuer ${STACK_NAME} (Microservices Setup)
# Generiert von install.sh
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

        # --- Health checks ---
        location /health {
            proxy_pass http://core/api/v1/health;
            access_log off;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
        }

        # --- WebSocket (Orders Service) ---
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

        # --- Webhooks ---
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

        # --- Orders Service ---
        location ~ ^/(api/v1|v1)/(orders|kitchen|order-statistics|sumup|invoices|waitlist)(/|$) {
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
            limit_req zone=api_limit burst=20 nodelay;
            proxy_pass http://ai;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
            proxy_set_header Connection "";
        }

        # --- Core Service (default API) ---
        location ~ ^/(api/v1|v1)/ {
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

        # --- Next.js static assets ---
        location /_next/static/ {
            proxy_pass http://web;
            proxy_http_version 1.1;
            expires 365d;
            add_header Cache-Control "public, immutable";
            proxy_set_header Host \$host;
        }

        # --- Web (catch-all) ---
        location / {
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
else
    echo "  nginx.conf vorhanden."
fi
echo

# ============================================
# 5. SQL-Init-Dateien kopieren
# ============================================
step "5/9 — SQL-Init-Dateien"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Versuche init.sql und rls.sql aus dem Repo zu kopieren (falls install.sh aus infra/ ausgefuehrt wird)
for SQL_FILE in init.sql rls.sql; do
    # Docker legt fehlende Mount-Ziele als Verzeichnisse an — aufraeumen
    if [ -d "$SQL_FILE" ]; then
        rm -rf "$SQL_FILE"
    fi

    if [ ! -f "$SQL_FILE" ]; then
        if [ -f "$SCRIPT_DIR/sql/$SQL_FILE" ]; then
            cp "$SCRIPT_DIR/sql/$SQL_FILE" "./$SQL_FILE"
            echo "  $SQL_FILE aus infra/sql/ kopiert."
        elif [ -f "$SCRIPT_DIR/../infra/sql/$SQL_FILE" ]; then
            cp "$SCRIPT_DIR/../infra/sql/$SQL_FILE" "./$SQL_FILE"
            echo "  $SQL_FILE aus infra/sql/ kopiert."
        else
            echo "  FEHLER: $SQL_FILE nicht gefunden!"
            echo "  Bitte manuell kopieren: scp infra/sql/$SQL_FILE user@server:$(pwd)/"
            exit 1
        fi
    else
        echo "  $SQL_FILE vorhanden."
    fi
done
echo

# ============================================
# 6. SSL-Zertifikate
# ============================================
step "6/9 — SSL-Zertifikate"

SSL_BASE_DIR="$SHARED_PROXY_DIR/ssl"

echo "  Pruefe SSL-Zertifikate fuer ${#ALL_DOMAINS[@]} Domains..."
echo

DOMAINS_NEEDING_CERT=()
for D in "${ALL_DOMAINS[@]}"; do
    if [ -f "$SSL_BASE_DIR/$D/fullchain.pem" ] && [ -f "$SSL_BASE_DIR/$D/privkey.pem" ]; then
        echo "  $D — vorhanden"
    else
        echo "  $D — fehlt"
        DOMAINS_NEEDING_CERT+=("$D")
    fi
done

if [ ${#DOMAINS_NEEDING_CERT[@]} -gt 0 ]; then
    echo
    echo "  ${#DOMAINS_NEEDING_CERT[@]} Domain(s) benoetigen SSL-Zertifikate:"
    printf "    %s\n" "${DOMAINS_NEEDING_CERT[@]}"
    echo
    echo "  1) Let's Encrypt (certbot) — einzeln pro Domain"
    echo "  2) Selbstsignierte Zertifikate — Test/Entwicklung"
    echo "  3) Ueberspringen — ich kopiere die Zertifikate selbst"
    echo
    read -rp "  Auswahl [1/2/3]: " SSL_CHOICE

    if [ "$SSL_CHOICE" = "1" ]; then
        read -rp "  E-Mail fuer Let's Encrypt: " CERT_EMAIL
        # Port 80 ggf. freigeben
        PORT80_CONTAINERS=$(docker ps --filter "publish=80" -q 2>/dev/null)
        if [ -n "$PORT80_CONTAINERS" ]; then
            echo "  Stoppe Container auf Port 80..."
            docker stop $PORT80_CONTAINERS 2>/dev/null || true
        fi

        for D in "${DOMAINS_NEEDING_CERT[@]}"; do
            echo "  Hole Zertifikat fuer $D..."
            mkdir -p "$SSL_BASE_DIR/$D"
            mkdir -p certbot
            docker run --rm -p 80:80 \
                -v "$(pwd)/certbot:/etc/letsencrypt" \
                certbot/certbot certonly --standalone \
                -d "$D" \
                --non-interactive --agree-tos \
                -m "$CERT_EMAIL"
            cp "certbot/live/$D/fullchain.pem" "$SSL_BASE_DIR/$D/"
            cp "certbot/live/$D/privkey.pem" "$SSL_BASE_DIR/$D/"
            echo "  $D — Zertifikat installiert."
        done

        # Port 80 Container wieder starten
        if [ -n "$PORT80_CONTAINERS" ]; then
            echo "  Starte gestoppte Container..."
            docker start $PORT80_CONTAINERS 2>/dev/null || true
        fi

    elif [ "$SSL_CHOICE" = "2" ]; then
        for D in "${DOMAINS_NEEDING_CERT[@]}"; do
            mkdir -p "$SSL_BASE_DIR/$D"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$SSL_BASE_DIR/$D/privkey.pem" \
                -out "$SSL_BASE_DIR/$D/fullchain.pem" \
                -subj "/CN=$D" 2>/dev/null
            echo "  $D — selbstsigniert erstellt."
        done
    else
        echo "  Kopiere Zertifikate nach $SSL_BASE_DIR/<domain>/ und starte install.sh erneut."
    fi
fi
echo

# ============================================
# 7. Shared-Proxy-Configs generieren
# ============================================
step "7/9 — Proxy-Configs fuer Shared Proxy"

PROXY_CONF_DIR="$SHARED_PROXY_DIR/conf.d"

# Template-Funktion fuer Proxy-Configs
write_proxy_conf() {
    local CONF_FILE="$1"
    local SERVER_NAME="$2"
    local BACKEND_VAR="$3"
    local BACKEND_TARGET="$4"
    local DESCRIPTION="$5"

    cat > "$CONF_FILE" << PROXYEOF
# ${DESCRIPTION}
server {
    listen 443 ssl;
    http2 on;
    server_name ${SERVER_NAME};

    resolver 127.0.0.11 valid=10s ipv6=off;
    set \$${BACKEND_VAR} ${BACKEND_TARGET};

    ssl_certificate /etc/nginx/ssl/${SERVER_NAME}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${SERVER_NAME}/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://\$${BACKEND_VAR};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$http_x_forwarded_proto;
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
    echo "  $(basename "$CONF_FILE") erstellt."
}

# Web (Webseite + Gaesteportal — Hauptdomain via interner nginx)
write_proxy_conf \
    "$PROXY_CONF_DIR/${DOMAIN}.conf" \
    "$DOMAIN" \
    "backend" \
    "${STACK_NAME}-nginx:80" \
    "Web — Webseite + Gaesteportal via internem nginx"

# Dashboard (Restaurant-Dashboard — eigene Subdomain, direkt)
write_proxy_conf \
    "$PROXY_CONF_DIR/${APP_DOMAIN}.conf" \
    "$APP_DOMAIN" \
    "dashboard_backend" \
    "${STACK_NAME}-dashboard:3001" \
    "Dashboard — Restaurant-Dashboard"

# API
write_proxy_conf \
    "$PROXY_CONF_DIR/${API_DOMAIN}.conf" \
    "$API_DOMAIN" \
    "api_backend" \
    "${STACK_NAME}-nginx:80" \
    "API — Backend Microservices via internem nginx"

# Table Order
write_proxy_conf \
    "$PROXY_CONF_DIR/${ORDER_DOMAIN}.conf" \
    "$ORDER_DOMAIN" \
    "order_backend" \
    "${STACK_NAME}-table-order:3003" \
    "Table Order — QR-Tischbestellung"

# KDS
write_proxy_conf \
    "$PROXY_CONF_DIR/${KDS_DOMAIN}.conf" \
    "$KDS_DOMAIN" \
    "kds_backend" \
    "${STACK_NAME}-kds:3004" \
    "KDS — Kitchen Display System"

# Alte Portal-Config entfernen (falls vorhanden)
PORTAL_DOMAIN="${DOMAIN_PREFIX}-portal.gpilot.app"
if [ -f "$PROXY_CONF_DIR/${PORTAL_DOMAIN}.conf" ]; then
    rm -f "$PROXY_CONF_DIR/${PORTAL_DOMAIN}.conf"
    echo "  ${PORTAL_DOMAIN}.conf entfernt (guest-portal nicht mehr vorhanden)."
fi

# Shared Proxy neu laden
echo "  Lade Shared Proxy neu..."
docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || \
    docker compose -f "$SHARED_PROXY_DIR/docker-compose.proxy.yml" up -d
echo

# ============================================
# 8. Update-Skript & Container starten
# ============================================
step "8/9 — Update-Skript & Container starten"

if [ ! -f "update.sh" ]; then
    cat > update.sh << 'UPDATEEOF'
#!/bin/bash
set -e
STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
STACK_NAME="${STACK_NAME:-gastropilot}"

echo "== GastroPilot Update ($STACK_NAME) =="

echo "== 1/5 Images pullen =="
docker compose pull

echo "== 2/5 Infrastruktur starten =="
docker compose up -d postgres redis
echo "  Warte auf Datenbank..."
for i in $(seq 1 15); do
    if docker compose exec -T postgres pg_isready -q 2>/dev/null; then break; fi
    sleep 2
done

echo "== 3/5 DB-Migration =="
docker compose run --rm core alembic -c alembic.ini upgrade head 2>/dev/null || echo "  Migration uebersprungen."

echo "== 4/5 Container starten =="
docker compose up -d

echo "== 5/5 nginx neu laden =="
sleep 3
docker restart "${STACK_NAME}-nginx"
docker exec gastropilot-shared-proxy nginx -s reload 2>/dev/null || true

echo
echo "== Update abgeschlossen =="
docker compose ps
UPDATEEOF
    chmod +x update.sh
    echo "  update.sh erstellt."
else
    echo "  update.sh vorhanden."
fi

# Container starten
echo
echo "  Pullen der Images..."
docker compose pull
echo
echo "  Starte Container..."
docker compose up -d

# Auf Core-Service warten
echo
echo "  Warte auf Core-Service..."
for i in $(seq 1 30); do
    if docker exec "${STACK_NAME}-core" python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/api/v1/health')" > /dev/null 2>&1; then
        echo "  Core-Service bereit."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  Warnung: Core-Service antwortet noch nicht."
        echo "  Pruefe: docker compose logs core"
    fi
    sleep 2
done

# DB-Migration
echo
echo "  Fuehre DB-Migration aus..."
docker compose exec core alembic -c alembic.ini upgrade head 2>/dev/null || echo "  Migration uebersprungen."

# Status
echo
echo "  Service-Status:"
for svc in core orders ai notifications web dashboard table-order kds nginx; do
    CONTAINER="${STACK_NAME}-${svc}"
    STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER" 2>/dev/null || echo "nicht gefunden")
    HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}-{{end}}' "$CONTAINER" 2>/dev/null || echo "-")
    printf "    %-20s %-10s %s\n" "$svc" "$STATUS" "$HEALTH"
done
echo

# ============================================
# 9. Admin-Account & Abschluss
# ============================================
step "9/9 — Admin-Account & Abschluss"

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
echo "Domains:"
echo "  Webseite:     https://$DOMAIN"
echo "  Dashboard:    https://$APP_DOMAIN"
echo "  API:          https://$API_DOMAIN"
echo "  Table Order:  https://$ORDER_DOMAIN"
echo "  KDS:          https://$KDS_DOMAIN"
echo
echo "Services:"
echo "  core          — Auth, Users, Restaurants, Reservierungen"
echo "  orders        — Bestellungen, Kitchen, Payments"
echo "  ai            — Sitzplatz-Optimierung, Prognosen"
echo "  notifications — E-Mail, SMS, WhatsApp"
echo "  web           — Webseite + Gaesteportal"
echo "  dashboard     — Restaurant-Dashboard"
echo "  table-order   — QR-Tischbestellung"
echo "  kds           — Kitchen Display System"
echo
echo "Dateien:"
echo "  .env              — Konfiguration & Secrets"
echo "  docker-compose.yml — Service-Definition"
echo "  update.sh         — Update (Pull + Migration + Restart)"
echo
echo "Befehle:"
echo "  ./update.sh                    — Update ausfuehren"
echo "  docker compose logs -f         — Alle Logs"
echo "  docker compose logs -f core    — Core-Logs"
echo "  docker compose ps              — Service-Status"
echo "  docker compose exec core alembic upgrade head — DB-Migration"
echo
