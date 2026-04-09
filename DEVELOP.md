# GastroPilot - Entwicklerhandbuch

Internes Handbuch für das Entwicklerteam (Luca & Sascha). Beschreibt Setup, Workflows, Testing, Deployment und Versionierung.

## Inhaltsverzeichnis

- [Projekt-Überblick](#projekt-Überblick)
- [Arbeitsbereiche & Zuständigkeiten](#arbeitsbereiche--zuständigkeiten)
- [Entwicklungsumgebung einrichten](#entwicklungsumgebung-einrichten)
- [Git & Submodule Workflow](#git--submodule-workflow)
- [Arbeitsbereich: Web-Frontend](#arbeitsbereich-web-frontend)
- [Arbeitsbereich: Backend](#arbeitsbereich-backend)
- [Arbeitsbereich: Mobile Apps](#arbeitsbereich-mobile-apps)
- [Bereichsübergreifende Entwicklung](#bereichsübergreifende-entwicklung)
- [Deployment](#deployment)
- [Versionierung & Releases](#versionierung--releases)
- [Hilfreiche Befehle](#hilfreiche-befehle)
- [Troubleshooting](#troubleshooting)

---

## Projekt-Überblick

GastroPilot ist ein **Monorepo mit Git Submodules**. Jede Komponente lebt in einem eigenen Repository und wird hier als Submodule eingebunden.

```
GastroPilot/
├── .github/workflows/       # CI/CD (deploy.yml, release.yml)
├── backend/                  # FastAPI Microservices (Submodule)
│   ├── services/core/        #   Auth, Restaurants, Menüs, Reservierungen (Port 8000)
│   ├── services/orders/      #   Bestellungen, Küche, Rechnungen, SumUp (Port 8001)
│   ├── services/ai/          #   Sitzplatz-Optimierung, Peak-Prediction (Port 8002)
│   ├── services/notifications/ # Email, SMS, WhatsApp via Celery (Port 8003)
│   └── packages/shared/      #   Geteilter Code (Auth, Tenant, Events, Schemas)
├── web/                      # Öffentliche Website + Gäste-Portal (Port 3000, Submodule)
├── dashboard/                # Restaurant-Management Dashboard (Port 3001, Submodule)
├── kds/                      # Kitchen Display System (Port 3004, Submodule)
├── table-order/              # QR-Tischbestellung PWA (Port 3003, Submodule)
├── app/                      # Gäste Mobile App (Expo, Submodule)
├── restaurant-app/           # Restaurant Staff App (Expo, Submodule)
├── dev/                      # Docker Compose, nginx, .env
├── scripts/                  # Versions- und Deploy-Skripte
├── infra/                    # SQL-Init, RLS-Policies, Demo-Seeds
└── VERSION                   # Aktuelle Plattform-Version (semver)
```

---

## Arbeitsbereiche & Zuständigkeiten

Das Projekt ist in **drei Arbeitsbereiche** aufgeteilt:

| Arbeitsbereich | Submodules | Zuständig | Tech-Stack |
|---------------|------------|------------|------------|
| **Web-Frontend** | `web`, `dashboard`, `kds`, `table-order` | Luca: web; Sascha: dashboard, kds, table-order | Next.js 16, React 19, Tailwind 4, shadcn/ui |
| **Backend** | `backend` | Beide | FastAPI, Python 3.11, SQLAlchemy 2.0 async, PostgreSQL |
| **Mobile Apps** | `app`, `restaurant-app` | Luca: app; Sascha: restaurant-app | Expo, React Native, Expo Router |

**Code Review:** Mindestens 1 Approval erforderlich. Wir reviewen gegenseitig — jeder kontrolliert die Arbeit des anderen. Beim Backend reviewen beide.

---

## Entwicklungsumgebung einrichten

### Voraussetzungen

- Git
- Docker & Docker Compose
- Node.js 22+
- Python 3.11+
- npm

### 1. Repository klonen

```bash
git clone --recurse-submodules https://github.com/GastroPilot/GastroPilot.git
cd GastroPilot
```

Falls bereits geklont ohne Submodules:

```bash
git submodule update --init --recursive
```

### 2. Docker Compose (empfohlen)

Die einfachste Methode — startet alle Services mit Hot-Reload:

```bash
# Umgebungsvariablen anlegen
cp dev/.env.example dev/.env

# Alle Services starten
docker compose -f dev/docker-compose.yml up -d

# Oder nur Backend-Basis (für Frontend-Entwicklung)
docker compose -f dev/docker-compose.yml up -d postgres redis core orders nginx

# Logs verfolgen
docker compose -f dev/docker-compose.yml logs -f core orders
```

**Erreichbare Services:**

| Service | URL |
|---------|-----|
| nginx Gateway (API) | http://localhost:80 |
| Web | http://localhost:3000 |
| Dashboard | http://localhost:3001 |
| Table-Order | http://localhost:3003 |
| KDS | http://localhost:3004 |
| MinIO Console | http://localhost:9001 |
| PostgreSQL | localhost:5432 |
| Redis | localhost:6379 |

### 3. Einzelne Arbeitsbereiche einrichten

Wenn du ohne Docker direkt in einem Arbeitsbereich entwickeln willst, siehe die jeweiligen Abschnitte unten:

- [Web-Frontend Setup](#lokales-setup)
- [Backend Setup](#lokales-setup-1)
- [Mobile Apps Setup](#lokales-setup-2)

---

## Git & Submodule Workflow

### Branch-Konvention

- `main` — Produktionsbereiter Code
- `feature/*` — Neue Features
- `fix/*` — Bugfixes
- `chore/*` — Wartungsarbeiten

### Commit-Konvention

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

| Type | Verwendung |
|------|-----------|
| `feat` | Neues Feature |
| `fix` | Bugfix |
| `refactor` | Code-Umbau ohne Funktionsänderung |
| `docs` | Dokumentation |
| `test` | Tests |
| `style` | Formatierung |
| `chore` | Wartung, Dependencies, CI |

```bash
# Beispiele
git commit -m "feat(reservations): add waitlist functionality"
git commit -m "fix(auth): resolve token refresh issue"
git commit -m "chore(deps): update shadcn/ui components"
```

### In einem Submodule arbeiten

```bash
# 1. Ins Submodule wechseln
cd dashboard

# 2. Branch erstellen
git checkout -b feature/neue-ansicht

# 3. Entwickeln, committen
git add .
git commit -m "feat(dashboard): add analytics view"
git push origin feature/neue-ansicht

# 4. PR im Submodule-Repository erstellen
# 5. Review abwarten, mergen lassen
```

### Submodule-Referenz im Hauptrepo aktualisieren

Nach dem Merge eines PR im Submodule muss das Hauptrepo die neue Referenz kennen:

```bash
# Im Root-Verzeichnis
cd dashboard
git checkout main
git pull

cd ..
git add dashboard
git commit -m "chore: update dashboard submodule"
git push
```

### Alle Submodules aktualisieren

```bash
# Alle auf neuesten main-Stand bringen
git submodule update --remote --merge

# Oder nur ein bestimmtes
git submodule update --remote backend
```

---

## Arbeitsbereich: Web-Frontend

**Submodules:** `web` (Port 3000), `dashboard` (Port 3001), `kds` (Port 3004), `table-order` (Port 3003)

Alle vier Apps teilen denselben Tech-Stack und dieselbe Projektstruktur.

### Tech-Stack

| Komponente | Technologie |
|------------|-------------|
| Framework | Next.js 16+ (App Router) |
| UI | React 19, TypeScript 5 |
| Styling | Tailwind CSS 4, shadcn/ui |
| State | Zustand |
| Data Fetching | TanStack React Query v5 |
| Dates | date-fns |
| Icons | lucide-react |
| Linting | ESLint, Prettier |
| Testing | Vitest (Unit), Playwright (E2E) |

### Lokales Setup

```bash
cd web  # oder dashboard, kds, table-order

# Dependencies installieren
npm install

# Umgebungsvariablen
cp .env.example .env.local
```

**Wichtige Umgebungsvariablen (.env.local):**

```bash
# Mit nginx-Gateway (empfohlen, erfordert Docker Compose Backend)
NEXT_PUBLIC_API_BASE_URL=http://localhost:80
NEXT_PUBLIC_API_PREFIX=api/v1

# Alternative: Direkt gegen Core-Service (eingeschränkte Funktionalität)
# NEXT_PUBLIC_API_BASE_URL=http://localhost:8000
# NEXT_PUBLIC_API_PREFIX=v1
```

```bash
# Dev-Server starten
npm run dev
```

### Entwicklungs-Workflow

1. **Branch erstellen** im Submodule-Repo (`feature/*`, `fix/*`)
2. **Entwickeln** mit `npm run dev` — Hot-Reload ist aktiv
3. **Qualität prüfen** vor dem Commit:
   ```bash
   npm run lint          # ESLint
   npm run format:check  # Prettier
   npm run type-check    # TypeScript
   ```
4. **Automatisch formatieren** bei Bedarf:
   ```bash
   npm run format:write
   ```
5. **Committen & pushen**, PR erstellen
6. **Review** durch den anderen Entwickler (1 Approval)
7. **Merge** in `main`

### Testing

```bash
# Unit/Integration Tests (Vitest)
npm run test
npm run test:coverage

# E2E Tests (Playwright)
npm run test:e2e
```

**Hinweise:**
- `web` und `dashboard` haben vollständige Test-Setups (Vitest + Playwright)
- `kds` und `table-order` haben aktuell noch minimale Test-Abdeckung

### Submodule CI/CD

Jedes Web-Frontend-Submodule hat einen eigenen `ci-cd.yml` Workflow:

```
Push auf main → GitHub Actions → Lint & Build Check → Docker Build & Push (:test Tag)
```

Die Version wird aus der jeweiligen `package.json` gelesen.

---

## Arbeitsbereich: Backend

**Submodule:** `backend` mit 4 Microservices und Shared-Packages.

### Tech-Stack

| Komponente | Technologie |
|------------|-------------|
| Framework | FastAPI 0.115+ |
| Sprache | Python 3.11 |
| ORM | SQLAlchemy 2.0 (async) |
| Datenbank | PostgreSQL 16 mit RLS |
| Auth | JWT (python-jose) |
| Events | Redis Pub/Sub |
| Async Tasks | Celery (Notifications) |
| Linting | Ruff, Black, isort |
| Testing | pytest, pytest-asyncio |

### Microservices

| Service | Port | Scope |
|---------|------|-------|
| `services/core` | 8000 | Auth, Users, Restaurants, Reservierungen, Menüs, Tische, Gutscheine, Warteliste |
| `services/orders` | 8001 | Bestellungen, Küche, Rechnungen, SumUp-Zahlung, WebSocket |
| `services/ai` | 8002 | Sitzplatz-Optimierung, Peak-Prediction, Menüempfehlungen |
| `services/notifications` | 8003 | Email (SMTP/Resend), SMS, WhatsApp (Twilio), Celery Worker |

### Lokales Setup

```bash
cd backend

# Virtuelle Umgebung
python -m venv venv
source venv/bin/activate  # macOS/Linux
# venv\Scripts\activate   # Windows

# Dependencies
pip install -r requirements.txt

# Umgebungsvariablen
cp services/core/.env.example services/core/.env
cp services/orders/.env.example services/orders/.env
```

**Wichtige .env-Variablen (beide Services):**

```bash
ENV=development
DATABASE_URL=postgresql+asyncpg://gastropilot_app:gastropilot_app_password@localhost:5432/gastropilot
DATABASE_ADMIN_URL=postgresql+asyncpg://gastropilot_admin:gastropilot_admin_password@localhost:5432/gastropilot
JWT_SECRET=<gleicher Wert in core und orders>
CORS_ORIGINS=http://localhost:3000,http://localhost:3001
REDIS_URL=redis://localhost:6379/0
```

**Startvarianten:**

```bash
# A) Nur Core (für Auth/Tenant/Reservierungen)
cd services/core && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# B) Core + Orders (zwei Terminals)
cd services/core && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
cd services/orders && uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

# C) Empfohlen: Alles via Docker Compose
docker compose -f dev/docker-compose.yml up -d
```

### Entwicklungs-Workflow

1. **Branch erstellen** im Backend-Repo
2. **Entwickeln** — bei Docker Compose werden Sourcen per Volume gemountet (Hot-Reload)
3. **Qualität prüfen** vor dem Commit:
   ```bash
   ruff check services/ packages/
   black --check services/ packages/
   isort --check-only services/ packages/
   ```
4. **Automatisch formatieren:**
   ```bash
   black services/ packages/
   isort services/ packages/
   ```
5. **Tests ausführen** (siehe Testing)
6. **Committen & pushen**, PR erstellen
7. **Review** durch den anderen Entwickler (1 Approval)
8. **Merge** in `main`

### Datenbank-Migrationen

Alembic-Migrationen liegen nur im `services/core`-Verzeichnis:

```bash
# Migration erstellen
cd services/core && alembic revision --autogenerate -m "add xyz column"

# Migration ausführen (lokal)
cd services/core && alembic upgrade head

# Migration ausführen (Docker)
docker compose -f dev/docker-compose.yml exec core alembic upgrade head
```

**Wichtig:** PostgreSQL Row-Level Security (RLS) isoliert Mandanten auf DB-Ebene. Jede Tabelle mit `tenant_id` hat RLS-Policies. Bei neuen Tabellen müssen entsprechende Policies in `infra/sql/rls.sql` ergänzt werden.

### Testing

```bash
cd backend

# Alle Tests
pytest

# Mit Coverage-Report
pytest --cov=app --cov-report=html

# Einzelne Datei
pytest tests/test_orders.py -v

# Nur schnelle Tests
pytest -m "not slow"

# Nur Integration-Tests
pytest -m "integration"
```

**Konfiguration (pytest.ini):**
- Mindest-Coverage: 35%
- Async-Modus: auto
- Reports: Terminal, HTML, XML, JSON
- Marker: `slow`, `integration`

### Submodule CI/CD

```
Push auf main → GitHub Actions → Lint & Build → Docker Build & Push (:test Tag)
```

---

## Arbeitsbereich: Mobile Apps

**Submodules:** `app` (Gäste-App), `restaurant-app` (Staff-App)

### Tech-Stack

| Komponente | Technologie |
|------------|-------------|
| Framework | Expo 54+, React Native 0.81+ |
| Navigation | Expo Router 6 |
| State | Zustand |
| Data Fetching | TanStack React Query |
| Auth | PIN-Login, NFC-Login (restaurant-app) |
| Benachrichtigungen | Expo Notifications |
| Build & Deploy | EAS Build, EAS Update |

### Lokales Setup

```bash
cd restaurant-app  # oder app

# Dependencies
npm install

# Umgebungsvariablen
cp env.example .env
```

**Wichtige .env-Variablen:**

```bash
EXPO_PUBLIC_API_URL=http://localhost:8000/v1
```

```bash
# Expo starten
npx expo start
```

**Hinweise:**
- Beim ersten Start fragt die App nach dem Restaurant-Kürzel (`tenant_slug`)
- NFC-Login erfordert ein echtes Gerät (nicht in Expo Go oder Web verfügbar)
- Für iOS-Simulator: `npx expo start --ios`
- Für Android-Emulator: `npx expo start --android`

### Entwicklungs-Workflow

1. **Branch erstellen** im Submodule-Repo
2. **Entwickeln** mit `npx expo start`
3. **Qualität prüfen:**
   ```bash
   npm run lint
   npm run typecheck  # nur app/
   ```
4. **Committen & pushen**, PR erstellen
5. **Review** durch den anderen Entwickler (1 Approval)
6. **Merge** in `main`

### Testing

Aktuell sind noch keine automatisierten Tests in den mobilen Apps eingerichtet. Qualitätssicherung erfolgt über:

- `npm run lint` — ESLint
- `npm run typecheck` — TypeScript (app/)
- Manuelles Testen auf Gerät/Simulator

### Deployment (EAS)

Die Apps werden manuell über das `eas-deploy.sh` Script deployed:

```bash
# Restaurant-App deployen (intern/TestFlight)
./scripts/eas-deploy.sh restaurant-app

# Gäste-App deployen
./scripts/eas-deploy.sh app

# Mit Optionen
./scripts/eas-deploy.sh restaurant-app --platform all --channel production
./scripts/eas-deploy.sh app --platform ios --channel internal
./scripts/eas-deploy.sh app --skip-check  # Fingerprint-Check überspringen
```

**Das Script erkennt automatisch**, ob ein voller Build nötig ist oder ein OTA-Update reicht:

1. Berechnet den nativen Fingerprint (`@expo/fingerprint`)
2. Vergleicht mit dem letzten Build-Fingerprint (`.last-build-fingerprint`)
3. **Fingerprint gleich** → EAS Update (OTA, schnell, kein Store-Review)
4. **Fingerprint unterschiedlich** → EAS Build + Submit (neuer nativer Build)

**EAS-Profile:**

| Profil | Zweck | Distribution |
|--------|-------|-------------|
| `development` | Lokale Entwicklung | Simulator/Dev-Client |
| `internal` | Internes Testing | TestFlight / Internal |
| `production` | App Store Release | App Store / Google Play |

**Kein CI/CD** für die Apps — Deployment erfolgt manuell vom Entwickler-Rechner.

---

## Bereichsübergreifende Entwicklung

Viele Features erfordern Änderungen in mehreren Arbeitsbereichen gleichzeitig (z.B. ein neuer API-Endpunkt + Frontend-Anbindung + App-Integration).

### Workflow: Feature über mehrere Bereiche

**Beispiel:** Neues Feature "Gäste-Feedback" erfordert Backend-API + Dashboard-UI + Gäste-App-Screen.

```
1. Issue erstellen im Hauptrepo, Milestone zuweisen

2. Backend zuerst (API bereitstellen)
   cd backend
   git checkout -b feature/guest-feedback
   # API-Endpunkte implementieren, Tests schreiben
   # PR erstellen → Review → Merge

3. Frontends parallel (sobald API steht)
   cd dashboard
   git checkout -b feature/guest-feedback
   # Dashboard-Ansicht implementieren
   # PR erstellen → Review → Merge

   cd app
   git checkout -b feature/guest-feedback
   # App-Screen implementieren
   # PR erstellen → Review → Merge

4. Hauptrepo aktualisieren
   git submodule update --remote backend dashboard app
   git add backend dashboard app
   git commit -m "chore: update submodules for guest-feedback feature"
   git push
```

### Reihenfolge bei Änderungen

| Szenario | Reihenfolge |
|----------|------------|
| Neuer API-Endpunkt + UI | Backend → Frontend(s) |
| Neues DB-Feld + API + UI | Migration → Backend → Frontend(s) |
| Nur Frontend-Änderung | Frontend direkt (kein Backend nötig) |
| Nur Backend-Änderung (ohne API-Änderung) | Backend direkt |
| Schema-Änderung (Enums, Events) | `packages/shared/` → Services → Frontend(s) |
| Neues Event (Redis Pub/Sub) | `packages/shared/events.py` → Publisher-Service → Subscriber-Service → UI |

### API-Routing beachten

Beim Entwickeln neuer Endpunkte muss das nginx-Routing stimmen:

```
/api/v1/                    → core:8000       (Default)
/api/v1/orders/*            → orders:8001
/api/v1/kitchen/*           → orders:8001
/api/v1/invoices/*          → orders:8001
/api/v1/ai/*                → ai:8002
/api/v1/notifications/*     → notifications:8003
/webhooks/sumup             → orders:8001
/webhooks/whatsapp          → notifications:8003
/ws/*                       → orders:8001     (WebSocket)
```

Falls ein neuer Service oder ein neuer Routing-Pfad nötig ist, muss `dev/nginx/conf.d/gastropilot.conf` angepasst werden.

### Multi-Tenancy beachten

- Jeder Request trägt `tenant_id` aus dem JWT
- `TenantMiddleware` setzt `request.state.tenant_id`
- PostgreSQL RLS erzwingt DB-Isolation
- Neue Tabellen brauchen `tenant_id`-Spalte + RLS-Policy
- Platform-Admins (`is_admin=True`) nutzen `session_factory_admin`

### Lokale Entwicklung bereichsübergreifend

**Empfohlenes Setup:** Docker Compose für Backend + nginx, lokale Dev-Server für Frontends:

```bash
# Terminal 1: Backend-Stack
docker compose -f dev/docker-compose.yml up -d postgres redis core orders nginx minio

# Terminal 2: Frontend (das du gerade entwickelst)
cd dashboard && npm run dev

# Terminal 3: Ggf. zweites Frontend
cd web && npm run dev

# Terminal 4: Ggf. Mobile App
cd restaurant-app && npx expo start
```

So kannst du Frontend-Code mit Hot-Reload entwickeln, während die API über nginx läuft.

---

## Deployment

### Umgebungen

| Umgebung | URL | Server | Trigger |
|----------|-----|--------|---------|
| Development | localhost | Lokal | `docker compose up` |
| Test | test.gpilot.app | APP-02 (10.0.3.1) | Submodule CI (auto) oder Deploy-Workflow |
| Staging | staging.gpilot.app | APP-02 (10.0.3.1) | Deploy-Workflow (manuell) |
| Demo | demo.gpilot.app | APP-02 (10.0.3.1) | Deploy-Workflow (manuell) |
| Production | gpilot.app | APP-01 (10.0.1.1) | Release-Workflow (manuell) |

### Server-Architektur

```
APP-01 (10.0.1.1)  — Production
  /opt/production/

APP-02 (10.0.3.1)  — Non-Production
  /opt/test/
  /opt/staging/
  /opt/demo/

DB-01  (10.0.2.1)  — PostgreSQL Primary + Redis
DB-02  (10.0.2.2)  — PostgreSQL Replica
INFRA  (10.0.0.2)  — WireGuard, CoreDNS, Monitoring
```

### Deploy-Workflow: Web-Frontend & Backend

#### Automatisch (Submodule CI)

Bei jedem Push auf `main` in einem Submodule (ausser app und restaurant-app):

```
Push auf main → ci-cd.yml → Lint & Build → Docker Image :test → Server Pull
```

#### Manuell (Deploy-Workflow)

Über **GitHub Actions > Deploy > Run workflow**:

| Parameter | Optionen | Beschreibung |
|-----------|----------|-------------|
| Environment | `test`, `staging`, `demo`, `all` | Ziel-Umgebung |
| Services | `all`, `frontend`, `backend`, einzelner Service | Was deployen |
| Ref | Branch/Tag | Code-Basis (default: `main`) |
| Version Bump | `auto`, `patch`, `minor`, `major` | RC-Version berechnen |

**Beispiele:**

```
Dashboard auf Test:     Environment=test, Services=dashboard, Bump=auto
                        → v0.14.3-rc.1-dashboard

Alles auf Staging:      Environment=staging, Services=all, Bump=auto
                        → v0.14.3-rc.2 (alle 8 Services gebaut)

Backend auf Demo:       Environment=demo, Services=backend, Bump=auto
                        → v0.14.3-rc.3
```

#### Release-Workflow (Production)

Über **GitHub Actions > Release > Run workflow**:

| Release-Typ | Beschreibung |
|-------------|-------------|
| `promote` | Aktuelle RC zur Production machen (z.B. `0.14.3-rc.4` → `0.14.3`) |
| `patch` | Hotfix-Release ohne RC-Zyklus |
| `minor` | Minor-Release ohne RC-Zyklus |
| `major` | Major-Release ohne RC-Zyklus |

Optional: "Deploy to production" aktivieren, um direkt auszurollen.

### Deploy-Workflow: Mobile Apps

Die mobilen Apps werden **manuell** über das EAS-Script deployed:

```bash
# Internes Testing (TestFlight)
./scripts/eas-deploy.sh restaurant-app --channel internal
./scripts/eas-deploy.sh app --channel internal

# Production (App Store)
./scripts/eas-deploy.sh restaurant-app --channel production --platform all
./scripts/eas-deploy.sh app --channel production --platform all
```

Kein CI/CD — der zuständige Entwickler führt das Script lokal aus.

### Docker Image Tags

| Umgebung | Tag | Erstellt durch |
|----------|-----|---------------|
| Test | `:test` | Submodule CI oder Deploy-Workflow |
| Staging | `:staging` | Deploy-Workflow |
| Demo | `:demo` | Deploy-Workflow |
| Production | `:v{version}`, `:latest`, `:production` | Release-Workflow |

Images werden auf DockerHub gepusht: `servecta/gastropilot-{service}`.

### Manuelles Server-Deployment

```bash
# SSH (via WireGuard + INFRA Jump-Host)
ssh app-02    # Test/Staging/Demo
ssh app-01    # Production

# Zum Environment wechseln
cd /opt/test  # oder /opt/staging, /opt/demo, /opt/production

# Update (Pull + Migration + Restart)
./update.sh

# Oder manuell
docker compose pull
docker compose up -d
docker compose exec core alembic -c alembic.ini upgrade head
```

**Hilfs-Skripte (pro Environment):**

| Skript | Funktion |
|--------|----------|
| `./update.sh` | Images pullen, DB-Migration, Container neustarten |
| `./maintenance.sh on\|off` | Wartungsmodus ein-/ausschalten |
| `./coming-soon.sh on\|off` | Coming-Soon-Seite ein-/ausschalten |

---

## Versionierung & Releases

### Versionsmodell

GastroPilot nutzt **Semantic Versioning** mit **Release Candidates**:

```
v{MAJOR}.{MINOR}.{PATCH}[-rc.{N}[-{service}]]
```

| Beispiel | Bedeutung |
|----------|-----------|
| `v0.14.3` | Stabile Production-Version |
| `v0.14.3-rc.2` | Plattform-RC (alle Services) |
| `v0.14.3-rc.1-dashboard` | Service-RC (nur Dashboard) |
| `v0.15.0-rc.1` | Erster RC für nächstes Minor-Release |

### VERSION-Datei

Die `VERSION`-Datei im Root enthält die aktuelle Plattform-Version:
- Während RC-Zyklus: `0.15.0-rc.4`
- Nach Release: `0.15.0`

Wird automatisch durch die Workflows aktualisiert.

### Typischer Release-Zyklus

```
Tag        Aktion                              VERSION            Git-Tag
---------- ----------------------------------- ------------------ ----------------------
Mo 06.04   Dashboard-Fix → Deploy auf Test     (unv.)             v0.14.3-rc.1-dashboard
Di 07.04   Core-Bugfix → Deploy auf Test       (unv.)             v0.14.3-rc.1-core
Mi 08.04   Alles auf Staging deployen          0.14.3-rc.1        v0.14.3-rc.1
Do 09.04   Noch ein Fix → Staging              0.14.3-rc.2        v0.14.3-rc.2
Fr 10.04   Promote → Production                0.14.3             v0.14.3
Mo 13.04   Neues Feature → Deploy auf Test     (unv.)             v0.14.4-rc.1-web
```

**Ablauf:**
1. **Einzelne Services testen** — Deploy-Workflow mit einzelnem Service auf `test` (Service-RC, VERSION-Datei bleibt unverändert)
2. **Plattform auf Staging** — Deploy-Workflow mit `all` auf `staging` (Plattform-RC, VERSION wird aktualisiert)
3. **Auf Staging testen** — Manuelle QA
4. **Release** — Release-Workflow mit `promote` (RC-Suffix wird entfernt)

### Versions-Skripte

```bash
# Nächste RC berechnen
./scripts/bump-rc.sh                     # 0.14.3-rc.1     (Plattform)
./scripts/bump-rc.sh auto dashboard      # 0.14.3-rc.1-dashboard (Service)
./scripts/bump-rc.sh minor               # 0.15.0-rc.1     (neuer Minor-Zyklus)

# Aktuelle Version abfragen
./scripts/version.sh web production      # v0.14.2  (aus package.json)
./scripts/version.sh core test           # v0.14.3-rc.2 (aus VERSION)
```

### Versionsanzeige im Frontend

Alle Web-Frontends zeigen die Version im Footer:

```
Test:       v0.14.3-rc.2-test (20260405-143025)
Staging:    v0.14.3-rc.3-staging (20260409-091500)
Production: v0.14.3-prod (20260410-120000)
```

Build-Variablen `NEXT_PUBLIC_APP_VERSION` und `NEXT_PUBLIC_BUILD_DATE` werden im CI gesetzt.

### Mobile App Versionierung

Die mobilen Apps haben eigene Versionierung über EAS:
- `appVersionSource: remote` — EAS verwaltet Build-Nummern
- `autoIncrement: true` — Build-Nummer wird automatisch hochgezählt
- Version in `app.json` bzw. `app.config.js` gepflegt

### Milestones

Wir nutzen **GitHub Milestones** zur Release-Planung:

1. **Milestone erstellen** mit Versionsname (z.B. `v0.15.0`) und optionalem Datum
2. **Issues zuweisen** mit Priority-Labels (`priority:high`, `priority:medium`, `priority:low`)
3. **Fortschritt verfolgen** über GitHub Milestone-Ansicht
4. **Release auslösen** wenn alle Issues geschlossen sind

```bash
# Issue mit Milestone erstellen
gh issue create --title "feat: Gäste-Feedback" --milestone "v0.15.0"

# PR mit Milestone verknüpfen
gh pr create --title "feat(dashboard): feedback-ansicht" --milestone "v0.15.0"
```

---

## Hilfreiche Befehle

### Docker Compose

```bash
docker compose -f dev/docker-compose.yml up -d              # Alles starten
docker compose -f dev/docker-compose.yml up -d postgres redis core orders nginx  # Minimal-Backend
docker compose -f dev/docker-compose.yml logs -f core        # Logs folgen
docker compose -f dev/docker-compose.yml down                # Stoppen
docker compose -f dev/docker-compose.yml down -v             # Stoppen + DB zurücksetzen
docker compose -f dev/docker-compose.yml restart core        # Service neustarten
```

### Datenbank

```bash
# Migration ausführen
docker compose -f dev/docker-compose.yml exec core alembic upgrade head

# Migration erstellen
cd backend/services/core && alembic revision --autogenerate -m "beschreibung"

# PostgreSQL CLI
docker compose -f dev/docker-compose.yml exec postgres psql -U gastropilot -d gastropilot
```

### Git Submodules

```bash
git submodule update --init --recursive     # Initialisieren
git submodule update --remote --merge       # Alle aktualisieren
git submodule update --remote backend       # Einzelnes aktualisieren
```

---

## Troubleshooting

### Submodule zeigt falschen Commit

```bash
# Submodule auf den im Hauptrepo referenzierten Commit zurücksetzen
git submodule update --init

# Oder komplett neu initialisieren
git submodule deinit -f .
git submodule update --init --recursive
```

### Docker: Service startet nicht

```bash
# Logs prüfen
docker compose -f dev/docker-compose.yml logs core

# Komplett neu bauen
docker compose -f dev/docker-compose.yml down -v
docker compose -f dev/docker-compose.yml build --no-cache
docker compose -f dev/docker-compose.yml up -d
```

### Port bereits belegt

```bash
lsof -i :8000
kill -9 <PID>
```

### Datenbank zurücksetzen

```bash
docker compose -f dev/docker-compose.yml down -v
docker compose -f dev/docker-compose.yml up -d
# Warten bis postgres hochgefahren ist, dann:
docker compose -f dev/docker-compose.yml exec core alembic upgrade head
```

### Frontend: API nicht erreichbar

- Prüfen ob nginx läuft: `docker compose -f dev/docker-compose.yml ps nginx`
- Prüfen ob `NEXT_PUBLIC_API_BASE_URL=http://localhost:80` in `.env.local` gesetzt ist
- Browser-Console auf CORS-Fehler prüfen

---

*Letzte Aktualisierung: April 2026*
