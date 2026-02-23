#!/bin/bash
# GastroPilot API-Update (api.servecta.local)
set -e
COMPOSE_FILE="docker-compose.api.yml"
ENV_FILE=".env.api"
[ ! -f "$ENV_FILE" ] && { echo "Fehler: $ENV_FILE nicht gefunden."; exit 1; }
echo "== API-Images pullen (Docker Hub) =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull backend
echo "== Container neu starten =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo "Update abgeschlossen."
