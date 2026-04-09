#!/usr/bin/env bash
# =============================================================================
# GastroPilot EAS Deploy
# =============================================================================
# Erkennt automatisch ob ein EAS Update reicht oder ein neuer Build nötig ist.
# Vergleicht den nativen Fingerprint mit dem letzten Build-Fingerprint.
#
# Verwendung:
#   ./scripts/eas-deploy.sh app            # Guest App deployen
#   ./scripts/eas-deploy.sh restaurant-app # Restaurant App deployen
#
# Optionen:
#   --platform ios|android|all   (default: ios)
#   --channel  internal|production (default: internal)
#   --skip-check                 Build erzwingen ohne Fingerprint-Check
# =============================================================================

set -euo pipefail

# ─── Farben ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Defaults ────────────────────────────────────────────────────
PLATFORM="ios"
CHANNEL="internal"
SKIP_CHECK=false
APP_DIR=""

# ─── Argument Parsing ────────────────────────────────────────────
print_usage() {
  echo -e "${BOLD}Verwendung:${NC}"
  echo "  ./scripts/eas-deploy.sh <app|restaurant-app> [optionen]"
  echo ""
  echo -e "${BOLD}Optionen:${NC}"
  echo "  --platform ios|android|all   Plattform (default: ios)"
  echo "  --channel  internal|production  Channel/Profil (default: internal)"
  echo "  --skip-check                 Fingerprint-Check überspringen"
  echo ""
  echo -e "${BOLD}Beispiele:${NC}"
  echo "  ./scripts/eas-deploy.sh app"
  echo "  ./scripts/eas-deploy.sh app --channel production"
  echo "  ./scripts/eas-deploy.sh restaurant-app --platform all"
  echo "  ./scripts/eas-deploy.sh app --skip-check"
}

if [[ $# -lt 1 ]]; then
  print_usage
  exit 1
fi

APP_DIR="$1"
shift

while [[ $# -gt 0 ]]; do
  case $1 in
    --platform) PLATFORM="$2"; shift 2 ;;
    --channel)  CHANNEL="$2"; shift 2 ;;
    --skip-check) SKIP_CHECK=true; shift ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo -e "${RED}Unbekannte Option: $1${NC}"; print_usage; exit 1 ;;
  esac
done

# ─── Validierung ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$REPO_ROOT/$APP_DIR"

if [[ ! -d "$PROJECT_DIR" ]]; then
  echo -e "${RED}Fehler: Verzeichnis '$APP_DIR' existiert nicht.${NC}"
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/package.json" ]]; then
  echo -e "${RED}Fehler: Kein package.json in '$APP_DIR' gefunden.${NC}"
  exit 1
fi

FINGERPRINT_FILE="$PROJECT_DIR/.last-build-fingerprint"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  GastroPilot EAS Deploy${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  App:       ${BOLD}$APP_DIR${NC}"
echo -e "  Plattform: ${BOLD}$PLATFORM${NC}"
echo -e "  Channel:   ${BOLD}$CHANNEL${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ─── Fingerprint berechnen ───────────────────────────────────────
echo -e "${BLUE}▸ Berechne nativen Fingerprint...${NC}"
CURRENT_FINGERPRINT=$(npx -y @expo/fingerprint "$PROJECT_DIR" 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('hash',''))" 2>/dev/null || echo "")

if [[ -z "$CURRENT_FINGERPRINT" ]]; then
  echo -e "${YELLOW}⚠ Fingerprint konnte nicht berechnet werden. Neuer Build empfohlen.${NC}"
  NEEDS_BUILD=true
elif [[ "$SKIP_CHECK" == true ]]; then
  echo -e "${YELLOW}⚠ Fingerprint-Check übersprungen (--skip-check).${NC}"
  NEEDS_BUILD=true
elif [[ ! -f "$FINGERPRINT_FILE" ]]; then
  echo -e "${YELLOW}⚠ Kein gespeicherter Fingerprint gefunden (.last-build-fingerprint).${NC}"
  echo -e "  Erster Build? Neuer Build wird empfohlen."
  NEEDS_BUILD=true
else
  LAST_FINGERPRINT=$(cat "$FINGERPRINT_FILE")
  echo -e "  Aktuell:  ${CYAN}${CURRENT_FINGERPRINT:0:16}...${NC}"
  echo -e "  Letzter:  ${CYAN}${LAST_FINGERPRINT:0:16}...${NC}"

  if [[ "$CURRENT_FINGERPRINT" == "$LAST_FINGERPRINT" ]]; then
    echo -e "${GREEN}✔ Fingerprints stimmen überein → EAS Update möglich${NC}"
    NEEDS_BUILD=false
  else
    echo -e "${YELLOW}✘ Fingerprints unterscheiden sich → Neuer Build nötig${NC}"
    echo ""
    echo -e "${BLUE}▸ Unterschiede:${NC}"
    # Zeige was sich geändert hat
    DIFF_OUTPUT=$(npx -y @expo/fingerprint "$PROJECT_DIR" --diff "$FINGERPRINT_FILE" 2>/dev/null || echo "")
    if [[ -n "$DIFF_OUTPUT" ]]; then
      echo "$DIFF_OUTPUT" | head -20
    else
      echo "  (Details konnten nicht ermittelt werden)"
    fi
    NEEDS_BUILD=true
  fi
fi

echo ""

# ─── Aktion bestimmen und bestätigen ────────────────────────────
if [[ "$NEEDS_BUILD" == true ]]; then
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Empfehlung: Neuer Build + Submit${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Dies wird ausgeführt:"
  echo -e "    1. ${BOLD}eas build${NC} --platform $PLATFORM --profile $CHANNEL"
  echo -e "    2. ${BOLD}eas submit${NC} --platform $PLATFORM --profile $CHANNEL"
  echo ""
  echo -e "  Oder wähle eine Alternative:"
  echo -e "    ${BOLD}b${NC} = Build + Submit (empfohlen)"
  echo -e "    ${BOLD}u${NC} = Trotzdem nur Update (auf eigenes Risiko)"
  echo -e "    ${BOLD}n${NC} = Abbrechen"
  echo ""
  read -rp "$(echo -e "${BOLD}Auswahl [b/u/n]: ${NC}")" CHOICE

  case $CHOICE in
    b|B)
      ACTION="build"
      ;;
    u|U)
      echo -e "${YELLOW}⚠ Update trotz geändertem Fingerprint — kann zu Runtime-Fehlern führen!${NC}"
      ACTION="update"
      ;;
    n|N|*)
      echo -e "${RED}Abgebrochen.${NC}"
      exit 0
      ;;
  esac
else
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  Empfehlung: EAS Update${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "  Dies wird ausgeführt:"
  echo -e "    ${BOLD}eas update${NC} --channel $CHANNEL --platform $PLATFORM"
  echo ""
  echo -e "  Oder wähle eine Alternative:"
  echo -e "    ${BOLD}u${NC} = Update (empfohlen)"
  echo -e "    ${BOLD}b${NC} = Trotzdem neu builden"
  echo -e "    ${BOLD}n${NC} = Abbrechen"
  echo ""
  read -rp "$(echo -e "${BOLD}Auswahl [u/b/n]: ${NC}")" CHOICE

  case $CHOICE in
    u|U)
      ACTION="update"
      ;;
    b|B)
      ACTION="build"
      ;;
    n|N|*)
      echo -e "${RED}Abgebrochen.${NC}"
      exit 0
      ;;
  esac
fi

echo ""
cd "$PROJECT_DIR"

# ─── Update ausführen ────────────────────────────────────────────
if [[ "$ACTION" == "update" ]]; then
  read -rp "$(echo -e "${BOLD}Update-Nachricht: ${NC}")" UPDATE_MSG

  if [[ -z "$UPDATE_MSG" ]]; then
    UPDATE_MSG="update: $(date +%Y-%m-%d_%H:%M)"
  fi

  echo ""
  echo -e "${BLUE}▸ Starte EAS Update...${NC}"
  eas update --channel "$CHANNEL" --platform "$PLATFORM" --message "$UPDATE_MSG"

  echo ""
  echo -e "${GREEN}✔ Update erfolgreich deployed!${NC}"
fi

# ─── Build + Submit ausführen ────────────────────────────────────
if [[ "$ACTION" == "build" ]]; then
  echo -e "${BLUE}▸ Starte EAS Build...${NC}"
  eas build --platform "$PLATFORM" --profile "$CHANNEL"

  echo ""
  echo -e "${GREEN}✔ Build abgeschlossen.${NC}"
  echo ""

  read -rp "$(echo -e "${BOLD}Jetzt an App Store Connect submitten? [j/n]: ${NC}")" SUBMIT_CHOICE
  if [[ "$SUBMIT_CHOICE" == "j" || "$SUBMIT_CHOICE" == "J" ]]; then
    echo -e "${BLUE}▸ Starte Submit...${NC}"
    eas submit --platform "$PLATFORM" --profile "$CHANNEL" --latest
    echo -e "${GREEN}✔ Submit abgeschlossen.${NC}"
  fi

  # Fingerprint speichern nach erfolgreichem Build
  if [[ -n "$CURRENT_FINGERPRINT" ]]; then
    echo "$CURRENT_FINGERPRINT" > "$FINGERPRINT_FILE"
    echo -e "${GREEN}✔ Fingerprint gespeichert in .last-build-fingerprint${NC}"
  fi
fi

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Fertig! ✔${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
