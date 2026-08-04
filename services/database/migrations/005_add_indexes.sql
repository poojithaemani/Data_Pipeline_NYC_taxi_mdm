-- =================================================================
-- 005_add_indexes.sql
-- Create indexes to support SCD operations and enforce a single current row via partial unique indexes.
-- IMPORTANT: CONCURRENT index creation must be run outside of explicit transactions.
-- Run this file as-is (it does not contain BEGIN/COMMIT) in production.
-- =================================================================

-- vendors: partial unique index to ensure one current row per business vendor_id
-- Run concurrently in production to avoid locks:
-- CREATE UNIQUE INDEX CONCURRENTLY idx_vendors_vendorid_current ON vendors (vendor_id) WHERE is_current;

-- vendors: history index (vendor_id, effective_date)
-- CREATE INDEX CONCURRENTLY idx_vendors_vendorid_effective_date ON vendors (vendor_id, effective_date);

-- golden_zones: partial unique index to ensure one current row per location_id
-- Note: location_id may be NULL for ambiguous mappings until manually resolved.
-- Create this index only after golden_zones.location_id is populated for current rows.
-- CREATE UNIQUE INDEX CONCURRENTLY idx_golden_locationid_current ON golden_zones (location_id) WHERE is_current AND location_id IS NOT NULL;

-- golden_zones: history indexes
-- CREATE INDEX CONCURRENTLY idx_golden_borough_zone_effective ON golden_zones (borough, zone, effective_date);
-- CREATE INDEX CONCURRENTLY idx_golden_effective_date ON golden_zones (effective_date);

-- If you prefer scripted creation with existence checks, run the following checks manually and then execute the CREATE INDEX CONCURRENTLY statements.

-- Quick existence checks (run before attempting to create indexes):
SELECT 'idx_vendors_vendorid_current' AS index_name, to_regclass('public.idx_vendors_vendorid_current') IS NOT NULL AS exists;
SELECT 'idx_vendors_vendorid_effective_date' AS index_name, to_regclass('public.idx_vendors_vendorid_effective_date') IS NOT NULL AS exists;
SELECT 'idx_golden_locationid_current' AS index_name, to_regclass('public.idx_golden_locationid_current') IS NOT NULL AS exists;
SELECT 'idx_golden_borough_zone_effective' AS index_name, to_regclass('public.idx_golden_borough_zone_effective') IS NOT NULL AS exists;
SELECT 'idx_golden_effective_date' AS index_name, to_regclass('public.idx_golden_effective_date') IS NOT NULL AS exists;

-- NOTE: Run each CREATE INDEX CONCURRENTLY statement only when the environment is ready (no long-running transactions) and outside an explicit transaction.

-- Example create command to run in psql (production safe):
-- psql -h <host> -U <user> -d <db> -c "CREATE UNIQUE INDEX CONCURRENTLY idx_vendors_vendorid_current ON vendors (vendor_id) WHERE is_current;"

-- End of 005_add_indexes.sql
