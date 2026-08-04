-- =================================================================
-- 007_switch_primary_keys.sql
-- Switch primary keys to the surrogate row identifiers (vendor_row_id, golden_zone_row_id).
-- This migration MUST be executed only after:
--   - all validation queries in 006_validate_dependencies.sql return no blocking dependencies
--   - location_id backfill has been completed and validated
--   - partial unique indexes for current rows exist (or are planned) to enforce uniqueness
-- Note: This operation changes PK constraints. Run in a maintenance window.
-- =================================================================

BEGIN;

-- Safety checks: ensure no NULLs and uniqueness for surrogate columns
-- 1) vendor_row_id must be NOT NULL and unique
DO $$
DECLARE cnt_nulls int;
DECLARE cnt_dups int;
BEGIN
  SELECT COUNT(*) INTO cnt_nulls FROM vendors WHERE vendor_row_id IS NULL;
  IF cnt_nulls > 0 THEN
    RAISE EXCEPTION 'vendors.vendor_row_id contains % rows with NULLs - populate them before switching PKs', cnt_nulls;
  END IF;
  SELECT COUNT(*) INTO cnt_dups FROM (
    SELECT vendor_row_id, COUNT(*) FROM vendors GROUP BY vendor_row_id HAVING COUNT(*) > 1
  ) t;
  IF cnt_dups > 0 THEN
    RAISE EXCEPTION 'vendors.vendor_row_id contains % duplicate values - resolve before switching PKs', cnt_dups;
  END IF;
END
$$;

-- 2) golden_zone_row_id must be NOT NULL and unique
DO $$
DECLARE cnt_nulls int;
DECLARE cnt_dups int;
BEGIN
  SELECT COUNT(*) INTO cnt_nulls FROM golden_zones WHERE golden_zone_row_id IS NULL;
  IF cnt_nulls > 0 THEN
    RAISE EXCEPTION 'golden_zones.golden_zone_row_id contains % rows with NULLs - populate them before switching PKs', cnt_nulls;
  END IF;
  SELECT COUNT(*) INTO cnt_dups FROM (
    SELECT golden_zone_row_id, COUNT(*) FROM golden_zones GROUP BY golden_zone_row_id HAVING COUNT(*) > 1
  ) t;
  IF cnt_dups > 0 THEN
    RAISE EXCEPTION 'golden_zones.golden_zone_row_id contains % duplicate values - resolve before switching PKs', cnt_dups;
  END IF;
END
$$;

-- 3) Add UNIQUE constraint to vendors.vendor_id (business key)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'vendors'::regclass AND contype = 'u' AND conname = 'vendors_vendor_id_key') THEN
    ALTER TABLE vendors ADD CONSTRAINT vendors_vendor_id_key UNIQUE (vendor_id);
  END IF;
END
$$;

-- 4) Switch vendors primary key to vendor_row_id
ALTER TABLE vendors DROP CONSTRAINT IF EXISTS vendors_pkey;
ALTER TABLE vendors ADD CONSTRAINT vendors_pkey PRIMARY KEY (vendor_row_id);

-- 5) Add UNIQUE constraint to golden_zones.golden_id (business key)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'golden_zones'::regclass AND contype = 'u' AND conname = 'golden_zones_golden_id_key') THEN
    -- Ensure golden_id is NOT NULL before adding UNIQUE, though SERIAL implies NOT NULL.
    ALTER TABLE golden_zones ALTER COLUMN golden_id SET NOT NULL;
    ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_golden_id_key UNIQUE (golden_id);
  END IF;
END
$$;

-- 6) Switch golden_zones primary key to golden_zone_row_id
ALTER TABLE golden_zones DROP CONSTRAINT IF EXISTS golden_zones_pkey;
ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_pkey PRIMARY KEY (golden_zone_row_id);

COMMIT;

-- End of 007_switch_primary_keys.sql
