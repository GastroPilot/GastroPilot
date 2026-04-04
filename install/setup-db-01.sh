#!/bin/bash
# =========================================
#  GastroPilot — DB-01 Server-Setup
#  (PostgreSQL 16 Primary + Redis 7)
# =========================================
#
# Richtet den Primary-Datenbankserver ein:
#   - SSH-Härtung (Port 2222, Ed25519, Fail2Ban)
#   - PostgreSQL 16 + Redis 7 Container
#   - Bind an Private Network IP (10.0.2.1)
#   - Schema (init.sql) + RLS (rls.sql) anwenden
#   - Replication für Replica (db-02) konfigurieren
#   - Automatische Backups (pg_dump Cronjob)
#   - UFW-Firewall (nur App-Server + Replica)
#   - Netplan DNS (CoreDNS auf INFRA-SRV)
#
# Voraussetzung:
#   - INFRA-SRV läuft (WireGuard + CoreDNS)
#   - Server ist im gastropilot-net (10.0.0.0/16)
#   - SSH-Keys für lucakohls + saschadolgow hinterlegt
#
# Verwendung:
#   ssh db-01         # via WireGuard + INFRA-SRV
#   sudo ./setup-db-01.sh
#
set -euo pipefail

# ============================================
# Netzwerk-Konstanten (Hetzner Private Network)
# ============================================
PRIVATE_IP="10.0.2.1"              # DB-01
INFRA_IP="10.0.0.2"                # INFRA-SRV (DNS + WireGuard)
APP01_IP="10.0.1.1"                # APP-01 (Production)
APP02_IP="10.0.3.1"                # APP-02 (Staging/Demo/Test)
DB02_IP="10.0.2.2"                 # DB-02 (Replica)
CORP01_IP="10.1.1.1"               # CORP-01 (Website)
WG_SUBNET="10.8.0.0/24"           # WireGuard VPN
SSH_PORT=2222
SSH_USERS=("lucakohls" "saschadolgow")

# ============================================
# Service-Konfiguration
# ============================================
POSTGRES_VERSION="16-alpine"
CONTAINER_NAME="gastropilot-postgres"
REDIS_CONTAINER="gastropilot-redis"
DATA_DIR="/opt/gastropilot-db/pgdata"
BACKUP_DIR="/opt/gastropilot-db/backups"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DB_PORT=5432
REDIS_PORT=6379
BACKUP_RETENTION_DAYS=14

# -------------------------------------------
# Hilfsfunktionen
# -------------------------------------------
header() {
    echo
    echo "==========================================="
    echo "  $1"
    echo "==========================================="
    echo
}

step() { echo "== $1 =="; }

generate_password() { openssl rand -base64 32 | tr -d '/+=' | head -c 32; }

confirm_or_exit() {
    read -rp "  Korrekt? (J/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[nN]$ ]]; then echo "  Abgebrochen."; exit 0; fi
}

# -------------------------------------------
header "GastroPilot — DB-01 Primary Setup"
# -------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "Fehler: Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

# ============================================
# 1. Voraussetzungen + Docker
# ============================================
step "1/10 — Voraussetzungen prüfen"

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
    echo "  Docker installiert."
else
    echo "  Docker $(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
fi

for pkg in fail2ban ufw unattended-upgrades apt-listchanges openssl; do
    if ! dpkg -s "$pkg" &> /dev/null 2>&1; then
        apt-get install -y -qq "$pkg"
    fi
done
echo

# ============================================
# 2. SSH-Härtung
# ============================================
step "2/10 — SSH-Härtung"

# Admin-User sicherstellen
for USER in "${SSH_USERS[@]}"; do
    if ! id "$USER" &>/dev/null; then
        useradd -m -s /bin/bash -G sudo,docker "$USER"
        echo "$USER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USER"
        chmod 440 "/etc/sudoers.d/$USER"
        echo "  User '$USER' erstellt — SSH-Key muss noch hinterlegt werden!"
    else
        # docker-Gruppe sicherstellen
        usermod -aG docker "$USER" 2>/dev/null || true
        echo "  User '$USER' vorhanden."
    fi
done

# SSHD-Konfiguration
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak.$(date +%s)"

cat > /etc/ssh/sshd_config << SSHEOF
# Servecta SSH — DB-01 (generiert von setup-db-01.sh)
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
  SERVECTA INFRASTRUCTURE — DB-01
  Unauthorized access is prohibited.
  All connections are monitored and logged.
======================================================
EOF

# Nur Ed25519 Host-Keys
rm -f /etc/ssh/ssh_host_dsa_key* /etc/ssh/ssh_host_ecdsa_key* /etc/ssh/ssh_host_rsa_key*
[ -f /etc/ssh/ssh_host_ed25519_key ] || ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""

# Fail2Ban
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

# Unattended-Upgrades
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UUEOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UUEOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUEOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUEOF

# SSHD testen + neustarten
if sshd -t 2>/dev/null; then
    systemctl restart ssh
    echo "  SSH gehärtet: Port $SSH_PORT, nur Ed25519, nur ${SSH_USERS[*]}"
else
    echo "  FEHLER: SSHD-Config ungültig! Backup wiederhergestellt."
    cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config 2>/dev/null
    systemctl restart ssh
    exit 1
fi
echo

# ============================================
# 3. Netplan DNS (CoreDNS auf INFRA-SRV)
# ============================================
step "3/10 — DNS-Konfiguration (CoreDNS)"

# Private Network Interface ermitteln (ens10 auf Hetzner)
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

netplan apply 2>/dev/null || echo "  WARNUNG: netplan apply fehlgeschlagen — manuell prüfen."
echo "  DNS: ${INFRA_IP} (INFRA-SRV CoreDNS)"
echo

# ============================================
# 4. UFW-Firewall (DB-01 spezifisch)
# ============================================
step "4/10 — Firewall (UFW)"

ufw --force reset > /dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing

# SSH nur von INFRA-SRV + WireGuard
ufw allow in from "$INFRA_IP" to any port "$SSH_PORT" proto tcp comment "SSH from INFRA-SRV"
ufw allow in from "$WG_SUBNET" to any port "$SSH_PORT" proto tcp comment "SSH via WireGuard"

# PostgreSQL
ufw allow in from "$APP01_IP" to any port "$DB_PORT" proto tcp comment "PG from APP-01 (Production)"
ufw allow in from "$APP02_IP" to any port "$DB_PORT" proto tcp comment "PG from APP-02 (Staging/Demo)"
ufw allow in from "$DB02_IP" to any port "$DB_PORT" proto tcp comment "PG Replication from DB-02"
ufw allow in from "$CORP01_IP" to any port "$DB_PORT" proto tcp comment "PG from CORP-01 (Website)"
ufw allow in from "$INFRA_IP" to any port "$DB_PORT" proto tcp comment "PG from INFRA-SRV (WG NAT)"
ufw allow in from "$WG_SUBNET" to any port "$DB_PORT" proto tcp comment "PG via WireGuard"

# Redis
ufw allow in from "$APP01_IP" to any port "$REDIS_PORT" proto tcp comment "Redis from APP-01"
ufw allow in from "$APP02_IP" to any port "$REDIS_PORT" proto tcp comment "Redis from APP-02"
ufw allow in from "$INFRA_IP" to any port "$REDIS_PORT" proto tcp comment "Redis from INFRA-SRV (WG NAT)"
ufw allow in from "$WG_SUBNET" to any port "$REDIS_PORT" proto tcp comment "Redis via WireGuard"

# Port 22 explizit sperren
ufw deny 22/tcp

ufw --force enable
echo "  UFW aktiv: SSH($SSH_PORT) von INFRA+WG, PG($DB_PORT), Redis($REDIS_PORT)"
echo

# ============================================
# 5. Datenbank-Konfiguration
# ============================================
step "5/10 — Datenbank-Konfiguration"

echo
echo "  Welche Datenbanken sollen erstellt werden?"
echo "  (Kommagetrennt, z.B.: production,staging,demo)"
echo
read -rp "  Environments [production]: " DB_ENVIRONMENTS
DB_ENVIRONMENTS=${DB_ENVIRONMENTS:-production}

IFS=',' read -ra ENVS <<< "$DB_ENVIRONMENTS"

declare -A DB_PASSWORDS
for ENV in "${ENVS[@]}"; do
    ENV=$(echo "$ENV" | xargs)
    DB_PASSWORDS[$ENV]=$(generate_password)
    echo "  DB: gastropilot_${ENV} — Passwort generiert"
done

echo
read -rp "  Replica erlauben? (J/n): " REPLICA_CHOICE
ENABLE_REPLICATION=true
if [[ "$REPLICA_CHOICE" =~ ^[nN]$ ]]; then
    ENABLE_REPLICATION=false
fi

REPLICATION_PASSWORD=""
if [ "$ENABLE_REPLICATION" = true ]; then
    REPLICATION_PASSWORD=$(generate_password)
    echo "  Replication-User wird für ${DB02_IP} konfiguriert."
fi

echo
read -rp "  Redis-Passwort generieren? (J/n): " REDIS_PW_CHOICE
if [[ "$REDIS_PW_CHOICE" =~ ^[nN]$ ]]; then
    read -rsp "  Redis-Passwort: " REDIS_PASSWORD; echo
else
    REDIS_PASSWORD=$(generate_password)
    echo "  Redis-Passwort generiert."
fi

echo
echo "  Konfiguration:"
echo "    Private IP:     $PRIVATE_IP"
echo "    PostgreSQL:     ${PRIVATE_IP}:${DB_PORT}"
echo "    Redis:          ${PRIVATE_IP}:${REDIS_PORT}"
echo "    Environments:   ${ENVS[*]}"
echo "    Replication:    $ENABLE_REPLICATION"
[ "$ENABLE_REPLICATION" = true ] && echo "    Replica-IP:     $DB02_IP"
echo
confirm_or_exit
echo

# ============================================
# 6. Verzeichnisse + PostgreSQL-Konfiguration
# ============================================
step "6/10 — Verzeichnisse & PostgreSQL-Config"

mkdir -p "$DATA_DIR" "$BACKUP_DIR" /opt/gastropilot-db/conf

cat > /opt/gastropilot-db/conf/postgresql.conf << 'PGCONF'
# GastroPilot PostgreSQL Primary — Optimiert für SaaS-Workload

listen_addresses = '*'
max_connections = 200

# Speicher
shared_buffers = '256MB'
effective_cache_size = '768MB'
work_mem = '4MB'
maintenance_work_mem = '128MB'

# WAL / Replication
wal_level = replica
max_wal_senders = 5
wal_keep_size = '512MB'
max_replication_slots = 5

# Checkpoints
checkpoint_completion_target = 0.9
max_wal_size = '1GB'
min_wal_size = '256MB'

# Logging
log_timezone = 'Europe/Berlin'
log_min_duration_statement = 500
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_statement = 'ddl'

# Locale
timezone = 'Europe/Berlin'
lc_messages = 'en_US.utf8'

# Autovacuum
autovacuum_max_workers = 3
autovacuum_naptime = '60s'
autovacuum_vacuum_scale_factor = 0.05
autovacuum_analyze_scale_factor = 0.025
PGCONF

# pg_hba.conf — nur bekannte Quellen
cat > /opt/gastropilot-db/conf/pg_hba.conf << PGHBA
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256

# Docker-Netzwerk
host    all             all             172.16.0.0/12           scram-sha-256

# App-Server (Private Network)
host    all             all             ${APP01_IP}/32          scram-sha-256
host    all             all             ${APP02_IP}/32          scram-sha-256
host    all             all             ${CORP01_IP}/32         scram-sha-256

# Admin-Zugang via WireGuard (NAT über INFRA-SRV)
host    all             all             ${INFRA_IP}/32          scram-sha-256
host    all             all             10.8.0.0/24             scram-sha-256
PGHBA

if [ "$ENABLE_REPLICATION" = true ]; then
    cat >> /opt/gastropilot-db/conf/pg_hba.conf << PGHBA_REPL

# Replication (DB-02 Replica)
host    replication     replicator      ${DB02_IP}/32           scram-sha-256
PGHBA_REPL
fi

echo "  postgresql.conf + pg_hba.conf erstellt."
echo

# ============================================
# 7. PostgreSQL-Container starten
# ============================================
step "7/10 — PostgreSQL-Container starten"

FIRST_ENV="${ENVS[0]}"
POSTGRES_USER="gastropilot_${FIRST_ENV}"
POSTGRES_PASSWORD="${DB_PASSWORDS[$FIRST_ENV]}"
POSTGRES_DB="gastropilot_${FIRST_ENV}"

# Container stoppen falls vorhanden
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "  Stoppe bestehenden Container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -e POSTGRES_USER="$POSTGRES_USER" \
    -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    -e POSTGRES_DB="$POSTGRES_DB" \
    -p "${PRIVATE_IP}:${DB_PORT}:5432" \
    -v "${DATA_DIR}:/var/lib/postgresql/data" \
    -v /opt/gastropilot-db/conf/postgresql.conf:/etc/postgresql/postgresql.conf:ro \
    -v /opt/gastropilot-db/conf/pg_hba.conf:/etc/postgresql/pg_hba.conf:ro \
    --shm-size=256m \
    postgres:${POSTGRES_VERSION} \
    postgres \
        -c config_file=/etc/postgresql/postgresql.conf \
        -c hba_file=/etc/postgresql/pg_hba.conf

echo "  PostgreSQL gestartet auf ${PRIVATE_IP}:${DB_PORT}"
echo "  Warte auf Readiness..."

for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; then
        echo "  PostgreSQL bereit."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  FEHLER: PostgreSQL antwortet nicht."
        echo "  Logs: docker logs $CONTAINER_NAME"
        exit 1
    fi
    sleep 2
done
echo

# ============================================
# 8. Redis-Container starten
# ============================================
step "8/10 — Redis-Container starten"

if docker ps -a --format '{{.Names}}' | grep -q "^${REDIS_CONTAINER}$"; then
    docker stop "$REDIS_CONTAINER" 2>/dev/null || true
    docker rm "$REDIS_CONTAINER" 2>/dev/null || true
fi

docker run -d \
    --name "$REDIS_CONTAINER" \
    --restart always \
    -p "${PRIVATE_IP}:${REDIS_PORT}:6379" \
    -v /opt/gastropilot-db/redis-data:/data \
    redis:7-alpine \
    redis-server \
        --appendonly yes \
        --maxmemory 512mb \
        --maxmemory-policy allkeys-lru \
        --requirepass "$REDIS_PASSWORD"

echo "  Redis gestartet auf ${PRIVATE_IP}:${REDIS_PORT}"

# Warten
for i in $(seq 1 10); do
    if docker exec "$REDIS_CONTAINER" redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        echo "  Redis bereit."
        break
    fi
    sleep 1
done
echo

# ============================================
# 9. Datenbanken + Schema erstellen
# ============================================
step "9/10 — Datenbanken & Schema initialisieren"

# SQL-Dateien finden
INIT_SQL=""
RLS_SQL=""
for CHECK_PATH in "$SCRIPT_DIR/sql/init.sql" "$SCRIPT_DIR/init.sql"; do
    if [ -f "$CHECK_PATH" ]; then INIT_SQL="$CHECK_PATH"; break; fi
done
for CHECK_PATH in "$SCRIPT_DIR/sql/rls.sql" "$SCRIPT_DIR/rls.sql"; do
    if [ -f "$CHECK_PATH" ]; then RLS_SQL="$CHECK_PATH"; break; fi
done

SKIP_SCHEMA=false
if [ -z "$INIT_SQL" ] || [ -z "$RLS_SQL" ]; then
    echo "  WARNUNG: SQL-Dateien nicht gefunden (sql/init.sql, sql/rls.sql)."
    echo "  Schema muss manuell initialisiert werden."
    SKIP_SCHEMA=true
else
    docker cp "$INIT_SQL" "${CONTAINER_NAME}:/tmp/init.sql"
    docker cp "$RLS_SQL" "${CONTAINER_NAME}:/tmp/rls.sql"
fi

for ENV in "${ENVS[@]}"; do
    ENV=$(echo "$ENV" | xargs)
    DB="gastropilot_${ENV}"
    USER="gastropilot_${ENV}"
    PASS="${DB_PASSWORDS[$ENV]}"

    if [ "$DB" = "$POSTGRES_DB" ]; then
        echo "  DB '$DB' — existiert bereits (Haupt-DB)."
    else
        echo "  Erstelle DB '$DB'..."
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
            "CREATE ROLE ${USER} WITH LOGIN PASSWORD '${PASS}';" 2>/dev/null || true
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
            "CREATE DATABASE ${DB} OWNER ${USER};" 2>/dev/null || true
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$DB" -c \
            "GRANT ALL PRIVILEGES ON DATABASE ${DB} TO ${USER};" 2>/dev/null || true
        docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$DB" -c \
            "GRANT ALL ON SCHEMA public TO ${USER};" 2>/dev/null || true
    fi

    if [ "$SKIP_SCHEMA" = false ]; then
        echo "  Schema auf '$DB' anwenden..."
        docker exec "$CONTAINER_NAME" psql -U "$USER" -d "$DB" -f /tmp/init.sql > /dev/null 2>&1 || \
            echo "    WARNUNG: init.sql fehlgeschlagen (evtl. schon vorhanden)"
        docker exec "$CONTAINER_NAME" psql -U "$USER" -d "$DB" -f /tmp/rls.sql > /dev/null 2>&1 || \
            echo "    WARNUNG: rls.sql fehlgeschlagen (evtl. schon vorhanden)"
    fi
done

if [ "$ENABLE_REPLICATION" = true ]; then
    echo "  Erstelle Replication-User..."
    docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';" 2>/dev/null || \
        echo "  Replicator-User existiert bereits."
fi
echo

# ============================================
# 10. Backups konfigurieren
# ============================================
step "10/10 — Automatische Backups"

cat > /opt/gastropilot-db/backup.sh << 'BACKUPEOF'
#!/bin/bash
set -euo pipefail
CONTAINER_NAME="gastropilot-postgres"
BACKUP_DIR="/opt/gastropilot-db/backups"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
DATE=$(date +%Y%m%d_%H%M%S)

DATABASES=$(docker exec "$CONTAINER_NAME" psql -U postgres -Atc \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';" 2>/dev/null || true)

for DB in $DATABASES; do
    BACKUP_FILE="${BACKUP_DIR}/${DB}_${DATE}.sql.gz"
    docker exec "$CONTAINER_NAME" pg_dump -U postgres -d "$DB" --format=custom | \
        gzip > "$BACKUP_FILE"
    echo "[$(date)] Backup: $BACKUP_FILE ($(du -sh "$BACKUP_FILE" | cut -f1))"
done

find "$BACKUP_DIR" -name "*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
echo "[$(date)] Alte Backups (>${RETENTION_DAYS} Tage) bereinigt."
BACKUPEOF
chmod +x /opt/gastropilot-db/backup.sh

CRON_LINE="0 3 * * * /opt/gastropilot-db/backup.sh >> /opt/gastropilot-db/backups/backup.log 2>&1"
{ crontab -l 2>/dev/null | grep -v "gastropilot-db/backup.sh" || true; echo "$CRON_LINE"; } | crontab -
echo "  backup.sh erstellt. Cronjob: täglich 03:00 Uhr"
echo

# ============================================
header "DB-01 Setup abgeschlossen!"
# ============================================

SERVER_IP="$PRIVATE_IP"

echo "Server:       DB-01 (${SERVER_IP})"
echo "PostgreSQL:   ${SERVER_IP}:${DB_PORT} (${POSTGRES_VERSION})"
echo "Redis:        ${SERVER_IP}:${REDIS_PORT} (7-alpine)"
echo "SSH:          Port ${SSH_PORT} (nur via INFRA-SRV / WireGuard)"
echo "Backups:      ${BACKUP_DIR} (täglich 03:00)"
echo

echo "Datenbanken:"
for ENV in "${ENVS[@]}"; do
    ENV=$(echo "$ENV" | xargs)
    echo "  gastropilot_${ENV}"
    echo "    User:     gastropilot_${ENV}"
    echo "    Passwort: ${DB_PASSWORDS[$ENV]}"
done

echo
echo "Redis:"
echo "  Passwort:   ${REDIS_PASSWORD}"

if [ "$ENABLE_REPLICATION" = true ]; then
    echo
    echo "Replication:"
    echo "  User:       replicator"
    echo "  Passwort:   ${REPLICATION_PASSWORD}"
    echo "  Replica-IP: ${DB02_IP}"
fi

echo
echo "Verbindungs-URLs (für App-Server .env):"
for ENV in "${ENVS[@]}"; do
    ENV=$(echo "$ENV" | xargs)
    echo "  ${ENV}:"
    echo "    DATABASE_URL=postgresql+asyncpg://gastropilot_${ENV}:${DB_PASSWORDS[$ENV]}@${SERVER_IP}:${DB_PORT}/gastropilot_${ENV}"
done
echo "  REDIS_URL=redis://:${REDIS_PASSWORD}@${SERVER_IP}:${REDIS_PORT}/0"

echo
echo "DNS (via CoreDNS):"
echo "  db-primary.servecta.local  →  ${SERVER_IP}"

echo
echo "Befehle:"
echo "  docker logs -f $CONTAINER_NAME                — PG-Logs"
echo "  docker logs -f $REDIS_CONTAINER               — Redis-Logs"
echo "  docker exec -it $CONTAINER_NAME psql -U gastropilot_${FIRST_ENV}  — SQL-Shell"
echo "  /opt/gastropilot-db/backup.sh                 — Manuelles Backup"
echo

# Credentials sicher speichern
CREDS_FILE="/opt/gastropilot-db/credentials.txt"
cat > "$CREDS_FILE" << CREDSEOF
# GastroPilot DB-01 Credentials
# Generiert am $(date +%Y-%m-%d)
# ACHTUNG: Diese Datei sicher aufbewahren!

Server: ${SERVER_IP}
PostgreSQL: ${SERVER_IP}:${DB_PORT}
Redis: ${SERVER_IP}:${REDIS_PORT}

CREDSEOF

for ENV in "${ENVS[@]}"; do
    ENV=$(echo "$ENV" | xargs)
    cat >> "$CREDS_FILE" << CREDSEOF
[gastropilot_${ENV}]
User: gastropilot_${ENV}
Password: ${DB_PASSWORDS[$ENV]}
Database: gastropilot_${ENV}
URL: postgresql+asyncpg://gastropilot_${ENV}:${DB_PASSWORDS[$ENV]}@${SERVER_IP}:${DB_PORT}/gastropilot_${ENV}

CREDSEOF
done

cat >> "$CREDS_FILE" << CREDSEOF
[redis]
Password: ${REDIS_PASSWORD}
URL: redis://:${REDIS_PASSWORD}@${SERVER_IP}:${REDIS_PORT}/0

CREDSEOF

if [ "$ENABLE_REPLICATION" = true ]; then
    cat >> "$CREDS_FILE" << CREDSEOF
[replication]
User: replicator
Password: ${REPLICATION_PASSWORD}

CREDSEOF
fi

chmod 600 "$CREDS_FILE"
echo "Credentials: $CREDS_FILE (nur root lesbar)"
echo
