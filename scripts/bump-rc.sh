#!/usr/bin/env bash
# =============================================================================
# GastroPilot RC Version Bump
# =============================================================================
# Ermittelt die nächste Release-Candidate-Version basierend auf Git-Tags.
#
# Usage:
#   ./scripts/bump-rc.sh [bump_type] [service]
#
# bump_type: auto (default), patch, minor, major
# service:   Optional. Z.B. "dashboard", "core", "web".
#            Ohne Service → Plattform-RC (v0.14.3-rc.1)
#            Mit Service  → Service-RC  (v0.14.3-rc.1-dashboard)
#
# Beispiele:
#   VERSION=0.14.2, keine RCs:
#     ./scripts/bump-rc.sh                     → 0.14.3-rc.1
#     ./scripts/bump-rc.sh auto dashboard      → 0.14.3-rc.1-dashboard
#     ./scripts/bump-rc.sh minor               → 0.15.0-rc.1
#
#   VERSION=0.14.3-rc.2:
#     ./scripts/bump-rc.sh                     → 0.14.3-rc.3
#     ./scripts/bump-rc.sh auto dashboard      → 0.14.3-rc.1-dashboard
#                                                (eigener Zähler pro Service)
#
# Output: Nur die Version, ohne "v" Prefix.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUMP_TYPE="${1:-auto}"
SERVICE="${2:-}"

# -------------------------------------------
# Aktuelle Version lesen
# -------------------------------------------
if [ -f "$ROOT_DIR/VERSION" ]; then
    CURRENT_VERSION=$(cat "$ROOT_DIR/VERSION" | tr -d '[:space:]')
else
    CURRENT_VERSION="0.0.0"
fi

# -------------------------------------------
# Prüfen ob bereits ein RC-Zyklus läuft
# VERSION kann sein: 0.14.2 | 0.14.3-rc.2
# -------------------------------------------
if [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-rc\.([0-9]+)$ ]]; then
    RC_MAJOR="${BASH_REMATCH[1]}"
    RC_MINOR="${BASH_REMATCH[2]}"
    RC_PATCH="${BASH_REMATCH[3]}"
    RC_NUM="${BASH_REMATCH[4]}"
    IN_RC_CYCLE=true
    BASE_VERSION="${RC_MAJOR}.${RC_MINOR}.${RC_PATCH}"
elif [[ "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    MAJOR="${BASH_REMATCH[1]}"
    MINOR="${BASH_REMATCH[2]}"
    PATCH="${BASH_REMATCH[3]}"
    IN_RC_CYCLE=false
else
    echo "Fehler: VERSION '$CURRENT_VERSION' hat ein ungültiges Format." >&2
    exit 1
fi

# -------------------------------------------
# Nächste Base-Version berechnen
# -------------------------------------------
if [ "$IN_RC_CYCLE" = true ] && [ "$BUMP_TYPE" = "auto" ]; then
    NEW_BASE="$BASE_VERSION"
else
    if [ "$IN_RC_CYCLE" = true ]; then
        MAJOR="$RC_MAJOR"
        MINOR="$RC_MINOR"
        PATCH="$RC_PATCH"
    fi

    case "$BUMP_TYPE" in
        auto|patch)
            if [ "$IN_RC_CYCLE" = false ]; then
                NEW_BASE="${MAJOR}.${MINOR}.$((PATCH + 1))"
            else
                NEW_BASE="$BASE_VERSION"
            fi
            ;;
        minor)
            NEW_BASE="${MAJOR}.$((MINOR + 1)).0"
            ;;
        major)
            NEW_BASE="$((MAJOR + 1)).0.0"
            ;;
        *)
            echo "Fehler: Ungültiger Bump-Type '$BUMP_TYPE'. Erlaubt: auto, patch, minor, major" >&2
            exit 1
            ;;
    esac
fi

# -------------------------------------------
# Tag-Pattern bestimmen (mit oder ohne Service-Suffix)
# -------------------------------------------
if [ -n "$SERVICE" ]; then
    TAG_PATTERN="v${NEW_BASE}-rc.*-${SERVICE}"
    TAG_REGEX="^v?${NEW_BASE}-rc\.([0-9]+)-${SERVICE}$"
else
    TAG_PATTERN="v${NEW_BASE}-rc.*"
    # Nur Plattform-RCs matchen (kein Service-Suffix)
    TAG_REGEX="^v?${NEW_BASE}-rc\.([0-9]+)$"
fi

# -------------------------------------------
# Höchste bestehende RC-Nummer ermitteln
# -------------------------------------------
HIGHEST_RC=0

if command -v git &> /dev/null && [ -d "$ROOT_DIR/.git" ]; then
    while IFS= read -r tag; do
        if [[ "$tag" =~ $TAG_REGEX ]]; then
            NUM="${BASH_REMATCH[1]}"
            if [ "$NUM" -gt "$HIGHEST_RC" ]; then
                HIGHEST_RC="$NUM"
            fi
        fi
    done < <(git -C "$ROOT_DIR" tag -l "$TAG_PATTERN" 2>/dev/null || true)
fi

# Falls Plattform-RC und VERSION eine höhere RC hat
if [ -z "$SERVICE" ] && [ "$IN_RC_CYCLE" = true ] && [ "$NEW_BASE" = "$BASE_VERSION" ]; then
    if [ "$RC_NUM" -gt "$HIGHEST_RC" ]; then
        HIGHEST_RC="$RC_NUM"
    fi
fi

NEXT_RC=$((HIGHEST_RC + 1))

if [ -n "$SERVICE" ]; then
    echo "${NEW_BASE}-rc.${NEXT_RC}-${SERVICE}"
else
    echo "${NEW_BASE}-rc.${NEXT_RC}"
fi
