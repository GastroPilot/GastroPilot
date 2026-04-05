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
│   └── sql/             # DB-Initialisierung & Migrations
├── dev/                     # Entwicklungsumgebung (Docker Compose, nginx, .env)
│   ├── docker-compose.yml
│   ├── .env.example
│   └── nginx/
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
docker compose -f dev/docker-compose.yml up -d
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
# Empfohlen (nginx-Gateway aus dev/docker-compose.yml)
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
# 1. Umgebungsvariablen kopieren
cp dev/.env.example dev/.env

# 2. Optional: dev/.env anpassen (Ports, Secrets, etc.)

# 3. Services starten
docker compose -f dev/docker-compose.yml up

# Oder im Hintergrund:
docker compose -f dev/docker-compose.yml up -d

# Logs anzeigen
docker compose -f dev/docker-compose.yml logs -f

# Services stoppen
docker compose -f dev/docker-compose.yml down
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
docker compose -f dev/docker-compose.yml up -d postgres redis core orders nginx

# Frontend zusätzlich
docker compose -f dev/docker-compose.yml up -d frontend

# Optional bei Bedarf
docker compose -f dev/docker-compose.yml up -d ai notifications notifications-worker
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

| Umgebung | URL | Deployment | Server |
|----------|-----|------------|--------|
| Development | localhost | `dev/docker-compose.yml` (lokal) | Lokal |
| Test | test.gpilot.app | Submodule CI / Deploy-Workflow | APP-02 (10.0.3.1) |
| Staging | staging.gpilot.app | Deploy-Workflow | APP-02 (10.0.3.1) |
| Demo | demo.gpilot.app | Deploy-Workflow | APP-02 (10.0.3.1) |
| Production | gpilot.app | Release-Workflow | APP-01 (10.0.1.1) |

### CI/CD Workflows

#### Submodule CI/CD (automatisch)

Jedes Submodule hat einen eigenen CI/CD-Workflow (`ci-cd.yml`). Bei Push auf `main` werden Docker Images automatisch mit dem Tag `:test` gebaut. Die Version wird aus `package.json` gelesen.

```
Push auf main (Submodule)
    |
GitHub Actions: ci-cd.yml
    +-- Lint & Build Check
    +-- Docker Build & Push -> :test Tag
        +-- Server: docker compose pull && ./update.sh
```

#### Deploy Workflow (Test, Staging, Demo)

Der zentrale **Deploy**-Workflow im Haupt-Repo erstellt automatisch RC-Versionen:

1. **Actions** > **Deploy** > **Run workflow**
2. Wähle:
   - **Environment:** `test`, `staging`, `demo` oder `all`
   - **Services:** `all`, `frontend`, `backend` oder einzelner Service (z.B. `dashboard`)
   - **Ref:** Branch oder Tag (z.B. `main`)
   - **Version Bump:** `auto` (nächste RC-Nummer) oder `patch`/`minor`/`major` (neuer Zyklus)

**Beispiel: Nur Dashboard auf Test deployen:**
- Environment: `test`, Services: `dashboard`, Bump: `auto`
- Erstellt: `v0.14.3-rc.1-dashboard`, baut nur das Dashboard-Image

**Beispiel: Alles auf Staging deployen:**
- Environment: `staging`, Services: `all`, Bump: `auto`
- Erstellt: `v0.14.3-rc.2`, baut alle 8 Services

#### Release Workflow (Production)

1. **Actions** > **Release** > **Run workflow**
2. Wähle:
   - **`promote`** - Aktuelle RC zur Production machen (z.B. `0.14.3-rc.4` -> `0.14.3`)
   - **`patch`/`minor`/`major`** - Direkter Release (Hotfix ohne RC-Zyklus)
3. Optional: "Deploy to production" aktivieren

Images werden mit `:v{version}`, `:latest` und `:production` getaggt.

### Docker Image Tags

| Environment | Image Tag | Trigger | Version-Beispiel |
|-------------|-----------|---------|-----------------|
| Test | `:test` | Submodule CI oder Deploy-Workflow | `v0.14.3-rc.1-dashboard` |
| Staging | `:staging` | Deploy-Workflow | `v0.14.3-rc.2` |
| Demo | `:demo` | Deploy-Workflow | `v0.14.3-rc.2` |
| Production | `:v0.14.3`, `:latest`, `:production` | Release-Workflow | `v0.14.3` |

### Manuelles Deployment

```bash
# SSH auf Server (via WireGuard + INFRA-SRV Jump-Host)
ssh app-02      # Test/Staging/Demo
ssh app-01      # Production

# Zum Environment-Verzeichnis wechseln
cd /opt/test    # oder /opt/staging, /opt/demo, /opt/production

# Update (Pull + Migration + Restart)
./update.sh

# Oder manuell:
docker compose pull
docker compose up -d
docker compose exec core alembic -c alembic.ini upgrade head
```

### Server-Architektur

```
APP-01 (10.0.1.1) - Production
  /opt/production/

APP-02 (10.0.3.1) - Non-Production
  /opt/test/        <- gastropilot-test-*
  /opt/staging/     <- gastropilot-staging-*
  /opt/demo/        <- gastropilot-demo-*

DB-01  (10.0.2.1) - PostgreSQL Primary + Redis
DB-02  (10.0.2.2) - PostgreSQL Replica
INFRA  (10.0.0.2) - WireGuard, CoreDNS, Monitoring
```

### Hilfs-Skripte (pro Environment)

| Skript | Funktion |
|--------|----------|
| `./update.sh` | Images pullen, DB-Migration, Container neustarten |
| `./maintenance.sh on\|off` | Wartungsmodus ein-/ausschalten |
| `./coming-soon.sh on\|off` | Coming-Soon-Seite ein-/ausschalten |

---

## Versioning & Releases

### Versionierungsmodell

GastroPilot nutzt **Semantic Versioning** mit **Release Candidates** (RC):

```
v{MAJOR}.{MINOR}.{PATCH}[-rc.{N}[-{service}]]
```

| Beispiel | Bedeutung |
|----------|-----------|
| `v0.14.2` | Stabile Production-Version |
| `v0.14.3-rc.1` | Plattform-RC (alle Services, auf Test/Staging) |
| `v0.14.3-rc.3-dashboard` | Service-RC (nur Dashboard, auf Test) |
| `v0.15.0-rc.1` | Erster RC fuer naechstes Minor-Release |

### Typischer Release-Zyklus

```
Tag        Aktion                              VERSION            Git-Tag
---------- ----------------------------------- ------------------ ----------------------
Mo 06.04   Dashboard-Fix -> Deploy auf Test    (unv.)             v0.14.3-rc.1-dashboard
Di 07.04   Core-Bugfix -> Deploy auf Test      (unv.)             v0.14.3-rc.1-core
Mi 08.04   Alles auf Staging deployen          0.14.3-rc.1        v0.14.3-rc.1
Do 09.04   Noch ein Fix -> Staging             0.14.3-rc.2        v0.14.3-rc.2
Fr 10.04   Promote -> Production               0.14.3             v0.14.3
Mo 13.04   Neues Feature -> Deploy auf Test    (unv.)             v0.14.4-rc.1-web
```

### Versionsanzeige im Frontend

Alle 4 Frontends (Web, Dashboard, KDS, Table-Order) zeigen die Version im Footer:

```
Test:       v0.14.3-rc.2-test (20260405-143025)
Staging:    v0.14.3-rc.3-staging (20260409-091500)
Production: v0.14.3-prod (20260410-120000)
```

### Versions-Skripte

| Skript | Funktion |
|--------|----------|
| `scripts/bump-rc.sh [bump] [service]` | Berechnet naechste RC-Version aus Git-Tags |
| `scripts/version.sh <component> [env]` | Gibt aktuelle Version fuer eine Komponente aus |

```bash
# Beispiele
./scripts/bump-rc.sh                     # 0.14.3-rc.1     (Plattform)
./scripts/bump-rc.sh auto dashboard      # 0.14.3-rc.1-dashboard (Service)
./scripts/bump-rc.sh minor               # 0.15.0-rc.1     (neuer Minor-Zyklus)

./scripts/version.sh web production      # v0.14.2          (aus package.json)
./scripts/version.sh core test           # v0.14.3-rc.2     (aus VERSION, falls RC)
```

### Release erstellen

#### A) RC auf Test/Staging deployen

1. **Actions** > **Deploy**
2. Environment: `test` oder `staging`
3. Services: `all` oder einzelner Service
4. Version Bump: `auto`

-> Erstellt automatisch die naechste RC-Version und taggt sie.

#### B) RC zur Production promoten

1. **Actions** > **Release**
2. Release-Typ: **`promote`**
3. Deploy to Production: `true`

-> Entfernt den RC-Suffix (z.B. `0.14.3-rc.4` -> `0.14.3`) und baut alle Images.

#### C) Hotfix (direkt ohne RC)

1. **Actions** > **Release**
2. Release-Typ: **`patch`**
3. Deploy to Production: `true`

-> Erstellt direkt einen neuen Patch-Release ohne vorherigen RC-Zyklus.

### VERSION-Datei

Die `VERSION`-Datei im Root-Verzeichnis enthaelt die aktuelle Version:

- **Stabile Version:** `0.14.2` (Production)
- **RC-Version:** `0.14.3-rc.2` (waehrend eines RC-Zyklus)

Die VERSION-Datei wird automatisch durch die Workflows aktualisiert.

---

## Milestones

Wir verwenden **GitHub Milestones** zur Planung und Verfolgung von Releases. Jeder Milestone repraesentiert eine geplante Version.

### Milestone-Workflow

1. **Milestone erstellen** (GitHub > Issues > Milestones > New milestone)
   - Name: Version (z.B. `v0.15.0`)
   - Beschreibung: Ziele und Fokus des Releases
   - Due Date: Geplantes Release-Datum (optional)

2. **Issues zuweisen**
   - Jedes Issue/PR sollte einem Milestone zugewiesen werden
   - Labels verwenden: `priority:high`, `priority:medium`, `priority:low`

3. **Fortschritt verfolgen**
   - GitHub zeigt automatisch den Fortschritt (offene vs. geschlossene Issues)

4. **Release ausloesen**
   - Wenn alle Issues eines Milestones geschlossen sind
   - RC auf Test/Staging deployen und testen
   - Release-Workflow mit "promote" starten
   - Milestone schliessen

### Issues mit Milestones verknuepfen

```bash
# Issue mit Milestone erstellen
gh issue create --title "Bug: Login fehlerhaft" --milestone "v0.15.0"

# Bestehendes Issue zuweisen
gh issue edit 123 --milestone "v0.15.0"

# PR mit Milestone erstellen
gh pr create --title "fix: Login-Bug beheben" --milestone "v0.15.0"
```

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
docker compose -f dev/docker-compose.yml up -d

# Logs anzeigen
docker compose -f dev/docker-compose.yml logs -f

# Logs fuer einzelnen Service
docker compose -f dev/docker-compose.yml logs -f core

# Services stoppen
docker compose -f dev/docker-compose.yml down

# Services stoppen + Datenbank zuruecksetzen
docker compose -f dev/docker-compose.yml down -v
```

### Datenbank

```bash
# Migration
docker compose -f dev/docker-compose.yml exec core alembic upgrade head

# PostgreSQL CLI
docker compose -f dev/docker-compose.yml exec postgres psql -U gastropilot -d gastropilot
```

### Mobile App

```bash
cd restaurant-app && npx expo start
```

---

## Troubleshooting

### Submodule-Probleme

```bash
git submodule deinit -f .
git submodule update --init --recursive
```

### Docker-Probleme

```bash
docker compose -f dev/docker-compose.yml down -v
docker compose -f dev/docker-compose.yml build --no-cache
docker compose -f dev/docker-compose.yml up -d
```

### Port bereits belegt

```bash
lsof -i :8000
kill -9 <PID>
```

---

## Kontakt & Support

- **GitHub Issues:** Bugs und Feature Requests
- **Slack:** Team-Kommunikation
- **SECURITY.md:** Sicherheitsluecken melden

---

*Letzte Aktualisierung: April 2026*
