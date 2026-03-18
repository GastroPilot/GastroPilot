-- Migration 008: Premium Placement
-- Adds featured restaurant support for premium placement in search

ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT FALSE;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS featured_until TIMESTAMPTZ;
