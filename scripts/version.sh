#!/usr/bin/env bash
# =============================================================================
# GastroPilot Version Generator
# =============================================================================
# Generiert Versionsstrings für Builds und Deployments.
#
# Usage:
#   ./scripts/version.sh <component> [environment]
#
# Komponenten: web, dashboard, kds, table-order, core, orders, ai, notifications
# Environments: test, staging, demo, development, production (default: development)
#
# Die Version wird aus der VERSION-Datei im Root gelesen.
# Falls diese eine RC enthält (z.B. 0.14.3-rc.2), wird diese genutzt.
# Falls nicht (z.B. 0.14.2), wird die package.json/pyproject.toml Version genutzt.
#
# Beispiele:
#   VERSION=0.14.3-rc.2:
#     ./scripts/version.sh web test         → v0.14.3-rc.2
#     ./scripts/version.sh core production  → v0.14.3-rc.2
#
#   VERSION=0.14.2 (stabile Version):
#     ./scripts/version.sh web production   → v0.14.2
#     ./scripts/version.sh web test         → v0.14.2
#     ./scripts/version.sh core production  → v2.0.0
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPONENT="${1:-}"
ENVIRONMENT="${2:-development}"
BUILD_DATE="${BUILD_DATE:-$(date +%Y%m%d)}"
BUILD_TIME="${BUILD_TIME:-$(date +%H%M%S)}"
BUILD_TIMESTAMP="${BUILD_DATE}-${BUILD_TIME}"

if [ -z "$COMPONENT" ]; then
  echo "Usage: $0 <component> [environment]" >&2
  echo "" >&2
  echo "Komponenten:" >&2
  echo "  Frontend: web, dashboard, kds, table-order" >&2
  echo "  Backend:  core, orders, ai, notifications" >&2
  echo "" >&2
  echo "Environments: test, staging, demo, development, production" >&2
  exit 1
fi

# -------------------------------------------
# Root-VERSION lesen (kann RC enthalten)
# -------------------------------------------
ROOT_VERSION=""
if [ -f "$ROOT_DIR/VERSION" ]; then
    ROOT_VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
fi

# -------------------------------------------
# Falls ROOT_VERSION eine RC ist, diese direkt nutzen
# -------------------------------------------
if [[ "$ROOT_VERSION" =~ -rc\.[0-9]+$ ]]; then
    echo "v${ROOT_VERSION}"
    exit 0
fi

# -------------------------------------------
# Sonst: Komponentenversion aus package.json / pyproject.toml
# -------------------------------------------
get_frontend_version() {
  local dir="$1"
  local pkg="$ROOT_DIR/$dir/package.json"
  if [ -f "$pkg" ]; then
    grep '"version"' "$pkg" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/'
  else
    echo "0.0.0"
  fi
}

get_backend_version() {
  local service="$1"
  local toml="$ROOT_DIR/backend/services/$service/pyproject.toml"
  if [ -f "$toml" ]; then
    grep '^version' "$toml" | head -1 | sed 's/.*"\([^"]*\)".*/\1/'
  else
    echo "0.0.0"
  fi
}

case "$COMPONENT" in
  web)          BASE_VERSION=$(get_frontend_version "web") ;;
  dashboard)    BASE_VERSION=$(get_frontend_version "dashboard") ;;
  kds)          BASE_VERSION=$(get_frontend_version "kds") ;;
  table-order)  BASE_VERSION=$(get_frontend_version "table-order") ;;
  core)         BASE_VERSION=$(get_backend_version "core") ;;
  orders)       BASE_VERSION=$(get_backend_version "orders") ;;
  ai)           BASE_VERSION=$(get_backend_version "ai") ;;
  notifications) BASE_VERSION=$(get_backend_version "notifications") ;;
  *)
    echo "Unbekannte Komponente: $COMPONENT" >&2
    exit 1
    ;;
esac

echo "v${BASE_VERSION}"
