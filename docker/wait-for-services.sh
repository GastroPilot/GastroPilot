#!/bin/sh
# Wartet auf PostgreSQL und Redis bevor der Hauptprozess gestartet wird.
set -e

MAX_RETRIES=30
SLEEP_INTERVAL=2

# Auf PostgreSQL warten
echo "Warte auf PostgreSQL..."
i=0
while [ $i -lt $MAX_RETRIES ]; do
    if python -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(('postgres', 5432))
    s.close()
    exit(0)
except:
    exit(1)
" 2>/dev/null; then
        echo "PostgreSQL erreichbar."
        break
    fi
    i=$((i + 1))
    echo "  Versuch $i/$MAX_RETRIES..."
    sleep $SLEEP_INTERVAL
done

if [ $i -eq $MAX_RETRIES ]; then
    echo "FEHLER: PostgreSQL nicht erreichbar nach $MAX_RETRIES Versuchen."
    exit 1
fi

# Auf Redis warten
echo "Warte auf Redis..."
i=0
while [ $i -lt $MAX_RETRIES ]; do
    if python -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(2)
try:
    s.connect(('redis', 6379))
    s.close()
    exit(0)
except:
    exit(1)
" 2>/dev/null; then
        echo "Redis erreichbar."
        break
    fi
    i=$((i + 1))
    echo "  Versuch $i/$MAX_RETRIES..."
    sleep $SLEEP_INTERVAL
done

if [ $i -eq $MAX_RETRIES ]; then
    echo "FEHLER: Redis nicht erreichbar nach $MAX_RETRIES Versuchen."
    exit 1
fi

echo "Alle Services erreichbar. Starte Backend..."
exec "$@"
