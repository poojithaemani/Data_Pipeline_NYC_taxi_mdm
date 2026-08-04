-- =================================================================
-- 005a_zone_matches_mapping.sql
-- Add golden_zone_row_id to zone_matches and populate mapping from golden_id.
-- Idempotent: safe to re-run.
-- Ensures referential compatibility before switching golden_zones PK to golden_zone_row_id.
-- =================================================================

BEGIN;

-- 1) Add golden_zone_row_id column if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'zone_matches' AND column_name = 'golden_zone_row_id'
  ) THEN
    ALTER TABLE zone_matches ADD COLUMN golden_zone_row_id BIGINT;
  END IF;
END
$$;

-- 2) Populate golden_zone_row_id from golden_zones mapping where possible
UPDATE zone_matches zm
SET golden_zone_row_id = gz.golden_zone_row_id
FROM golden_zones gz
WHERE zm.golden_zone_row_id IS NULL
  AND zm.golden_zone_id = gz.golden_id;

-- 3) Report mapping coverage
-- Expect unmapped_matches = 0 before adding FK
SELECT
  COUNT(*) AS total_matches,
  SUM(CASE WHEN golden_zone_row_id IS NULL THEN 1 ELSE 0 END) AS unmapped_matches
FROM zone_matches;

-- 4) Add index on zone_matches.golden_zone_row_id to support FK creation (create concurrently in production)
-- Example (run outside transaction):
-- CREATE INDEX CONCURRENTLY idx_zone_matches_golden_zone_row_id ON zone_matches (golden_zone_row_id);

COMMIT;
-- 5) Foreign key creation has been moved to 007a_add_zone_matches_fk.sql.
--    This is because golden_zones.golden_zone_row_id is not yet a PRIMARY KEY.
--    The supporting index should be created concurrently before running the FK migration.

COMMIT;

-- End of 005a_zone_matches_mapping.sql
