-- Migration 006: Allergen Kitchen Chain (SafePlate)
-- Adds allergen tracking on order items and guest allergens on orders
-- Also adds push_token support for guest profiles

ALTER TABLE order_items ADD COLUMN IF NOT EXISTS allergens JSONB DEFAULT '[]';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS guest_allergens JSONB DEFAULT '[]';
ALTER TABLE guest_profiles ADD COLUMN IF NOT EXISTS push_token VARCHAR(512);
