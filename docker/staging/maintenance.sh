#!/bin/bash
# Wartungsmodus aktivieren/deaktivieren
STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot-staging}-nginx"

case "$1" in
  on)
    docker exec "$CONTAINER" touch /etc/nginx/maintenance.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Wartungsmodus aktiviert."
    ;;
  off)
    docker exec "$CONTAINER" rm -f /etc/nginx/maintenance.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Wartungsmodus deaktiviert."
    ;;
  *)
    echo "Verwendung: $0 {on|off}"
    exit 1
    ;;
esac
