-- Migration 007: Stripe Billing Sync
-- Ensures all billing columns exist on restaurants table (idempotent)

ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS stripe_customer_id VARCHAR(128);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS stripe_subscription_id VARCHAR(128);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS stripe_price_id VARCHAR(128);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_status VARCHAR(32) DEFAULT 'inactive';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_current_period_end TIMESTAMPTZ;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS billing_email VARCHAR(255);
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_tier VARCHAR(32) DEFAULT 'free';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_suspended BOOLEAN DEFAULT FALSE;
