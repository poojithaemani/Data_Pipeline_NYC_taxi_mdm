-- =================================================================
-- 009_switch_primary_keys.sql
--
-- Description:
-- Switches the primary keys to the surrogate row identifiers.
-- This migration MUST be executed after business keys have been protected
-- with UNIQUE constraints (007_prepare_business_keys.sql).
--
-- Note: This operation requires exclusive locks. Run in a maintenance window.
-- =================================================================

BEGIN;

-- 1) Safety check: vendor_row_id must be NOT NULL and unique
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM vendors WHERE vendor_row_id IS NULL) > 0 THEN
    RAISE EXCEPTION 'vendors.vendor_row_id contains NULLs. Populate before switching PK.';
  END IF;
  IF (SELECT COUNT(*) FROM (SELECT 1 FROM vendors GROUP BY vendor_row_id HAVING COUNT(*) > 1) t) > 0 THEN
    RAISE EXCEPTION 'vendors.vendor_row_id contains duplicate values. Resolve before switching PK.';
  END IF;
END
$$;

-- 2) Safety check: golden_zone_row_id must be NOT NULL and unique
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM golden_zones WHERE golden_zone_row_id IS NULL) > 0 THEN
    RAISE EXCEPTION 'golden_zones.golden_zone_row_id contains NULLs. Populate before switching PK.';
  END IF;
  IF (SELECT COUNT(*) FROM (SELECT 1 FROM golden_zones GROUP BY golden_zone_row_id HAVING COUNT(*) > 1) t) > 0 THEN
    RAISE EXCEPTION 'golden_zones.golden_zone_row_id contains duplicate values. Resolve before switching PK.';
  END IF;
END
$$;

-- 3) Switch vendors primary key to vendor_row_id
ALTER TABLE vendors DROP CONSTRAINT IF EXISTS vendors_pkey;
ALTER TABLE vendors ADD CONSTRAINT vendors_pkey PRIMARY KEY (vendor_row_id);

-- 4) Switch golden_zones primary key to golden_zone_row_id
ALTER TABLE golden_zones DROP CONSTRAINT IF EXISTS golden_zones_pkey;
ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_pkey PRIMARY KEY (golden_zone_row_id);

COMMIT;