-- =============================================================================
-- Migration 001: Guest Portal, QR-Ordering, KDS Courses, Reviews, Waitlist Tracking
-- =============================================================================
-- Erweitert das Schema für:
--   Phase A: Guest Auth + Profil
--   Phase B: QR-Code-Bestellen (Table Tokens)
--   Phase C: KDS Gänge-Synchronisation
--   Phase E: Bewertungssystem
--   Phase F: Wartelisten-Live-Tracking
--   Phase J: Stripe Billing
-- =============================================================================

BEGIN;

-- ============================================================
-- Phase A: Guest Auth – guest_profiles erweitern
-- ============================================================

ALTER TABLE guest_profiles
    ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255),
    ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS email_verification_token VARCHAR(255),
    ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(255),
    ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ;

-- allergens + preferences existieren bereits in init.sql

CREATE INDEX IF NOT EXISTS idx_guest_profiles_verification_token
    ON guest_profiles(email_verification_token)
    WHERE email_verification_token IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_guest_profiles_password_reset
    ON guest_profiles(password_reset_token)
    WHERE password_reset_token IS NOT NULL;

-- ============================================================
-- Phase B: QR-Code-Bestellen – Table Tokens
-- ============================================================

ALTER TABLE tables
    ADD COLUMN IF NOT EXISTS table_token VARCHAR(64) UNIQUE,
    ADD COLUMN IF NOT EXISTS token_created_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_tables_token
    ON tables(table_token)
    WHERE table_token IS NOT NULL;

-- Order-Quelle: Staff vs. QR-Guest
DO $$ BEGIN
    CREATE TYPE order_source AS ENUM ('staff', 'qr_guest', 'guest_app');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE orders
    ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'staff',
    ADD COLUMN IF NOT EXISTS session_id VARCHAR(64),
    ADD COLUMN IF NOT EXISTS guest_profile_id UUID REFERENCES guest_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_orders_session_id
    ON orders(session_id)
    WHERE session_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_orders_guest_profile_id
    ON orders(guest_profile_id)
    WHERE guest_profile_id IS NOT NULL;

-- ============================================================
-- Phase C: KDS Gänge-Synchronisation
-- ============================================================

ALTER TABLE order_items
    ADD COLUMN IF NOT EXISTS course INTEGER NOT NULL DEFAULT 1,
    ADD COLUMN IF NOT EXISTS course_released_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_order_items_course
    ON order_items(order_id, course);

-- ============================================================
-- Phase E: Bewertungssystem
-- ============================================================

CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    reservation_id UUID REFERENCES reservations(id) ON DELETE SET NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    title VARCHAR(200),
    text TEXT,
    is_visible BOOLEAN NOT NULL DEFAULT TRUE,
    moderated_at TIMESTAMPTZ,
    moderated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Ein Gast kann pro Restaurant nur eine Bewertung abgeben
    UNIQUE(tenant_id, guest_profile_id)
);

CREATE INDEX IF NOT EXISTS idx_reviews_tenant_id ON reviews(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_guest_profile_id ON reviews(guest_profile_id);
CREATE INDEX IF NOT EXISTS idx_reviews_rating ON reviews(tenant_id, rating);
CREATE INDEX IF NOT EXISTS idx_reviews_visible ON reviews(tenant_id, is_visible)
    WHERE is_visible = TRUE;

-- ============================================================
-- Phase F: Wartelisten-Live-Tracking
-- ============================================================

ALTER TABLE waitlist
    ADD COLUMN IF NOT EXISTS tracking_token VARCHAR(64) UNIQUE,
    ADD COLUMN IF NOT EXISTS estimated_wait_minutes INTEGER,
    ADD COLUMN IF NOT EXISTS phone VARCHAR(32),
    ADD COLUMN IF NOT EXISTS guest_name VARCHAR(200);

CREATE INDEX IF NOT EXISTS idx_waitlist_tracking_token
    ON waitlist(tracking_token)
    WHERE tracking_token IS NOT NULL;

-- ============================================================
-- Phase J: Stripe Billing – Subscription-Erweiterungen
-- ============================================================

ALTER TABLE restaurants
    ADD COLUMN IF NOT EXISTS stripe_price_id VARCHAR(128),
    ADD COLUMN IF NOT EXISTS subscription_status VARCHAR(32) DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS subscription_current_period_end TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS billing_email VARCHAR(255);

-- ============================================================
-- Materialisierten View für Restaurant-Bewertungen (Performance)
-- ============================================================

CREATE OR REPLACE VIEW restaurant_ratings AS
SELECT
    r.tenant_id,
    COUNT(*) AS review_count,
    ROUND(AVG(r.rating)::numeric, 2) AS avg_rating,
    COUNT(*) FILTER (WHERE r.rating >= 4) AS positive_count,
    COUNT(*) FILTER (WHERE r.rating <= 2) AS negative_count
FROM reviews r
WHERE r.is_visible = TRUE
GROUP BY r.tenant_id;

-- ============================================================
-- RLS-Policies für neue Tabellen
-- ============================================================

ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY reviews_tenant_isolation ON reviews
    FOR ALL
    USING (
        tenant_id::text = current_setting('app.tenant_id', true)
        OR current_setting('app.user_role', true) IN ('platform_admin', 'platform_support')
    );

-- Reviews: Gäste dürfen eigene Reviews sehen/erstellen
CREATE POLICY reviews_guest_access ON reviews
    FOR SELECT
    USING (
        is_visible = TRUE
        OR guest_profile_id::text = current_setting('app.guest_profile_id', true)
    );

COMMIT;
