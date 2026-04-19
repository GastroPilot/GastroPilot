# CLAUDE.md

Leitfaden für Claude Code beim Arbeiten am GastroPilot-Monorepo.

## Starte hier — nur ein Command zu merken

**`/weiter` ist der einzige Command, den der User aktiv aufruft.**

Alles andere chained Claude automatisch. `/weiter` erkennt anhand des Arguments, was getan werden soll, und ruft intern die passenden Follow-up-Commands via `Skill`-Tool auf.

### Was `/weiter` versteht

| Eingabe | Was passiert |
|---------|--------------|
| `/weiter` | Lagebericht + Top-3-Vorschläge (fortsetzen / neues Issue / neue Version) |
| `/weiter 31` | Deep-Analyse von Issue #31 → nach Bestätigung → Implementierung |
| `/weiter v0.26.0` | Neue Version v0.26.0 planen → Milestone anlegen → ggf. Issues dazu |
| `/weiter v0.20.0` (existierender Milestone) | Issues dieses Milestones anzeigen → User wählt → weiter |
| `/weiter backend` | Offene Issues im Backend zeigen → User wählt → weiter |
| `/weiter Reviews mit Videos` | Feature-Idee erkennen → Issue-Draft anlegen |
| `/weiter plane v0.26.0` | Explizite Versions-Planung |

### Flow unter der Haube

**Planen:**
```
/weiter v0.26.0
  → /milestone-new v0.26.0         (auto)
  → /issue-new … (mehrfach)        (auto, pro Feature)
  → Milestone-Übersicht am Ende
```

**Entwickeln:**
```
/weiter 31
  → /issue-plan 31                 (auto, via issue-analyst)
  → Plan bestätigen lassen
  → /issue-start 31                (auto nach Bestätigung)
  → Subagent implementiert         (backend-specialist / frontend-web / mobile)
  → /preflight                     (auto nach letztem Kriterium)
  → commit-push-pr                 (einmalige User-Bestätigung vor PR)
```

### Wann Claude **nicht** auto-chained

Immer **explizite User-Bestätigung** bevor:
- `gh issue create` / `gh issue edit --milestone`
- `git commit`, `git push`
- `gh pr create`
- Destruktive Git-Operationen
- `docker compose down -v`, Migration-Rollbacks

Alles andere (Analyse, Lint, Tests, Draft-Erstellung) darf Claude selbstständig chainen.

## Projekt-Überblick

GastroPilot ist eine SaaS-Plattform für Gastronomie-Management. **Monorepo mit Git-Submodulen** — jede Hauptkomponente ist ein eigenes Repository. Projekt-Sprache Deutsch (Docs, Commits, UI); Code-Identifier auf Englisch.

## Repository-Struktur

| Submodul | Tech | Port | Zweck |
|----------|------|------|-------|
| `backend/` | FastAPI, Python 3.11, SQLAlchemy 2.0 async | 8000-8003 | Microservices (core, orders, ai, notifications) |
| `web/` | Next.js 16, React 19, Tailwind 4 | 3000 | Public Website + Gast-Portal |
| `dashboard/` | Next.js 16, React 19, Tailwind 4 | 3001 | Restaurant-Management-Dashboard |
| `kds/` | Next.js 16, React 19, Tailwind 4 | 3004 | Kitchen Display System |
| `table-order/` | Next.js 16, React 19, Tailwind 4 | 3003 | QR-basierte Tisch-Bestellung (PWA) |
| `restaurant-app/` | Expo, React Native | — | Personal-App (Mobile) |
| `app/` | Expo, React Native | — | Gäste-App (Mobile) |

Zusatzordner: `dev/` (docker-compose, nginx, .env), `install/` (Prod-Setup), `scripts/` (Versionstools).

## Entwicklungs-Workflow

### Slash-Commands (in `.claude/commands/`)

**Einziger Einstieg:** `/weiter [arg]` — Claude erkennt Intent und invoked die folgenden intern.

| Command (intern) | Zweck |
|------------------|-------|
| `/weiter [arg]` | Einziger User-facing Entry. Router für alle anderen. |
| `/issue-new [beschreibung]` | Neues Issue anlegen. Immer mit Draft-Review. |
| `/milestone-new <version>` | Neue Version / Milestone anlegen. |
| `/issue-plan <num>` | Deep-Analyse durch `issue-analyst`. |
| `/issue-start <num>` | Branch + Tasks + Subagent-Aufteilung. |
| `/preflight` | Pre-PR-Check in allen geänderten Submodulen. |
| `/sync-subs [submodul]` | Submodule-Sync. |

Der User **muss** nur `/weiter` kennen. Alle anderen Commands sind intern verfügbar und werden von Claude per `Skill`-Tool gechained.

Zusätzliche nützliche Plugin-Skills: `/commit`, `/commit-push-pr`, `/code-review`, `/security-review`.

### Subagents (in `.claude/agents/`)

Delegiere gezielt — nicht alles selber machen.

| Agent | Wann nutzen |
|-------|-------------|
| `backend-specialist` | Arbeit in `backend/` — Modelle, Migrationen, Endpoints, Events, Multi-Tenancy |
| `frontend-web-specialist` | Arbeit in Next.js-Apps (`web`, `dashboard`, `kds`, `table-order`) |
| `mobile-specialist` | Arbeit in Expo-Apps (`app`, `restaurant-app`) |
| `issue-analyst` | Deep-Analyse eines GitHub-Issues (automatisch von `/issue-plan`) |
| `gastropilot-reviewer` | Projekt-spezifischer Code-Review vor PR-Merge |

Jeder Subagent hat ein hartes Rule-Set im Frontmatter. Lies die Agent-Datei, wenn du verstehen willst, was der Agent tun wird.

### Issue-basiertes Arbeiten (Prinzip)

1. **Jede Arbeit hat ein Issue.** Ausnahme: triviale Typos, aber selbst dann klug ein Issue anzulegen.
2. **Akzeptanzkriterien sind Tasks.** Was im Issue als `- [ ]` steht, wird zum lokalen Task.
3. **Multi-Component-Issues:** Der Body hat eine "Betroffene Komponenten"-Sektion. Backend-First-Items blockieren Frontend-Items.
4. **Branches:** `feat/<issue-num>-<kebab-slug>` / `fix/<issue-num>-<slug>` / `chore/<issue-num>-<slug>`.
5. **Commit-Messages:** Conventional Commits (`feat(scope):`, `fix(scope):`, `chore:`, `docs:`, `refactor:`, `test:`, `style:`).
6. **PR-Body referenziert das Issue** (`Closes #<num>`) und listet die erledigten Akzeptanzkriterien.

## Architektur-Essentials

### Backend-Microservices

| Service | Port | Scope |
|---------|------|-------|
| `services/core` | 8000 | Auth, Users, Restaurants, Reservierungen, Menüs, Tische, Gutscheine, Waitlist, Reviews |
| `services/orders` | 8001 | Orders, Küche, Rechnungen, SumUp, WebSocket |
| `services/ai` | 8002 | Seating-Solver, Peak-Prediction, Empfehlungen |
| `services/notifications` | 8003 | Email (SMTP/Resend), SMS, WhatsApp (Twilio), Celery |

Shared Code in `packages/shared/`:
- `auth.py` — JWT-Handling
- `tenant.py` — Multi-Tenancy-Middleware + RLS-Helper
- `events.py` — Redis-Pub/Sub-Event-Registry
- `schemas.py` — geteilte Enums

### Multi-Tenancy (kritisch)

- Jede Request trägt `tenant_id` im JWT. `TenantMiddleware` schreibt in `request.state.tenant_id`.
- PostgreSQL Row-Level Security erzwingt DB-seitige Isolation via `set_tenant_context()`.
- Plattform-Admins (`is_admin=True`) nutzen `session_factory_admin` mit erhöhten Rechten.
- **Jede neue tenant-scoped Tabelle braucht eine RLS-Policy** (nicht vergessen in Alembic-Migration!).

### Datenbank

- Zwei Engines pro Service: `_engine_app` (normal) und `_engine_admin` (Plattform-Admin).
- UUID-Primary-Keys. `tenant_id` auf allen tenant-scoped Tabellen.
- `_strip_sslmode()` entfernt den `sslmode`-Query-Param (asyncpg-Kompatibilität).
- **Alembic-Migrationen ausschließlich in `services/core`.**

### Events

Redis-Pub/Sub auf Channels `gastropilot:{tenant_id}:{event_name}`. Neue Event-Namen zuerst in `packages/shared/events.py` registrieren — keine Hardcoded Strings.

### Nginx-API-Routing

```
/api/v1/              → core:8000        (Default)
/api/v1/orders/       → orders:8001
/api/v1/kitchen/      → orders:8001
/api/v1/ai/           → ai:8002
/webhooks/whatsapp    → notifications:8003
/webhooks/sumup       → orders:8001
/ws/                  → orders:8001      (WebSocket)
```

Alle Routen unter `/api/v1` UND `/v1` registrieren. Public-Endpoints (`/public/*`) und Webhooks (`/webhook_*`) haben keinen Auth.

### Frontend-Stack (alle Next.js-Apps)

- Next.js 16+ App Router, React 19, TypeScript 5
- Tailwind CSS 4, shadcn/ui
- Zustand (Client-State), TanStack React Query v5 (Server-State)
- date-fns, lucide-react

### Mobile-Stack (beide Expo-Apps)

- Expo Router 6, React Native 0.81, React 19
- TanStack React Query 5 + MMKV-Persist (Offline)
- Reanimated 4.1 (Animationen + Shared Transitions)
- FlashList, BottomSheet, expo-notifications, Sentry
- expo-local-authentication + expo-secure-store (Biometric-Lock)

## Häufige Kommandos

### Dev-Environment

```bash
docker compose -f dev/docker-compose.yml up -d                              # alle Services
docker compose -f dev/docker-compose.yml up -d postgres redis core orders nginx  # minimal Backend
docker compose -f dev/docker-compose.yml logs -f core
docker compose -f dev/docker-compose.yml down
docker compose -f dev/docker-compose.yml down -v                            # + DB-Reset
```

### Backend (in `backend/`)

```bash
# Lint (CI)
ruff check services/ packages/
black --check services/ packages/
isort --check-only services/ packages/

# Format
black services/ packages/
isort services/ packages/

# Tests
pytest                        # Full suite, min 35% Coverage
pytest tests/test_orders.py   # Einzeldatei
pytest -m "not slow"          # ohne slow
pytest -m "integration"       # nur Integration

# Einzelner Service lokal
cd services/core && uvicorn app.main:app --reload --port 8000
cd services/orders && uvicorn app.main:app --reload --port 8001

# Migrationen (nur in services/core)
cd services/core && alembic upgrade head
cd services/core && alembic revision --autogenerate -m "description"
# In Docker:
docker compose -f dev/docker-compose.yml exec core alembic upgrade head
```

### Frontends (in `web/`, `dashboard/`, `kds/`, `table-order/`)

```bash
npm install
npm run dev
npm run lint
npm run format:check
npm run format:write
npm run type-check
npm run test           # Vitest
npm run test:e2e       # Playwright
```

### Mobile (in `app/` oder `restaurant-app/`)

```bash
npm install
npx expo start
```

### Submodule

```bash
git submodule update --init --recursive            # nach Clone
git submodule update --remote --merge              # alle aktuell ziehen
git submodule update --remote backend              # einzelnes Submodul
# oder einfacher:
/sync-subs [submodul]
```

## Code-Style

**Backend:** Line length 100, Ruff E/F/W/UP, isort profile black, SQLAlchemy `Mapped[]` + `mapped_column()`.

**Frontend:** Prettier + ESLint (pro Submodul, wird von `npm run lint` / `format:check` gefahren).

**Commits:** Conventional Commits (siehe oben). **Niemals** `Co-Authored-By: Claude …` oder "🤖 Generated with Claude Code"-Trailer anhängen — weder in Commit-Messages noch in PR-Bodies. Gilt auch für alle Subagents.

**Branches:** `main` (Production), `feat/*`, `fix/*`, `chore/*`.

## Docker-Images

Images: `servecta/gastropilot-{core,orders,ai,notifications}`. Tags: `:test` (auto bei Push auf main), `:staging`, `:demo` (manueller Deploy), `:v{version}`, `:latest`, `:production` (Release-Workflow).

## Environment

- `dev/.env.example` → `dev/.env` kopieren für docker-compose
- Pro Submodul `.env.example`
- Frontends: `NEXT_PUBLIC_API_BASE_URL=http://localhost:80` (Nginx-Gateway)
- Backend-Services: `JWT_SECRET` muss zwischen `core` und `orders` übereinstimmen

## Hinweise für Claude

- **Immer zuerst Issue prüfen:** Neuer Task? `gh issue view <num>` bevor du etwas baust. Niemals ins Blaue implementieren.
- **Backend-First bei Multi-Component-Issues:** Schema → Migration → API → Frontend. Ohne fertiges Backend gibt es kein Frontend.
- **Subagents delegieren, nicht simulieren.** Wenn du Backend-Arbeit siehst, rufe den `backend-specialist` auf, statt selbst zu coden.
- **Destruktives immer bestätigen lassen.** `docker compose down -v`, `git push --force`, Migration-Rollbacks — nicht ohne explizites Go.
- **Submodule-Grenzen respektieren.** Ein `services/core`-Import aus `services/orders` ist falsch — stattdessen `packages/shared` nutzen.
- **Akzeptanzkriterien vollständig abarbeiten.** PR ist erst mergeable, wenn alle offenen Checkboxen des Issues abgehakt sind (oder explizit als Follow-up herausgelöst).
