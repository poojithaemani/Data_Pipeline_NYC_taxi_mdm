-- =================================================================
-- 008_drop_legacy_constraints.sql
-- Drop legacy global UNIQUE constraints after validation and after partial unique indexes
-- are in place and have been validated. This script is idempotent and will only drop
-- constraints that match the legacy uniqueness patterns.
-- Run this after a successful validation window and after backups.
-- =================================================================

BEGIN;

-- 1) Drop legacy UNIQUE constraint on golden_zones that enforces UNIQUE(borough, zone)
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname, oid
    FROM pg_constraint
    WHERE conrelid = 'golden_zones'::regclass AND contype = 'u'
  LOOP
    IF pg_get_constraintdef(c.oid) LIKE '%(borough, zone)%' THEN
      EXECUTE format('ALTER TABLE golden_zones DROP CONSTRAINT %I', c.conname);
      RAISE NOTICE 'Dropped constraint %', c.conname;
    END IF;
  END LOOP;
END
$$;

-- 2) Convert vendor_name unique constraint to partial unique on vendor_name WHERE is_current
-- Strategy: if a UNIQUE constraining vendor_name exists, drop it and rely on a partial unique index
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname, oid
    FROM pg_constraint
    WHERE conrelid = 'vendors'::regclass AND contype = 'u'
  LOOP
    IF pg_get_constraintdef(c.oid) LIKE '%(vendor_name)%' THEN
      EXECUTE format('ALTER TABLE vendors DROP CONSTRAINT %I', c.conname);
      RAISE NOTICE 'Dropped constraint %', c.conname;
    END IF;
  END LOOP;
END
$$;

COMMIT;

-- After running this migration, ensure the partial unique indexes on current rows exist:
-- CREATE UNIQUE INDEX CONCURRENTLY idx_golden_locationid_current ON golden_zones (location_id) WHERE is_current AND location_id IS NOT NULL;
-- CREATE UNIQUE INDEX CONCURRENTLY idx_vendors_vendorid_current ON vendors (vendor_id) WHERE is_current;

-- End of 008_drop_legacy_constraints.sql
