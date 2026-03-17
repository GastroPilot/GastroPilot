-- ============================================================================
-- GastroPilot Demo Seed: Bela Vita
-- Modernes mediterran-italienisches Restaurant in Kiel
--
-- Idempotent: kann mehrfach ausgefuehrt werden (DELETE + INSERT).
-- Erfordert: pgcrypto Extension (fuer gen_random_uuid)
-- ============================================================================

BEGIN;

-- Feste IDs
DO $$ BEGIN
    PERFORM set_config('demo.tenant_id',     '22222222-2222-2222-2222-222222222222', true);
    PERFORM set_config('demo.restaurant_id',  '22222222-2222-2222-2222-222222222222', true);
END $$;

-- Tenant-Context setzen (RLS)
SELECT set_tenant_context(
    '22222222-2222-2222-2222-222222222222'::UUID,
    'owner'
);

-- ============================================================================
-- 1. Bestehende Daten loeschen (abhaengigkeitsgerecht, fehlertolerant)
-- ============================================================================

DO $$ BEGIN
    -- Volatile Daten
    DELETE FROM order_items WHERE order_id IN (
        SELECT id FROM orders WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
    );
    DELETE FROM orders           WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM reservation_tables WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM reservations     WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM waitlist         WHERE tenant_id = '22222222-2222-2222-2222-222222222222';

    -- Stammdaten
    DELETE FROM menu_items       WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM menu_categories  WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM guests           WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM tables           WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM areas            WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
    DELETE FROM refresh_tokens   WHERE user_id IN (
        SELECT id FROM users WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
    );
    DELETE FROM users            WHERE tenant_id = '22222222-2222-2222-2222-222222222222';

    -- Optionale Tabellen (existieren evtl. nicht in allen Environments)
    BEGIN DELETE FROM reviews  WHERE tenant_id = '22222222-2222-2222-2222-222222222222'; EXCEPTION WHEN undefined_table THEN NULL; END;
    BEGIN DELETE FROM vouchers WHERE tenant_id = '22222222-2222-2222-2222-222222222222'; EXCEPTION WHEN undefined_table THEN NULL; END;

    DELETE FROM restaurants      WHERE id = '22222222-2222-2222-2222-222222222222';
END $$;

-- ============================================================================
-- 2. Restaurant
-- ============================================================================

INSERT INTO restaurants (
    id, name, slug, description, address, phone, email,
    subscription_tier, is_suspended, settings,
    public_booking_enabled, booking_lead_time_hours,
    booking_max_party_size, booking_default_duration,
    opening_hours, created_at, updated_at
) VALUES (
    '22222222-2222-2222-2222-222222222222',
    'Bela Vita',
    'bela-vita',
    'Modernes mediterran-italienisches Restaurant in Kiel. Frische Pasta, knusprige Pizza und klassische Secondi – mit Blick auf die Kieler Foerde.',
    'Holstenstrasse 42, 24103 Kiel',
    '+49 431 555 0042',
    'info@bela-vita-demo.gpilot.app',
    'professional',
    false,
    '{"currency": "EUR", "timezone": "Europe/Berlin", "language": "de", "tax_rate": 0.19}'::jsonb,
    true,
    2,
    12,
    120,
    '{
        "monday":    {"open": "11:30", "close": "23:00"},
        "tuesday":   {"open": "11:30", "close": "23:00"},
        "wednesday": {"open": "11:30", "close": "23:00"},
        "thursday":  {"open": "11:30", "close": "23:00"},
        "friday":    {"open": "11:30", "close": "00:00"},
        "saturday":  {"open": "11:30", "close": "00:00"},
        "sunday":    {"open": "12:00", "close": "22:00"}
    }'::jsonb,
    NOW(),
    NOW()
);

-- ============================================================================
-- 3. Staff-Accounts
-- Passwort: Demo2026!
-- bcrypt hash (rounds=12): $2b$12$rixBumimZfpfnf8FKUuAMu89fCXHxyXNuO3Jh03n7qo/8CNzUO6oC
-- ============================================================================

INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, auth_method, is_active, created_at, updated_at) VALUES
    ('aaaaaaaa-0001-0001-0001-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'marco@bela-vita-demo.gpilot.app',  '$2b$12$rixBumimZfpfnf8FKUuAMu89fCXHxyXNuO3Jh03n7qo/8CNzUO6oC', 'Marco',  'Rossi',    'owner',   'password', true, NOW(), NOW()),
    ('aaaaaaaa-0002-0002-0002-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'giulia@bela-vita-demo.gpilot.app', '$2b$12$rixBumimZfpfnf8FKUuAMu89fCXHxyXNuO3Jh03n7qo/8CNzUO6oC', 'Giulia', 'Ferrari',  'manager', 'password', true, NOW(), NOW()),
    ('aaaaaaaa-0003-0003-0003-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'lena@bela-vita-demo.gpilot.app',   '$2b$12$rixBumimZfpfnf8FKUuAMu89fCXHxyXNuO3Jh03n7qo/8CNzUO6oC', 'Lena',   'Hoffmann', 'staff',   'password', true, NOW(), NOW()),
    ('aaaaaaaa-0004-0004-0004-aaaaaaaaaaaa', '22222222-2222-2222-2222-222222222222', 'kai@bela-vita-demo.gpilot.app',    '$2b$12$rixBumimZfpfnf8FKUuAMu89fCXHxyXNuO3Jh03n7qo/8CNzUO6oC', 'Kai',    'Braun',    'kitchen', 'password', true, NOW(), NOW());

-- ============================================================================
-- 4. Zonen (areas)
-- ============================================================================

INSERT INTO areas (id, tenant_id, name, created_at) VALUES
    ('bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'Innen',    NOW()),
    ('bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'Terrasse', NOW()),
    ('bbbbbbbb-0003-0003-0003-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'Bar',      NOW()),
    ('bbbbbbbb-0004-0004-0004-bbbbbbbbbbbb', '22222222-2222-2222-2222-222222222222', 'Privat',   NOW());

-- ============================================================================
-- 5. Tische (28 Stueck in 4 Zonen)
-- ============================================================================

-- Zone: Innen (14 Tische)
INSERT INTO tables (id, tenant_id, area_id, number, capacity, position_x, position_y, is_active, is_outdoor, created_at, updated_at) VALUES
    -- 2er-Tische T1-T4
    ('cccccccc-0001-0001-0001-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T1',  2, 100, 100, true, false, NOW(), NOW()),
    ('cccccccc-0002-0002-0002-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T2',  2, 200, 100, true, false, NOW(), NOW()),
    ('cccccccc-0003-0003-0003-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T3',  2, 300, 100, true, false, NOW(), NOW()),
    ('cccccccc-0004-0004-0004-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T4',  2, 400, 100, true, false, NOW(), NOW()),
    -- 4er-Tische T5-T8
    ('cccccccc-0005-0005-0005-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T5',  4, 100, 250, true, false, NOW(), NOW()),
    ('cccccccc-0006-0006-0006-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T6',  4, 200, 250, true, false, NOW(), NOW()),
    ('cccccccc-0007-0007-0007-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T7',  4, 300, 250, true, false, NOW(), NOW()),
    ('cccccccc-0008-0008-0008-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T8',  4, 400, 250, true, false, NOW(), NOW()),
    -- 6er-Tische T9-T12
    ('cccccccc-0009-0009-0009-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T9',  6, 100, 400, true, false, NOW(), NOW()),
    ('cccccccc-0010-0010-0010-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T10', 6, 200, 400, true, false, NOW(), NOW()),
    ('cccccccc-0011-0011-0011-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T11', 6, 300, 400, true, false, NOW(), NOW()),
    ('cccccccc-0012-0012-0012-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T12', 6, 400, 400, true, false, NOW(), NOW()),
    -- 8er-Tische T13-T14
    ('cccccccc-0013-0013-0013-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T13', 8, 150, 550, true, false, NOW(), NOW()),
    ('cccccccc-0014-0014-0014-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0001-0001-0001-bbbbbbbbbbbb', 'T14', 8, 350, 550, true, false, NOW(), NOW());

-- Zone: Terrasse (8 Tische)
INSERT INTO tables (id, tenant_id, area_id, number, capacity, position_x, position_y, is_active, is_outdoor, created_at, updated_at) VALUES
    ('cccccccc-0015-0015-0015-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA1', 2, 600, 100, true, true, NOW(), NOW()),
    ('cccccccc-0016-0016-0016-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA2', 2, 700, 100, true, true, NOW(), NOW()),
    ('cccccccc-0017-0017-0017-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA3', 2, 800, 100, true, true, NOW(), NOW()),
    ('cccccccc-0018-0018-0018-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA4', 2, 900, 100, true, true, NOW(), NOW()),
    ('cccccccc-0019-0019-0019-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA5', 4, 600, 250, true, true, NOW(), NOW()),
    ('cccccccc-0020-0020-0020-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA6', 4, 700, 250, true, true, NOW(), NOW()),
    ('cccccccc-0021-0021-0021-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA7', 4, 800, 250, true, true, NOW(), NOW()),
    ('cccccccc-0022-0022-0022-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0002-0002-0002-bbbbbbbbbbbb', 'TA8', 4, 900, 250, true, true, NOW(), NOW());

-- Zone: Bar (4 Tische)
INSERT INTO tables (id, tenant_id, area_id, number, capacity, position_x, position_y, is_active, is_outdoor, created_at, updated_at) VALUES
    ('cccccccc-0023-0023-0023-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0003-0003-0003-bbbbbbbbbbbb', 'B1', 2, 100, 700, true, false, NOW(), NOW()),
    ('cccccccc-0024-0024-0024-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0003-0003-0003-bbbbbbbbbbbb', 'B2', 2, 200, 700, true, false, NOW(), NOW()),
    ('cccccccc-0025-0025-0025-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0003-0003-0003-bbbbbbbbbbbb', 'B3', 2, 300, 700, true, false, NOW(), NOW()),
    ('cccccccc-0026-0026-0026-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0003-0003-0003-bbbbbbbbbbbb', 'B4', 2, 400, 700, true, false, NOW(), NOW());

-- Zone: Privat (2 Tische)
INSERT INTO tables (id, tenant_id, area_id, number, capacity, position_x, position_y, is_active, is_outdoor, created_at, updated_at) VALUES
    ('cccccccc-0027-0027-0027-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0004-0004-0004-bbbbbbbbbbbb', 'P1', 10, 650, 500, true, false, NOW(), NOW()),
    ('cccccccc-0028-0028-0028-cccccccccccc', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0004-0004-0004-bbbbbbbbbbbb', 'P2', 12, 800, 500, true, false, NOW(), NOW());

-- ============================================================================
-- 6. Speisekarte — Kategorien
-- ============================================================================

INSERT INTO menu_categories (id, tenant_id, name, description, sort_order, is_active, created_at, updated_at) VALUES
    ('dddddddd-0001-0001-0001-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'Antipasti',  'Vorspeisen aus der mediterranen Kueche',          1, true, NOW(), NOW()),
    ('dddddddd-0002-0002-0002-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'Pasta',      'Handgemachte Pasta – taeglich frisch',             2, true, NOW(), NOW()),
    ('dddddddd-0003-0003-0003-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'Secondi',    'Hauptgerichte mit Fisch, Fleisch und Gemuese',     3, true, NOW(), NOW()),
    ('dddddddd-0004-0004-0004-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'Pizza',      'Steinofen-Pizza nach neapolitanischer Tradition',  4, true, NOW(), NOW()),
    ('dddddddd-0005-0005-0005-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'Dolci',      'Hausgemachte Desserts',                             5, true, NOW(), NOW()),
    ('dddddddd-0006-0006-0006-dddddddddddd', '22222222-2222-2222-2222-222222222222', 'Getraenke',  'Kalte und warme Getraenke',                        6, true, NOW(), NOW());

-- ============================================================================
-- 7. Speisekarte — Items (41 Stueck)
-- ============================================================================

-- --- Antipasti (6) ---
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('eeeeeeee-0101-0101-0101-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0001-0001-0001-dddddddddddd',
     'Bruschetta al Pomodoro', 'Geroestetest Ciabatta mit Tomaten, Basilikum und Olivenoel', 7.50, 0.19, true, 1,
     '{"contains": ["gluten", "sesam"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0102-0102-0102-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0001-0001-0001-dddddddddddd',
     'Carpaccio di Manzo', 'Hauchdünn geschnittenes Rinderfilet mit Rucola, Parmesan und Trüffelöl', 14.90, 0.19, true, 2,
     '{"contains": ["milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0103-0103-0103-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0001-0001-0001-dddddddddddd',
     'Burrata con Rucola', 'Cremige Burrata auf frischem Rucola mit Kirschtomaten und Balsamico', 12.90, 0.19, true, 3,
     '{"contains": ["milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0104-0104-0104-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0001-0001-0001-dddddddddddd',
     'Calamari Fritti', 'Knusprig frittierte Tintenfischringe mit Zitrone und Aioli', 13.50, 0.19, true, 4,
     '{"contains": ["gluten", "weichtiere"], "may_contain": ["ei"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0105-0105-0105-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0001-0001-0001-dddddddddddd',
     'Vitello Tonnato', 'Zartes Kalbfleisch mit cremiger Thunfischsauce und Kapern', 16.90, 0.19, true, 5,
     '{"contains": ["fisch", "ei", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0106-0106-0106-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0001-0001-0001-dddddddddddd',
     'Antipasto Misto (fuer 2)', 'Gemischte Vorspeisenplatte mit Schinken, Kaese, Oliven und gegrilltem Gemuese', 22.90, 0.19, true, 6,
     '{"contains": ["gluten", "milch", "fisch"], "may_contain": ["nuesse"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW());

-- --- Pasta (8) ---
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('eeeeeeee-0201-0201-0201-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Spaghetti Carbonara', 'Klassisch mit Guanciale, Pecorino, Eigelb und schwarzem Pfeffer', 16.90, 0.19, true, 1,
     '{"contains": ["gluten", "ei", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0202-0202-0202-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Tagliatelle al Ragu', 'Breite Bandnudeln mit langsam geschmortem Rindfleisch-Ragu', 17.90, 0.19, true, 2,
     '{"contains": ["gluten", "milch"], "may_contain": ["ei", "sellerie"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0203-0203-0203-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Pappardelle al Cinghiale', 'Breite Nudeln mit Wildschwein-Ragu nach toskanischer Art', 19.90, 0.19, true, 3,
     '{"contains": ["gluten"], "may_contain": ["sellerie"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0204-0204-0204-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Rigatoni all''Arrabbiata', 'Roehren-Pasta in feuriger Tomatensauce mit Knoblauch und Peperoncino', 14.90, 0.19, true, 4,
     '{"contains": ["gluten"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0205-0205-0205-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Gnocchi al Gorgonzola', 'Kartoffelgnocchi in cremiger Gorgonzola-Sauce mit Walnuessen', 16.50, 0.19, true, 5,
     '{"contains": ["gluten", "milch"], "may_contain": ["nuesse"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0206-0206-0206-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Linguine allo Scoglio', 'Meeresfruechte-Linguine mit Muscheln, Garnelen und Vongole', 22.90, 0.19, true, 6,
     '{"contains": ["gluten", "weichtiere", "krebstiere", "fisch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0207-0207-0207-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Lasagne della Nonna', 'Klassische Lasagne nach Grossmutters Rezept mit Bechamel und Ragu', 18.90, 0.19, true, 7,
     '{"contains": ["gluten", "milch", "ei"], "may_contain": ["sellerie"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0208-0208-0208-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0002-0002-0002-dddddddddddd',
     'Pasta del Giorno', 'Taeglich wechselnde Pasta-Kreation – fragen Sie unseren Kellner', 17.90, 0.19, true, 8,
     '{"contains": ["gluten"], "may_contain": ["milch", "ei", "fisch", "nuesse"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW());

-- --- Secondi (6) ---
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('eeeeeeee-0301-0301-0301-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0003-0003-0003-dddddddddddd',
     'Branzino al Forno', 'Im Ofen gebackener Wolfsbarsch mit Zitrone, Kapern und Rosmarin', 26.90, 0.19, true, 1,
     '{"contains": ["fisch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0302-0302-0302-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0003-0003-0003-dddddddddddd',
     'Tagliata di Manzo', 'Geschnittenes Rindersteak auf Rucola mit Parmesan und Balsamico', 29.90, 0.19, true, 2,
     '{"contains": [], "may_contain": ["milch"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0303-0303-0303-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0003-0003-0003-dddddddddddd',
     'Pollo alla Parmigiana', 'Paniertes Haehnchenschnitzel ueberbacken mit Tomatensauce und Mozzarella', 21.90, 0.19, true, 3,
     '{"contains": ["gluten", "milch", "ei"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0304-0304-0304-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0003-0003-0003-dddddddddddd',
     'Agnello al Rosmarino', 'Geschmorte Lammkeule mit Rosmarin, Knoblauch und Ofenkartoffeln', 27.90, 0.19, true, 4,
     '{"contains": [], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0305-0305-0305-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0003-0003-0003-dddddddddddd',
     'Saltimbocca alla Romana', 'Kalbsschnitzel mit Salbei und Parmaschinken in Weisswein-Butter', 24.90, 0.19, true, 5,
     '{"contains": [], "may_contain": ["milch"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0306-0306-0306-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0003-0003-0003-dddddddddddd',
     'Melanzane alla Parmigiana', 'Geschichtete Auberginen mit Tomatensauce, Mozzarella und Parmesan', 17.90, 0.19, true, 6,
     '{"contains": ["milch"], "may_contain": ["gluten"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- --- Pizza (6) ---
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('eeeeeeee-0401-0401-0401-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0004-0004-0004-dddddddddddd',
     'Margherita', 'Tomatensauce, Fior di Latte, frischer Basilikum', 13.90, 0.19, true, 1,
     '{"contains": ["gluten", "milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0402-0402-0402-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0004-0004-0004-dddddddddddd',
     'Diavola', 'Tomatensauce, Mozzarella, scharfe Salami, Peperoncini', 15.90, 0.19, true, 2,
     '{"contains": ["gluten", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0403-0403-0403-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0004-0004-0004-dddddddddddd',
     'Quattro Formaggi', 'Mozzarella, Gorgonzola, Fontina und Parmesan', 17.90, 0.19, true, 3,
     '{"contains": ["gluten", "milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0404-0404-0404-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0004-0004-0004-dddddddddddd',
     'Prosciutto e Funghi', 'Tomatensauce, Mozzarella, Parmaschinken und Champignons', 16.90, 0.19, true, 4,
     '{"contains": ["gluten", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0405-0405-0405-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0004-0004-0004-dddddddddddd',
     'Tartufo Bianco', 'Crème fraîche, Mozzarella, Trueffelcreme und Rucola', 22.90, 0.19, true, 5,
     '{"contains": ["gluten", "milch"], "may_contain": ["nuesse"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0406-0406-0406-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0004-0004-0004-dddddddddddd',
     'Pizza Vegana', 'Tomatensauce, gegrilltes Gemuese, Oliven und veganer Kaese', 14.90, 0.19, true, 6,
     '{"contains": ["gluten"], "may_contain": ["soja"], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- --- Dolci (5) ---
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('eeeeeeee-0501-0501-0501-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0005-0005-0005-dddddddddddd',
     'Tiramisu', 'Klassisches Tiramisu mit Mascarpone, Espresso und Amaretto', 7.90, 0.19, true, 1,
     '{"contains": ["gluten", "milch", "ei"], "may_contain": ["nuesse"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0502-0502-0502-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0005-0005-0005-dddddddddddd',
     'Panna Cotta ai Frutti di Bosco', 'Vanille-Panna-Cotta mit Waldbeeren-Coulis', 7.50, 0.19, true, 2,
     '{"contains": ["milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0503-0503-0503-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0005-0005-0005-dddddddddddd',
     'Cannoli Siciliani (2 Stueck)', 'Knusprige Teigroellchen gefuellt mit Ricotta-Creme und Pistazien', 8.90, 0.19, true, 3,
     '{"contains": ["gluten", "milch"], "may_contain": ["nuesse"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0504-0504-0504-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0005-0005-0005-dddddddddddd',
     'Gelato Artigianale (3 Kugeln)', 'Hausgemachtes Eis – Auswahl taeglich wechselnd', 6.50, 0.19, true, 4,
     '{"contains": ["milch", "ei"], "may_contain": ["nuesse", "erdnuesse"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0505-0505-0505-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0005-0005-0005-dddddddddddd',
     'Torta al Cioccolato Fondente', 'Warmer Schokoladenkuchen mit fluessigem Kern und Vanilleeis', 8.90, 0.19, true, 5,
     '{"contains": ["gluten", "milch"], "may_contain": ["nuesse", "soja"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- --- Getraenke (10) ---
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('eeeeeeee-0601-0601-0601-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Acqua Naturale 0,5l', 'Stilles Mineralwasser', 3.50, 0.19, true, 1,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0602-0602-0602-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Acqua Frizzante 0,5l', 'Sprudel-Mineralwasser', 3.50, 0.19, true, 2,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0603-0603-0603-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Coca-Cola 0,33l', NULL, 4.50, 0.19, true, 3,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0604-0604-0604-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Hauslimonade', 'Hausgem. Limonade mit Zitrone, Minze und Agave', 5.50, 0.19, true, 4,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0605-0605-0605-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Bier lokal 0,5l', 'Kieler Craft-Bier vom Fass', 5.90, 0.19, true, 5,
     '{"contains": ["gluten"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0606-0606-0606-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Hauswein Weiss 0,2l', 'Pinot Grigio aus dem Veneto', 6.90, 0.19, true, 6,
     '{"contains": ["schwefeldioxid"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0607-0607-0607-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Hauswein Rot 0,2l', 'Montepulciano d''Abruzzo', 6.90, 0.19, true, 7,
     '{"contains": ["schwefeldioxid"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0608-0608-0608-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Prosecco 0,1l', 'Prosecco DOC aus Valdobbiadene', 7.50, 0.19, true, 8,
     '{"contains": ["schwefeldioxid"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0609-0609-0609-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Espresso', 'Italienischer Espresso aus der Siebtraegermaschine', 2.80, 0.19, true, 9,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('eeeeeeee-0610-0610-0610-eeeeeeeeeeee', '22222222-2222-2222-2222-222222222222', 'dddddddd-0006-0006-0006-dddddddddddd',
     'Cappuccino', 'Espresso mit aufgeschaeumter Milch', 4.20, 0.19, true, 10,
     '{"contains": ["milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- ============================================================================
-- 8. Stammgaeste (10 Eintraege)
--    - 3 mit Allergen-Profilen
--    - 2 mit Geburtstag in den naechsten 14 Tagen
--    - 2 mit besonderen Notizen
-- ============================================================================

INSERT INTO guests (id, tenant_id, first_name, last_name, email, phone, birthday, notes, created_at, updated_at) VALUES
    -- Stammgast 1: Allergen-Profil (Laktoseintoleranz)
    ('ffffffff-0001-0001-0001-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Thomas', 'Mueller',
     'thomas.mueller@example.de', '+49 170 1234501',
     '1978-05-15',
     'Stammgast seit 2022. Laktoseintoleranz – immer laktosefreie Alternativen anbieten.',
     NOW(), NOW()),

    -- Stammgast 2: Allergen-Profil (Glutenunvertraeglichkeit)
    ('ffffffff-0002-0002-0002-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Sabine', 'Winkler',
     'sabine.winkler@example.de', '+49 171 2345602',
     '1985-09-22',
     'Zoeliakie – nur glutenfreie Gerichte. Bevorzugt Terrasse bei gutem Wetter.',
     NOW(), NOW()),

    -- Stammgast 3: Allergen-Profil (Nuss-Allergie)
    ('ffffffff-0003-0003-0003-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Giovanni', 'Bianchi',
     'giovanni.bianchi@example.de', '+49 172 3456703',
     '1990-11-08',
     'Schwere Nuss-Allergie (Epipen). Immer Kueche informieren!',
     NOW(), NOW()),

    -- Stammgast 4: Geburtstag in naechsten 14 Tagen
    ('ffffffff-0004-0004-0004-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Anna', 'Schmidt',
     'anna.schmidt@example.de', '+49 173 4567804',
     (CURRENT_DATE + INTERVAL '5 days')::date - INTERVAL '32 years',
     NULL,
     NOW(), NOW()),

    -- Stammgast 5: Geburtstag in naechsten 14 Tagen
    ('ffffffff-0005-0005-0005-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Roberto', 'Conti',
     'roberto.conti@example.de', '+49 174 5678905',
     (CURRENT_DATE + INTERVAL '10 days')::date - INTERVAL '45 years',
     NULL,
     NOW(), NOW()),

    -- Stammgast 6: Besondere Notiz (Fensterplatz)
    ('ffffffff-0006-0006-0006-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Petra', 'Lange',
     'petra.lange@example.de', '+49 175 6789006',
     '1972-03-17',
     'Bevorzugt immer Fensterplatz (T3 oder T4). Kommt meist freitags zum Abendessen.',
     NOW(), NOW()),

    -- Stammgast 7: Besondere Notiz (Jahrestag)
    ('ffffffff-0007-0007-0007-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Klaus', 'Hoffmann',
     'klaus.hoffmann@example.de', '+49 176 7890107',
     '1968-07-30',
     'Feiert jeden Hochzeitstag hier (15. Juni). Immer Prosecco-Flasche bereitstellen.',
     NOW(), NOW()),

    -- Stammgast 8
    ('ffffffff-0008-0008-0008-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Elena', 'Russo',
     'elena.russo@example.de', '+49 177 8901208',
     '1995-01-12',
     NULL,
     NOW(), NOW()),

    -- Stammgast 9
    ('ffffffff-0009-0009-0009-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Michael', 'Weber',
     'michael.weber@example.de', '+49 178 9012309',
     '1982-08-25',
     NULL,
     NOW(), NOW()),

    -- Stammgast 10
    ('ffffffff-0010-0010-0010-ffffffffffff', '22222222-2222-2222-2222-222222222222',
     'Francesca', 'De Luca',
     'francesca.deluca@example.de', '+49 179 0123410',
     '1988-12-03',
     NULL,
     NOW(), NOW());

COMMIT;

-- ============================================================================
-- Verifizierung
-- ============================================================================
SELECT 'Restaurant' AS entity, COUNT(*) FROM restaurants WHERE id = '22222222-2222-2222-2222-222222222222'
UNION ALL SELECT 'Users',       COUNT(*) FROM users          WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
UNION ALL SELECT 'Areas',       COUNT(*) FROM areas          WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
UNION ALL SELECT 'Tables',      COUNT(*) FROM tables         WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
UNION ALL SELECT 'Categories',  COUNT(*) FROM menu_categories WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
UNION ALL SELECT 'Menu Items',  COUNT(*) FROM menu_items     WHERE tenant_id = '22222222-2222-2222-2222-222222222222'
UNION ALL SELECT 'Guests',      COUNT(*) FROM guests         WHERE tenant_id = '22222222-2222-2222-2222-222222222222';
