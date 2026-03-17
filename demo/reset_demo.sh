#!/bin/bash
# ============================================================================
# GastroPilot Demo Reset — Docker Compose Wrapper
# Fuehrt reset_demo.py als eigenen Container im Demo-Stack aus.
# ============================================================================

set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/demo}"
LOG_PREFIX="[$(date '+%Y-%m-%d %H:%M:%S')]"

echo "${LOG_PREFIX} Demo Reset gestartet."

cd "${COMPOSE_DIR}"

# demo-reset Service ausfuehren (--rm raeumt Container danach auf)
docker compose --profile tools run --rm demo-reset
EXIT_CODE=$?

if [ ${EXIT_CODE} -eq 0 ]; then
    echo "${LOG_PREFIX} Demo Reset erfolgreich abgeschlossen."
else
    echo "${LOG_PREFIX} FEHLER: Demo Reset fehlgeschlagen (Exit-Code: ${EXIT_CODE})!" >&2
fi

exit ${EXIT_CODE}
