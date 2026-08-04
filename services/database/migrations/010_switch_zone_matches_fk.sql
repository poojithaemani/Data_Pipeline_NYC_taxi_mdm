-- =================================================================
-- 010_switch_zone_matches_fk.sql
--
-- Description:
-- Switches the foreign key on zone_matches to reference the new surrogate
-- primary key on golden_zones (golden_zone_row_id).
--
-- This must run AFTER the primary key on golden_zones has been switched.
-- =================================================================

BEGIN;

-- 1) Drop the old foreign key that references the business key (golden_id)
-- The constraint name is derived from the table and column it references.
ALTER TABLE zone_matches DROP CONSTRAINT IF EXISTS zone_matches_golden_zone_id_fkey;

-- 2) Add the new foreign key referencing the surrogate key (golden_zone_row_id)
-- This reuses the logic from the original 007a migration.
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