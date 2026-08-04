-- =================================================================
-- 008_switch_primary_keys.sql
--
-- Description:
-- Switches the primary keys on vendors and golden_zones to the
-- surrogate row identifiers. This can only run after dependencies
-- (like foreign keys) have been removed.
--
-- Note: This operation requires exclusive locks. Run in a maintenance window.
-- =================================================================

BEGIN;

-- 1) Switch vendors primary key to vendor_row_id
-- This assumes no FKs are pointing to the original vendors_pkey.
ALTER TABLE vendors DROP CONSTRAINT IF EXISTS vendors_pkey;
ALTER TABLE vendors ADD CONSTRAINT vendors_pkey PRIMARY KEY (vendor_row_id);

-- 2) Switch golden_zones primary key to golden_zone_row_id
-- This is now safe because the FK from zone_matches was dropped in the
-- previous migration.
ALTER TABLE golden_zones DROP CONSTRAINT IF EXISTS golden_zones_pkey;
ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_pkey PRIMARY KEY (golden_zone_row_id);

COMMIT;