"""
GastroPilot Demo Reset
Taeglich um 04:00 Uhr via Cron — loescht volatile Daten und generiert neue.

Verwendet asyncpg direkt (kein ORM).
Deterministischer Random: random.seed(date.today().isoformat())
"""
import asyncio
import json
import logging
import os
import random
import sys
import uuid
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import asyncpg
import redis.asyncio as aioredis

# ---------------------------------------------------------------------------
# Konfiguration
# ---------------------------------------------------------------------------
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://gastropilot:gastropilot@postgres:5432/gastropilot_demo",
)
# asyncpg braucht postgresql:// statt postgresql+asyncpg://
DATABASE_URL = DATABASE_URL.replace("postgresql+asyncpg://", "postgresql://")

REDIS_URL = os.environ.get("REDIS_URL", "redis://:changeme@redis:6379/0")
DEMO_RESTAURANT_ID = os.environ.get(
    "DEMO_RESTAURANT_ID", "22222222-2222-2222-2222-222222222222"
)
DEMO_TENANT_ID = os.environ.get(
    "DEMO_TENANT_ID", "22222222-2222-2222-2222-222222222222"
)

TZ = ZoneInfo("Europe/Berlin")
MAX_RETRIES = 3

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("demo-reset")

# ---------------------------------------------------------------------------
# Realistische deutsche/italienische Namen
# ---------------------------------------------------------------------------
FIRST_NAMES = [
    "Anna", "Marco", "Lena", "Giulia", "Thomas", "Sabine", "Roberto",
    "Elena", "Klaus", "Petra", "Michael", "Francesca", "Stefan", "Laura",
    "Hans", "Maria", "David", "Sophie", "Andrea", "Felix", "Chiara",
    "Moritz", "Valentina", "Christian", "Isabella", "Tobias", "Alessia",
    "Niklas", "Carla", "Jan", "Marta", "Lukas", "Birgit", "Antonio",
    "Katharina", "Emilio", "Heike", "Lorenzo", "Johanna", "Fabian",
]
LAST_NAMES = [
    "Mueller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer",
    "Wagner", "Becker", "Hoffmann", "Schulz", "Rossi", "Bianchi",
    "Romano", "Colombo", "Ricci", "Marino", "Conti", "De Luca",
    "Esposito", "Russo", "Braun", "Lange", "Krause", "Richter",
    "Wolf", "Neumann", "Schwarz", "Berger", "Kaiser", "Lang",
]
OCCASIONS = [
    None, None, None, None, None, None,  # meistens kein Anlass
    "Geburtstag", "Jubilaeum", "Geschaeftsessen", "Familienfeier",
]

# ---------------------------------------------------------------------------
# Helfer
# ---------------------------------------------------------------------------

def _rand_name() -> tuple[str, str]:
    return random.choice(FIRST_NAMES), random.choice(LAST_NAMES)


def _rand_phone() -> str:
    return f"+49 1{random.randint(50,79)} {random.randint(1000000,9999999)}"


def _rand_email(first: str, last: str) -> str:
    return f"{first.lower()}.{last.lower()}@example.de"


def _today_berlin() -> date:
    return datetime.now(TZ).date()


def _to_utc(d: date, h: int, m: int) -> datetime:
    """Erstellt eine Berlin-Uhrzeit und gibt UTC zurueck."""
    local = datetime.combine(d, time(h, m), tzinfo=TZ)
    return local.astimezone(ZoneInfo("UTC"))


# ---------------------------------------------------------------------------
# Phase 1: Volatile Daten loeschen
# ---------------------------------------------------------------------------

async def delete_volatile_data(conn, restaurant_id: str) -> None:
    log.info("Phase 1: Loesche volatile Daten ...")
    await conn.execute(
        """
        DELETE FROM order_items WHERE order_id IN (
            SELECT id FROM orders WHERE tenant_id = $1::uuid
        )
        """,
        restaurant_id,
    )
    await conn.execute("DELETE FROM orders WHERE tenant_id = $1::uuid", restaurant_id)
    await conn.execute(
        "DELETE FROM reservation_tables WHERE tenant_id = $1::uuid", restaurant_id
    )
    await conn.execute(
        "DELETE FROM reservations WHERE tenant_id = $1::uuid", restaurant_id
    )
    await conn.execute("DELETE FROM waitlist WHERE tenant_id = $1::uuid", restaurant_id)
    log.info("  Volatile Daten geloescht.")


# ---------------------------------------------------------------------------
# Phase 2: Reservierungen generieren
# ---------------------------------------------------------------------------

async def generate_reservations(
    conn, restaurant_id: str, tenant_id: str, tables: list, guest_ids: list
) -> int:
    log.info("Phase 2: Generiere Reservierungen ...")
    today = _today_berlin()
    count = 0

    for day_offset in range(8):  # heute + 7 Tage
        d = today + timedelta(days=day_offset)
        is_weekend = d.weekday() in (5, 6)
        base_count = random.randint(18, 25)
        if is_weekend:
            base_count = int(base_count * 1.3)

        # Aufteilen: Mittag + Abend
        lunch_count = random.randint(6, 8)
        dinner_count = base_count - lunch_count

        slots = []
        # Mittagsreservierungen
        for _ in range(lunch_count):
            h = random.randint(12, 14)
            m = random.choice([0, 15, 30, 45])
            if h == 14 and m > 30:
                m = 0
            party = random.randint(1, 4)
            slots.append((h, m, party))

        # Abendreservierungen
        for _ in range(dinner_count):
            h = random.randint(18, 21)
            m = random.choice([0, 15, 30, 45])
            if h == 21 and m > 30:
                m = 0
            party = random.randint(2, 8)
            slots.append((h, m, party))

        for i, (h, m, party) in enumerate(slots):
            start_utc = _to_utc(d, h, m)
            end_utc = start_utc + timedelta(minutes=90)

            # Passenden Tisch finden
            suitable = [t for t in tables if t["capacity"] >= party]
            table = random.choice(suitable) if suitable else random.choice(tables)

            # 2-3 Reservierungen pro Tag sollen Stammgaeste sein
            if i < 3 and guest_ids:
                guest_id = random.choice(guest_ids)
                first, last = None, None
            else:
                guest_id = None
                first, last = _rand_name()

            # Status: nur fuer heute variabel
            if day_offset == 0:
                r = random.random()
                if r < 0.4:
                    status = "confirmed"
                elif r < 0.7:
                    status = "seated"
                elif r < 0.9:
                    status = "confirmed"
                else:
                    status = "pending"
            else:
                status = "confirmed"

            # Besondere Anlaesse in den naechsten 3 Tagen
            occasion = None
            if day_offset <= 3 and i == 0:
                occasion = "Geburtstag"
            elif day_offset <= 3 and i == 1:
                occasion = "Jubilaeum"

            res_id = uuid.uuid4()
            guest_name = f"{first} {last}" if first else None
            guest_email = _rand_email(first, last) if first else None
            guest_phone = _rand_phone() if first else None

            # Reservierung anlegen
            if guest_id:
                # Gaeste-Name aus DB holen
                row = await conn.fetchrow(
                    "SELECT first_name, last_name, email, phone FROM guests WHERE id = $1::uuid",
                    guest_id,
                )
                if row:
                    guest_name = f"{row['first_name']} {row['last_name']}"
                    guest_email = row["email"]
                    guest_phone = row["phone"]

            notes = occasion if occasion else None
            tags = json.dumps([occasion]) if occasion else "[]"

            await conn.execute(
                """
                INSERT INTO reservations (
                    id, tenant_id, guest_id, table_id,
                    start_at, end_at, party_size, status, channel,
                    guest_name, guest_email, guest_phone,
                    notes, tags, created_at, updated_at
                ) VALUES (
                    $1::uuid, $2::uuid, $3, $4::uuid,
                    $5, $6, $7, $8::reservation_status, 'online',
                    $9, $10, $11,
                    $12, $13::jsonb, NOW(), NOW()
                )
                """,
                res_id,
                tenant_id,
                guest_id if guest_id else None,
                table["id"],
                start_utc,
                end_utc,
                party,
                status,
                guest_name,
                guest_email,
                guest_phone,
                notes,
                tags,
            )
            count += 1

    log.info(f"  {count} Reservierungen erstellt (heute + 7 Tage).")
    return count


# ---------------------------------------------------------------------------
# Phase 3: Bestellungen generieren
# ---------------------------------------------------------------------------

async def generate_orders(
    conn,
    restaurant_id: str,
    tenant_id: str,
    tables: list,
    menu_items: list,
) -> int:
    log.info("Phase 3: Generiere Bestellungen ...")
    today = _today_berlin()
    now_utc = datetime.now(ZoneInfo("UTC"))
    count = 0

    # 8-10 Tische sind derzeit besetzt
    occupied_count = random.randint(8, 10)
    occupied_tables = random.sample(tables, min(occupied_count, len(tables)))

    # Aktive Orders fuer besetzte Tische
    statuses = ["open", "sent_to_kitchen", "in_preparation", "ready"]
    item_statuses_map = {
        "open": ["pending"],
        "sent_to_kitchen": ["sent", "in_preparation"],
        "in_preparation": ["in_preparation", "ready"],
        "ready": ["ready", "served"],
    }

    for table in occupied_tables:
        order_id = uuid.uuid4()
        order_number = f"BV-{today.strftime('%y%m%d')}-{count + 1:03d}"
        order_status = random.choice(statuses)

        num_items = random.randint(2, 5)
        chosen_items = random.sample(menu_items, min(num_items, len(menu_items)))

        subtotal = 0.0
        item_rows = []
        for sort_idx, mi in enumerate(chosen_items):
            qty = random.randint(1, 2)
            unit_price = mi["price"]
            total_price = unit_price * qty
            subtotal += total_price

            possible_statuses = item_statuses_map.get(order_status, ["pending"])
            item_status = random.choice(possible_statuses)

            item_rows.append(
                (
                    uuid.uuid4(),
                    order_id,
                    mi["id"],
                    mi["name"],
                    mi.get("description"),
                    mi.get("category_name"),
                    qty,
                    unit_price,
                    total_price,
                    item_status,
                    sort_idx + 1,
                    mi.get("allergens", "[]"),
                )
            )

        tax_amount = round(subtotal * 0.19, 2)
        total = round(subtotal + tax_amount, 2)

        await conn.execute(
            """
            INSERT INTO orders (
                id, tenant_id, table_id, order_number, status,
                subtotal, tax_amount, total,
                payment_status,
                opened_at, created_at, updated_at
            ) VALUES (
                $1::uuid, $2::uuid, $3::uuid, $4, $5::order_status,
                $6, $7, $8,
                'unpaid',
                $9, NOW(), NOW()
            )
            """,
            order_id,
            tenant_id,
            table["id"],
            order_number,
            order_status,
            subtotal,
            tax_amount,
            total,
            now_utc - timedelta(minutes=random.randint(5, 45)),
        )

        for row in item_rows:
            await conn.execute(
                """
                INSERT INTO order_items (
                    id, order_id, menu_item_id, item_name, item_description,
                    category, quantity, unit_price, total_price,
                    status, sort_order,
                    created_at, updated_at
                ) VALUES (
                    $1::uuid, $2::uuid, $3::uuid, $4, $5,
                    $6, $7, $8, $9,
                    $10::order_item_status, $11,
                    NOW(), NOW()
                )
                """,
                row[0], row[1], row[2], row[3], row[4],
                row[5], row[6], row[7], row[8],
                row[9], row[10],
            )
        count += 1

    # 5-8 abgeschlossene Orders vom heutigen Tag
    completed_count = random.randint(5, 8)
    available_tables = [t for t in tables if t not in occupied_tables]
    if not available_tables:
        available_tables = tables

    for i in range(completed_count):
        order_id = uuid.uuid4()
        order_number = f"BV-{today.strftime('%y%m%d')}-{count + 1:03d}"
        table = random.choice(available_tables)

        num_items = random.randint(2, 5)
        chosen_items = random.sample(menu_items, min(num_items, len(menu_items)))

        subtotal = 0.0
        item_rows = []
        for sort_idx, mi in enumerate(chosen_items):
            qty = random.randint(1, 2)
            unit_price = mi["price"]
            total_price = unit_price * qty
            subtotal += total_price
            item_rows.append(
                (
                    uuid.uuid4(),
                    order_id,
                    mi["id"],
                    mi["name"],
                    mi.get("description"),
                    mi.get("category_name"),
                    qty,
                    unit_price,
                    total_price,
                    "served",
                    sort_idx + 1,
                    mi.get("allergens", "[]"),
                )
            )

        tax_amount = round(subtotal * 0.19, 2)
        tip = round(random.choice([0, 0, 2.0, 3.0, 5.0]), 2)
        total = round(subtotal + tax_amount + tip, 2)

        opened_h = random.randint(12, 20)
        opened_at = _to_utc(today, opened_h, random.randint(0, 59))
        closed_at = opened_at + timedelta(minutes=random.randint(45, 90))

        payment_method = random.choice(["cash", "card", "card", "card"])

        # SplitPay-Demo: 1 abgeschlossene Order mit split_payment_data
        split_payments = None
        if i == 0:
            split_amount_1 = round(total * 0.6, 2)
            split_amount_2 = round(total - split_amount_1, 2)
            split_payments = json.dumps([
                {"guest": "Gast 1", "amount": split_amount_1, "method": "card", "paid": True},
                {"guest": "Gast 2", "amount": split_amount_2, "method": "cash", "paid": True},
            ])

        await conn.execute(
            """
            INSERT INTO orders (
                id, tenant_id, table_id, order_number, status,
                subtotal, tax_amount, tip_amount, total,
                payment_method, payment_status, split_payments,
                opened_at, closed_at, paid_at,
                created_at, updated_at
            ) VALUES (
                $1::uuid, $2::uuid, $3::uuid, $4, 'paid'::order_status,
                $5, $6, $7, $8,
                $9, 'paid', $10::jsonb,
                $11, $12, $12,
                NOW(), NOW()
            )
            """,
            order_id,
            tenant_id,
            table["id"],
            order_number,
            subtotal,
            tax_amount,
            tip,
            total,
            payment_method,
            split_payments,
            opened_at,
            closed_at,
        )

        for row in item_rows:
            await conn.execute(
                """
                INSERT INTO order_items (
                    id, order_id, menu_item_id, item_name, item_description,
                    category, quantity, unit_price, total_price,
                    status, sort_order,
                    created_at, updated_at
                ) VALUES (
                    $1::uuid, $2::uuid, $3::uuid, $4, $5,
                    $6, $7, $8, $9,
                    'served'::order_item_status, $10,
                    NOW(), NOW()
                )
                """,
                row[0], row[1], row[2], row[3], row[4],
                row[5], row[6], row[7], row[8],
                row[10],
            )
        count += 1

    log.info(
        f"  {count} Bestellungen erstellt "
        f"({occupied_count} aktiv, {completed_count} abgeschlossen, 1 SplitPay)."
    )
    return count


# ---------------------------------------------------------------------------
# Phase 4: Warteliste
# ---------------------------------------------------------------------------

async def generate_waitlist(conn, restaurant_id: str, tenant_id: str) -> int:
    log.info("Phase 4: Generiere Warteliste ...")
    today = _today_berlin()
    count = random.randint(2, 3)

    for _ in range(count):
        first, last = _rand_name()
        party_size = random.randint(2, 5)
        desired_h = random.randint(18, 20)
        desired_from = _to_utc(today, desired_h, 0)
        desired_to = desired_from + timedelta(hours=2)

        await conn.execute(
            """
            INSERT INTO waitlist (
                id, tenant_id, party_size,
                desired_from, desired_to, status,
                notes, created_at
            ) VALUES (
                $1::uuid, $2::uuid, $3,
                $4, $5, 'waiting',
                $6, NOW()
            )
            """,
            uuid.uuid4(),
            tenant_id,
            party_size,
            desired_from,
            desired_to,
            random.choice([None, f"{first} {last} – Bevorzugt Terrasse", f"{first} {last} – Mit Kinderwagen"]),
        )

    log.info(f"  {count} Wartelisten-Eintraege erstellt.")
    return count


# ---------------------------------------------------------------------------
# Phase 5: Redis-Cache flushen
# ---------------------------------------------------------------------------

async def flush_redis_cache(restaurant_id: str) -> None:
    log.info("Phase 5: Redis-Cache flushen ...")
    try:
        r = aioredis.from_url(REDIS_URL, decode_responses=True)
        pattern = f"restaurant:{restaurant_id}:*"
        cursor = 0
        deleted = 0
        while True:
            cursor, keys = await r.scan(cursor=cursor, match=pattern, count=100)
            if keys:
                await r.delete(*keys)
                deleted += len(keys)
            if cursor == 0:
                break
        await r.aclose()
        log.info(f"  {deleted} Redis-Keys geloescht (Pattern: {pattern}).")
    except Exception as e:
        log.warning(f"  Redis-Flush fehlgeschlagen (nicht kritisch): {e}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> None:
    today = _today_berlin()
    random.seed(today.isoformat())
    log.info(f"=== GastroPilot Demo Reset — {today.isoformat()} ===")

    conn = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            conn = await asyncpg.connect(DATABASE_URL)
            break
        except Exception as e:
            wait = 2 ** attempt
            log.error(f"DB-Verbindung fehlgeschlagen (Versuch {attempt}/{MAX_RETRIES}): {e}")
            if attempt == MAX_RETRIES:
                log.critical("Maximale Retries erreicht. Abbruch.")
                sys.exit(1)
            await asyncio.sleep(wait)

    try:
        async with conn.transaction():
            # Tenant-Context setzen
            await conn.execute(
                "SELECT set_tenant_context($1::uuid, 'owner')",
                DEMO_TENANT_ID,
            )

            # Phase 1: Loeschen
            await delete_volatile_data(conn, DEMO_RESTAURANT_ID)

            # Tische und Menu-Items laden
            tables_rows = await conn.fetch(
                "SELECT id, number, capacity FROM tables WHERE tenant_id = $1::uuid AND is_active = true",
                DEMO_TENANT_ID,
            )
            tables = [dict(r) for r in tables_rows]

            items_rows = await conn.fetch(
                """
                SELECT mi.id, mi.name, mi.description, mi.price, mi.allergens,
                       mc.name AS category_name
                FROM menu_items mi
                JOIN menu_categories mc ON mi.category_id = mc.id
                WHERE mi.tenant_id = $1::uuid AND mi.is_available = true
                """,
                DEMO_TENANT_ID,
            )
            menu_items = []
            for r in items_rows:
                item = dict(r)
                # allergens als String behalten fuer JSONB-Insert
                if isinstance(item["allergens"], dict):
                    item["allergens"] = json.dumps(item["allergens"])
                elif isinstance(item["allergens"], list):
                    item["allergens"] = json.dumps(item["allergens"])
                elif item["allergens"] is None:
                    item["allergens"] = "[]"
                menu_items.append(item)

            guest_rows = await conn.fetch(
                "SELECT id FROM guests WHERE tenant_id = $1::uuid",
                DEMO_TENANT_ID,
            )
            guest_ids = [r["id"] for r in guest_rows]

            if not tables:
                log.error("Keine Tische gefunden! Wurde seed_bela_vita.sql ausgefuehrt?")
                sys.exit(1)

            if not menu_items:
                log.error("Keine Menu-Items gefunden! Wurde seed_bela_vita.sql ausgefuehrt?")
                sys.exit(1)

            log.info(
                f"  Geladen: {len(tables)} Tische, "
                f"{len(menu_items)} Menu-Items, {len(guest_ids)} Stammgaeste."
            )

            # Phase 2-4: Generieren
            await generate_reservations(conn, DEMO_RESTAURANT_ID, DEMO_TENANT_ID, tables, guest_ids)
            await generate_orders(conn, DEMO_RESTAURANT_ID, DEMO_TENANT_ID, tables, menu_items)
            await generate_waitlist(conn, DEMO_RESTAURANT_ID, DEMO_TENANT_ID)

        # Phase 5: Redis (ausserhalb der Transaktion)
        await flush_redis_cache(DEMO_RESTAURANT_ID)

        log.info("=== Demo Reset abgeschlossen ===")

    except Exception as e:
        log.critical(f"Fehler beim Reset: {e}", exc_info=True)
        sys.exit(1)
    finally:
        await conn.close()


if __name__ == "__main__":
    asyncio.run(main())
