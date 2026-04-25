-- =============================================================================
-- GastroPilot Demo DB — Konsolidiertes Schema
-- Vereint: init.sql + migrations 001-009 + rls.sql + Staging-Spalten
-- Komplett idempotent (IF NOT EXISTS / IF EXISTS überall)
-- =============================================================================

BEGIN;

-- ============================================================
-- EXTENSIONS
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================
DO $$ BEGIN CREATE TYPE user_role AS ENUM ('guest','owner','manager','staff','kitchen','platform_admin','platform_support','platform_analyst'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE subscription_tier AS ENUM ('free','starter','professional','enterprise'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE payment_provider AS ENUM ('stripe','sumup','both'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE reservation_status AS ENUM ('pending','confirmed','seated','completed','canceled','no_show'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE order_status AS ENUM ('open','sent_to_kitchen','in_preparation','ready','served','paid','canceled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE order_item_status AS ENUM ('pending','sent','in_preparation','ready','served','canceled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE payment_status AS ENUM ('unpaid','partial','paid'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE auth_method AS ENUM ('pin','password'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE order_source AS ENUM ('staff','qr_guest','guest_app'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- TABLES (CREATE IF NOT EXISTS)
-- ============================================================

CREATE TABLE IF NOT EXISTS restaurants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(100) UNIQUE,
    address VARCHAR(500),
    phone VARCHAR(50),
    email VARCHAR(255),
    description TEXT,
    subscription_tier subscription_tier NOT NULL DEFAULT 'starter',
    is_suspended BOOLEAN NOT NULL DEFAULT FALSE,
    suspended_reason TEXT,
    suspended_at TIMESTAMPTZ,
    payment_provider payment_provider NOT NULL DEFAULT 'sumup',
    stripe_customer_id VARCHAR(128),
    stripe_subscription_id VARCHAR(128),
    sumup_merchant_code VARCHAR(32),
    sumup_api_key VARCHAR(255),
    sumup_default_reader_id VARCHAR(64),
    stripe_price_id VARCHAR(128),
    subscription_status VARCHAR(32) DEFAULT 'active',
    subscription_current_period_end TIMESTAMPTZ,
    billing_email VARCHAR(255),
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    featured_until TIMESTAMPTZ,
    public_booking_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    booking_lead_time_hours INTEGER NOT NULL DEFAULT 2,
    booking_max_party_size INTEGER NOT NULL DEFAULT 12,
    booking_default_duration INTEGER NOT NULL DEFAULT 120,
    opening_hours JSONB,
    settings JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS guest_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(32),
    first_name VARCHAR(120) NOT NULL,
    last_name VARCHAR(120) NOT NULL,
    language VARCHAR(10) DEFAULT 'de',
    birthday DATE,
    company VARCHAR(200),
    notes TEXT,
    allergens JSONB DEFAULT '[]',
    preferences JSONB DEFAULT '{}',
    password_hash VARCHAR(255),
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    email_verification_token VARCHAR(255),
    password_reset_token VARCHAR(255),
    password_reset_expires_at TIMESTAMPTZ,
    push_token TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
    email VARCHAR(255),
    password_hash VARCHAR(255),
    pin_hash VARCHAR(255),
    operator_number VARCHAR(4),
    nfc_tag_id VARCHAR(64) UNIQUE,
    first_name VARCHAR(120) NOT NULL,
    last_name VARCHAR(120) NOT NULL,
    role user_role NOT NULL DEFAULT 'staff',
    auth_method auth_method NOT NULL DEFAULT 'pin',
    guest_profile_id UUID REFERENCES guest_profiles(id) ON DELETE SET NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    rotated_from_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_settings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    settings JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS platform_audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    admin_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_tenant_id UUID REFERENCES restaurants(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id UUID,
    description TEXT,
    details JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS areas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, name)
);

CREATE TABLE IF NOT EXISTS tables (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    area_id UUID REFERENCES areas(id) ON DELETE SET NULL,
    number VARCHAR(50) NOT NULL,
    capacity INTEGER NOT NULL,
    shape VARCHAR(20) DEFAULT 'rectangle',
    position_x FLOAT,
    position_y FLOAT,
    width FLOAT DEFAULT 120.0,
    height FLOAT DEFAULT 120.0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_joinable BOOLEAN NOT NULL DEFAULT FALSE,
    join_group_id INTEGER,
    is_outdoor BOOLEAN NOT NULL DEFAULT FALSE,
    rotation INTEGER,
    notes TEXT,
    table_token VARCHAR(64) UNIQUE,
    token_created_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS table_day_configs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    table_id UUID REFERENCES tables(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    is_hidden BOOLEAN NOT NULL DEFAULT FALSE,
    is_temporary BOOLEAN NOT NULL DEFAULT FALSE,
    number VARCHAR(50),
    capacity INTEGER,
    shape VARCHAR(20),
    position_x FLOAT,
    position_y FLOAT,
    width FLOAT,
    height FLOAT,
    is_active BOOLEAN,
    color VARCHAR(16),
    join_group_id INTEGER,
    is_joinable BOOLEAN,
    rotation INTEGER,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, table_id, date)
);

CREATE TABLE IF NOT EXISTS obstacles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    area_id UUID REFERENCES areas(id) ON DELETE SET NULL,
    type VARCHAR(32) NOT NULL,
    name VARCHAR(120),
    x INTEGER NOT NULL,
    y INTEGER NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    rotation INTEGER,
    blocking BOOLEAN NOT NULL DEFAULT TRUE,
    color VARCHAR(16),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS guests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    guest_profile_id UUID REFERENCES guest_profiles(id) ON DELETE SET NULL,
    first_name VARCHAR(120) NOT NULL,
    last_name VARCHAR(120) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(32),
    language VARCHAR(10),
    birthday TIMESTAMPTZ,
    company VARCHAR(200),
    type VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    guest_id UUID REFERENCES guests(id) ON DELETE SET NULL,
    table_id UUID REFERENCES tables(id) ON DELETE SET NULL,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    party_size INTEGER NOT NULL,
    status reservation_status NOT NULL DEFAULT 'pending',
    channel VARCHAR(32) NOT NULL DEFAULT 'manual',
    guest_name VARCHAR(240),
    guest_email VARCHAR(255),
    guest_phone VARCHAR(32),
    confirmation_code VARCHAR(64),
    notes TEXT,
    tags JSONB DEFAULT '[]',
    confirmed_at TIMESTAMPTZ,
    seated_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    canceled_at TIMESTAMPTZ,
    canceled_reason TEXT,
    no_show_at TIMESTAMPTZ,
    reminder_sent BOOLEAN DEFAULT FALSE,
    confirmation_sent BOOLEAN DEFAULT FALSE,
    source TEXT DEFAULT 'manual',
    external_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reservation_tables (
    reservation_id UUID REFERENCES reservations(id) ON DELETE CASCADE,
    table_id UUID REFERENCES tables(id) ON DELETE RESTRICT,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (reservation_id, table_id)
);

CREATE TABLE IF NOT EXISTS blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    reason TEXT,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS block_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    block_id UUID NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    table_id UUID NOT NULL REFERENCES tables(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(block_id, table_id)
);

CREATE TABLE IF NOT EXISTS waitlist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    guest_id UUID REFERENCES guests(id) ON DELETE CASCADE,
    party_size INTEGER NOT NULL,
    desired_from TIMESTAMPTZ,
    desired_to TIMESTAMPTZ,
    status VARCHAR(24) NOT NULL DEFAULT 'waiting',
    priority INTEGER,
    notified_at TIMESTAMPTZ,
    confirmed_at TIMESTAMPTZ,
    notes TEXT,
    tracking_token VARCHAR(64) UNIQUE,
    estimated_wait_minutes INTEGER,
    phone VARCHAR(32),
    guest_name VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS menu_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    category_id UUID REFERENCES menu_categories(id) ON DELETE SET NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price FLOAT NOT NULL,
    tax_rate FLOAT NOT NULL DEFAULT 0.19,
    is_available BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER DEFAULT 0,
    allergens JSONB DEFAULT '[]',
    modifiers JSONB,
    ingredients JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    table_id UUID REFERENCES tables(id) ON DELETE SET NULL,
    guest_id UUID REFERENCES guests(id) ON DELETE SET NULL,
    reservation_id UUID REFERENCES reservations(id) ON DELETE SET NULL,
    order_number VARCHAR(64) UNIQUE,
    status order_status NOT NULL DEFAULT 'open',
    party_size INTEGER,
    subtotal FLOAT NOT NULL DEFAULT 0.0,
    tax_amount_7 FLOAT NOT NULL DEFAULT 0.0,
    tax_amount_19 FLOAT NOT NULL DEFAULT 0.0,
    tax_amount FLOAT NOT NULL DEFAULT 0.0,
    discount_amount FLOAT NOT NULL DEFAULT 0.0,
    discount_percentage FLOAT,
    discount_reason TEXT,
    tip_amount FLOAT NOT NULL DEFAULT 0.0,
    total FLOAT NOT NULL DEFAULT 0.0,
    payment_method VARCHAR(32),
    payment_status payment_status NOT NULL DEFAULT 'unpaid',
    split_payments JSONB,
    notes TEXT,
    special_requests TEXT,
    opened_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_to_kitchen_at TIMESTAMPTZ,
    in_preparation_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    ready_at TIMESTAMPTZ,
    served_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancelled_reason TEXT,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    source VARCHAR(20) DEFAULT 'staff',
    session_id VARCHAR(64),
    guest_profile_id UUID REFERENCES guest_profiles(id) ON DELETE SET NULL,
    guest_allergens JSONB,
    guest_count INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id UUID REFERENCES menu_items(id) ON DELETE SET NULL,
    item_name VARCHAR(200) NOT NULL,
    item_description TEXT,
    category VARCHAR(100),
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price FLOAT NOT NULL,
    total_price FLOAT NOT NULL,
    tax_rate FLOAT NOT NULL DEFAULT 0.19,
    status order_item_status NOT NULL DEFAULT 'pending',
    notes TEXT,
    sort_order INTEGER DEFAULT 0,
    course INTEGER NOT NULL DEFAULT 1,
    course_released_at TIMESTAMPTZ,
    allergens JSONB,
    sent_to_kitchen BOOLEAN DEFAULT FALSE,
    sent_at TIMESTAMPTZ,
    ready_at TIMESTAMPTZ,
    served_at TIMESTAMPTZ,
    special_requests TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sumup_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    checkout_id VARCHAR(128),
    client_transaction_id VARCHAR(128),
    transaction_code VARCHAR(64),
    transaction_id VARCHAR(128),
    reader_id VARCHAR(64),
    amount FLOAT NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'EUR',
    status VARCHAR(32) NOT NULL DEFAULT 'pending',
    webhook_data JSONB,
    initiated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reservation_table_day_configs (
    reservation_id UUID REFERENCES reservations(id) ON DELETE CASCADE,
    table_day_config_id UUID REFERENCES table_day_configs(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (reservation_id, table_day_config_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    reservation_id UUID REFERENCES reservations(id) ON DELETE SET NULL,
    guest_id UUID REFERENCES guests(id) ON DELETE SET NULL,
    direction VARCHAR(32) NOT NULL,
    channel VARCHAR(32) NOT NULL,
    address VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'queued',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    entity_type VARCHAR(50) NOT NULL,
    entity_id UUID,
    action VARCHAR(32) NOT NULL,
    description TEXT,
    details JSONB,
    ip_address VARCHAR(45),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    reservation_id UUID REFERENCES reservations(id) ON DELETE SET NULL,
    rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
    title VARCHAR(200),
    text TEXT,
    is_visible BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    staff_reply TEXT,
    staff_reply_at TIMESTAMPTZ,
    staff_reply_by UUID REFERENCES users(id) ON DELETE SET NULL,
    moderated_at TIMESTAMPTZ,
    moderated_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, guest_profile_id)
);

CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    station VARCHAR(50) DEFAULT 'alle',
    device_token VARCHAR(128) NOT NULL UNIQUE,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS guest_favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(guest_profile_id, restaurant_id)
);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_profile_id UUID REFERENCES guest_profiles(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES restaurants(id) ON DELETE SET NULL,
    type VARCHAR(64) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ADD MISSING COLUMNS (idempotent for existing tables)
-- ============================================================

-- restaurants
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS stripe_price_id VARCHAR(128);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_status VARCHAR(32) DEFAULT 'active';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_current_period_end TIMESTAMPTZ;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS billing_email VARCHAR(255);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_tier subscription_tier NOT NULL DEFAULT 'starter';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS suspended_reason TEXT;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS featured_until TIMESTAMPTZ;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR(128);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS stripe_subscription_id VARCHAR(128);

-- guest_profiles
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS email_verification_token VARCHAR(255);
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS password_reset_token VARCHAR(255);
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS password_reset_expires_at TIMESTAMPTZ;
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS push_token TEXT;

-- tables
ALTER TABLE tables ADD COLUMN IF NOT EXISTS table_token VARCHAR(64);
ALTER TABLE tables ADD COLUMN IF NOT EXISTS token_created_at TIMESTAMPTZ;
ALTER TABLE tables ADD COLUMN IF NOT EXISTS qr_code_url TEXT;

-- orders
ALTER TABLE orders ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'staff';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS session_id VARCHAR(64);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS guest_profile_id UUID;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS guest_allergens JSONB;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS guest_count INTEGER;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS discount_reason TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancelled_reason TEXT;

-- order_items
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS course INTEGER DEFAULT 1;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS course_released_at TIMESTAMPTZ;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS allergens JSONB;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS sent_to_kitchen BOOLEAN DEFAULT FALSE;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS ready_at TIMESTAMPTZ;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS served_at TIMESTAMPTZ;
ALTER TABLE order_items ADD COLUMN IF NOT EXISTS special_requests TEXT;

-- waitlist
ALTER TABLE waitlist ADD COLUMN IF NOT EXISTS tracking_token VARCHAR(64);
ALTER TABLE waitlist ADD COLUMN IF NOT EXISTS estimated_wait_minutes INTEGER;
ALTER TABLE waitlist ADD COLUMN IF NOT EXISTS phone VARCHAR(32);
ALTER TABLE waitlist ADD COLUMN IF NOT EXISTS guest_name VARCHAR(200);

-- reservations
ALTER TABLE reservations ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE reservations ADD COLUMN IF NOT EXISTS confirmation_sent BOOLEAN DEFAULT FALSE;
ALTER TABLE reservations ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual';
ALTER TABLE reservations ADD COLUMN IF NOT EXISTS external_id TEXT;
ALTER TABLE reservations ADD COLUMN IF NOT EXISTS canceled_reason TEXT;

-- reviews
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS staff_reply TEXT;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS staff_reply_at TIMESTAMPTZ;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS staff_reply_by UUID;

-- devices
ALTER TABLE devices ADD COLUMN IF NOT EXISTS station VARCHAR(50) DEFAULT 'alle';

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_restaurants_slug ON restaurants(slug);
CREATE INDEX IF NOT EXISTS idx_guest_profiles_email ON guest_profiles(email);
CREATE INDEX IF NOT EXISTS idx_guest_profiles_phone ON guest_profiles(phone);
CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_areas_tenant_id ON areas(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tables_tenant_id ON tables(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tables_area_id ON tables(area_id);
CREATE INDEX IF NOT EXISTS idx_table_day_configs_tenant_id ON table_day_configs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_table_day_configs_date ON table_day_configs(date);
CREATE INDEX IF NOT EXISTS idx_obstacles_tenant_id ON obstacles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_guests_tenant_id ON guests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reservations_tenant_id ON reservations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reservations_start_at ON reservations(start_at);
CREATE INDEX IF NOT EXISTS idx_reservations_status ON reservations(status);
CREATE INDEX IF NOT EXISTS idx_reservation_tables_tenant_id ON reservation_tables(tenant_id);
CREATE INDEX IF NOT EXISTS idx_blocks_tenant_id ON blocks(tenant_id);
CREATE INDEX IF NOT EXISTS idx_block_assignments_tenant_id ON block_assignments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_waitlist_tenant_id ON waitlist(tenant_id);
CREATE INDEX IF NOT EXISTS idx_menu_categories_tenant_id ON menu_categories(tenant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_tenant_id ON menu_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_category_id ON menu_items(category_id);
CREATE INDEX IF NOT EXISTS idx_orders_tenant_id ON orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_opened_at ON orders(opened_at);
CREATE INDEX IF NOT EXISTS idx_orders_table_id ON orders(table_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_menu_item_id ON order_items(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_order_items_course ON order_items(order_id, course);
CREATE INDEX IF NOT EXISTS idx_sumup_payments_tenant_id ON sumup_payments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sumup_payments_order_id ON sumup_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_reservation_table_day_configs_tenant_id ON reservation_table_day_configs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_messages_tenant_id ON messages(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_id ON audit_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_reviews_tenant_id ON reviews(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_guest_profile_id ON reviews(guest_profile_id);
CREATE INDEX IF NOT EXISTS idx_devices_tenant ON devices(tenant_id);
CREATE INDEX IF NOT EXISTS idx_devices_token ON devices(device_token);
CREATE INDEX IF NOT EXISTS idx_notifications_guest_profile_id ON notifications(guest_profile_id);

-- ============================================================
-- HELPER FUNCTIONS (RLS)
-- ============================================================

CREATE OR REPLACE FUNCTION current_tenant_id() RETURNS UUID AS $$
BEGIN
    RETURN current_setting('app.current_tenant', true)::UUID;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

CREATE OR REPLACE FUNCTION set_tenant_context(p_tenant_id UUID, p_role TEXT)
RETURNS VOID AS $$
BEGIN
    PERFORM set_config('app.current_tenant', p_tenant_id::TEXT, true);
    PERFORM set_config('app.current_role', p_role, true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_current_role() RETURNS TEXT AS $$
BEGIN
    RETURN current_setting('app.current_role', true);
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- ENABLE RLS
-- ============================================================

ALTER TABLE areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_day_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE obstacles ENABLE ROW LEVEL SECURITY;
ALTER TABLE guests ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservation_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE block_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE sumup_payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservation_table_day_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;

-- Drop + recreate all tenant_isolation policies
DO $$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT schemaname, tablename, policyname
             FROM pg_policies WHERE policyname = 'tenant_isolation'
    LOOP
        EXECUTE format('DROP POLICY tenant_isolation ON %I.%I', r.schemaname, r.tablename);
    END LOOP;
END $$;

CREATE POLICY tenant_isolation ON areas USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON tables USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON table_day_configs USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON obstacles USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON guests USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON reservations USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON reservation_tables USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON blocks USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON block_assignments USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON waitlist USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON menu_categories USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON menu_items USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON orders USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON order_items USING (order_id IN (SELECT id FROM orders WHERE tenant_id = current_tenant_id()));
CREATE POLICY tenant_isolation ON sumup_payments USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON messages USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON reservation_table_day_configs USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON audit_logs USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON reviews USING (tenant_id = current_tenant_id());
CREATE POLICY tenant_isolation ON devices USING (tenant_id = current_tenant_id());

-- ============================================================
-- UPDATED_AT TRIGGER
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN CREATE TRIGGER trg_restaurants_updated_at BEFORE UPDATE ON restaurants FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_tables_updated_at BEFORE UPDATE ON tables FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_reservations_updated_at BEFORE UPDATE ON reservations FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_menu_items_updated_at BEFORE UPDATE ON menu_items FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_guest_profiles_updated_at BEFORE UPDATE ON guest_profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_guests_updated_at BEFORE UPDATE ON guests FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_sumup_payments_updated_at BEFORE UPDATE ON sumup_payments FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_user_settings_updated_at BEFORE UPDATE ON user_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_table_day_configs_updated_at BEFORE UPDATE ON table_day_configs FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_reviews_updated_at BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TRIGGER trg_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_updated_at(); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- VIEW
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

COMMIT;
