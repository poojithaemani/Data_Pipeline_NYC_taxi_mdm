-- =================================================================
-- 003_initialize_records.sql
-- Backfill surrogate ids (if any left), initialize SCD columns from created_at
-- and add/attempt to backfill golden_zones.location_id when missing.
-- Produces reporting rows for ambiguous mappings (left NULL) for manual review.
-- =================================================================

BEGIN;

-- 1) Ensure vendor_row_id / golden_zone_row_id populated (idempotent)
UPDATE vendors
SET vendor_row_id = nextval('vendors_vendor_row_id_seq')
WHERE vendor_row_id IS NULL;

UPDATE golden_zones
SET golden_zone_row_id = nextval('golden_zones_golden_zone_row_id_seq')
WHERE golden_zone_row_id IS NULL;

-- 2) Add location_id to golden_zones if it does not exist (we will reuse existing if present)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'golden_zones' AND column_name = 'location_id'
  ) THEN
    ALTER TABLE golden_zones ADD COLUMN location_id INT;
  END IF;
END
$$;

-- 3) Backfill golden_zones.location_id from taxi_zones when there is an exact 1:1 match on borough+zone
-- Only populate when golden_zones.location_id IS NULL to avoid overwriting manual fixes
UPDATE golden_zones gz
SET location_id = t.location_id
FROM taxi_zones t
WHERE gz.location_id IS NULL
  AND gz.borough = t.borough
  AND gz.zone = t.zone
  AND (
    SELECT COUNT(*) FROM taxi_zones tx
    WHERE tx.borough = gz.borough AND tx.zone = gz.zone
  ) = 1;

-- 4) Report ambiguous/unmatched golden_zones rows where location_id remains NULL
-- (Users should review these rows manually and resolve before switching PKs)
-- Note: This SELECT is for inspection when run interactively; migration runners can capture the output.
-- Rows count remaining
SELECT
  COUNT(*) AS golden_zones_total,
  SUM(CASE WHEN location_id IS NULL THEN 1 ELSE 0 END) AS golden_zones_location_id_null
FROM golden_zones;

-- 5) Initialize SCD fields for vendors and golden_zones where they appear uninitialized
UPDATE vendors
SET
  version = COALESCE(version, 1),
  is_current = COALESCE(is_current, TRUE),
  effective_date = COALESCE(effective_date, created_at),
  end_date = NULL
WHERE (version IS NULL OR is_current IS NULL OR effective_date IS NULL);

UPDATE golden_zones
SET
  version = COALESCE(version, 1),
  is_current = COALESCE(is_current, TRUE),
  effective_date = COALESCE(effective_date, created_at),
  end_date = NULL
WHERE (version IS NULL OR is_current IS NULL OR effective_date IS NULL);

COMMIT;

-- End of 003_initialize_records.sql
