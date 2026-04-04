-- Migration: Add reminder_sent column to reservations
-- Date: 2026-03-02

ALTER TABLE reservations
    ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN NOT NULL DEFAULT false;
