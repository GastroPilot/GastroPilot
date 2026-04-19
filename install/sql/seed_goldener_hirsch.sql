-- ============================================================================
-- GastroPilot Seed: Goldener Hirsch
-- Traditionelles deutsches Wirtshaus in Hamburg
--
-- Idempotent: kann mehrfach ausgeführt werden (DELETE + INSERT).
-- ============================================================================

BEGIN;

-- Feste IDs
DO $$ BEGIN
    PERFORM set_config('seed.tenant_id', '33333333-3333-3333-3333-333333333333', true);
END $$;

-- Tenant-Context setzen (RLS)
SELECT set_tenant_context(
    '33333333-3333-3333-3333-333333333333'::UUID,
    'owner'
);

-- ============================================================================
-- 1. Bestehende Daten löschen
-- ============================================================================

DO $$ BEGIN
    DELETE FROM order_items WHERE order_id IN (
        SELECT id FROM orders WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
    );
    DELETE FROM orders           WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM reservation_tables WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM reservations     WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM waitlist         WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM menu_items       WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM menu_categories  WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM guests           WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM tables           WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM areas            WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    DELETE FROM refresh_tokens   WHERE user_id IN (
        SELECT id FROM users WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
    );
    DELETE FROM users            WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
    BEGIN DELETE FROM reviews WHERE tenant_id = '33333333-3333-3333-3333-333333333333'; EXCEPTION WHEN undefined_table THEN NULL; END;
    DELETE FROM restaurants      WHERE id = '33333333-3333-3333-3333-333333333333';
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
    '33333333-3333-3333-3333-333333333333',
    'Goldener Hirsch',
    'goldener-hirsch',
    'Traditionelles deutsches Wirtshaus in Hamburg-Altona. Deftige Hausmannskost, frisch gezapftes Bier und norddeutsche Gemütlichkeit.',
    'Große Elbstraße 78, 22767 Hamburg',
    '+49 40 555 0078',
    'info@goldener-hirsch.gpilot.app',
    'starter',
    false,
    '{"currency": "EUR", "timezone": "Europe/Berlin", "language": "de", "tax_rate": 0.19}'::jsonb,
    true,
    3,
    20,
    90,
    '{
        "monday":    null,
        "tuesday":   {"open": "11:00", "close": "23:00"},
        "wednesday": {"open": "11:00", "close": "23:00"},
        "thursday":  {"open": "11:00", "close": "23:00"},
        "friday":    {"open": "11:00", "close": "00:00"},
        "saturday":  {"open": "10:00", "close": "00:00"},
        "sunday":    {"open": "10:00", "close": "22:00"}
    }'::jsonb,
    NOW(),
    NOW()
);

-- ============================================================================
-- 3. Staff-Accounts
-- Passwort: Test2026!
-- bcrypt hash (rounds=10): $2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy
-- ============================================================================

INSERT INTO users (id, tenant_id, email, password_hash, first_name, last_name, role, auth_method, is_active, created_at, updated_at) VALUES
    ('aa333333-0001-0001-0001-aa3333333333', '33333333-3333-3333-3333-333333333333', 'hans@goldener-hirsch.gpilot.app',    '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Hans',     'Brauer',     'owner',   'password', true, NOW(), NOW()),
    ('aa333333-0002-0002-0002-aa3333333333', '33333333-3333-3333-3333-333333333333', 'katrin@goldener-hirsch.gpilot.app',  '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Katrin',   'Schreiber',  'manager', 'password', true, NOW(), NOW()),
    ('aa333333-0003-0003-0003-aa3333333333', '33333333-3333-3333-3333-333333333333', 'jan@goldener-hirsch.gpilot.app',     '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Jan',      'Peters',     'staff',   'password', true, NOW(), NOW()),
    ('aa333333-0004-0004-0004-aa3333333333', '33333333-3333-3333-3333-333333333333', 'murat@goldener-hirsch.gpilot.app',   '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Murat',    'Yilmaz',     'kitchen', 'password', true, NOW(), NOW()),
    ('aa333333-0005-0005-0005-aa3333333333', '33333333-3333-3333-3333-333333333333', 'lisa@goldener-hirsch.gpilot.app',    '$2b$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'Lisa',     'Krause',     'staff',   'password', true, NOW(), NOW());

-- ============================================================================
-- 4. Zonen
-- ============================================================================

INSERT INTO areas (id, tenant_id, name, created_at) VALUES
    ('bb333333-0001-0001-0001-bb3333333333', '33333333-3333-3333-3333-333333333333', 'Innenbereich', NOW()),
    ('bb333333-0002-0002-0002-bb3333333333', '33333333-3333-3333-3333-333333333333', 'Terrasse', NOW());

-- ============================================================================
-- 5. Tische (15 Stueck in 2 Zonen)
-- ============================================================================

-- Innenbereich (9 Tische)
INSERT INTO tables (
    id, tenant_id, area_id, number, capacity, position_x, position_y,
    width, height, shape, rotation, is_active, is_outdoor, created_at, updated_at
) VALUES
    ('cc333333-0001-0001-0001-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Stammtisch', 6, 953, 271, 162, 114, 'rectangle',  38,   true, false, NOW(), NOW()),
    ('cc333333-0002-0002-0002-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 1',    4, 335,  71, 143, 120, 'rectangle',   0,   true, false, NOW(), NOW()),
    ('cc333333-0003-0003-0003-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 2',    4, 527,  71, 148, 120, 'rectangle', -360,  true, false, NOW(), NOW()),
    ('cc333333-0004-0004-0004-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 3',    4, 335, 214, 143, 129, 'rectangle',   0,   true, false, NOW(), NOW()),
    ('cc333333-0005-0005-0005-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 4',    4, 527, 214, 148, 129, 'rectangle',   0,   true, false, NOW(), NOW()),
    ('cc333333-0006-0006-0006-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 5',    4, 740,  71, 155, 120, 'rectangle', -720,  true, false, NOW(), NOW()),
    ('cc333333-0007-0007-0007-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 6',    4, 740, 214, 155, 114, 'rectangle',   0,   true, false, NOW(), NOW()),
    ('cc333333-0008-0008-0008-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 7',    4, 953,  71, 162, 120, 'rectangle',   0,   true, false, NOW(), NOW()),
    ('cc333333-0009-0009-0009-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0001-0001-0001-bb3333333333', 'Tisch 8',    4, 740, 385, 155, 121, 'rectangle',   0,   true, false, NOW(), NOW());

-- Terrasse (6 Tische)
INSERT INTO tables (
    id, tenant_id, area_id, number, capacity, position_x, position_y,
    width, height, shape, rotation, is_active, is_outdoor, created_at, updated_at
) VALUES
    ('cc333333-0010-0010-0010-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0002-0002-0002-bb3333333333', 'Tisch 11', 4,  74,  46, 140, 130, 'rectangle', 0, true, false, NOW(), NOW()),
    ('cc333333-0011-0011-0011-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0002-0002-0002-bb3333333333', 'Tisch 12', 4, 240,  46, 140, 130, 'rectangle', 0, true, false, NOW(), NOW()),
    ('cc333333-0012-0012-0012-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0002-0002-0002-bb3333333333', 'Tisch 13', 4,  74, 221, 140, 130, 'rectangle', 0, true, false, NOW(), NOW()),
    ('cc333333-0013-0013-0013-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0002-0002-0002-bb3333333333', 'Tisch 14', 4, 240, 221, 140, 130, 'rectangle', 0, true, false, NOW(), NOW()),
    ('cc333333-0014-0014-0014-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0002-0002-0002-bb3333333333', 'Tisch 15', 4, 466,  46, 140, 130, 'rectangle', 0, true, false, NOW(), NOW()),
    ('cc333333-0015-0015-0015-cc3333333333', '33333333-3333-3333-3333-333333333333', 'bb333333-0002-0002-0002-bb3333333333', 'Tisch 16', 4, 466, 221, 140, 130, 'rectangle', 0, true, false, NOW(), NOW());

-- ============================================================================
-- 6. Speisekarte — Kategorien
-- ============================================================================

INSERT INTO menu_categories (id, tenant_id, name, description, sort_order, is_active, created_at, updated_at) VALUES
    ('dd333333-0001-0001-0001-dd3333333333', '33333333-3333-3333-3333-333333333333', 'Suppen',       'Hausgemachte Suppen',                          1, true, NOW(), NOW()),
    ('dd333333-0002-0002-0002-dd3333333333', '33333333-3333-3333-3333-333333333333', 'Vorspeisen',   'Kalte und warme Vorspeisen',                   2, true, NOW(), NOW()),
    ('dd333333-0003-0003-0003-dd3333333333', '33333333-3333-3333-3333-333333333333', 'Hauptgerichte','Deftige Hausmannskost',                        3, true, NOW(), NOW()),
    ('dd333333-0004-0004-0004-dd3333333333', '33333333-3333-3333-3333-333333333333', 'Vom Grill',    'Frisch vom Holzkohlegrill',                    4, true, NOW(), NOW()),
    ('dd333333-0005-0005-0005-dd3333333333', '33333333-3333-3333-3333-333333333333', 'Desserts',     'Süßes zum Abschluss',                         5, true, NOW(), NOW()),
    ('dd333333-0006-0006-0006-dd3333333333', '33333333-3333-3333-3333-333333333333', 'Getränke',     'Bier, Wein und alkoholfreie Getränke',         6, true, NOW(), NOW());

-- ============================================================================
-- 7. Speisekarte — Items
-- ============================================================================

-- Suppen (3)
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('ee333333-0101-0101-0101-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0001-0001-0001-dd3333333333',
     'Hamburger Aalsuppe', 'Nach traditionellem Rezept mit Backobst und Gemüse', 8.90, 0.19, true, 1,
     '{"contains": ["fisch", "sellerie"], "may_contain": ["gluten"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0102-0102-0102-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0001-0001-0001-dd3333333333',
     'Kartoffelsuppe', 'Cremige Kartoffelsuppe mit Würstcheneinlage und Schnittlauch', 7.50, 0.19, true, 2,
     '{"contains": ["sellerie"], "may_contain": ["milch"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0103-0103-0103-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0001-0001-0001-dd3333333333',
     'Gulaschsuppe', 'Kräftige Rindergulaschsuppe mit Paprika und Brot', 9.50, 0.19, true, 3,
     '{"contains": ["gluten", "sellerie"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW());

-- Vorspeisen (4)
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('ee333333-0201-0201-0201-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0002-0002-0002-dd3333333333',
     'Matjes Hausfrauenart', 'Nordseematjes mit Zwiebeln, Äpfeln und Sahnesauce', 11.90, 0.19, true, 1,
     '{"contains": ["fisch", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0202-0202-0202-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0002-0002-0002-dd3333333333',
     'Flammkuchen Elsässer Art', 'Dünn und knusprig mit Crème fraîche, Speck und Zwiebeln', 10.90, 0.19, true, 2,
     '{"contains": ["gluten", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0203-0203-0203-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0002-0002-0002-dd3333333333',
     'Obatzda mit Brezel', 'Bayerischer Käseaufstrich mit Butter, Paprika und frischer Brezel', 9.90, 0.19, true, 3,
     '{"contains": ["gluten", "milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0204-0204-0204-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0002-0002-0002-dd3333333333',
     'Gemischter Salat', 'Saisonaler Salat mit Hausdressing', 7.90, 0.19, true, 4,
     '{"contains": ["senf"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- Hauptgerichte (8)
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('ee333333-0301-0301-0301-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Schnitzel Wiener Art', 'Paniertes Schweineschnitzel mit Pommes und Preiselbeeren', 16.90, 0.19, true, 1,
     '{"contains": ["gluten", "ei"], "may_contain": ["milch"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0302-0302-0302-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Jägerschnitzel', 'Schweineschnitzel mit Champignon-Rahmsauce und Spätzle', 17.90, 0.19, true, 2,
     '{"contains": ["gluten", "ei", "milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0303-0303-0303-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Labskaus', 'Hamburger Klassiker mit Corned Beef, Roter Bete, Spiegelei und Rollmops', 15.90, 0.19, true, 3,
     '{"contains": ["ei", "fisch"], "may_contain": ["sellerie", "senf"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0304-0304-0304-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Königsberger Klopse', 'Fleischklöße in Kapernsauce mit Kartoffeln und Rote Bete', 16.50, 0.19, true, 4,
     '{"contains": ["gluten", "ei", "milch"], "may_contain": ["sellerie"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0305-0305-0305-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Rinderroulade', 'Geschmorte Rinderroulade mit Rotkohl und Kartoffelklößen', 21.90, 0.19, true, 5,
     '{"contains": ["gluten", "sellerie", "senf"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0306-0306-0306-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Sauerbraten', 'Rheinischer Sauerbraten mit Rosinen-Sauce und Klößen', 22.90, 0.19, true, 6,
     '{"contains": ["gluten", "schwefeldioxid"], "may_contain": ["sellerie"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0307-0307-0307-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Backfisch mit Kartoffelsalat', 'Knusprig panierter Kabeljau mit norddeutschem Kartoffelsalat', 17.90, 0.19, true, 7,
     '{"contains": ["gluten", "fisch", "ei"], "may_contain": ["senf"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0308-0308-0308-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0003-0003-0003-dd3333333333',
     'Käsespätzle', 'Handgeschabte Spätzle mit Bergkäse und Röstzwiebeln', 14.90, 0.19, true, 8,
     '{"contains": ["gluten", "ei", "milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- Vom Grill (4)
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('ee333333-0401-0401-0401-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0004-0004-0004-dd3333333333',
     'Rumpsteak (250g)', 'Vom Holzkohlegrill mit Kräuterbutter, Pommes und Salat', 26.90, 0.19, true, 1,
     '{"contains": ["milch"], "may_contain": [], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0402-0402-0402-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0004-0004-0004-dd3333333333',
     'Bratwurst (2 Stück)', 'Thüringer Rostbratwurst mit Sauerkraut und Kartoffelpüree', 13.90, 0.19, true, 2,
     '{"contains": ["gluten", "milch"], "may_contain": ["sellerie", "senf"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0403-0403-0403-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0004-0004-0004-dd3333333333',
     'Spareribs (400g)', 'Marinierte Rippchen mit BBQ-Sauce, Coleslaw und Maiskolben', 19.90, 0.19, true, 3,
     '{"contains": ["gluten", "senf", "soja"], "may_contain": ["sellerie"], "vegan": false, "vegetarisch": false}'::jsonb, NOW(), NOW()),

    ('ee333333-0404-0404-0404-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0004-0004-0004-dd3333333333',
     'Grillkäse mit Ofenkartoffel', 'Halloumi vom Grill mit Kräuterquark und Salat', 14.90, 0.19, true, 4,
     '{"contains": ["milch"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- Desserts (4)
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('ee333333-0501-0501-0501-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0005-0005-0005-dd3333333333',
     'Rote Grütze', 'Norddeutsche Rote Grütze mit Vanillesauce', 6.90, 0.19, true, 1,
     '{"contains": ["milch"], "may_contain": ["gluten"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0502-0502-0502-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0005-0005-0005-dd3333333333',
     'Warmer Apfelstrudel', 'Mit Vanilleeis und Sahne', 7.90, 0.19, true, 2,
     '{"contains": ["gluten", "milch", "ei"], "may_contain": ["nüsse"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0503-0503-0503-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0005-0005-0005-dd3333333333',
     'Franzbrötchen', 'Warmes Hamburger Franzbrötchen mit Zimtzucker und Eis', 6.50, 0.19, true, 3,
     '{"contains": ["gluten", "milch", "ei"], "may_contain": [], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0504-0504-0504-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0005-0005-0005-dd3333333333',
     'Schokoladenkuchen', 'Warmer Schokoladenkuchen mit flüssigem Kern', 7.50, 0.19, true, 4,
     '{"contains": ["gluten", "milch", "ei"], "may_contain": ["nüsse", "soja"], "vegan": false, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- Getränke (10)
INSERT INTO menu_items (id, tenant_id, category_id, name, description, price, tax_rate, is_available, sort_order, allergens, created_at, updated_at) VALUES
    ('ee333333-0601-0601-0601-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Astra Urtyp 0,5l', 'Hamburgs Bier vom Fass', 4.90, 0.19, true, 1,
     '{"contains": ["gluten"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0602-0602-0602-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Flensburger Pilsener 0,33l', 'Plop!', 4.50, 0.19, true, 2,
     '{"contains": ["gluten"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0603-0603-0603-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Alsterwasser 0,5l', 'Bier-Limo-Mischung', 4.90, 0.19, true, 3,
     '{"contains": ["gluten"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0604-0604-0604-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Weißwein Grauburgunder 0,2l', 'Aus der Pfalz', 6.50, 0.19, true, 4,
     '{"contains": ["schwefeldioxid"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0605-0605-0605-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Rotwein Spätburgunder 0,2l', 'Aus Baden', 6.90, 0.19, true, 5,
     '{"contains": ["schwefeldioxid"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0606-0606-0606-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Apfelschorle 0,4l', NULL, 3.90, 0.19, true, 6,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0607-0607-0607-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Coca-Cola 0,33l', NULL, 3.90, 0.19, true, 7,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0608-0608-0608-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Mineralwasser 0,5l', 'Still oder mit Kohlensäure', 3.50, 0.19, true, 8,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0609-0609-0609-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Kaffee', 'Frisch aufgebrüht', 2.90, 0.19, true, 9,
     '{"contains": [], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW()),

    ('ee333333-0610-0610-0610-ee3333333333', '33333333-3333-3333-3333-333333333333', 'dd333333-0006-0006-0006-dd3333333333',
     'Lüttje Lage', 'Braunschweiger Tradition – Schankbier mit Kornbrand', 5.90, 0.19, true, 10,
     '{"contains": ["gluten"], "may_contain": [], "vegan": true, "vegetarisch": true}'::jsonb, NOW(), NOW());

-- ============================================================================
-- 8. Stammgäste (8)
-- ============================================================================

INSERT INTO guests (id, tenant_id, first_name, last_name, email, phone, birthday, notes, created_at, updated_at) VALUES
    ('ff333333-0001-0001-0001-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Jürgen', 'Meier', 'juergen.meier@example.de', '+49 160 1110001',
     '1965-04-22', 'Stammgast seit Eröffnung. Trinkt nur Astra. Immer Tisch 1.',
     NOW(), NOW()),

    ('ff333333-0002-0002-0002-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Brigitte', 'Hansen', 'brigitte.hansen@example.de', '+49 161 2220002',
     '1958-11-30', 'Laktoseintoleranz. Kommt immer mit Ehemann (Tisch für 2).',
     NOW(), NOW()),

    ('ff333333-0003-0003-0003-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Özkan', 'Demir', 'oezkan.demir@example.de', '+49 162 3330003',
     '1980-07-14', 'Isst kein Schwein. Grill-Gerichte immer mit Rind.',
     NOW(), NOW()),

    ('ff333333-0004-0004-0004-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Heike', 'Wulf', 'heike.wulf@example.de', '+49 163 4440004',
     (CURRENT_DATE + INTERVAL '3 days')::date - INTERVAL '50 years',
     NULL, NOW(), NOW()),

    ('ff333333-0005-0005-0005-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Torsten', 'Nissen', 'torsten.nissen@example.de', '+49 164 5550005',
     (CURRENT_DATE + INTERVAL '8 days')::date - INTERVAL '38 years',
     NULL, NOW(), NOW()),

    ('ff333333-0006-0006-0006-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Anja', 'Berger', 'anja.berger@example.de', '+49 165 6660006',
     '1992-02-28', 'Glutenunverträglichkeit.',
     NOW(), NOW()),

    ('ff333333-0007-0007-0007-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Wolfgang', 'Struck', 'wolfgang.struck@example.de', '+49 166 7770007',
     '1955-09-10', 'Reserviert jeden Freitag Nebenzimmer N1 für Skatrunde (8 Personen).',
     NOW(), NOW()),

    ('ff333333-0008-0008-0008-ff3333333333', '33333333-3333-3333-3333-333333333333',
     'Svenja', 'Thomsen', 'svenja.thomsen@example.de', '+49 167 8880008',
     '1998-06-05', NULL,
     NOW(), NOW());

COMMIT;

-- Verifizierung
SELECT 'Restaurant' AS entity, COUNT(*) FROM restaurants WHERE id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'Users',       COUNT(*) FROM users          WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'Areas',       COUNT(*) FROM areas          WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'Tables',      COUNT(*) FROM tables         WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'Categories',  COUNT(*) FROM menu_categories WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'Menu Items',  COUNT(*) FROM menu_items     WHERE tenant_id = '33333333-3333-3333-3333-333333333333'
UNION ALL SELECT 'Guests',      COUNT(*) FROM guests         WHERE tenant_id = '33333333-3333-3333-3333-333333333333';
