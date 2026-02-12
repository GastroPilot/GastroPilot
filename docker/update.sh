#!/bin/bash
# GastroPilot Update: Images pullen und Container neu starten
# Dieses Skript aktualisiert die Docker-Container von GastroPilot, indem es die neuesten Images vom Docker-Registry zieht und die Container neu startet.

# Verwendung:
#   ./update.sh
set -e

COMPOSE_FILE="docker-compose.server.yml"
ENV_FILE=".env.server"

# Pruefen ob .env.server existiert
if [ ! -f "$ENV_FILE" ]; then
    echo "Fehler: $ENV_FILE nicht gefunden."
    exit 1
fi

# Images pullen
echo "== Images pullen =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull backend frontend
echo

# Container neu starten
echo "== Container neu starten =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo

echo "Update abgeschlossen."
