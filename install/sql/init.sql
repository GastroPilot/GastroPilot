-- GastroPilot PostgreSQL Schema
-- Multi-Tenant Architecture with Row-Level Security

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

DO $$ BEGIN
    CREATE TYPE user_role AS ENUM (
        'guest', 'owner', 'manager', 'staff', 'kitchen',
        'platform_admin', 'platform_support', 'platform_analyst'
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- subscription_tier und payment_provider werden als VARCHAR genutzt (nicht als ENUM)

DO $$ BEGIN
    CREATE TYPE reservation_status AS ENUM ('pending', 'confirmed', 'seated', 'completed', 'canceled', 'no_show');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('open', 'sent_to_kitchen', 'in_preparation', 'ready', 'served', 'paid', 'canceled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE order_item_status AS ENUM ('pending', 'sent', 'in_preparation', 'ready', 'served', 'canceled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE payment_status AS ENUM ('unpaid', 'partial', 'paid');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE auth_method AS ENUM ('pin', 'password');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- PLATFORM-LEVEL TABLES (no tenant_id)
-- ============================================================

CREATE TABLE IF NOT EXISTS restaurants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200) NOT NULL,
    slug VARCHAR(100) UNIQUE,
    address VARCHAR(500),
    phone VARCHAR(50),
    email VARCHAR(255),
    description TEXT,
    subscription_tier VARCHAR(32) DEFAULT 'free',
    is_suspended BOOLEAN NOT NULL DEFAULT FALSE,
    suspended_reason TEXT,
    suspended_at TIMESTAMPTZ,
    stripe_customer_id VARCHAR(128),
    stripe_subscription_id VARCHAR(128),
    stripe_price_id VARCHAR(128),
    subscription_status VARCHAR(32) DEFAULT 'active',
    subscription_current_period_end TIMESTAMPTZ,
    billing_email VARCHAR(255),
    sumup_merchant_code VARCHAR(32),
    sumup_api_key VARCHAR(255),
    sumup_default_reader_id VARCHAR(64),
    public_booking_enabled BOOLEAN NOT NULL DEFAULT FALSE,
    booking_lead_time_hours INTEGER NOT NULL DEFAULT 2,
    booking_max_party_size INTEGER NOT NULL DEFAULT 12,
    booking_default_duration INTEGER NOT NULL DEFAULT 120,
    opening_hours JSONB,
    settings JSONB DEFAULT '{}',
    is_featured BOOLEAN NOT NULL DEFAULT FALSE,
    featured_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_restaurants_slug ON restaurants(slug);

CREATE TABLE IF NOT EXISTS guest_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE,
    phone VARCHAR(32),
    first_name VARCHAR(120) NOT NULL,
    last_name VARCHAR(120) NOT NULL,
    language VARCHAR(10) DEFAULT 'de',
    notes TEXT,
    allergens JSONB DEFAULT '[]',
    allergen_profile JSONB DEFAULT '[]',
    preferences JSONB DEFAULT '{}',
    password_hash VARCHAR(255),
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    email_verification_token VARCHAR(255),
    password_reset_token VARCHAR(255),
    password_reset_expires_at TIMESTAMPTZ,
    push_token VARCHAR(512),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_guest_profiles_email ON guest_profiles(email);
CREATE INDEX IF NOT EXISTS idx_guest_profiles_phone ON guest_profiles(phone);

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

CREATE INDEX IF NOT EXISTS idx_users_tenant_id ON users(tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_unique ON users(email) WHERE email IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_operator_number_unique ON users(tenant_id, operator_number) WHERE operator_number IS NOT NULL;

CREATE TABLE IF NOT EXISTS refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) UNIQUE NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    rotated_from_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at);

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

CREATE INDEX IF NOT EXISTS idx_platform_audit_log_admin ON platform_audit_log(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_platform_audit_log_tenant ON platform_audit_log(target_tenant_id);
CREATE INDEX IF NOT EXISTS idx_platform_audit_log_created ON platform_audit_log(created_at);

-- ============================================================
-- TENANT-SCOPED TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS areas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(120) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_areas_tenant_id ON areas(tenant_id);

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

CREATE INDEX IF NOT EXISTS idx_tables_tenant_id ON tables(tenant_id);
CREATE INDEX IF NOT EXISTS idx_tables_area_id ON tables(area_id);
CREATE INDEX IF NOT EXISTS idx_tables_token ON tables(table_token) WHERE table_token IS NOT NULL;

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

CREATE INDEX IF NOT EXISTS idx_table_day_configs_tenant_id ON table_day_configs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_table_day_configs_date ON table_day_configs(date);

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

CREATE INDEX IF NOT EXISTS idx_obstacles_tenant_id ON obstacles(tenant_id);

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

CREATE INDEX IF NOT EXISTS idx_guests_tenant_id ON guests(tenant_id);
CREATE INDEX IF NOT EXISTS idx_guests_email ON guests(email);

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
    reminder_sent BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reservations_tenant_id ON reservations(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reservations_start_at ON reservations(start_at);
CREATE INDEX IF NOT EXISTS idx_reservations_status ON reservations(status);
CREATE INDEX IF NOT EXISTS idx_reservations_confirmation_code ON reservations(confirmation_code);
CREATE INDEX IF NOT EXISTS idx_reservations_guest_id ON reservations(guest_id);

CREATE TABLE IF NOT EXISTS reservation_tables (
    reservation_id UUID REFERENCES reservations(id) ON DELETE CASCADE,
    table_id UUID REFERENCES tables(id) ON DELETE RESTRICT,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (reservation_id, table_id)
);

CREATE INDEX IF NOT EXISTS idx_reservation_tables_tenant_id ON reservation_tables(tenant_id);

CREATE TABLE IF NOT EXISTS blocks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    reason TEXT,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_blocks_tenant_id ON blocks(tenant_id);

CREATE TABLE IF NOT EXISTS block_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    block_id UUID NOT NULL REFERENCES blocks(id) ON DELETE CASCADE,
    table_id UUID NOT NULL REFERENCES tables(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(block_id, table_id)
);

CREATE INDEX IF NOT EXISTS idx_block_assignments_tenant_id ON block_assignments(tenant_id);

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
    guest_name VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_waitlist_tenant_id ON waitlist(tenant_id);
CREATE INDEX IF NOT EXISTS idx_waitlist_tracking_token ON waitlist(tracking_token) WHERE tracking_token IS NOT NULL;

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

CREATE INDEX IF NOT EXISTS idx_menu_categories_tenant_id ON menu_categories(tenant_id);

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

CREATE INDEX IF NOT EXISTS idx_menu_items_tenant_id ON menu_items(tenant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_category_id ON menu_items(category_id);

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
    ready_at TIMESTAMPTZ,
    served_at TIMESTAMPTZ,
    closed_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    created_by_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    source VARCHAR(20) DEFAULT 'staff',
    session_id VARCHAR(64),
    guest_profile_id UUID REFERENCES guest_profiles(id) ON DELETE SET NULL,
    guest_allergens JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_tenant_id ON orders(tenant_id);
CREATE INDEX IF NOT EXISTS idx_orders_session_id ON orders(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_guest_profile_id ON orders(guest_profile_id) WHERE guest_profile_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_opened_at ON orders(opened_at);
CREATE INDEX IF NOT EXISTS idx_orders_table_id ON orders(table_id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_active_reservation
ON orders(tenant_id, reservation_id)
WHERE reservation_id IS NOT NULL
  AND status NOT IN ('paid', 'canceled')
  AND payment_status <> 'paid';
CREATE UNIQUE INDEX IF NOT EXISTS uq_orders_active_table
ON orders(tenant_id, table_id)
WHERE table_id IS NOT NULL
  AND status NOT IN ('paid', 'canceled')
  AND payment_status <> 'paid';

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
    allergens JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_menu_item_id ON order_items(menu_item_id);
CREATE INDEX IF NOT EXISTS idx_order_items_course ON order_items(order_id, course);

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

CREATE INDEX IF NOT EXISTS idx_sumup_payments_tenant_id ON sumup_payments(tenant_id);
CREATE INDEX IF NOT EXISTS idx_sumup_payments_order_id ON sumup_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_sumup_payments_checkout_id ON sumup_payments(checkout_id);

CREATE TABLE IF NOT EXISTS reservation_table_day_configs (
    reservation_id UUID REFERENCES reservations(id) ON DELETE CASCADE,
    table_day_config_id UUID REFERENCES table_day_configs(id) ON DELETE CASCADE,
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (reservation_id, table_day_config_id)
);

CREATE INDEX IF NOT EXISTS idx_reservation_table_day_configs_tenant_id ON reservation_table_day_configs(tenant_id);

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

CREATE INDEX IF NOT EXISTS idx_messages_tenant_id ON messages(tenant_id);

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

CREATE INDEX IF NOT EXISTS idx_audit_logs_tenant_id ON audit_logs(tenant_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- ============================================================
-- DEVICES, REVIEWS, GUEST FAVORITES, NOTIFICATIONS (v0.13.0)
-- ============================================================

CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    station VARCHAR(50) NOT NULL DEFAULT 'alle',
    device_token VARCHAR(128) NOT NULL UNIQUE,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_tenant_id ON devices(tenant_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_device_token ON devices(device_token);

CREATE TABLE IF NOT EXISTS reviews (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    rating INTEGER NOT NULL,
    title VARCHAR(200),
    text TEXT,
    is_visible BOOLEAN NOT NULL DEFAULT TRUE,
    is_verified BOOLEAN NOT NULL DEFAULT FALSE,
    staff_reply TEXT,
    staff_reply_at TIMESTAMPTZ,
    staff_reply_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reviews_tenant_id ON reviews(tenant_id);
CREATE INDEX IF NOT EXISTS idx_reviews_guest_profile_id ON reviews(guest_profile_id);

CREATE TABLE IF NOT EXISTS guest_favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_guest_favorites_unique ON guest_favorites(guest_profile_id, restaurant_id);
CREATE INDEX IF NOT EXISTS idx_guest_favorites_guest_profile_id ON guest_favorites(guest_profile_id);
CREATE INDEX IF NOT EXISTS idx_guest_favorites_restaurant_id ON guest_favorites(restaurant_id);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES restaurants(id) ON DELETE CASCADE,
    type VARCHAR(64) NOT NULL,
    title VARCHAR(255) NOT NULL,
    body TEXT,
    data JSONB DEFAULT '{}',
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_guest_profile_id ON notifications(guest_profile_id);

-- ============================================================
-- PERMISSIONS
-- Der POSTGRES_USER (Superuser) wird für alle Verbindungen genutzt.
-- Grants auf Schema public sicherstellen (PostgreSQL 15+ entzieht CREATE standardmäßig).
-- ============================================================

DO $$
BEGIN
    EXECUTE format('GRANT ALL PRIVILEGES ON DATABASE %I TO current_user', current_database());
END $$;
GRANT ALL ON SCHEMA public TO current_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO current_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO current_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO current_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO current_user;

-- ============================================================
-- UPDATED_AT TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$ BEGIN
    CREATE TRIGGER trg_restaurants_updated_at BEFORE UPDATE ON restaurants FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_tables_updated_at BEFORE UPDATE ON tables FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_reservations_updated_at BEFORE UPDATE ON reservations FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_orders_updated_at BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_menu_items_updated_at BEFORE UPDATE ON menu_items FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_guest_profiles_updated_at BEFORE UPDATE ON guest_profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_guests_updated_at BEFORE UPDATE ON guests FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_sumup_payments_updated_at BEFORE UPDATE ON sumup_payments FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_user_settings_updated_at BEFORE UPDATE ON user_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_table_day_configs_updated_at BEFORE UPDATE ON table_day_configs FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_reviews_updated_at BEFORE UPDATE ON reviews FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    CREATE TRIGGER trg_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION update_updated_at();
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================
-- ALEMBIC: Stamp als "head" da init.sql das vollständige Schema erstellt
-- ============================================================

CREATE TABLE IF NOT EXISTS alembic_version (
    version_num VARCHAR(32) NOT NULL,
    CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num)
);
DELETE FROM alembic_version;
INSERT INTO alembic_version (version_num) VALUES ('0008_sync_remaining_core_models');

-- ============================================================
-- OWNERSHIP: Tabellen dem aktuellen User zuweisen (= POSTGRES_USER)
-- ============================================================

DO $$
DECLARE
    tbl TEXT;
BEGIN
    FOR tbl IN
        SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE format('ALTER TABLE public.%I OWNER TO %I', tbl, current_user);
    END LOOP;
END $$;
