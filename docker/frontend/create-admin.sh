#!/bin/bash
# GastroPilot: Admin-Account (Restaurantinhaber) erstellen
set -e

STACK_NAME=$(grep -E '^STACK_NAME=' .env.server 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot}-backend"

echo "== Admin-Account erstellen =="
echo

read -rp "Bedienernummer (4-stellig) [0000]: " OPERATOR_NUMBER
OPERATOR_NUMBER=${OPERATOR_NUMBER:-0000}
read -rp "Vorname: " FIRST_NAME
read -rp "Nachname: " LAST_NAME
read -rsp "PIN (min. 6 Zeichen): " PIN
echo

if [ ${#OPERATOR_NUMBER} -ne 4 ]; then
    echo "Fehler: Bedienernummer muss genau 4 Zeichen lang sein."
    exit 1
fi

if [ ${#PIN} -lt 6 ]; then
    echo "Fehler: PIN muss mindestens 6 Zeichen lang sein."
    exit 1
fi

echo
echo "  Rolle:"
echo "    1) restaurantinhaber (Standard-Admin)"
echo "    2) servecta (Super-Admin)"
read -rp "  Auswahl [1/2]: " ROLE_CHOICE
if [ "$ROLE_CHOICE" = "2" ]; then
    ROLE="servecta"
else
    ROLE="restaurantinhaber"
fi

docker exec \
    -e ADMIN_OPERATOR_NUMBER="$OPERATOR_NUMBER" \
    -e ADMIN_FIRST_NAME="$FIRST_NAME" \
    -e ADMIN_LAST_NAME="$LAST_NAME" \
    -e ADMIN_PIN="$PIN" \
    -e ADMIN_ROLE="$ROLE" \
    "$CONTAINER" python -c "
import asyncio, os
from app.database.instance import async_session
from app.database.models import User
from app.auth import hash_password

async def create_admin():
    operator_number = os.environ['ADMIN_OPERATOR_NUMBER']
    first_name = os.environ['ADMIN_FIRST_NAME'].strip()
    last_name = os.environ['ADMIN_LAST_NAME'].strip()
    pin = os.environ['ADMIN_PIN']
    role = os.environ['ADMIN_ROLE']

    async with async_session() as session:
        async with session.begin():
            user = User(
                operator_number=operator_number,
                pin_hash=hash_password(pin),
                first_name=first_name,
                last_name=last_name,
                role=role
            )
            session.add(user)
    print(f'Admin-Account erstellt: {first_name} {last_name} (Bediener {operator_number}, Rolle: {role})')

asyncio.run(create_admin())
"
