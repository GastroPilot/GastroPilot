# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GastroPilot is a restaurant management SaaS platform. This is a **monorepo using Git submodules** — each major component is a separate repository. The project language is German (docs, commit messages, UI), but code identifiers are in English.

## Repository Structure

| Submodule | Tech | Port | Purpose |
|-----------|------|------|---------|
| `backend/` | FastAPI, Python 3.11, SQLAlchemy 2.0 async | 8000-8003 | Microservices (core, orders, ai, notifications) |
| `web/` | Next.js 16, React 19, Tailwind 4 | 3000 | Public website + guest portal |
| `dashboard/` | Next.js 16, React 19, Tailwind 4 | 3001 | Restaurant management dashboard |
| `kds/` | Next.js 16, React 19, Tailwind 4 | 3004 | Kitchen Display System |
| `table-order/` | Next.js 16, React 19, Tailwind 4 | 3003 | QR-based table ordering PWA |
| `restaurant-app/` | Expo, React Native | — | Restaurant staff mobile app |
| `app/` | Expo, React Native | — | Guest mobile app |

Supporting directories: `dev/` (docker-compose, nginx, .env), `install/` (production setup), `scripts/` (version tooling).

## Common Commands

### Full dev environment (recommended)
```bash
docker compose -f dev/docker-compose.yml up -d          # all services
docker compose -f dev/docker-compose.yml up -d postgres redis core orders nginx  # minimal backend
docker compose -f dev/docker-compose.yml logs -f core    # follow logs
docker compose -f dev/docker-compose.yml down            # stop
docker compose -f dev/docker-compose.yml down -v         # stop + reset DB
```

### Backend (in backend/)
```bash
# Lint (CI checks)
ruff check services/ packages/
black --check services/ packages/
isort --check-only services/ packages/

# Format
black services/ packages/
isort services/ packages/

# Tests
pytest                              # full suite (min 35% coverage)
pytest tests/test_orders.py         # single file
pytest -m "not slow"                # skip slow
pytest -m "integration"             # integration only

# Run single service locally
cd services/core && uvicorn app.main:app --reload --port 8000
cd services/orders && uvicorn app.main:app --reload --port 8001

# Database migrations (core service only)
cd services/core && alembic upgrade head
cd services/core && alembic revision --autogenerate -m "description"
# Via docker:
docker compose -f dev/docker-compose.yml exec core alembic upgrade head
```

### Frontend (in web/, dashboard/, kds/, table-order/)
```bash
npm install
npm run dev
npm run lint
npm run format:check
npm run format:write
npm run type-check
npm run test              # Vitest
npm run test:e2e          # Playwright
```

### Mobile (in restaurant-app/ or app/)
```bash
npm install
npx expo start
```

### Git submodules
```bash
git submodule update --init --recursive           # init after clone
git submodule update --remote --merge             # pull latest all
git submodule update --remote backend             # pull latest one
```

## Architecture

### Backend Microservices

| Service | Port | Scope |
|---------|------|-------|
| `services/core` | 8000 | Auth, users, restaurants, reservations, menus, tables, vouchers, waitlist |
| `services/orders` | 8001 | Orders, kitchen, invoices, SumUp payments, WebSocket |
| `services/ai` | 8002 | Seating solver, peak prediction, menu recommendations |
| `services/notifications` | 8003 | Email (SMTP/Resend), SMS, WhatsApp (Twilio), Celery worker |

Shared code in `packages/shared/`: `auth.py` (JWT), `tenant.py` (multi-tenancy middleware + RLS), `events.py` (Redis Pub/Sub), `schemas.py` (enums).

### Multi-Tenancy

Every request carries `tenant_id` from JWT. `TenantMiddleware` sets `request.state.tenant_id`. PostgreSQL Row-Level Security enforces DB-level isolation via `set_tenant_context()`. Platform admins (`is_admin=True`) use a separate `session_factory_admin` with elevated privileges.

### Database

- Two engines per service: `_engine_app` (normal) and `_engine_admin` (platform admin)
- UUID primary keys, `tenant_id` on all tenant-scoped tables
- `_strip_sslmode()` removes sslmode from URL for asyncpg compatibility
- Alembic migrations only in `services/core`

### Event System

Redis Pub/Sub on channels `gastropilot:{tenant_id}:{event_name}`. Events defined in `packages/shared/events.py`.

### Nginx API Routing

```
/api/v1/              → core:8000       (default)
/api/v1/orders/       → orders:8001
/api/v1/kitchen/      → orders:8001
/api/v1/ai/           → ai:8002
/webhooks/whatsapp    → notifications:8003
/webhooks/sumup       → orders:8001
/ws/                  → orders:8001     (WebSocket)
```

All routes registered under both `/api/v1` and `/v1` prefixes. Public endpoints (`/public/*`) and webhooks (`/webhook_*`) have no auth.

### Frontend Stack (all Next.js apps)

- Next.js 16+ App Router, React 19, TypeScript 5
- Tailwind CSS 4, shadcn/ui components
- Zustand for state, TanStack React Query v5 for data fetching
- date-fns for dates, lucide-react for icons

## Code Style

### Backend
- Line length: 100 chars
- Ruff rules: E, F, W, UP
- isort profile: black
- SQLAlchemy models use `Mapped[]` with `mapped_column()`

### Commits
Conventional Commits: `feat(scope):`, `fix(scope):`, `docs:`, `refactor:`, `chore:`, `test:`, `style:`

### Branches
`main` (production), `feature/*`, `fix/*`, `chore/*`

## Docker Images

Built as `servecta/gastropilot-{core,orders,ai,notifications}`. Tags: `:test` (auto on push to main), `:staging`, `:demo` (manual deploy), `:v{version}`, `:latest`, `:production` (release workflow).

## Environment Setup

- Copy `dev/.env.example` → `dev/.env` for docker-compose
- Per-service `.env.example` files exist in each submodule
- Frontend apps use `NEXT_PUBLIC_API_BASE_URL=http://localhost:80` with nginx gateway
- Backend services need matching `JWT_SECRET` across core and orders
