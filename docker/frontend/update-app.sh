#!/bin/bash
# GastroPilot App-Update (app.servecta.local)
set -e
COMPOSE_FILE="docker-compose.app.yml"
ENV_FILE=".env.app"
[ ! -f "$ENV_FILE" ] && { echo "Fehler: $ENV_FILE nicht gefunden."; exit 1; }
echo "== App-Images pullen (Docker Hub) =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull frontend
echo "== Container neu starten =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo "Update abgeschlossen."
