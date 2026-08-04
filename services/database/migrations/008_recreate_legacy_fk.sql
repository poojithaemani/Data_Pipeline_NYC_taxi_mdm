-- =================================================================
-- 008_recreate_legacy_fk.sql
--
-- Description:
-- Drops and recreates the foreign key on zone_matches(golden_zone_id).
-- This is a critical step to shift the FK's dependency from the original
-- PRIMARY KEY (golden_zones_pkey) to the new UNIQUE constraint
-- (golden_zones_golden_id_key) on the same column (golden_id).
--
-- This frees up the primary key to be dropped and switched in the next step.
--
-- This migration is idempotent.
-- =================================================================

BEGIN;

-- 1) Drop the existing foreign key constraint if it exists.
-- The original name was likely inferred by PostgreSQL.
ALTER TABLE zone_matches DROP CONSTRAINT IF EXISTS zone_matches_golden_zone_id_fkey;

-- 2) Recreate the foreign key constraint with the same name.
-- It will now depend on the UNIQUE constraint on golden_zones(golden_id).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'zone_matches_golden_zone_id_fkey' AND conrelid = 'zone_matches'::regclass) THEN
    ALTER TABLE zone_matches ADD CONSTRAINT zone_matches_golden_zone_id_fkey
      FOREIGN KEY (golden_zone_id) REFERENCES golden_zones(golden_id);
  END IF;
END;
$$;

COMMIT;

-- =================================================================
-- Validation:
-- After running, this query should show the FK depends on the UNIQUE key, not the PK.
-- SELECT conname, confrelid::regclass, confkey, contype FROM pg_constraint WHERE conrelid = 'zone_matches'::regclass AND conname = 'zone_matches_golden_zone_id_fkey';
-- =================================================================