#!/bin/bash
# GastroPilot Staging-Update (stage.gpilot.org)
# Pullt alle Microservice-Images und startet Container neu.
set -e
COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
[ ! -f "$ENV_FILE" ] && { echo "Fehler: $ENV_FILE nicht gefunden."; exit 1; }
echo "== Staging-Images pullen (Docker Hub) =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" pull frontend core orders ai notifications
echo "== Container neu starten =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
echo
echo "== Core DB-Migration (Alembic) =="
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" exec -T core alembic -c alembic.ini upgrade head
echo
echo "== Health-Check =="
sleep 5
for svc in core orders ai notifications; do
    STACK_NAME=$(grep -E '^STACK_NAME=' "$ENV_FILE" 2>/dev/null | cut -d= -f2)
    CONTAINER="${STACK_NAME:-gastropilot-staging}-${svc}"
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo "unknown")
    echo "  $svc: $STATUS"
done
echo
echo "Update abgeschlossen."
