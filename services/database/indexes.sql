-- =================================================================
-- services/database/indexes.sql
--
-- Description:
-- This script defines all database indexes for the NYC Taxi MDM project.
-- It is designed to be idempotent and can be executed multiple times
-- without causing errors. Indexes are critical for query performance.
--
-- Best Practices:
-- - Use `CREATE INDEX IF NOT EXISTS` to ensure idempotency.
-- - Index all foreign key columns to prevent table-locking on deletes
--   and to improve join performance.
-- - Create indexes to support frequent query patterns (e.g., WHERE clauses,
--   ORDER BY clauses).
-- - Name indexes clearly using the pattern: idx_{table_name}_{column_names}.
-- =================================================================

-- =================================================================
-- Table: vendors
-- For SCD Type 2 we enforce uniqueness only for the current row using a partial unique index.
-- Create the following partial unique index (CONCURRENTLY in production):
-- CREATE UNIQUE INDEX CONCURRENTLY idx_vendors_vendor_name_current ON vendors (vendor_name) WHERE is_current;
-- Recommended supporting index (CONCURRENTLY):
-- CREATE INDEX CONCURRENTLY idx_vendors_vendorid_effective_date ON vendors (vendor_id, effective_date);
-- Note: Do not drop the original UNIQUE constraint until partial unique index is in place and validated.
-- =================================================================

-- =================================================================
-- Table: taxi_zones
-- Indexes to speed up lookups by zone, borough, or service zone.
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_taxi_zones_zone ON taxi_zones(zone);
CREATE INDEX IF NOT EXISTS idx_taxi_zones_borough ON taxi_zones(borough);

-- =================================================================
-- Table: golden_zones
-- For SCD Type 2 we enforce uniqueness only for the current row using a partial unique index.
-- Keep the legacy UNIQUE(borough, zone) until migration 008 removes it after validation.
-- Create the following partial unique index (CONCURRENTLY in production):
-- CREATE UNIQUE INDEX CONCURRENTLY idx_golden_locationid_current ON golden_zones (location_id) WHERE is_current AND location_id IS NOT NULL;
-- Recommended supporting indexes (CONCURRENTLY):
-- CREATE INDEX CONCURRENTLY idx_golden_borough_zone_effective ON golden_zones (borough, zone, effective_date);
-- CREATE INDEX CONCURRENTLY idx_golden_effective_date ON golden_zones (effective_date);
-- Note: Do not drop the original UNIQUE constraint until the partial unique index is in place and validated.

-- =================================================================
-- Table: zone_matches
-- Description: Foreign key columns must be indexed.
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_zone_matches_golden_zone_id ON zone_matches(golden_zone_id);
CREATE INDEX IF NOT EXISTS idx_zone_matches_source_zone_id ON zone_matches(source_zone_id);
CREATE INDEX IF NOT EXISTS idx_zone_matches_status ON zone_matches(status);

-- =================================================================
-- Table: pipeline_runs
-- Description: Indexes to support filtering runs by job name or status.
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_job_name ON pipeline_runs(job_name);
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_status ON pipeline_runs(status);
CREATE INDEX IF NOT EXISTS idx_pipeline_runs_started_at ON pipeline_runs(started_at DESC);

-- =================================================================
-- Table: audit_log
-- Description: Indexes to support searching the audit trail.
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_audit_log_table_name_record_id ON audit_log(table_name, record_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_changed_at ON audit_log(changed_at DESC);
