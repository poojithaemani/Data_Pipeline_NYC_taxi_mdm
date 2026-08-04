-- =================================================================
-- 007_prepare_business_keys.sql
--
-- Description:
-- Adds UNIQUE constraints to the business key columns (vendor_id, golden_id)
-- to preserve their uniqueness after the primary key is switched to the
-- surrogate row identifier. This is a prerequisite for safely switching the PK.
--
-- This migration is idempotent and safe to run.
-- =================================================================

BEGIN;

-- 1) Add UNIQUE constraint to vendors.vendor_id (business key)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'vendors'::regclass AND contype = 'u' AND conname = 'vendors_vendor_id_key') THEN
    ALTER TABLE vendors ADD CONSTRAINT vendors_vendor_id_key UNIQUE (vendor_id);
  END IF;
END
$$;

-- 2) Add UNIQUE constraint to golden_zones.golden_id (business key)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'golden_zones'::regclass AND contype = 'u' AND conname = 'golden_zones_golden_id_key') THEN
    ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_golden_id_key UNIQUE (golden_id);
  END IF;
END
$$;

COMMIT;