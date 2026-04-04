#!/usr/bin/env bash
# =============================================================================
# GastroPilot Version Generator
# =============================================================================
# Generiert Versionsstrings im Format:
#   vmajor.minor.patch-YYYYMMDD-environment   (non-production)
#   vmajor.minor.patch-YYYYMMDD               (production)
#
# Usage:
#   ./scripts/version.sh <component> [environment]
#
# Komponenten: web, dashboard, kds, table-order, core, orders, ai, notifications
# Environments: staging, demo, development, production (default: development)
#
# Beispiele:
#   ./scripts/version.sh web staging        → v0.14.0-20260320-staging
#   ./scripts/version.sh core production    → v2.0.0-20260320
#   ./scripts/version.sh kds               → v0.1.0-20260320-development
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

COMPONENT="${1:-}"
ENVIRONMENT="${2:-development}"
BUILD_DATE="${BUILD_DATE:-$(date +%Y%m%d)}"

if [ -z "$COMPONENT" ]; then
  echo "Usage: $0 <component> [environment]" >&2
  echo "" >&2
  echo "Komponenten:" >&2
  echo "  Frontend: web, dashboard, kds, table-order" >&2
  echo "  Backend:  core, orders, ai, notifications" >&2
  echo "" >&2
  echo "Environments: staging, demo, development, production" >&2
  exit 1
fi

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

if [ "$ENVIRONMENT" = "production" ]; then
  FULL_VERSION="v${BASE_VERSION}-${BUILD_DATE}"
else
  FULL_VERSION="v${BASE_VERSION}-${BUILD_DATE}-${ENVIRONMENT}"
fi

echo "$FULL_VERSION"
