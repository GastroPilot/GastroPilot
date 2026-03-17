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
├── .github/workflows/   # CI/CD Pipelines
├── .github/ISSUE_TEMPLATE/
├── backend/             # FastAPI Backend Microservices (Submodule)
├── web/                 # Next.js Dashboard (Submodule)
├── restaurant-app/      # Expo React Native App (Submodule)
├── guest-portal/        # Guest Web Portal (Submodule)
├── kds/                 # Kitchen Display System (Submodule)
├── table-order/         # QR Table Ordering PWA (Submodule)
├── infra/
│   ├── demo/            # Demo-Environment Reset & Seeds
│   ├── nginx/           # API Gateway Konfiguration
│   └── sql/             # DB-Initialisierung & Migrations
├── docker-compose.yml       # Staging-Umgebung
├── docker-compose.dev.yml   # Entwicklungsumgebung
├── docker-compose.prod.yml  # Produktionsumgebung
├── VERSION              # Aktuelle Version (semver)
├── AUTHORS.md           # Projektautoren
├── LICENSE              # Lizenzinformationen
├── SECURITY.md          # Sicherheitsrichtlinien
├── README.md            # Projektübersicht
└── CHANGELOG.md         # Release-Historie
```

### Submodule-Repositories

| Submodule | Repository |
|-----------|------------|
| Backend | `https://github.com/GastroPilot/backend.git` |
| Frontend | `https://github.com/GastroPilot/web.git` |
| App | `https://github.com/GastroPilot/restaurant-app.git` |
| Guest Portal | `https://github.com/GastroPilot/gastropilot-guest-portal.git` |
| KDS | `https://github.com/GastroPilot/gastropilot-kds.git` |
| Table Order | `https://github.com/GastroPilot/gastropilot-table-order.git` |

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
cd backend

# Virtuelle Umgebung erstellen
python -m venv venv
source venv/bin/activate  # macOS/Linux
# oder: venv\Scripts\activate  # Windows

# Dependencies installieren
pip install -r requirements.txt

# Service-Umgebungsvariablen anlegen
cp services/core/.env.example services/core/.env
cp services/orders/.env.example services/orders/.env
```

**Wichtige Umgebungsvariablen (services/core/.env):**

```bash
ENV=development
DATABASE_URL=postgresql+asyncpg://gastropilot_app:gastropilot_app_password@localhost:5432/gastropilot
DATABASE_ADMIN_URL=postgresql+asyncpg://gastropilot_admin:gastropilot_admin_password@localhost:5432/gastropilot
JWT_SECRET=<generiere-einen-sicheren-schlüssel>
CORS_ORIGINS=http://localhost:3000,http://localhost:3001
# Optional lokal ohne Redis:
REDIS_URL=
```

**Wichtige Umgebungsvariablen (services/orders/.env):**

```bash
ENV=development
DATABASE_URL=postgresql+asyncpg://gastropilot_app:gastropilot_app_password@localhost:5432/gastropilot
DATABASE_ADMIN_URL=postgresql+asyncpg://gastropilot_admin:gastropilot_admin_password@localhost:5432/gastropilot
JWT_SECRET=<derselbe JWT_SECRET wie im core-service>
CORS_ORIGINS=http://localhost:3000,http://localhost:3001
REDIS_URL=redis://localhost:6379/0
```

**Startvarianten (lokal):**

```bash
# A) Nur Core (Auth/Tenant/Reservierungen etc., NICHT vollständige App-Funktion)
cd backend/services/core
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

```bash
# B) Core + Orders (zwei Terminals)
# Terminal 1
cd backend/services/core
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Terminal 2
cd backend/services/orders
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

```bash
# C) Empfohlen für vollständige lokale Entwicklung:
# nginx + core + orders + db + redis (+ optional ai/notifications)
cd GastroPilot
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d
```

### 3. Frontend einrichten

```bash
cd web

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
# Empfohlen (nginx-Gateway aus docker-compose.dev.yml)
NEXT_PUBLIC_API_BASE_URL=http://localhost:80
NEXT_PUBLIC_API_PREFIX=api/v1

# Alternative nur für Core-Debugging:
# NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
# NEXT_PUBLIC_API_PREFIX=v1
#
# Achtung: Mit "nur Core" sind nicht alle Frontend-Features verfügbar
# (z.B. Orders/Kitchen und aktuell fehlende Table-CRUD-Endpunkte im core-service).
```

### 4. Mobile App einrichten

```bash
cd restaurant-app

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
EXPO_PUBLIC_API_URL=http://localhost:8000/v1
```

**Hinweise:**
- Beim ersten Start fragt die App nach dem Restaurant-Kürzel (`tenant_slug`, z.B. `mein-restaurant`)
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
docker compose -f docker-compose.dev.yml --env-file .env.dev up

# Oder im Hintergrund:
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d

# Logs anzeigen
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f

# Services stoppen
docker compose -f docker-compose.dev.yml --env-file .env.dev down
```

**Verfügbare Services:**
- **Gateway (nginx):** http://localhost:80
- **Frontend:** http://localhost:3001
- **API über Gateway:** http://localhost:80/api/v1
- **Orders/Kitchen über Gateway:** http://localhost:80/api/v1/orders, http://localhost:80/api/v1/kitchen
- **Database:** localhost:5432 (PostgreSQL)

**Features:**
- ✅ Hot-Reload für Backend und Frontend
- ✅ Source-Code wird per Volume gemountet
- ✅ PostgreSQL mit persistent storage
- ✅ Gemeinsames Docker-Netzwerk
- ✅ Health-Checks für alle Services

**Hinweis:** Im Microservice-Stack ist Auth im `core`-Service. Für PIN-Login ist dort `tenant_slug` erforderlich.

#### Option B: Einzelne Services

Für mehr Kontrolle können Services auch einzeln gestartet werden:

```bash
# Aus dem Root-Verzeichnis:
# API-Basis für fast alle Flows: Core + Orders + DB + Redis + Gateway
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d postgres redis core orders nginx

# Frontend zusätzlich
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d frontend

# Optional bei Bedarf
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d ai notifications notifications-worker
```

---

## Git Submodules Workflow

### Submodules aktualisieren

```bash
# Alle Submodules auf den neuesten Stand bringen
git submodule update --remote --merge

# Oder nur ein spezifisches Submodule
git submodule update --remote backend
git submodule update --remote web
git submodule update --remote restaurant-app
git submodule update --remote gastropilot-guest-portal
git submodule update --remote gastropilot-kds
git submodule update --remote gastropilot-table-order
```

### In einem Submodule arbeiten (Feature)

```bash
cd backend

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
cd backend

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
cd backend
git checkout main
git pull

cd ..
git add backend
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
cd backend

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
cd web

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
cd backend

# Alle Tests ausführen
pytest

# Mit Coverage
pytest --cov=app --cov-report=html

# Spezifische Tests
pytest tests/test_reservations.py -v
```

### Frontend Tests

```bash
cd web

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

| Umgebung | URL | Compose-File |
|----------|-----|-------------|
| Development | localhost | `docker-compose.dev.yml` |
| Staging | staging.gastropilot.de | `docker-compose.yml` |
| Demo | demo.gastropilot.de | `docker-compose.yml` |
| Production | gastropilot.de | `docker-compose.prod.yml` |

### CI/CD Workflows

#### Submodule CI/CD (automatisch)

Jedes Submodule hat einen eigenen CI/CD-Workflow (`ci-cd.yml`). Bei Push auf `main` werden die Docker Images automatisch mit dem Tag `:test` gebaut und gepusht. Watchtower auf dem Test-Server aktualisiert die Container automatisch.

```
Push auf main (Submodule)
    ↓
GitHub Actions: ci-cd.yml
    ├── Lint & Build Check
    └── Docker Build & Push → :test Tag
        └── Watchtower → Test-Environment
```

#### Deploy Workflow (manuell für Staging & Demo)

Für Staging und Demo wird der zentrale **Deploy**-Workflow im Haupt-Repo verwendet:

1. Gehe zu **Actions** → **Deploy**
2. Klicke auf **Run workflow**
3. Wähle:
   - **Environment:** `staging` oder `demo`
   - **Ref:** Branch oder Tag (z.B. `main`, `v0.13.0`)
   - **Version:** App-Version als Text (wird als `NEXT_PUBLIC_APP_VERSION` übernommen)
4. Klicke auf **Run workflow**

Alle 8 Docker Images werden mit dem Environment-Tag (`:staging` oder `:demo`) gebaut und gepusht.

#### Release Workflow (Production)

Für Production wird der **Release**-Workflow verwendet. Die Release-Version wird automatisch als `NEXT_PUBLIC_APP_VERSION` übernommen.

1. Gehe zu **Actions** → **Release**
2. Wähle den Bump-Type (patch/minor/major)
3. Optional: "Deploy to production" aktivieren

Images werden mit `:v{version}`, `:latest` und `:production` getaggt.

### Docker Image Tags pro Environment

| Environment | Image Tag | Trigger |
|-------------|-----------|---------|
| Test | `:test` | Automatisch bei Push auf `main` (Submodule) |
| Staging | `:staging` | Manuell via Deploy-Workflow |
| Demo | `:demo` | Manuell via Deploy-Workflow |
| Production | `:v{version}`, `:latest`, `:production` | Manuell via Release-Workflow |

### Manuelles Deployment

```bash
# SSH auf Server
ssh user@server

# Zum Umgebungsverzeichnis wechseln
cd /opt/gastropilot/test  # oder staging/demo/production

# Images pullen und neu starten
docker compose pull
docker compose up -d

# DB-Migration (falls nötig)
docker compose exec core alembic -c alembic.ini upgrade head

# Health Check
curl http://localhost:8000/v1/health
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
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d

# Services neu bauen
docker compose -f docker-compose.dev.yml --env-file .env.dev build

# Logs anzeigen (alle Services)
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f

# Logs für einzelnen Service
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f core
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f orders
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f frontend
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f postgres

# In Container einloggen
docker compose -f docker-compose.dev.yml --env-file .env.dev exec core sh
docker compose -f docker-compose.dev.yml --env-file .env.dev exec orders sh
docker compose -f docker-compose.dev.yml --env-file .env.dev exec frontend sh
docker compose -f docker-compose.dev.yml --env-file .env.dev exec postgres psql -U gastropilot -d gastropilot

# Services stoppen
docker compose -f docker-compose.dev.yml --env-file .env.dev down

# Services stoppen und Volumes löschen (Datenbank wird zurückgesetzt!)
docker compose -f docker-compose.dev.yml --env-file .env.dev down -v

# Service neu starten
docker compose -f docker-compose.dev.yml --env-file .env.dev restart core
docker compose -f docker-compose.dev.yml --env-file .env.dev restart orders
```

### Einzelne Services (Alternative)

```bash
# Core + Orders + Database + Redis + Gateway
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d postgres redis core orders nginx
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f core
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f orders

# Frontend
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d frontend
docker compose -f docker-compose.dev.yml --env-file .env.dev logs -f frontend
```

### Datenbank

```bash
# Datenbank-Migration (Core)
docker compose -f docker-compose.dev.yml --env-file .env.dev exec core alembic upgrade head

# PostgreSQL CLI (wenn mit docker-compose.dev.yml gestartet)
docker compose -f docker-compose.dev.yml --env-file .env.dev exec postgres psql -U gastropilot -d gastropilot

# Datenbank zurücksetzen
docker compose -f docker-compose.dev.yml --env-file .env.dev down -v
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d
```

### Dependencies

```bash
# Dependency Updates prüfen
cd backend && pip list --outdated
cd web && npm outdated
cd restaurant-app && npm outdated
```

### Mobile App

```bash
# Mobile App starten
cd restaurant-app && npx expo start
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
docker compose -f docker-compose.dev.yml --env-file .env.dev down -v

# Images neu bauen
docker compose -f docker-compose.dev.yml --env-file .env.dev build --no-cache

# Neu starten
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d

# Nur Core frisch bauen/starten
docker compose -f docker-compose.dev.yml --env-file .env.dev build --no-cache core
docker compose -f docker-compose.dev.yml --env-file .env.dev up -d core
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

*Letzte Aktualisierung: März 2026*
