#!/bin/bash
# GastroPilot: Admin-Account erstellen (Microservices)
# Erstellt einen User im Core-Service via docker exec.
set -e

STACK_NAME=$(grep -E '^STACK_NAME=' .env 2>/dev/null | cut -d= -f2)
CONTAINER="${STACK_NAME:-gastropilot-staging}-core"

echo "== Admin-Account erstellen =="
echo

echo "  Typ:"
echo "    1) Platform-Admin (Zugriff auf alle Restaurants)"
echo "    2) Restaurant-Owner (Zugriff auf ein Restaurant)"
read -rp "  Auswahl [1/2]: " TYPE_CHOICE
echo

if [ "$TYPE_CHOICE" = "1" ]; then
    # Platform-Admin: E-Mail + Passwort
    ROLE="platform_admin"
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
        -e ADMIN_ROLE="$ROLE" \
        "$CONTAINER" python -c "
import asyncio, os
from app.core.database import get_session_factories
from app.models.user import User
from app.core.security import hash_password

async def create_admin():
    factory, _ = get_session_factories()
    async with factory() as session:
        async with session.begin():
            user = User(
                email=os.environ['ADMIN_EMAIL'],
                password_hash=hash_password(os.environ['ADMIN_PASSWORD']),
                first_name=os.environ['ADMIN_FIRST_NAME'].strip(),
                last_name=os.environ['ADMIN_LAST_NAME'].strip(),
                role=os.environ['ADMIN_ROLE'],
                auth_method='password',
                is_active=True,
            )
            session.add(user)
    print(f'Platform-Admin erstellt: {user.first_name} {user.last_name} ({user.email})')

asyncio.run(create_admin())
"

else
    # Restaurant-Owner: Bedienernummer + PIN
    ROLE="owner"
    read -rp "Restaurant-Slug: " TENANT_SLUG
    read -rp "Bedienernummer (4-stellig) [0001]: " OPERATOR_NUMBER
    OPERATOR_NUMBER=${OPERATOR_NUMBER:-0001}
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

    docker exec \
        -e ADMIN_SLUG="$TENANT_SLUG" \
        -e ADMIN_OPERATOR_NUMBER="$OPERATOR_NUMBER" \
        -e ADMIN_FIRST_NAME="$FIRST_NAME" \
        -e ADMIN_LAST_NAME="$LAST_NAME" \
        -e ADMIN_PIN="$PIN" \
        -e ADMIN_ROLE="$ROLE" \
        "$CONTAINER" python -c "
import asyncio, os
from sqlalchemy import select
from app.core.database import get_session_factories
from app.models.user import User
from app.models.restaurant import Restaurant
from app.core.security import hash_pin

async def create_owner():
    factory, _ = get_session_factories()
    slug = os.environ['ADMIN_SLUG']

    async with factory() as session:
        result = await session.execute(select(Restaurant).where(Restaurant.slug == slug))
        restaurant = result.scalar_one_or_none()
        if not restaurant:
            print(f'Fehler: Restaurant mit Slug \"{slug}\" nicht gefunden.')
            return

        async with session.begin():
            user = User(
                tenant_id=restaurant.id,
                operator_number=os.environ['ADMIN_OPERATOR_NUMBER'],
                pin_hash=hash_pin(os.environ['ADMIN_PIN']),
                first_name=os.environ['ADMIN_FIRST_NAME'].strip(),
                last_name=os.environ['ADMIN_LAST_NAME'].strip(),
                role=os.environ['ADMIN_ROLE'],
                auth_method='pin',
                is_active=True,
            )
            session.add(user)
    print(f'Owner erstellt: {user.first_name} {user.last_name} (Bediener {user.operator_number}, Restaurant: {slug})')

asyncio.run(create_owner())
"
fi
