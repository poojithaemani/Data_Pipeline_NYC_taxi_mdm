-- =================================================================
-- 001_add_surrogate_keys.sql
-- Add surrogate row primary keys for vendors and golden_zones.
-- Idempotent: safe to re-run.
-- Do NOT switch primary keys here; switching PKs is deferred to the final migration.
-- =================================================================

BEGIN;

-- 1) Add vendor_row_id (BIGINT) column if it does not exist and attach a sequence/DEFAULT.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'vendors' AND column_name = 'vendor_row_id'
  ) THEN
    ALTER TABLE vendors ADD COLUMN vendor_row_id BIGINT;
  END IF;

  -- Create sequence for vendor_row_id if it does not exist
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind = 'S' AND relname = 'vendors_vendor_row_id_seq') THEN
    CREATE SEQUENCE vendors_vendor_row_id_seq OWNED BY vendors.vendor_row_id;
  END IF;

  -- Attach default nextval to column
  EXECUTE format('ALTER TABLE vendors ALTER COLUMN vendor_row_id SET DEFAULT nextval(%L)', 'vendors_vendor_row_id_seq');

  -- Populate missing vendor_row_id values
  IF (SELECT COUNT(*) FROM vendors WHERE vendor_row_id IS NULL) > 0 THEN
    UPDATE vendors SET vendor_row_id = nextval('vendors_vendor_row_id_seq') WHERE vendor_row_id IS NULL;
    PERFORM setval('vendors_vendor_row_id_seq', (SELECT GREATEST(MAX(vendor_row_id), 1) FROM vendors));
  END IF;
END
$$;

-- 2) Add golden_zone_row_id (BIGINT) column and sequence if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'golden_zones' AND column_name = 'golden_zone_row_id'
  ) THEN
    ALTER TABLE golden_zones ADD COLUMN golden_zone_row_id BIGINT;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relkind = 'S' AND relname = 'golden_zones_golden_zone_row_id_seq') THEN
    CREATE SEQUENCE golden_zones_golden_zone_row_id_seq OWNED BY golden_zones.golden_zone_row_id;
  END IF;

  EXECUTE format('ALTER TABLE golden_zones ALTER COLUMN golden_zone_row_id SET DEFAULT nextval(%L)', 'golden_zones_golden_zone_row_id_seq');

  IF (SELECT COUNT(*) FROM golden_zones WHERE golden_zone_row_id IS NULL) > 0 THEN
    UPDATE golden_zones SET golden_zone_row_id = nextval('golden_zones_golden_zone_row_id_seq') WHERE golden_zone_row_id IS NULL;
    PERFORM setval('golden_zones_golden_zone_row_id_seq', (SELECT GREATEST(MAX(golden_zone_row_id), 1) FROM golden_zones));
  END IF;
END
$$;

COMMIT;

-- End of 001_add_surrogate_keys.sql
