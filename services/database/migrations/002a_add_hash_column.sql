-- =================================================================
-- 002a_add_hash_column.sql
--
-- Description:
-- Adds a record_hash column to the vendors and golden_zones tables.
-- This column will be used by ETL jobs (Glue/PySpark) to efficiently
-- detect changes in slowly changing dimension attributes.
-- =================================================================

BEGIN;

-- Add record_hash to vendors table
ALTER TABLE vendors ADD COLUMN IF NOT EXISTS record_hash TEXT;

-- Add record_hash to golden_zones table
ALTER TABLE golden_zones ADD COLUMN IF NOT EXISTS record_hash TEXT;

COMMIT;