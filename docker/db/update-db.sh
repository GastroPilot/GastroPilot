#!/bin/bash
# GastroPilot DB-Update (db-01.servecta.local)
set -e
COMPOSE_FILE="docker-compose.db.yml"
ENV_FILE=".env.db"
[ ! -f "$ENV_FILE" ] && { echo "Fehler: $ENV_FILE nicht gefunden."; exit 1; }
echo "== DB-Images pullen =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull
echo "== Container neu starten =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo "Update abgeschlossen."
