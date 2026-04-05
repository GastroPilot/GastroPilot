#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GP_ROOT="$ROOT_DIR"
FRONTEND_DIR="${FRONTEND_DIR:-web}"
export FRONTEND_DIR

if ! command -v gnome-terminal >/dev/null 2>&1; then
  echo "Fehler: gnome-terminal wurde nicht gefunden."
  echo "Installiere es unter Fedora z.B. mit: sudo dnf install gnome-terminal"
  exit 1
fi

if [ ! -x "$GP_ROOT/backend/venv/bin/python" ]; then
  echo "Fehler: Python-Venv fehlt: $GP_ROOT/backend/venv/bin/python"
  echo "Bitte zuerst im backend die venv anlegen und Dependencies installieren."
  exit 1
fi

if [ ! -f "$GP_ROOT/$FRONTEND_DIR/package.json" ]; then
  echo "Fehler: Frontend ($FRONTEND_DIR) nicht gefunden unter: $GP_ROOT/$FRONTEND_DIR"
  exit 1
fi

if [ ! -f "$GP_ROOT/restaurant-app/package.json" ]; then
  echo "Fehler: restaurant-app nicht gefunden unter: $GP_ROOT/restaurant-app"
  exit 1
fi

echo "Starte Entwicklungsdienste in neuen Terminal-Fenstern..."

gnome-terminal --window --title="Backend Core :8000" -- bash -lc 'cd "$GP_ROOT/backend/services/core" || exit 1; "$GP_ROOT/backend/venv/bin/python" -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload; echo; echo "[Core beendet]"; exec bash' &
gnome-terminal --window --title="Backend Orders :8001" -- bash -lc 'cd "$GP_ROOT/backend/services/orders" || exit 1; "$GP_ROOT/backend/venv/bin/python" -m uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload; echo; echo "[Orders beendet]"; exec bash' &
gnome-terminal --window --title="Frontend $FRONTEND_DIR" -- bash -lc 'cd "$GP_ROOT/$FRONTEND_DIR" || exit 1; npm run dev; echo; echo "[Frontend beendet]"; exec bash' &
gnome-terminal --window --title="Restaurant App (Expo)" -- bash -lc 'cd "$GP_ROOT/restaurant-app" || exit 1; npm run start; echo; echo "[Restaurant-App beendet]"; exec bash' &

echo "Alle Startbefehle wurden in separaten Fenstern ausgeführt."
