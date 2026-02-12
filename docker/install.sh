#!/bin/bash
# =========================================
#  GastroPilot — Server-Installation
# =========================================
#
# Verwendung:
#   mkdir gastropilot && cd gastropilot
#   gh api repos/GastroPilot/GastroPilot/contents/docker/install.sh?ref=main --jq '.content' | base64 -d > install.sh
#   chmod +x install.sh
#   ./install.sh
#
set -e

REPO="https://github.com/GastroPilot/GastroPilot.git"
BRANCH="main"
COMPOSE_FILE="docker-compose.server.yml"
ENV_FILE=".env.server"

# STACK_NAME aus .env.server lesen (falls vorhanden), sonst Default
STACK_NAME=$(grep -E '^STACK_NAME=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
STACK_NAME="${STACK_NAME:-gastropilot}"

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
step "1/11 — Voraussetzungen pruefen"

for cmd in docker git openssl curl; do
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
echo "  Git $(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
echo

# ============================================
# 2. GitHub Zugangsdaten
# ============================================
step "2/11 — Zugangsdaten"

# GitHub (fuer Repository-Clone)
echo "  --- GitHub ---"
read -rp "  GitHub Username: " GH_USER
read -rsp "  GitHub Token (repo): " GH_TOKEN
echo
echo

REPO_AUTH="https://${GH_USER}:${GH_TOKEN}@github.com/GastroPilot/GastroPilot.git"

# Docker Hub (fuer private Images)
echo "  --- Docker Hub ---"
read -rp "  Docker Hub Username: " DH_USER
read -rsp "  Docker Hub Token: " DH_TOKEN
echo
echo

echo "  Docker Hub Login..."
echo "$DH_TOKEN" | docker login -u "$DH_USER" --password-stdin
echo

# ============================================
# 3. Dateien aus GitHub holen
# ============================================
step "3/11 — Dateien aus GitHub holen"

if [ -f "$COMPOSE_FILE" ]; then
    echo "  Docker-Dateien bereits vorhanden — ueberspringe Clone."
    echo "  (Zum Aktualisieren: git pull)"
else
    echo "  Verfuegbare Environments:"
    echo "    1) Staging"
    echo "    2) Demo"
    echo "    3) Production"
    echo "    4) Test"
    read -rp "  Auswahl [1/2/3/4]: " ENV_CHOICE
    case "$ENV_CHOICE" in
        1)
            STACK_NAME="gastropilot-staging"
            IMAGE_TAG="staging"
            ;;
        2)
            STACK_NAME="gastropilot-demo"
            IMAGE_TAG="demo"
            ;;
        3)
            STACK_NAME="gastropilot"
            IMAGE_TAG="latest"
            ;;
        4)
            STACK_NAME="gastropilot-test"
            IMAGE_TAG="test"
            ;;
        *)
            echo "  Ungueltige Auswahl. Abbruch."
            exit 1
            ;;
    esac
    echo
    echo "  Lade docker/ Verzeichnis (Branch: $BRANCH)..."
    git clone --depth 1 --branch "$BRANCH" --sparse "$REPO_AUTH" _repo_tmp 2>&1 | grep -v "^remote:"
    cd _repo_tmp
    git sparse-checkout set docker
    cd ..
    # Dateien in aktuelles Verzeichnis verschieben
    cp -r _repo_tmp/docker/* _repo_tmp/docker/.gitignore .
    rm -rf _repo_tmp
    echo "  Dateien erfolgreich heruntergeladen."
fi
echo

# ============================================
# 4. Domain & Grundkonfiguration
# ============================================
step "4/11 — Konfiguration"

if [ -f "$ENV_FILE" ]; then
    echo "  $ENV_FILE existiert bereits — ueberspringe Konfiguration."
    echo "  (Zum Aendern: nano $ENV_FILE)"
else
    echo "  Erstelle $ENV_FILE..."
    echo

    # Domain
    read -rp "  Domain (z.B. staging.gpilot.app): " DOMAIN
    BASE_URL="https://${DOMAIN}"

    # API Domain
    API_DOMAIN_DEFAULT="api-${DOMAIN}"
    read -rp "  API Domain [${API_DOMAIN_DEFAULT}]: " API_DOMAIN
    API_DOMAIN=${API_DOMAIN:-$API_DOMAIN_DEFAULT}

    # Secrets automatisch generieren
    echo "  Generiere Secrets..."
    POSTGRES_PASSWORD=$(generate_secret)
    JWT_SECRET=$(generate_hex)
    AUTH_SECRET=$(generate_secret)
    REDIS_PASSWORD=$(generate_secret)

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
        read -rp "    Absender-E-Mail [noreply@${DOMAIN}]: " SMTP_FROM_EMAIL
        SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-noreply@${DOMAIN}}
    else
        SMTP_HOST="localhost"
        SMTP_PORT="587"
        SMTP_USER=""
        SMTP_PASSWORD=""
        SMTP_FROM_EMAIL="noreply@${DOMAIN}"
    fi

    # Mothership (optional)
    echo
    read -rp "  Mothership (Lizenzverwaltung) konfigurieren? (j/N): " MS_CHOICE
    if [[ "$MS_CHOICE" =~ ^[jJ]$ ]]; then
        read -rp "    Mothership API URL: " MOTHERSHIP_API_URL
        read -rsp "    Mothership API Key: " MOTHERSHIP_API_KEY
        echo
    else
        MOTHERSHIP_API_URL=""
        MOTHERSHIP_API_KEY=""
    fi

    # OpenAI (optional)
    echo
    read -rp "  OpenAI konfigurieren? (j/N): " OPENAI_CHOICE
    if [[ "$OPENAI_CHOICE" =~ ^[jJ]$ ]]; then
        read -rsp "    OpenAI API Key: " OPENAI_API_KEY
        echo
    else
        OPENAI_API_KEY=""
    fi

    # Twilio (optional)
    echo
    read -rp "  Twilio (SMS/Telefonie) konfigurieren? (j/N): " TWILIO_CHOICE
    if [[ "$TWILIO_CHOICE" =~ ^[jJ]$ ]]; then
        read -rp "    Twilio Account SID: " TWILIO_ACCOUNT_SID
        read -rsp "    Twilio Auth Token: " TWILIO_AUTH_TOKEN
        echo
        read -rp "    Twilio Phone Number (z.B. +49...): " TWILIO_PHONE_NUMBER
    else
        TWILIO_ACCOUNT_SID=""
        TWILIO_AUTH_TOKEN=""
        TWILIO_PHONE_NUMBER=""
    fi

    # SumUp (optional)
    echo
    read -rp "  SumUp (Zahlungen) konfigurieren? (j/N): " SUMUP_CHOICE
    if [[ "$SUMUP_CHOICE" =~ ^[jJ]$ ]]; then
        read -rsp "    SumUp API Key: " SUMUP_API_KEY
        echo
        read -rp "    SumUp Merchant Code: " SUMUP_MERCHANT_CODE
        read -rp "    SumUp Callback URL [${BASE_URL}/v1/payments/callback]: " SUMUP_CALLBACK_URL
        SUMUP_CALLBACK_URL=${SUMUP_CALLBACK_URL:-${BASE_URL}/v1/payments/callback}
    else
        SUMUP_API_KEY=""
        SUMUP_MERCHANT_CODE=""
        SUMUP_CALLBACK_URL=""
    fi

    # Sentry (optional)
    echo
    read -rp "  Sentry (Error Tracking) konfigurieren? (j/N): " SENTRY_CHOICE
    if [[ "$SENTRY_CHOICE" =~ ^[jJ]$ ]]; then
        read -rp "    Sentry DSN: " SENTRY_DSN
    else
        SENTRY_DSN=""
    fi

    # .env.server schreiben
    cat > "$ENV_FILE" << ENVEOF
# GastroPilot Server Environment
# Generiert am $(date +%Y-%m-%d)

# ==================== STACK ====================
STACK_NAME=${STACK_NAME}
API_DOMAIN=${API_DOMAIN}

# ==================== IMAGE ====================
IMAGE_TAG=${IMAGE_TAG}

# ==================== POSTGRESQL ====================
POSTGRES_DB=gastropilot
POSTGRES_USER=gastropilot
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
DATABASE_SSL_VERIFY=false

# ==================== BACKEND ====================
JWT_SECRET=${JWT_SECRET}
JWT_ALGORITHM=HS256
JWT_ISSUER=gastropilot
JWT_AUDIENCE=gastropilot-api
JWT_LEEWAY_SECONDS=10
ACCESS_TOKEN_EXPIRE_MINUTES=15
REFRESH_TOKEN_EXPIRE_DAYS=30
BCRYPT_ROUNDS=12

# CORS & Security
CORS_ORIGINS=https://${DOMAIN},https://www.${DOMAIN},https://${API_DOMAIN}
CORS_ALLOW_CREDENTIALS=true
ALLOWED_HOSTS=${DOMAIN},www.${DOMAIN},${API_DOMAIN}

# Logging & Performance
LOG_LEVEL=INFO
LOG_FORMAT=json
GUNICORN_WORKERS=4
GUNICORN_TIMEOUT=120
RATE_LIMIT_WINDOW_SECONDS=60
RATE_LIMIT_MAX_ATTEMPTS=10
HEALTH_CHECK_ENABLED=true

# Redis
REDIS_PASSWORD=${REDIS_PASSWORD}

# E-Mail (SMTP)
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT}
SMTP_USER=${SMTP_USER}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_USE_TLS=true
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL}
SMTP_FROM_NAME=GastroPilot

# Mothership
MOTHERSHIP_API_URL=${MOTHERSHIP_API_URL}
MOTHERSHIP_API_KEY=${MOTHERSHIP_API_KEY}

# OpenAI
OPENAI_API_KEY=${OPENAI_API_KEY}

# Twilio
TWILIO_ACCOUNT_SID=${TWILIO_ACCOUNT_SID}
TWILIO_AUTH_TOKEN=${TWILIO_AUTH_TOKEN}
TWILIO_PHONE_NUMBER=${TWILIO_PHONE_NUMBER}

# SumUp
SUMUP_API_KEY=${SUMUP_API_KEY}
SUMUP_MERCHANT_CODE=${SUMUP_MERCHANT_CODE}
SUMUP_CALLBACK_URL=${SUMUP_CALLBACK_URL}

# Sentry
SENTRY_DSN=${SENTRY_DSN}

# ==================== FRONTEND ====================
BASE_URL=${BASE_URL}
AUTH_SECRET=${AUTH_SECRET}
API_PREFIX=/v1
ENVEOF

    echo "  $ENV_FILE erstellt."
fi
echo

# ============================================
# 5. SSL-Zertifikate
# ============================================
step "5/11 — SSL-Zertifikate"

# Proxy-Verzeichnis bestimmen (Geschwister-Verzeichnis "proxy")
PROXY_DIR="$(cd "$(dirname "$0")" && cd .. && pwd)/proxy"

# Domains aus .env.server lesen falls nicht gesetzt
if [ -z "$DOMAIN" ]; then
    DOMAIN=$(grep -E '^ALLOWED_HOSTS=' "$ENV_FILE" 2>/dev/null | cut -d= -f2 | cut -d, -f1)
fi
if [ -z "$API_DOMAIN" ]; then
    API_DOMAIN=$(grep -E '^API_DOMAIN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
fi

# Pruefen welche Domains Zertifikate benoetigen
DOMAINS_NEED_SSL=""
for D in "$DOMAIN" "$API_DOMAIN"; do
    D_SSL_DIR="$PROXY_DIR/ssl/$D"
    if [ -f "$D_SSL_DIR/fullchain.pem" ] && [ -f "$D_SSL_DIR/privkey.pem" ]; then
        echo "  SSL-Zertifikate vorhanden fuer $D."
    else
        DOMAINS_NEED_SSL="$DOMAINS_NEED_SSL $D"
    fi
done

if [ -n "$DOMAINS_NEED_SSL" ]; then
    echo "  SSL-Zertifikate benoetigt fuer:$DOMAINS_NEED_SSL"
    echo
    echo "  1) Let's Encrypt (certbot) — Produktion"
    echo "  2) Vorhandene Let's Encrypt Zertifikate kopieren"
    echo "  3) Selbstsigniertes Zertifikat — Test/Entwicklung"
    echo "  4) Abbrechen — ich kopiere meine Zertifikate selbst"
    echo
    read -rp "  Auswahl [1/2/3/4]: " SSL_CHOICE

    if [ "$SSL_CHOICE" = "1" ]; then
        read -rp "  E-Mail fuer Let's Encrypt: " CERT_EMAIL
        echo
        echo "  Hole Let's Encrypt Zertifikate..."
        echo "  (Port 80 muss von aussen erreichbar sein)"
        echo
        # Alle Container stoppen, die Port 80 belegen (auch andere Stacks)
        PORT80_CONTAINERS=$(docker ps --filter "publish=80" -q 2>/dev/null)
        if [ -n "$PORT80_CONTAINERS" ]; then
            echo "  Stoppe Container auf Port 80..."
            docker stop $PORT80_CONTAINERS 2>/dev/null || true
        fi
        mkdir -p certbot
        for D in $DOMAINS_NEED_SSL; do
            D_SSL_DIR="$PROXY_DIR/ssl/$D"
            mkdir -p "$D_SSL_DIR"
            echo "  Zertifikat fuer $D..."
            docker run --rm -p 80:80 \
                -v "$(pwd)/certbot:/etc/letsencrypt" \
                certbot/certbot certonly --standalone \
                -d "$D" \
                --non-interactive --agree-tos \
                -m "$CERT_EMAIL"
            cp "certbot/live/$D/fullchain.pem" "$D_SSL_DIR/"
            cp "certbot/live/$D/privkey.pem" "$D_SSL_DIR/"
            echo "  Let's Encrypt Zertifikat fuer $D installiert."
        done
        echo
        echo "  Hinweis: Zertifikate erneuern (alle 90 Tage):"
        echo "    docker stop gastropilot-proxy"
        echo "    docker run --rm -p 80:80 -v \$(pwd)/certbot:/etc/letsencrypt certbot/certbot renew"
        for D in $DOMAINS_NEED_SSL; do
            echo "    cp certbot/live/$D/*.pem $PROXY_DIR/ssl/$D/"
        done
        echo "    docker start gastropilot-proxy"

    elif [ "$SSL_CHOICE" = "2" ]; then
        for D in $DOMAINS_NEED_SSL; do
            D_SSL_DIR="$PROXY_DIR/ssl/$D"
            mkdir -p "$D_SSL_DIR"
            if [ -f "certbot/live/$D/fullchain.pem" ]; then
                LE_PATH="certbot/live/$D"
            elif [ -f "/etc/letsencrypt/live/$D/fullchain.pem" ]; then
                LE_PATH="/etc/letsencrypt/live/$D"
            else
                echo "  Fehler: Keine Zertifikate fuer $D gefunden."
                echo "  Geprueft: ./certbot/live/$D/ und /etc/letsencrypt/live/$D/"
                exit 1
            fi
            cp "$LE_PATH/fullchain.pem" "$D_SSL_DIR/"
            cp "$LE_PATH/privkey.pem" "$D_SSL_DIR/"
            echo "  Zertifikate fuer $D aus $LE_PATH kopiert."
        done

    elif [ "$SSL_CHOICE" = "3" ]; then
        for D in $DOMAINS_NEED_SSL; do
            D_SSL_DIR="$PROXY_DIR/ssl/$D"
            mkdir -p "$D_SSL_DIR"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout "$D_SSL_DIR/privkey.pem" \
                -out "$D_SSL_DIR/fullchain.pem" \
                -subj "/CN=$D" 2>/dev/null
            echo "  Selbstsigniertes Zertifikat fuer $D erstellt."
        done

    else
        echo "  Kopiere deine Zertifikate nach:"
        for D in $DOMAINS_NEED_SSL; do
            echo "    $PROXY_DIR/ssl/$D/"
        done
        echo "  und starte install.sh erneut."
        exit 0
    fi
fi
echo

# ============================================
# 6. Gemeinsamer Proxy einrichten
# ============================================
step "6/11 — Gemeinsamer Proxy"

# Proxy-Verzeichnis und Basis-Dateien erstellen falls nicht vorhanden
if [ ! -f "$PROXY_DIR/docker-compose.proxy.yml" ]; then
    echo "  Erstelle Proxy-Verzeichnis ($PROXY_DIR)..."
    mkdir -p "$PROXY_DIR/conf.d" "$PROXY_DIR/ssl"
    cp proxy/docker-compose.proxy.yml "$PROXY_DIR/"
    cp proxy/proxy.conf "$PROXY_DIR/"
    echo "  Proxy-Infrastruktur erstellt."
else
    echo "  Proxy-Verzeichnis vorhanden."
    # conf.d Verzeichnis sicherstellen
    mkdir -p "$PROXY_DIR/conf.d"
fi

# Per-Domain nginx-Config generieren
UPSTREAM_NAME="${STACK_NAME}-nginx-upstream"
NGINX_CONTAINER="${STACK_NAME}-nginx"

echo "  Generiere Proxy-Config fuer $DOMAIN..."

cat > "$PROXY_DIR/conf.d/${DOMAIN}.conf" << PROXYEOF
upstream ${UPSTREAM_NAME} {
    server ${NGINX_CONTAINER}:80;
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/nginx/ssl/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}/privkey.pem;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://${UPSTREAM_NAME};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        # WebSocket / SSE
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_buffering off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
PROXYEOF

echo "  $PROXY_DIR/conf.d/${DOMAIN}.conf erstellt."

# API-Domain Proxy-Config
API_UPSTREAM_NAME="${STACK_NAME}-api-upstream"

echo "  Generiere Proxy-Config fuer $API_DOMAIN..."

cat > "$PROXY_DIR/conf.d/${API_DOMAIN}.conf" << PROXYEOF
upstream ${API_UPSTREAM_NAME} {
    server ${NGINX_CONTAINER}:80;
}

server {
    listen 443 ssl http2;
    server_name ${API_DOMAIN};

    ssl_certificate /etc/nginx/ssl/${API_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/${API_DOMAIN}/privkey.pem;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass http://${API_UPSTREAM_NAME};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;

        # WebSocket / SSE
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_buffering off;

        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
PROXYEOF

echo "  $PROXY_DIR/conf.d/${API_DOMAIN}.conf erstellt."

# Proxy starten / neuladen
echo "  Starte/aktualisiere Proxy..."
docker compose -f "$PROXY_DIR/docker-compose.proxy.yml" up -d
docker exec gastropilot-proxy nginx -s reload 2>/dev/null || true
echo "  Proxy bereit."
echo

# ============================================
# 7. Update-Skript einrichten
# ============================================
step "7/11 — Update-Skript"

if [ ! -f "update.sh" ] && [ -f "update.sh.example" ]; then
    cp update.sh.example update.sh
    chmod +x update.sh
    echo "  update.sh aus Vorlage erstellt."
else
    echo "  update.sh vorhanden."
fi
echo

# ============================================
# 8. Images pullen & Container starten
# ============================================
step "8/11 — Images pullen & Container starten"

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
echo
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d

# Auf Backend warten
echo
echo "  Warte auf Backend..."
for i in $(seq 1 30); do
    if docker exec "${STACK_NAME}-backend" curl -sf http://localhost:8000/v1/health > /dev/null 2>&1; then
        echo "  Backend bereit."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  Warnung: Backend antwortet noch nicht."
        echo "  Pruefe: docker compose -f $COMPOSE_FILE logs backend"
    fi
    sleep 2
done
echo

# ============================================
# 9. Admin-Account erstellen
# ============================================
step "9/11 — Admin-Account"

read -rp "  Admin-Account erstellen? (J/n): " ADMIN_CHOICE
if [[ ! "$ADMIN_CHOICE" =~ ^[nN]$ ]]; then
    echo
    read -rp "  Bedienernummer (4-stellig) [0000]: " ADMIN_OPERATOR
    ADMIN_OPERATOR=${ADMIN_OPERATOR:-0000}
    read -rp "  Vorname: " ADMIN_FIRST
    read -rp "  Nachname: " ADMIN_LAST
    read -rsp "  PIN (min. 6 Zeichen): " ADMIN_PIN
    echo

    if [ ${#ADMIN_OPERATOR} -ne 4 ]; then
        echo "  Fehler: Bedienernummer muss genau 4 Zeichen lang sein. Erstelle den Admin spaeter mit ./create-admin.sh"
    elif [ ${#ADMIN_PIN} -lt 6 ]; then
        echo "  Fehler: PIN zu kurz. Erstelle den Admin spaeter mit ./create-admin.sh"
    else
        echo
        echo "  Rolle:"
        echo "    1) restaurantinhaber (Standard-Admin)"
        echo "    2) servecta (Super-Admin)"
        read -rp "  Auswahl [1/2]: " ROLE_CHOICE
        if [ "$ROLE_CHOICE" = "2" ]; then
            ADMIN_ROLE="servecta"
        else
            ADMIN_ROLE="restaurantinhaber"
        fi

        docker exec \
            -e ADMIN_OPERATOR_NUMBER="$ADMIN_OPERATOR" \
            -e ADMIN_FIRST_NAME="$ADMIN_FIRST" \
            -e ADMIN_LAST_NAME="$ADMIN_LAST" \
            -e ADMIN_PIN="$ADMIN_PIN" \
            -e ADMIN_ROLE="$ADMIN_ROLE" \
            "${STACK_NAME}-backend" python -c "
import asyncio, os
from app.database.instance import async_session
from app.database.models import User
from app.auth import hash_password

async def create_admin():
    operator_number = os.environ['ADMIN_OPERATOR_NUMBER']
    first_name = os.environ['ADMIN_FIRST_NAME'].strip()
    last_name = os.environ['ADMIN_LAST_NAME'].strip()
    pin = os.environ['ADMIN_PIN']
    role = os.environ['ADMIN_ROLE']
    async with async_session() as session:
        async with session.begin():
            user = User(
                operator_number=operator_number,
                pin_hash=hash_password(pin),
                first_name=first_name,
                last_name=last_name,
                role=role
            )
            session.add(user)
    print(f'  Admin erstellt: {first_name} {last_name} (Bediener {operator_number}, Rolle: {role})')

asyncio.run(create_admin())
"
    fi
fi
echo

# ============================================
# 10. Coming Soon aktivieren
# ============================================
step "10/11 — Coming Soon"

read -rp "  Coming-Soon-Seite aktivieren? (J/n): " CS_CHOICE
if [[ ! "$CS_CHOICE" =~ ^[nN]$ ]]; then
    docker exec "${STACK_NAME}-nginx" touch /etc/nginx/coming-soon.on
    docker exec "${STACK_NAME}-nginx" nginx -s reload
    echo "  Coming-Soon-Seite aktiviert."
fi
echo

# ============================================
# 11. Fertig
# ============================================
header "Installation abgeschlossen!"

echo "Deine Secrets (sicher aufbewahren!):"
echo "  Datei: $ENV_FILE"
echo
echo "Proxy:"
echo "  Verzeichnis: $PROXY_DIR"
echo "  Frontend: $PROXY_DIR/conf.d/${DOMAIN}.conf"
echo "  API:      $PROXY_DIR/conf.d/${API_DOMAIN}.conf"
echo "  SSL:      $PROXY_DIR/ssl/${DOMAIN}/ + $PROXY_DIR/ssl/${API_DOMAIN}/"
echo
echo "Befehle:"
echo "  ./update.sh          — Update (Images pullen + Neustart)"
echo "  ./create-admin.sh    — Weiteren Admin erstellen"
echo "  ./coming-soon.sh off — Coming-Soon deaktivieren"
echo "  ./maintenance.sh on  — Wartungsmodus aktivieren"
echo
echo "Logs:"
echo "  docker compose -f $COMPOSE_FILE logs -f"
echo
