-- Migration 004: Review Replies
-- Allows restaurant staff to reply to guest reviews

ALTER TABLE reviews
    ADD COLUMN IF NOT EXISTS staff_reply TEXT,
    ADD COLUMN IF NOT EXISTS staff_reply_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS staff_reply_by UUID REFERENCES users(id) ON DELETE SET NULL;
