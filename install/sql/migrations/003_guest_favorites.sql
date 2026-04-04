-- Migration 003: Guest Favorites
-- Allows guests to save restaurants to their personal wishlist

CREATE TABLE IF NOT EXISTS guest_favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_profile_id UUID NOT NULL REFERENCES guest_profiles(id) ON DELETE CASCADE,
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_guest_favorites UNIQUE (guest_profile_id, restaurant_id)
);

CREATE INDEX IF NOT EXISTS idx_guest_favorites_guest
    ON guest_favorites (guest_profile_id);

CREATE INDEX IF NOT EXISTS idx_guest_favorites_restaurant
    ON guest_favorites (restaurant_id);
