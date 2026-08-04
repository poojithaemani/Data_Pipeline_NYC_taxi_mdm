-- =================================================================
-- 002_add_scd_columns.sql
-- Add minimal SCD Type 2 columns to vendors and golden_zones.
-- Idempotent: uses IF NOT EXISTS where possible.
-- Defaults are set so new inserts are well-formed; NOT NULL is deferred until backfill completes.
-- =================================================================

BEGIN;

-- Vendors: add version, is_current, effective_date, end_date
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS is_current BOOLEAN DEFAULT TRUE;
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS effective_date TIMESTAMPTZ;
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ;

-- Golden_zones: add version, is_current, effective_date, end_date
ALTER TABLE golden_zones ADD COLUMN IF NOT EXISTS version INTEGER DEFAULT 1;
ALTER TABLE golden_zones ADD COLUMN IF NOT EXISTS is_current BOOLEAN DEFAULT TRUE;
ALTER TABLE golden_zones ADD COLUMN IF NOT EXISTS effective_date TIMESTAMPTZ;
ALTER TABLE golden_zones ADD COLUMN IF NOT EXISTS end_date TIMESTAMPTZ;

COMMIT;

-- End of 002_add_scd_columns.sql
