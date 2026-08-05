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
-- uix_vendors_current: Ensures only one "current" row per vendor_id. This is critical for SCD2.
-- idx_vendors_lookup: Speeds up historical lookups by business key.
-- =================================================================
CREATE UNIQUE INDEX IF NOT EXISTS uix_vendors_current ON vendors (vendor_id) WHERE is_current = true;
CREATE INDEX IF NOT EXISTS idx_vendors_lookup ON vendors (vendor_id, effective_date DESC);

-- =================================================================
-- Table: taxi_zones
-- Index to speed up lookups by borough and zone.
-- =================================================================
CREATE INDEX IF NOT EXISTS idx_taxi_zones_lookup ON taxi_zones(borough, zone);

-- =================================================================
-- Table: golden_zones
-- uix_golden_zones_current: Ensures only one "current" row per location_id.
-- idx_golden_zones_lookup: Speeds up historical lookups.
-- =================================================================
CREATE UNIQUE INDEX IF NOT EXISTS uix_golden_zones_current ON golden_zones (location_id) WHERE is_current = true;
CREATE INDEX IF NOT EXISTS idx_golden_zones_lookup ON golden_zones (location_id, effective_date DESC);

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
