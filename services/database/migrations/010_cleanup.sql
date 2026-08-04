-- =================================================================
-- 010_cleanup.sql
--
-- Description:
-- Removes obsolete constraints after the primary key and foreign key
-- switches have been successfully completed and validated in production.
-- =================================================================

BEGIN;

-- 1) Drop the redundant UNIQUE constraint on the old business primary key.
-- The FK from zone_matches now points to golden_zone_row_id, so this is safe.
ALTER TABLE golden_zones DROP CONSTRAINT IF EXISTS golden_zones_golden_id_key;

COMMIT;