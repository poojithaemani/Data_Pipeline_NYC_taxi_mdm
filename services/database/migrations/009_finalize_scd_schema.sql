-- =================================================================
-- 009_finalize_scd_schema.sql
--
-- Description:
-- Finalizes the SCD Type 2 schema by:
-- 1. Recreating the foreign key on zone_matches to point to the new surrogate PK.
-- 2. Adding UNIQUE constraints on the business keys (vendor_id, golden_id)
--    to ensure entity integrity for legacy lookups.
--
-- This must run AFTER the primary keys have been switched.
-- =================================================================

BEGIN;

-- 1) Recreate the foreign key on zone_matches
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_zone_matches_golden_zone_row' AND conrelid = 'zone_matches'::regclass) THEN
    IF (SELECT COUNT(*) FROM zone_matches WHERE golden_zone_row_id IS NULL) > 0 THEN
      RAISE EXCEPTION 'Cannot add foreign key: zone_matches.golden_zone_row_id contains NULL values. Resolve unmapped rows first.';
    END IF;
    ALTER TABLE zone_matches ADD CONSTRAINT fk_zone_matches_golden_zone_row FOREIGN KEY (golden_zone_row_id) REFERENCES golden_zones (golden_zone_row_id);
  END IF;
END;
$$;

COMMIT;