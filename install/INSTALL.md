# GastroPilot — Server-Installation

## Voraussetzungen

- **Linux-Server** (Ubuntu 22.04+ / Debian 12+ empfohlen)
- **Docker** >= 24.0 + **Docker Compose** v2
- **Externe PostgreSQL 16** Datenbank (separater Server, Docker-Container)
- Ports **80** und **443** offen (Shared Proxy)
- DNS-Einträge für alle Subdomains

## Architektur

```
Internet
    │
    ▼
┌─────────────────────────┐
│  Shared Proxy (nginx)   │  ← TLS-Terminierung, Port 80/443
│  /opt/shared-proxy/     │     Wird automatisch installiert
└────────┬────────────────┘
         │ (Docker-Netzwerk: gastropilot-shared-proxy)
         │
┌────────┴────────────────────────────────────────────┐
│  GastroPilot Stack (z.B. /opt/staging/)             │
│                                                      │
│  ┌──────────┐   ┌─────────────────────────────────┐ │
│  │  nginx    │──→│  core (8000)                    │ │
│  │  (intern) │   │  orders (8001)                  │ │
│  │          │──→│  ai (8002)                       │ │
│  │          │   │  notifications (8003)            │ │
│  │          │   │  notifications-worker (Celery)   │ │
│  │          │──→│  web (3000)                      │ │
│  │          │   │  dashboard (3001)                │ │
│  └──────────┘   │  table-order (3003)              │ │
│                  │  kds (3004)                      │ │
│  ┌──────────┐   └─────────────────────────────────┘ │
│  │  Redis   │                                        │
│  └──────────┘                                        │
└──────────────────────────────────────────────────────┘
         │
         │ (Netzwerk / TCP)
         ▼
┌─────────────────────────┐
│  PostgreSQL (extern)     │  ← Separater Server
│  Primary + Replica       │
└─────────────────────────┘
```

## Environments

| Environment | Image-Tag | Log-Level | Token TTL | Bcrypt Rounds | Redis |
|-------------|-----------|-----------|-----------|---------------|-------|
| test        | `test`    | DEBUG     | 60 min    | 10            | 256mb |
| staging     | `staging` | INFO      | 30 min    | 12            | 512mb |
| demo        | `demo`    | DEBUG     | 60 min    | 10            | 256mb |
| production  | `latest`  | WARNING   | 15 min    | 14            | 1024mb |

## Schnellstart

### Variante A: Remote (curl)

```bash
mkdir -p /opt/staging && cd /opt/staging
curl -fsSL http://intranet.corp.servecta.local/install.sh | bash
```

Das Script erkennt automatisch den Pipe-Modus, leitet stdin auf `/dev/tty` um
und lädt SQL-Dateien von `http://intranet.corp.servecta.local/install/sql/` herunter.

### Variante B: Lokal

```bash
# Dateien auf den Server kopieren
scp -r install/* user@server:/opt/staging/

# Auf dem Server ausführen
cd /opt/staging
chmod +x install.sh
./install.sh
```

Das Skript führt interaktiv durch alle Schritte:

1. Voraussetzungen prüfen (Docker, openssl, curl)
2. Shared Proxy installieren (falls nicht vorhanden)
3. Environment wählen (test/staging/demo/production)
4. Domains konfigurieren
5. Externe PostgreSQL konfigurieren (Primary + Replica)
6. SMTP konfigurieren (optional)
7. docker-compose.yml + nginx.conf generieren
8. HTML-Seiten für Maintenance/Coming-Soon erzeugen
9. Hilfs-Skripte erzeugen (update, maintenance, coming-soon)
10. SSL-Zertifikate (Let's Encrypt / selbstsigniert)
11. Shared-Proxy-Configs + Container starten
12. DB-Migration ausführen
13. Platform-Admin erstellen (optional)

## Datenbank-Setup (externer Server)

Die Datenbank läuft auf einem separaten Server. Setup:

```bash
# Auf dem DB-Server
docker run -d \
  --name gastropilot-postgres \
  -e POSTGRES_USER=gastropilot_staging \
  -e POSTGRES_PASSWORD=<sicheres-passwort> \
  -e POSTGRES_DB=gastropilot_staging \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16-alpine

# Schema initialisieren
docker cp init.sql gastropilot-postgres:/tmp/
docker cp rls.sql gastropilot-postgres:/tmp/
docker exec -i gastropilot-postgres psql -U gastropilot_staging -d gastropilot_staging -f /tmp/init.sql
docker exec -i gastropilot-postgres psql -U gastropilot_staging -d gastropilot_staging -f /tmp/rls.sql
```

### Replica einrichten

```bash
# Auf dem Primary: postgresql.conf
wal_level = replica
max_wal_senders = 5
wal_keep_size = 256MB

# Auf dem Primary: pg_hba.conf
host replication replicator <replica-ip>/32 scram-sha-256

# Replica-User anlegen
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '<passwort>';

# Auf dem Replica-Server
docker run -d \
  --name gastropilot-postgres-replica \
  -e POSTGRES_USER=gastropilot_staging \
  -e POSTGRES_PASSWORD=<passwort> \
  -p 5432:5432 \
  -v pgdata_replica:/var/lib/postgresql/data \
  postgres:16-alpine

# Base-Backup vom Primary holen
docker exec gastropilot-postgres-replica bash -c \
  "pg_basebackup -h <primary-ip> -U replicator -D /var/lib/postgresql/data -Fp -Xs -P -R"

# Replica starten (erkennt standby.signal automatisch)
docker restart gastropilot-postgres-replica
```

## Domains & DNS

### Non-Production (Prefix-basiert)

| Subdomain | Ziel |
|-----------|------|
| `{prefix}.gpilot.app` | Webseite + Gästeportal |
| `{prefix}.gastropilot.org` | Webseite + Gästeportal |
| `{prefix}-dashboard.gpilot.app` | Restaurant-Dashboard |
| `{prefix}-api.gpilot.app` | API (Backend) |
| `{prefix}-order.gpilot.app` | Tischbestellung |
| `{prefix}-kds.gpilot.app` | Kitchen Display |

### Production

| Subdomain | Ziel |
|-----------|------|
| `gpilot.app` | Webseite + Gästeportal |
| `gastropilot.org` | Webseite + Gästeportal |
| `dashboard.gpilot.app` | Restaurant-Dashboard |
| `api.gpilot.app` | API (Backend) |
| `order.gpilot.app` | Tischbestellung |
| `kds.gpilot.app` | Kitchen Display |

Alle Domains müssen als A-Record auf die Server-IP zeigen.

## Erzeugte Dateien

| Datei | Beschreibung |
|-------|-------------|
| `.env` | Konfiguration & Secrets |
| `docker-compose.yml` | Service-Definition (ohne lokale DB) |
| `nginx.conf` | Interner API-Gateway mit Maintenance/Coming-Soon |
| `html/maintenance.html` | Wartungsseite |
| `html/coming-soon.html` | Coming-Soon-Seite |
| `update.sh` | Update: Pull + Migration + Restart |
| `maintenance.sh` | Wartungsmodus ein-/ausschalten |
| `coming-soon.sh` | Coming-Soon-Seite ein-/ausschalten |
| `init.sql` | DB-Schema (Referenz) |
| `rls.sql` | Row-Level Security (Referenz) |

## Betrieb

### Update

```bash
./update.sh
```

Pullt neü Images, führt DB-Migration aus und startet Container neu.

### Wartungsmodus

Zeigt eine Wartungsseite für Web-Besucher und gibt `503 MAINTENANCE` für API-Anfragen zurück.
Health-Checks und WebSocket-Verbindungen bleiben erreichbar.

```bash
./maintenance.sh on       # Aktivieren
./maintenance.sh off      # Deaktivieren
./maintenance.sh status   # Status prüfen
```

### Coming-Soon-Seite

Zeigt eine Coming-Soon-Seite. Hat Priorität über den Wartungsmodus.

```bash
./coming-soon.sh on       # Aktivieren
./coming-soon.sh off      # Deaktivieren
./coming-soon.sh status   # Status prüfen
```

### Logs

```bash
docker compose logs -f              # Alle Services
docker compose logs -f core         # Nur Core
docker compose logs -f orders       # Nur Orders
docker compose logs --since 1h      # Letzte Stunde
```

### Status

```bash
docker compose ps                   # Alle Container
docker compose exec core alembic current   # DB-Migrationsstand
```

### Manülles SSL-Zertifikat erneürn

```bash
# Shared Proxy stoppen
docker compose -f /opt/shared-proxy/docker-compose.proxy.yml stop proxy

# Zertifikat erneürn
docker run --rm -p 80:80 \
  -v $(pwd)/certbot:/etc/letsencrypt \
  certbot/certbot renew

# Zertifikate kopieren und Proxy starten
cp certbot/live/<domain>/fullchain.pem /opt/shared-proxy/ssl/<domain>/
cp certbot/live/<domain>/privkey.pem /opt/shared-proxy/ssl/<domain>/
docker compose -f /opt/shared-proxy/docker-compose.proxy.yml up -d
```

## Shared Proxy

Der Shared Proxy (`/opt/shared-proxy/`) wird automatisch installiert falls nicht vorhanden.
Er terminiert TLS und routet anhand des `server_name` an die richtigen Stacks.

Mehrere GastroPilot-Stacks (z.B. staging + demo) teilen sich denselben Proxy.

```
/opt/shared-proxy/
├── nginx.conf                   # Haupt-Config
├── docker-compose.proxy.yml     # Proxy-Container
├── conf.d/                      # Pro-Domain Configs (automatisch generiert)
│   ├── stage.gpilot.app.conf
│   ├── stage-api.gpilot.app.conf
│   └── ...
└── ssl/                         # SSL-Zertifikate pro Domain
    ├── stage.gpilot.app/
    │   ├── fullchain.pem
    │   └── privkey.pem
    └── ...
```

### Proxy manüll neu laden

```bash
docker exec gastropilot-shared-proxy nginx -s reload
```

## Mehrere Environments auf einem Server

```bash
# Staging
mkdir -p /opt/staging && cd /opt/staging && /path/to/install.sh

# Demo
mkdir -p /opt/demo && cd /opt/demo && /path/to/install.sh
```

Jeder Stack bekommt eigene Container-Namen (`gastropilot-staging-*`, `gastropilot-demo-*`)
und teilt sich den Shared Proxy für TLS-Terminierung.

## Troubleshooting

### Container startet nicht

```bash
docker compose logs <service>           # Logs prüfen
docker compose exec <service> sh        # In Container einsteigen
```

### Datenbank nicht erreichbar

```bash
# Verbindung testen
docker run --rm --network host postgres:16-alpine \
  pg_isready -h <db-host> -p 5432 -U <db-user>

# Firewall prüfen
ufw status
```

### Shared Proxy läd Config nicht

```bash
# Config-Syntax prüfen
docker exec gastropilot-shared-proxy nginx -t

# Neu starten
docker compose -f /opt/shared-proxy/docker-compose.proxy.yml restart
```

### Migration schlägt fehl

```bash
# init.sql manüll auf DB-Server ausführen
psql -h <db-host> -U <db-user> -d <db-name> -f init.sql
psql -h <db-host> -U <db-user> -d <db-name> -f rls.sql

# Dann Alembic erneut
docker compose exec core alembic -c alembic.ini upgrade head
```
