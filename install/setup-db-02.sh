#!/bin/bash
# =========================================
#  GastroPilot — DB-02 Server-Setup
#  (PostgreSQL 16 Replica — Read-Only)
# =========================================
#
# Richtet den Replica-Datenbankserver ein:
#   - SSH-Härtung (Port 2222, Ed25519, Fail2Ban)
#   - Base-Backup vom Primary (db-01 / 10.0.2.1)
#   - PostgreSQL 16 als Hot-Standby (10.0.2.2)
#   - UFW-Firewall (nur App-Server + INFRA)
#   - Netplan DNS (CoreDNS auf INFRA-SRV)
#   - Replication-Monitoring-Skript
#
# Voraussetzung:
#   - INFRA-SRV läuft (WireGuard + CoreDNS)
#   - DB-01 läuft und Replication ist konfiguriert
#   - Replication-User (replicator) existiert auf DB-01
#
# Verwendung:
#   ssh db-02         # via WireGuard + INFRA-SRV
#   sudo ./setup-db-02.sh
#
set -euo pipefail

# ============================================
# Netzwerk-Konstanten
# ============================================
PRIVATE_IP="10.0.2.2"              # DB-02
INFRA_IP="10.0.0.2"                # INFRA-SRV
PRIMARY_IP="10.0.2.1"              # DB-01 (Primary)
APP01_IP="10.0.1.1"                # APP-01
APP02_IP="10.0.3.1"                # APP-02
WG_SUBNET="10.8.0.0/24"           # WireGuard VPN

SSH_PORT=2222
SSH_USERS=("lucakohls" "saschadolgow")

# ============================================
# Service-Konfiguration
# ============================================
POSTGRES_VERSION="16-alpine"
CONTAINER_NAME="gastropilot-postgres-replica"
DATA_DIR="/opt/gastropilot-db/pgdata-replica"

DB_PORT=5432
PRIMARY_PORT=5432

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

confirm_or_exit() {
    read -rp "  Korrekt? (J/n): " CONFIRM
    if [[ "$CONFIRM" =~ ^[nN]$ ]]; then echo "  Abgebrochen."; exit 0; fi
}

# -------------------------------------------
header "GastroPilot — DB-02 Replica Setup"
# -------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "Fehler: Dieses Skript muss als root ausgeführt werden."
    exit 1
fi

# ============================================
# 1. Voraussetzungen + Docker
# ============================================
step "1/8 — Voraussetzungen prüfen"

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
    dpkg -s "$pkg" &> /dev/null 2>&1 || apt-get install -y -qq "$pkg"
done
echo

# ============================================
# 2. SSH-Härtung
# ============================================
step "2/8 — SSH-Härtung"

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
# Servecta SSH — DB-02 (generiert von setup-db-02.sh)
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
  SERVECTA INFRASTRUCTURE — DB-02
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

# Unattended-Upgrades
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
step "3/8 — DNS-Konfiguration (CoreDNS)"

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
# 4. UFW-Firewall (DB-02 spezifisch)
# ============================================
step "4/8 — Firewall (UFW)"

ufw --force reset > /dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing

# SSH nur von INFRA-SRV + WireGuard
ufw allow in from "$INFRA_IP" to any port "$SSH_PORT" proto tcp comment "SSH from INFRA-SRV"
ufw allow in from "$WG_SUBNET" to any port "$SSH_PORT" proto tcp comment "SSH via WireGuard"

# PostgreSQL (Read Replica)
ufw allow in from "$APP01_IP" to any port "$DB_PORT" proto tcp comment "PG from APP-01"
ufw allow in from "$APP02_IP" to any port "$DB_PORT" proto tcp comment "PG from APP-02"

# Port 22 sperren
ufw deny 22/tcp

ufw --force enable
echo "  UFW aktiv: SSH($SSH_PORT) von INFRA+WG, PG($DB_PORT) von APP-01+APP-02"
echo

# ============================================
# 5. Replication-Verbindung
# ============================================
step "5/8 — Primary-Verbindung"

echo "  Primary: ${PRIMARY_IP}:${PRIMARY_PORT} (DB-01)"
echo
read -rp "  Replication User [replicator]: " REPL_USER
REPL_USER=${REPL_USER:-replicator}
read -rsp "  Replication Passwort: " REPL_PASSWORD
echo
echo
confirm_or_exit
echo

# Verbindung testen
echo "  Teste Verbindung zum Primary..."
if docker run --rm --network host postgres:${POSTGRES_VERSION} \
    pg_isready -h "$PRIMARY_IP" -p "$PRIMARY_PORT" > /dev/null 2>&1; then
    echo "  Primary erreichbar."
else
    echo "  WARNUNG: Primary nicht erreichbar (${PRIMARY_IP}:${PRIMARY_PORT})."
    read -rp "  Trotzdem fortfahren? (j/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[jJ]$ ]]; then exit 1; fi
fi
echo

# ============================================
# 6. Base-Backup vom Primary
# ============================================
step "6/8 — Base-Backup vom Primary"

mkdir -p "$DATA_DIR"

if [ -d "$DATA_DIR" ] && [ "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    echo "  WARNUNG: $DATA_DIR ist nicht leer!"
    read -rp "  Daten löschen und neu synchronisieren? (j/N): " WIPE
    if [[ "$WIPE" =~ ^[jJ]$ ]]; then
        docker stop "$CONTAINER_NAME" 2>/dev/null || true
        docker rm "$CONTAINER_NAME" 2>/dev/null || true
        rm -rf "${DATA_DIR:?}/"*
    else
        echo "  Abgebrochen."; exit 0
    fi
fi

SLOT_NAME="replica_$(hostname -s | tr '-' '_')"

# Bestehenden Replication-Slot aufräumen (falls vom letzten Versuch übrig)
echo "  Prüfe Replication-Slot '${SLOT_NAME}'..."
docker run --rm --network host \
    -e PGPASSWORD="$REPL_PASSWORD" \
    postgres:${POSTGRES_VERSION} \
    psql -h "$PRIMARY_IP" -p "$PRIMARY_PORT" -U "$REPL_USER" -d postgres -c \
    "SELECT pg_drop_replication_slot('${SLOT_NAME}');" 2>/dev/null || true

echo "  pg_basebackup läuft... (kann einige Minuten dauern)"

docker run --rm --network host \
    -v "${DATA_DIR}:/var/lib/postgresql/data" \
    -e PGPASSWORD="$REPL_PASSWORD" \
    postgres:${POSTGRES_VERSION} \
    pg_basebackup \
        -h "$PRIMARY_IP" \
        -p "$PRIMARY_PORT" \
        -U "$REPL_USER" \
        -D /var/lib/postgresql/data \
        -Fp -Xs -P -R \
        -C -S "${SLOT_NAME}"

echo "  Base-Backup abgeschlossen."
echo

# ============================================
# 7. Replica-Container starten
# ============================================
step "7/8 — Replica-Container starten"

# Replica-Config ergänzen
cat >> "${DATA_DIR}/postgresql.auto.conf" << REPLICACONF

# GastroPilot Replica-Konfiguration
hot_standby = on
max_connections = 200
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
hot_standby_feedback = on
REPLICACONF

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart always \
    -p "${PRIVATE_IP}:${DB_PORT}:5432" \
    -v "${DATA_DIR}:/var/lib/postgresql/data" \
    --shm-size=256m \
    postgres:${POSTGRES_VERSION}

echo "  Replica gestartet auf ${PRIVATE_IP}:${DB_PORT}"
echo "  Warte auf Readiness..."

for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" pg_isready > /dev/null 2>&1; then
        echo "  PostgreSQL Replica bereit."
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "  FEHLER: Replica antwortet nicht."
        echo "  Logs: docker logs $CONTAINER_NAME"
        exit 1
    fi
    sleep 2
done

echo
echo "  Replication-Status:"
docker exec "$CONTAINER_NAME" psql -U postgres -c \
    "SELECT pg_is_in_recovery() AS is_replica, pg_last_wal_receive_lsn() AS receive_lsn, pg_last_wal_replay_lsn() AS replay_lsn;" 2>/dev/null || \
    echo "  Status noch nicht verfügbar."
echo

# ============================================
# 8. Monitoring-Skript
# ============================================
step "8/8 — Replication-Monitoring"

cat > /opt/gastropilot-db/check-replication.sh << 'REPLCHECK'
#!/bin/bash
# GastroPilot — Replication-Lag prüfen
CONTAINER="gastropilot-postgres-replica"

echo "=== Replication Status (DB-02) ==="
docker exec "$CONTAINER" psql -U postgres -c "
SELECT
    pg_is_in_recovery() AS is_replica,
    pg_last_wal_receive_lsn() AS received,
    pg_last_wal_replay_lsn() AS replayed,
    CASE
        WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN '0 bytes'
        ELSE pg_size_pretty(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()))
    END AS replication_lag,
    now() - pg_last_xact_replay_timestamp() AS replay_delay
;" 2>/dev/null || echo "Fehler: Container nicht erreichbar."
REPLCHECK
chmod +x /opt/gastropilot-db/check-replication.sh

echo "  check-replication.sh erstellt."
echo

# ============================================
header "DB-02 Replica Setup abgeschlossen!"
# ============================================

echo "Server:       DB-02 (${PRIVATE_IP})"
echo "PostgreSQL:   ${PRIVATE_IP}:${DB_PORT} (${POSTGRES_VERSION}, Hot-Standby)"
echo "Primary:      ${PRIMARY_IP}:${PRIMARY_PORT} (DB-01)"
echo "SSH:          Port ${SSH_PORT} (nur via INFRA-SRV / WireGuard)"
echo
echo "DNS (via CoreDNS):"
echo "  db-replica.servecta.local  →  ${PRIVATE_IP}"
echo
echo "Replica-URL (für App-Server .env):"
echo "  DATABASE_REPLICA_URL=postgresql+asyncpg://<user>:<password>@${PRIVATE_IP}:${DB_PORT}/<database>"
echo
echo "Befehle:"
echo "  /opt/gastropilot-db/check-replication.sh     — Replication-Lag prüfen"
echo "  docker logs -f $CONTAINER_NAME               — Logs"
echo "  docker restart $CONTAINER_NAME                — Neustart"
echo
echo "WICHTIG:"
echo "  Die Replica ist read-only."
echo "  Bei Failover: standby.signal löschen und Container neu starten."
echo
