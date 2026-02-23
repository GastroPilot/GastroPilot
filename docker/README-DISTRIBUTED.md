# GastroPilot — Verteiltes Deployment (servecta.local)

Frontend, Backend und Datenbank laufen auf getrennten Servern, verbunden über ein privates Netzwerk:

| Server | Hostname | Komponenten |
|--------|----------|-------------|
| App | app.servecta.local | Frontend, nginx (Proxy zu API) |
| API | api.servecta.local | Backend |
| DB | db-01.servecta.local | PostgreSQL, Redis |

**Images:** Docker Hub (`servecta/gastropilot-frontend`, `servecta/gastropilot-backend`)

---

## 1. Voraussetzungen

- Docker & Docker Compose auf allen drei Servern
- Private Netzwerk-Konnektivität (app ↔ api ↔ db-01)
- DNS: app.servecta.local, api.servecta.local, db-01.servecta.local auflösbar
- Gemeinsamer Proxy (z.B. auf separatem Host) für SSL-Terminierung

---

## 2. Start-Reihenfolge

1. **db-01.servecta.local** — Datenbank zuerst
2. **api.servecta.local** — Backend (benötigt DB)
3. **app.servecta.local** — Frontend (benötigt API)

---

## 3. Installation pro Server

### db-primary.servecta.local

```bash
cd docker
cp .env.db.example .env.db
# .env.db anpassen: POSTGRES_PASSWORD, REDIS_PASSWORD

docker compose -f docker-compose.db.yml --env-file .env.db pull
docker compose -f docker-compose.db.yml --env-file .env.db up -d
```

### api.servecta.local

```bash
cd docker
cp .env.api.example .env.api
# .env.api anpassen: POSTGRES_PASSWORD, REDIS_PASSWORD (identisch mit db!)
#                   JWT_SECRET, CORS_ORIGINS, BASE_URL

docker compose -f docker-compose.api.yml --env-file .env.api pull
docker compose -f docker-compose.api.yml --env-file .env.api up -d
```

### app.servecta.local

```bash
cd docker
cp .env.app.example .env.app
# .env.app anpassen: AUTH_SECRET, BASE_URL, NEXT_PUBLIC_API_BASE_URL

# Gastropilot-Proxy-Netzwerk anlegen (falls noch nicht vorhanden)
docker network create gastropilot-proxy 2>/dev/null || true

docker compose -f docker-compose.app.yml --env-file .env.app pull
docker compose -f docker-compose.app.yml --env-file .env.app up -d
```

---

## 4. Proxy-Konfiguration (SSL-Terminierung)

Der gemeinsame Proxy routet:

- **app.servecta.local** → app.servecta.local:80 (nginx auf App-Server)
- **api.servecta.local** → api.servecta.local:8000 (Backend direkt)

Beispiel `proxy/conf.d/app.servecta.local.conf`:

```nginx
upstream gastro-app {
    server app.servecta.local:80;
}

server {
    listen 443 ssl http2;
    server_name app.servecta.local;

    ssl_certificate /etc/nginx/ssl/app.servecta.local/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/app.servecta.local/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        proxy_pass http://gastro-app;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_buffering off;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

Beispiel `proxy/conf.d/api.servecta.local.conf`:

```nginx
upstream gastro-api {
    server api.servecta.local:8000;
}

server {
    listen 443 ssl http2;
    server_name api.servecta.local;

    ssl_certificate /etc/nginx/ssl/api.servecta.local/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/api.servecta.local/privkey.pem;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        proxy_pass http://gastro-api;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_buffering off;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

SSL-Zertifikate für `app.servecta.local` und `api.servecta.local` in `proxy/ssl/<domain>/` ablegen.

---

## 5. Update-Skripte

### db-01

```bash
docker compose -f docker-compose.db.yml --env-file .env.db pull
docker compose -f docker-compose.db.yml --env-file .env.db up -d
```

### api

```bash
docker compose -f docker-compose.api.yml --env-file .env.api pull
docker compose -f docker-compose.api.yml --env-file .env.api up -d
```

### app

```bash
docker compose -f docker-compose.app.yml --env-file .env.app pull
docker compose -f docker-compose.app.yml --env-file .env.app up -d
```

---

## 6. Admin erstellen

Nach dem Start des API-Servers:

```bash
docker exec gastropilot-api-backend python -c "
import asyncio, os
from app.database.instance import async_session
from app.database.models import User
from app.auth import hash_password

async def create_admin():
    async with async_session() as session:
        async with session.begin():
            user = User(
                operator_number='0000',
                pin_hash=hash_password('CHANGE_ME'),
                first_name='Admin',
                last_name='User',
                role='restaurantinhaber'
            )
            session.add(user)
    print('Admin erstellt')

asyncio.run(create_admin())
"
```
