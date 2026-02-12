#!/bin/bash
# GastroPilot: Admin-Account erstellen
set -e

STACK_NAME=$(grep -E '^STACK_NAME=' .env.server 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot}-backend"

echo "== Admin-Account erstellen =="
echo

read -rp "E-Mail: " EMAIL
read -rp "Vorname: " FIRST_NAME
read -rp "Nachname: " LAST_NAME
read -rsp "Passwort (min. 8 Zeichen): " PASSWORD
echo

if [ ${#PASSWORD} -lt 8 ]; then
    echo "Fehler: Passwort muss mindestens 8 Zeichen lang sein."
    exit 1
fi

docker exec \
    -e ADMIN_EMAIL="$EMAIL" \
    -e ADMIN_FIRST_NAME="$FIRST_NAME" \
    -e ADMIN_LAST_NAME="$LAST_NAME" \
    -e ADMIN_PASSWORD="$PASSWORD" \
    "$CONTAINER" python -c "
import asyncio, os
from app.database.instance import async_session
from app.database.models import Users
from app.auth import hash_password

async def create_admin():
    email = os.environ['ADMIN_EMAIL'].lower().strip()
    first_name = os.environ['ADMIN_FIRST_NAME'].strip()
    last_name = os.environ['ADMIN_LAST_NAME'].strip()
    password = os.environ['ADMIN_PASSWORD']

    async with async_session() as session:
        async with session.begin():
            user = Users(
                email=email,
                first_name=first_name,
                last_name=last_name,
                password_hash=hash_password(password),
                role='super_admin'
            )
            session.add(user)
    print(f'Admin-Account erstellt: {email}')

asyncio.run(create_admin())
"
