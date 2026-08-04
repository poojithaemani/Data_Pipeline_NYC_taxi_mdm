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

-- 5) Add FK if mapping is complete (no NULLs)
DO $$
DECLARE unmapped int;
BEGIN
  SELECT COUNT(*) INTO unmapped FROM zone_matches WHERE golden_zone_row_id IS NULL;
  IF unmapped = 0 THEN
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_name = 'zone_matches' AND tc.constraint_type = 'FOREIGN KEY' AND kcu.column_name = 'golden_zone_row_id'
    ) THEN
      ALTER TABLE zone_matches ADD CONSTRAINT fk_zone_matches_golden_zone_row FOREIGN KEY (golden_zone_row_id) REFERENCES golden_zones (golden_zone_row_id);
    END IF;
  ELSE
    RAISE NOTICE 'Zone matches mapping incomplete: % unmapped rows remain. Resolve before adding FK.', unmapped;
  END IF;
END
$$;

COMMIT;

-- Notes:
-- * Do NOT drop zone_matches.golden_zone_id in this migration. Keep the legacy column until migration is fully validated and cutover is complete.
-- * Create the supporting index CONCURRENTLY in production before adding the FK to avoid long locks.
-- * If unmapped rows remain, export them for manual review and resolution.

-- End of 005a_zone_matches_mapping.sql
