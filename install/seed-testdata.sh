#!/bin/bash
# =========================================
#  GastroPilot — Testdaten einspielen
# =========================================
#
# Spielt Seed-Daten (2 Restaurants) auf eine Datenbank ein.
# Idempotent: kann mehrfach ausgeführt werden.
#
# Verwendung:
#   ./seed-testdata.sh                          # Interaktiv
#   ./seed-testdata.sh --db-host 10.0.2.1 \
#     --db-name gastropilot_staging \
#     --db-user gastropilot_staging \
#     --db-pass <passwort>                      # Non-interaktiv
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/sql"
DEMO_DIR="${SCRIPT_DIR}/demo"

# ============================================
# Argumente parsen
# ============================================
DB_HOST="" DB_PORT="5432" DB_NAME="" DB_USER="" DB_PASS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db-host) DB_HOST="$2"; shift 2 ;;
        --db-port) DB_PORT="$2"; shift 2 ;;
        --db-name) DB_NAME="$2"; shift 2 ;;
        --db-user) DB_USER="$2"; shift 2 ;;
        --db-pass) DB_PASS="$2"; shift 2 ;;
        *) echo "Unbekannt: $1"; exit 1 ;;
    esac
done

echo
echo "==========================================="
echo "  GastroPilot — Testdaten einspielen"
echo "==========================================="
echo

# ============================================
# Interaktive Abfrage falls nötig
# ============================================
if [ -z "$DB_HOST" ]; then
    read -rp "  DB Host [10.0.2.1]: " DB_HOST
    DB_HOST=${DB_HOST:-10.0.2.1}
fi
if [ -z "$DB_NAME" ]; then
    read -rp "  DB Name [gastropilot_staging]: " DB_NAME
    DB_NAME=${DB_NAME:-gastropilot_staging}
fi
if [ -z "$DB_USER" ]; then
    read -rp "  DB User [gastropilot_staging]: " DB_USER
    DB_USER=${DB_USER:-gastropilot_staging}
fi
if [ -z "$DB_PASS" ]; then
    read -rsp "  DB Passwort: " DB_PASS; echo
fi

echo
echo "  Ziel: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo

# ============================================
# SQL-Dateien prüfen
# ============================================
SEED_FILES=()

# Bela Vita (italienisch) — aus demo/
if [ -f "$DEMO_DIR/seed_bela_vita.sql" ]; then
    SEED_FILES+=("$DEMO_DIR/seed_bela_vita.sql")
    echo "  [1] Bela Vita (Italienisch, Kiel) — seed_bela_vita.sql"
fi

# Goldener Hirsch (deutsch) — aus sql/
if [ -f "$SQL_DIR/seed_goldener_hirsch.sql" ]; then
    SEED_FILES+=("$SQL_DIR/seed_goldener_hirsch.sql")
    echo "  [2] Goldener Hirsch (Deutsch, Hamburg) — seed_goldener_hirsch.sql"
fi

if [ ${#SEED_FILES[@]} -eq 0 ]; then
    echo "  FEHLER: Keine Seed-Dateien gefunden."
    echo "  Erwartet: demo/seed_bela_vita.sql und/oder sql/seed_goldener_hirsch.sql"
    exit 1
fi

echo
echo "  ${#SEED_FILES[@]} Restaurant(s) werden eingespielt."
echo

# ============================================
# Verbindung testen
# ============================================
echo "  Teste Verbindung..."
if docker run --rm --network host \
    -e PGPASSWORD="$DB_PASS" \
    postgres:16-alpine \
    pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" > /dev/null 2>&1; then
    echo "  Verbindung OK."
else
    echo "  FEHLER: Datenbank nicht erreichbar (${DB_HOST}:${DB_PORT})."
    exit 1
fi
echo

# ============================================
# Seeds einspielen
# ============================================
for SQL_FILE in "${SEED_FILES[@]}"; do
    BASENAME=$(basename "$SQL_FILE")
    echo "  Spiele ein: $BASENAME ..."

    docker run --rm --network host \
        -e PGPASSWORD="$DB_PASS" \
        -v "$SQL_FILE:/tmp/seed.sql:ro" \
        postgres:16-alpine \
        psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
            -f /tmp/seed.sql 2>&1 | tail -20

    echo "  $BASENAME — fertig."
    echo
done

# ============================================
# Zusammenfassung
# ============================================
echo "==========================================="
echo "  Testdaten eingespielt!"
echo "==========================================="
echo
echo "  Datenbank: ${DB_NAME} @ ${DB_HOST}:${DB_PORT}"
echo
echo "  Restaurants:"
echo "    Bela Vita        — Italienisch, Kiel"
echo "      Owner-Login:   marco@bela-vita-demo.gpilot.app / Demo2026!"
echo "      Tenant-ID:     22222222-2222-2222-2222-222222222222"
echo
echo "    Goldener Hirsch  — Deutsch, Hamburg"
echo "      Owner-Login:   hans@goldener-hirsch.gpilot.app / Test2026!"
echo "      Tenant-ID:     33333333-3333-3333-3333-333333333333"
echo
echo "  Nochmal ausführen: $0 --db-host $DB_HOST --db-name $DB_NAME --db-user $DB_USER --db-pass '***'"
echo
