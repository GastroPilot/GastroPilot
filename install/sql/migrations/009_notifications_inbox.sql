-- Migration 009: Notifications Inbox
-- In-app notification inbox for guest profiles

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

CREATE INDEX IF NOT EXISTS idx_notifications_guest_profile_id
    ON notifications(guest_profile_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at
    ON notifications(created_at DESC);
