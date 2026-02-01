# GastroPilot - Entwicklerhandbuch

Dieses Dokument beschreibt, wie das GastroPilot-Projekt entwickelt, versioniert und deployed wird.

## Inhaltsverzeichnis

- [Projektstruktur](#projektstruktur)
- [Technologie-Stack](#technologie-stack)
- [Entwicklungsumgebung einrichten](#entwicklungsumgebung-einrichten)
- [Git Submodules Workflow](#git-submodules-workflow)
- [Entwicklungs-Workflow](#entwicklungs-workflow)
- [Code-Qualität](#code-qualität)
- [Testing](#testing)
- [Deployment](#deployment)
- [Versioning & Releases](#versioning--releases)
- [Milestones](#milestones)

---

## Projektstruktur

GastroPilot ist ein **Monorepo mit Git Submodules**:

```
GastroPilot/
├── .github/workflows/       # CI/CD Pipelines
├── .github/ISSUE_TEMPLATE/  # Issue-Vorlagen für GitHub
├── gastropilot-backend/     # FastAPI Backend (Submodule)
├── gastropilot-frontend/    # Next.js Frontend (Submodule)
├── gastropilot-app/         # Expo React Native App (Submodule)
├── docker-compose.yml       # Staging-Umgebung
├── VERSION                  # Aktuelle Version (semver)
├── AUTHORS                  # Projektautoren
├── LICENSE                  # Lizenzinformationen
├── SECURITY.md              # Sicherheitsrichtlinien
├── README.md                # Projektübersicht
└── CHANGELOG.md             # Release-Historie
```

### Submodule-Repositories

| Submodule | Repository |
|-----------|------------|
| Backend | `https://github.com/GastroPilot/gastropilot-backend.git` |
| Frontend | `https://github.com/GastroPilot/gastropilot-frontend.git` |
| App | `https://github.com/GastroPilot/gastropilot-app.git` |

---

## Technologie-Stack

### Backend

| Komponente | Technologie |
|------------|-------------|
| Framework | FastAPI 0.115+ |
| Sprache | Python 3.11 |
| Datenbank | PostgreSQL 16 (Prod), SQLite (Dev) |
| ORM | SQLAlchemy 2.0 (async) |
| Auth | JWT (python-jose) |
| Linting | Ruff, Black, isort |
| Testing | pytest, pytest-asyncio |

### Frontend

| Komponente | Technologie |
|------------|-------------|
| Framework | Next.js 16+ (App Router) |
| UI | React 19, TypeScript 5 |
| Styling | Tailwind CSS 4 |
| Components | shadcn/ui |
| Data Fetching | TanStack React Query v5 |
| Linting | ESLint, Prettier |
| Testing | Vitest, Playwright |

### Mobile App

| Komponente | Technologie |
|------------|-------------|
| Framework | Expo + Expo Router |
| UI | React Native, TypeScript |
| Auth | PIN-Login, NFC-Login (native) |
| API Client | Custom REST Client (`lib/api`) |
| Linting | ESLint |

---

## Entwicklungsumgebung einrichten

### Voraussetzungen

- Git
- Docker & Docker Compose
- Node.js 22+
- Python 3.11+
- pnpm oder npm

### 1. Repository klonen (mit Submodules)

```bash
git clone --recurse-submodules https://github.com/GastroPilot/GastroPilot.git
cd GastroPilot
```

Falls bereits geklont ohne Submodules:

```bash
git submodule update --init --recursive
```

### 2. Backend einrichten

```bash
cd gastropilot-backend

# Virtuelle Umgebung erstellen
python -m venv venv
source venv/bin/activate  # macOS/Linux
# oder: venv\Scripts\activate  # Windows

# Dependencies installieren
pip install -r requirements.txt

# Umgebungsvariablen kopieren
cp .env.example .env
# .env anpassen (DATABASE_URL, JWT_SECRET, etc.)

# Server starten (mit SQLite für lokale Entwicklung)
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Wichtige Umgebungsvariablen (.env):**

```bash
ENV=development
DATABASE_URL=sqlite+aiosqlite:///./reservation_dev.db
JWT_SECRET=<generiere-einen-sicheren-schlüssel>
SECRET_KEY=<generiere-einen-sicheren-schlüssel>
CORS_ORIGINS=http://localhost:3000,http://localhost:3001
LOG_LEVEL=DEBUG
```

### 3. Frontend einrichten

```bash
cd gastropilot-frontend

# Dependencies installieren
npm install

# Umgebungsvariablen kopieren
cp .env.example .env.local
# .env.local anpassen

# Development Server starten
npm run dev
```

**Wichtige Umgebungsvariablen (.env.local):**

```bash
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
```

### 4. Mobile App einrichten

```bash
cd gastropilot-app

# Dependencies installieren
npm install

# Umgebungsvariablen kopieren
cp env.example .env
# .env anpassen (EXPO_PUBLIC_API_URL)

# Expo starten
npx expo start
```

**Wichtige Umgebungsvariablen (.env):**

```bash
EXPO_PUBLIC_API_URL=http://localhost:8000
```

**Hinweise:**
- Für NFC-Login wird ein echtes Gerät mit NFC benötigt
- NFC funktioniert nicht in Expo Go oder im Web

### 5. Docker Compose für Entwicklung (empfohlen)

#### Option A: Komplette Dev-Umgebung (Backend + Frontend + DB)

Die einfachste Methode - startet alle Services zusammen mit Hot-Reload:

```bash
# Im Root-Verzeichnis
# 1. Umgebungsvariablen kopieren
cp .env.dev.example .env.dev

# 2. Optional: .env.dev anpassen (Ports, Secrets, etc.)

# 3. Services starten
docker compose -f docker-compose.dev.yml up

# Oder im Hintergrund:
docker compose -f docker-compose.dev.yml up -d

# Logs anzeigen
docker compose -f docker-compose.dev.yml logs -f

# Services stoppen
docker compose -f docker-compose.dev.yml down
```

**Verfügbare Services:**
- **Backend:** http://localhost:8000
- **Frontend:** http://localhost:3000
- **Database:** localhost:5432 (PostgreSQL)

**Features:**
- ✅ Hot-Reload für Backend und Frontend
- ✅ Source-Code wird per Volume gemountet
- ✅ PostgreSQL mit persistent storage
- ✅ Gemeinsames Docker-Netzwerk
- ✅ Health-Checks für alle Services
- ✅ Automatisches Anlegen eines Standard-Servecta-Benutzers

**Standard-Login (Development):**

Beim ersten Start wird automatisch ein Servecta-Administrator angelegt:
- **Bedienernummer:** `0000`
- **PIN:** `000000`
- **Rolle:** `servecta` (höchste Berechtigung)

> **Hinweis:** Dieser Benutzer wird nur in der Development- und Test-Umgebung automatisch angelegt.

#### Option B: Einzelne Services

Für mehr Kontrolle können Services auch einzeln gestartet werden:

```bash
# Nur Backend + Database
cd gastropilot-backend && docker compose up -d

# Nur Frontend
cd gastropilot-frontend && docker compose up -d
```

---

## Git Submodules Workflow

### Submodules aktualisieren

```bash
# Alle Submodules auf den neuesten Stand bringen
git submodule update --remote --merge

# Oder nur ein spezifisches Submodule
git submodule update --remote gastropilot-backend
git submodule update --remote gastropilot-frontend
git submodule update --remote gastropilot-app
```

### In einem Submodule arbeiten (Feature)

```bash
cd gastropilot-backend

# Eigenen Branch erstellen
git checkout -b feature/mein-feature

# Änderungen committen
git add .
git commit -m "feat: neue Funktion"
git push origin feature/mein-feature

# Pull Request im Submodule-Repository erstellen
```
### In einem Submodule arbeiten (Bugfix)

```bash
cd gastropilot-backend

# Eigenen Branch erstellen
git checkout -b fix/mein-bugfix

# Änderungen committen
git add .
git commit -m "fix: bugfix"
git push origin fix/mein-bugfix

# Pull Request im Submodule-Repository erstellen
```

### Submodule-Referenz im Hauptrepo aktualisieren

Nach dem Merge eines PR im Submodule:

```bash
# Im Root-Verzeichnis
cd gastropilot-backend
git checkout main
git pull

cd ..
git add gastropilot-backend
git commit -m "chore: update backend submodule"
git push
```

---

## Entwicklungs-Workflow

### Branch-Konvention

- `main` - Produktionsbereiter Code
- `feature/*` - Neue Features
- `fix/*` - Bugfixes
- `chore/*` - Wartungsarbeiten

### Commit-Konvention

Wir verwenden [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]
```

**Types:**
- `feat` - Neues Feature
- `fix` - Bugfix
- `docs` - Dokumentation
- `style` - Formatierung
- `refactor` - Code-Refactoring
- `test` - Tests
- `chore` - Wartung

**Beispiele:**

```bash
git commit -m "feat(reservations): add waitlist functionality"
git commit -m "fix(auth): resolve token refresh issue"
git commit -m "docs: update API documentation"
```

### Pull Request Workflow

1. Feature-Branch erstellen
2. Änderungen committen
3. PR erstellen gegen `main`
4. Code Review abwarten
5. Nach Approval: Merge in `main`
6. CI/CD deployed automatisch auf Staging

---

## Code-Qualität

### Backend

```bash
cd gastropilot-backend

# Linting
ruff check .

# Formatierung prüfen
black --check .
isort --check-only .

# Automatisch formatieren
black .
isort .
```

### Frontend

```bash
cd gastropilot-frontend

# Linting
npm run lint

# Formatierung prüfen
npm run format:check

# Automatisch formatieren
npm run format:write

# Type-Checking
npm run type-check
```

---

## Testing

### Backend Tests

```bash
cd gastropilot-backend

# Alle Tests ausführen
pytest

# Mit Coverage
pytest --cov=app --cov-report=html

# Spezifische Tests
pytest tests/test_reservations.py -v
```

### Frontend Tests

```bash
cd gastropilot-frontend

# Unit/Integration Tests
npm run test

# E2E Tests (Playwright)
npm run test:e2e

# Tests im Watch-Modus
npm run test:watch
```

---

## Deployment

### Umgebungen

| Umgebung | Frontend | Backend | Datenbank | URL |
|----------|----------|---------|-----------|-----|
| Test | :3004 | :8004 | :5433 | test.gpilot.app |
| Staging | :3003 | :8003 | :5433 | staging.gpilot.app |
| Demo | :3002 | :8002 | :5432 | demo.gpilot.app |
| Production | :3001 | :8001 | :5432 | gpilot.app |

### Automatisches Deployment (CI/CD)

```
Push auf main
    ↓
GitHub Actions: ci-cd.yml
    ├── Backend bauen → Push zu ghcr.io
    ├── Frontend bauen → Push zu ghcr.io
    └── Deploy auf Staging
        └── Health Checks
            └── Slack Notification
```

**Test:** Automatisch bei jedem Push mit `fix` oder `feat`-Präfix im Commit

**Staging:** Automatisch bei jedem Push auf `main`

**Demo/Production:** Manuell via GitHub Actions:

1. Gehe zu **Actions** → **CI/CD Pipeline**
2. Klicke auf **Run workflow**
3. Wähle `demo` oder `production`
4. Klicke auf **Run workflow**

### Manuelles Deployment

```bash
# SSH auf Server
ssh user@server

# Zum Umgebungsverzeichnis wechseln
cd /opt/gastropilot/staging  # oder test/demo/production

# Images pullen und neu starten
docker compose pull
docker compose up -d

# Health Check
curl http://localhost:8003/v1/health
```

### Server-Struktur

```
/opt/gastropilot/
├── test/
│   ├── docker-compose.yml
│   └── .env
├── staging/
│   ├── docker-compose.yml
│   └── .env
├── demo/
│   ├── docker-compose.yml
│   └── .env
└── production/
    ├── docker-compose.yml
    └── .env
```

---

## Versioning & Releases

### Semantic Versioning

Wir verwenden [Semantic Versioning](https://semver.org/) (SemVer):

```
MAJOR.MINOR.PATCH
  │     │     └── Bugfixes, kleine Änderungen
  │     └──────── Neue Features (abwärtskompatibel)
  └────────────── Breaking Changes
```

**Aktuelle Version:** Siehe `VERSION` Datei im Root

### Release erstellen

Releases werden über GitHub Actions erstellt:

1. Gehe zu **Actions** → **Release**
2. Klicke auf **Run workflow**
3. Wähle den Bump-Type:
   - `patch` (0.9.1 → 0.9.2) - Bugfixes
   - `minor` (0.9.1 → 0.10.0) - Neue Features
   - `major` (0.9.1 → 1.0.0) - Breaking Changes
4. Optional: "Deploy to production" aktivieren
5. Klicke auf **Run workflow**

**Was passiert beim Release:**

1. VERSION-Datei wird aktualisiert
2. CHANGELOG.md wird generiert
3. Git-Tag wird erstellt (z.B. `v0.9.2`)
4. GitHub Release wird erstellt
5. Docker Images werden getaggt (`v0.9.2`, `latest`)
6. Optional: Automatisches Production Deployment

### CHANGELOG

Der Changelog wird automatisch aus Commits generiert. Format:

```markdown
## [0.9.2] - 2026-01-30

### Added
- feat: neue Funktion XY

### Fixed
- fix: Problem mit AB behoben

### Changed
- refactor: Code-Verbesserungen
```

---

## Milestones

Wir verwenden **GitHub Milestones** zur Planung und Verfolgung von Releases. Jeder Milestone repräsentiert eine geplante Version.

### Geplante Milestones

| Milestone | Ziel | Fokus |
|-----------|------|-------|
| **v0.9.2** | Bugfixes & Stabilität | Behebung bekannter Fehler, Performance-Optimierungen |
| **v0.10.0** | Feature-Erweiterungen | Neue Funktionen basierend auf Kundenfeedback |
| **v1.0.0** | Stable Release | Produktionsreife, vollständige Dokumentation, API-Stabilität |

### Milestone-Workflow

1. **Milestone erstellen** (GitHub → Issues → Milestones → New milestone)
   - Name: Version (z.B. `v0.9.2`)
   - Beschreibung: Ziele und Fokus des Releases
   - Due Date: Geplantes Release-Datum (optional)

2. **Issues zuweisen**
   - Jedes Issue/PR sollte einem Milestone zugewiesen werden
   - Labels verwenden: `priority:high`, `priority:medium`, `priority:low`

3. **Fortschritt verfolgen**
   - GitHub zeigt automatisch den Fortschritt (offene vs. geschlossene Issues)
   - Regelmäßige Review-Meetings zum Milestone-Status

4. **Release auslösen**
   - Wenn alle Issues eines Milestones geschlossen sind
   - Release-Workflow starten (siehe [Release erstellen](#release-erstellen))
   - Milestone schließen

### Issues mit Milestones verknüpfen

**Via GitHub CLI:**

```bash
# Issue mit Milestone erstellen
gh issue create --title "Bug: Login fehlerhaft" --milestone "v0.9.2"

# Bestehendes Issue zuweisen
gh issue edit 123 --milestone "v0.9.2"

# PR mit Milestone erstellen
gh pr create --title "fix: Login-Bug beheben" --milestone "v0.9.2"
```

### Milestone-Kategorien

**v0.9.x (Patch Releases):**
- Kritische Bugfixes
- Sicherheitsupdates
- Kleine Verbesserungen
- Keine neuen Features

**v0.10.0+ (Minor Releases):**
- Neue Features
- UI/UX-Verbesserungen
- API-Erweiterungen (abwärtskompatibel)

**v1.0.0 (Major Release):**
- Stabile, produktionsreife Version
- Vollständige API-Dokumentation
- Breaking Changes (falls nötig)
- Langzeit-Support (LTS)

### Best Practices

- **Scope begrenzen:** Nicht zu viele Issues pro Milestone
- **Priorisieren:** Must-have vs. Nice-to-have klar trennen
- **Flexibel bleiben:** Issues bei Bedarf in späteren Milestone verschieben
- **Kommunizieren:** Team über Milestone-Änderungen informieren

---

## Hilfreiche Befehle

### Git & Submodules

```bash
# Alle Submodules aktualisieren
git submodule update --remote --merge
```

### Docker Development Environment

```bash
# Komplette Dev-Umgebung starten
docker compose -f docker-compose.dev.yml up -d

# Services neu bauen
docker compose -f docker-compose.dev.yml build

# Logs anzeigen (alle Services)
docker compose -f docker-compose.dev.yml logs -f

# Logs für einzelnen Service
docker compose -f docker-compose.dev.yml logs -f backend
docker compose -f docker-compose.dev.yml logs -f frontend
docker compose -f docker-compose.dev.yml logs -f db

# In Container einloggen
docker compose -f docker-compose.dev.yml exec backend bash
docker compose -f docker-compose.dev.yml exec frontend sh
docker compose -f docker-compose.dev.yml exec db psql -U postgres -d gastropilot_dev

# Services stoppen
docker compose -f docker-compose.dev.yml down

# Services stoppen und Volumes löschen (Datenbank wird zurückgesetzt!)
docker compose -f docker-compose.dev.yml down -v

# Service neu starten
docker compose -f docker-compose.dev.yml restart backend
```

### Einzelne Services (Alternative)

```bash
# Backend + Database
cd gastropilot-backend
docker compose logs -f backend
docker compose exec backend bash

# Frontend
cd gastropilot-frontend
docker compose logs -f frontend
docker compose exec frontend sh
```

### Datenbank

```bash
# Datenbank-Migration (Backend)
# Migrations werden automatisch beim Start ausgeführt

# PostgreSQL CLI (wenn mit docker-compose.dev.yml gestartet)
docker compose -f docker-compose.dev.yml exec db psql -U postgres -d gastropilot_dev

# Datenbank zurücksetzen
docker compose -f docker-compose.dev.yml down -v
docker compose -f docker-compose.dev.yml up -d
```

### Dependencies

```bash
# Dependency Updates prüfen
cd gastropilot-backend && pip list --outdated
cd gastropilot-frontend && npm outdated
cd gastropilot-app && npm outdated
```

### Mobile App

```bash
# Mobile App starten
cd gastropilot-app && npx expo start
```

---

## Troubleshooting

### Submodule-Probleme

```bash
# Submodules zurücksetzen
git submodule deinit -f .
git submodule update --init --recursive
```

### Docker-Probleme

```bash
# Development Environment: Alle Container stoppen und entfernen
docker compose -f docker-compose.dev.yml down -v

# Images neu bauen
docker compose -f docker-compose.dev.yml build --no-cache

# Neu starten
docker compose -f docker-compose.dev.yml up -d

# Einzelne Services (Backend/Frontend):
cd gastropilot-backend  # oder gastropilot-frontend
docker compose down -v
docker compose build --no-cache
docker compose up -d
```

### Port bereits belegt

```bash
# Prozess auf Port finden (macOS/Linux)
lsof -i :8000
# Prozess beenden
kill -9 <PID>
```

---

## Kontakt & Support

- **GitHub Issues:** Bugs und Feature Requests
- **Slack:** Team-Kommunikation
- **SECURITY.md:** Sicherheitslücken melden

---

*Letzte Aktualisierung: Januar 2026*
