# Changelog

## [0.17.0] - 2026-04-17

### Changes
- Update install.sh (11a2acd)
- Update docker-compose.yml (d307e02)
- Update docker-compose.yml (6343899)
- Configure uploads location with Minio fallback (f7faa1d)
- bezahlsystem überarbeitet und belege hinzugefügt (07d1ccc)
## [0.16.0] - 2026-04-14

### Changes
## [0.14.2] - 2026-04-04

### Changes
- fix(ci): Deploy-Matrix baut alle Services statt nur einzelne (b2cfdf7)
- update submodule (80483a9)
- feat: Multi-Environment Deploy-Workflow, Testdaten und Versions-Timestamp (5d0ad3c)


## [0.14.1] - 2026-04-04

### Changes
- update submodule (71ddb8b)
- updated haupt repo (61a00a2)
- updated submodules (b20152e)


## [0.14.0] - 2026-03-18

### Changes
- Update VERSION (ac93784)
- Remove version 0.14.0 entry from CHANGELOG (12128b5)
- chore(release): 0.14.0 (78c17f9)
- Update VERSION (90d2397)
- Update CHANGELOG.md (f457303)
- update submodule (8f6953e)
- chore(release): 0.14.0 (b41b5c2)
- refactor: replace guest-portal with dashboard in workflows and update submodule URLs (ef72d67)
- added dashboard and web insted of frontend and guest portal (37ad54a)


## [0.13.1] - 2026-03-18

### Changes
- updated workflows (07c3c9c)
- version bump (d295041)
- update submodule (dac1311)
- removed upsell & voucher (dd1bffe)
- Docker Dateien aufgeräumt. (e9adef2)
- changed directories (2cd020a)
- changed deploy (eed46a6)
- update app submodule (34d9d5e)
- chore: remove legacy deployment files and unused guest-app submodule (5fb0948)
- updated submodule (5db8318)
- fix sql.init.sql conflicts (839e002)
- fixed nginx startup and alembic migrations (82e67f5)
- init demo and more (b5ed950)
- added jwt variables for orders service (5be2d8e)
- added alembic db update to pipeline (0546fdb)
- feat: add guest-portal, kds, table-order, guest-app as submodules with CI/CD (f31503d)


## [0.13.0] - 2026-03-02

### Changes
- Update submodules (8ef92bc)
- feat: update submodules with email auth and staff-access page (8b42ec0)
- fix: drop tenant_analytics view before migration (f443fa2)
- fix: use DATABASE_ADMIN_URL consistently across all compose files (953bf73)
- fix: DB config naming + remove snowfall animation (4b8723b)


## [0.12.0] - 2026-02-24

### Changes
- feat: microservices and new deployment (36494b3)
- feat: microservices and new deployment (669de9f)
- Update BASE_URL in docker-compose for staging (c578dda)
- Update CORS origins and allowed hosts for staging (fb2d455)
- fix: staging nginx config for single-server setup (c57f257)
- Update Docker Hub organization to use secrets (5bd26a4)
- chore: update gastropilot-backend submodule (98ae92e)
- chore: update gastropilot-backend submodule to include ruff fixes (e005a1b)
- chore: update submodules to latest commits (4878df4)
- fix: added multi-tenancy and more (408b044)
- fix & feat: added dark mode and theme switcher and fixed light theme in table and obstacle card (2e6a7ab)
- feat: new design (a459191)
- fix: added limiter exempt to /v1/health (fea1122)
- fixed maintenance & coming soon (727a00f)
- Delete docker/wait-for-services.sh (e2c3957)
- Update docker-compose.server.yml (ee48b0e)
- fix: added api ssl and nginx conf (7b3272c)
- fix deploy with admin account (7307aeb)
- fix: added redis dependencie (81c2deb)
- fix: added redis dependencie (c6dad7d)
- Update ci-cd.yml (1eacb02)
- Update ci-cd.yml (52f67c6)
- Update ci-cd.yml (8391cb6)
- Update ci-cd.yml (1b84b0e)
- fix: deployment with personal account as docker hub user (bdd9149)
- fix: using now docker hub (aad2f89)
- fix: deployment with org as ghcr user (54ea444)
- updated deployment (77a17c7)


## [0.11.0] - 2026-02-01

### Changes
- added skeleton screen for loading and updated submodules. added dev environment (60d3085)


## [0.10.0] - 2026-01-31

### Changes
- Remove changelog entry for version 0.10.0 (590c241)
- Update VERSION (ff50b8b)
- fix mothership api url (37ef5fe)
- chore(release): 0.10.0 (1410448)
- fix app (4f5ddde)
- fixed api call url (3dc06b2)
- fix several deployment errors (3fdd521)
- update app (d23e9b1)
- fix: deployment (96acb04)
- feature: new submodule (4bae09b)
- docs: add comprehensive developer documentation for GastroPilot project (340c28d)
- fix health check (b521736)


## [0.9.1] - 2026-01-29

### Changes
- added submodule pat token (615082a)
- Update CHANGELOG.md (0f4362b)
- Update VERSION (9229024)
- chore(release): 0.9.1 (289bfb2)
- update release workflow (267667a)
- update release workflow (e552232)
- Update docker-compose and CI/CD configuration for staging deployment (1670be5)
- fixed health endpoints in ci-cd (e0784ba)
- fix(ci): use GHCR_TOKEN for container registry push (fb04d2a)
- added submodule pat token (58c6efa)
- updated submodules & init ci-cd and versioning (c94319c)
- feat: add centralized CI/CD and semantic versioning (a919c1e)
- updated submodule (25e936b)
- Create dependabot.yml (18ef347)
- init submodules (53674f2)
- deleted gitmodules file (fae0e2d)
- Update feature_request.md (469f500)
- Update bug_report.md (ff99d56)
- fixed directory name for issue templates (f500750)
- fixed README AUTHORS link (e3c5b43)
- init git modules and other git files (61596f4)
- Initial commit (96766c7)


The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).