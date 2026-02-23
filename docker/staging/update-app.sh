#!/bin/bash
# GastroPilot Staging-Update (stage.gpilot.org)
set -e
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
[ ! -f "$ENV_FILE" ] && { echo "Fehler: $ENV_FILE nicht gefunden."; exit 1; }
echo "== Staging-Images pullen (Docker Hub) =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull frontend backend nginx
echo "== Container neu starten =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo "Update abgeschlossen."
