-- Add is_verified column to reviews table
-- Indicates if the reviewer had a confirmed reservation at the restaurant

ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;
