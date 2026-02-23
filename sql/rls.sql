-- GastroPilot Row-Level Security Policies
-- Enables per-tenant data isolation via PostgreSQL RLS

-- ============================================================
-- ENABLE RLS ON ALL TENANT-SCOPED TABLES
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
ALTER TABLE vouchers ENABLE ROW LEVEL SECURITY;
ALTER TABLE upsell_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservation_prepayments ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- NOTE: users, restaurants, guest_profiles, platform_audit_log, refresh_tokens
-- do NOT have RLS (managed at application level)

-- ============================================================
-- HELPER FUNCTIONS
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
-- RLS POLICIES – TENANT ISOLATION
-- ============================================================

-- Drop existing policies to allow re-run
DO $$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT schemaname, tablename, policyname
             FROM pg_policies WHERE policyname = 'tenant_isolation'
    LOOP
        EXECUTE format('DROP POLICY tenant_isolation ON %I.%I', r.schemaname, r.tablename);
    END LOOP;
END $$;

-- areas
CREATE POLICY tenant_isolation ON areas
    USING (tenant_id = current_tenant_id());

-- tables
CREATE POLICY tenant_isolation ON tables
    USING (tenant_id = current_tenant_id());

-- table_day_configs
CREATE POLICY tenant_isolation ON table_day_configs
    USING (tenant_id = current_tenant_id());

-- obstacles
CREATE POLICY tenant_isolation ON obstacles
    USING (tenant_id = current_tenant_id());

-- guests
CREATE POLICY tenant_isolation ON guests
    USING (tenant_id = current_tenant_id());

-- reservations
CREATE POLICY tenant_isolation ON reservations
    USING (tenant_id = current_tenant_id());

-- reservation_tables
CREATE POLICY tenant_isolation ON reservation_tables
    USING (tenant_id = current_tenant_id());

-- blocks
CREATE POLICY tenant_isolation ON blocks
    USING (tenant_id = current_tenant_id());

-- block_assignments
CREATE POLICY tenant_isolation ON block_assignments
    USING (tenant_id = current_tenant_id());

-- waitlist
CREATE POLICY tenant_isolation ON waitlist
    USING (tenant_id = current_tenant_id());

-- menu_categories
CREATE POLICY tenant_isolation ON menu_categories
    USING (tenant_id = current_tenant_id());

-- menu_items
CREATE POLICY tenant_isolation ON menu_items
    USING (tenant_id = current_tenant_id());

-- orders
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_tenant_id());

-- order_items: access via parent order (no direct tenant_id column)
CREATE POLICY tenant_isolation ON order_items
    USING (
        order_id IN (
            SELECT id FROM orders WHERE tenant_id = current_tenant_id()
        )
    );

-- sumup_payments
CREATE POLICY tenant_isolation ON sumup_payments
    USING (tenant_id = current_tenant_id());

-- vouchers
CREATE POLICY tenant_isolation ON vouchers
    USING (tenant_id = current_tenant_id());

-- upsell_packages
CREATE POLICY tenant_isolation ON upsell_packages
    USING (tenant_id = current_tenant_id());

-- reservation_prepayments
CREATE POLICY tenant_isolation ON reservation_prepayments
    USING (tenant_id = current_tenant_id());

-- messages
CREATE POLICY tenant_isolation ON messages
    USING (tenant_id = current_tenant_id());

-- audit_logs
CREATE POLICY tenant_isolation ON audit_logs
    USING (tenant_id = current_tenant_id());
