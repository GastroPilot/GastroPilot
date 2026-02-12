#!/bin/bash
# Coming-Soon-Seite aktivieren/deaktivieren
STACK_NAME=$(grep -E '^STACK_NAME=' .env.server 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot}-nginx"

case "$1" in
  on)
    docker exec "$CONTAINER" touch /etc/nginx/coming-soon.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Coming-Soon-Seite aktiviert."
    ;;
  off)
    docker exec "$CONTAINER" rm -f /etc/nginx/coming-soon.on
    docker exec "$CONTAINER" nginx -s reload
    echo "Coming-Soon-Seite deaktiviert."
    ;;
  *)
    echo "Verwendung: $0 {on|off}"
    exit 1
    ;;
esac
