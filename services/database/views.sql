-- =================================================================
-- services/database/views.sql
--
-- Description:
-- This script defines all database views for the NYC Taxi MDM project.
-- Views are used to simplify complex queries, encapsulate business logic,
-- and provide a stable interface to the underlying tables.
--
-- Best Practices:
-- - Use `CREATE OR REPLACE VIEW` to ensure idempotency.
-- - Use clear and consistent table and column aliases.
-- - Select only the necessary columns to keep the view focused.
-- - Format joins and clauses for readability.
-- =================================================================

-- =================================================================
-- View: vw_zone_matches_details
-- Purpose:
-- Provides a de-normalized, detailed view of zone matches, joining
-- the golden zone and source zone information for easy comparison and analysis.
-- =================================================================
CREATE OR REPLACE VIEW vw_zone_matches_details AS
SELECT
    zm.match_id,
    zm.status,
    zm.confidence_score,
    -- Golden Record Details
    gz.golden_id,
    gz.borough         AS golden_borough,
    gz.zone            AS golden_zone,
    gz.service_zone    AS golden_service_zone,
    -- Source Record Details
    tz.location_id     AS source_location_id,
    tz.borough         AS source_borough,
    tz.zone            AS source_zone,
    tz.service_zone    AS source_service_zone,
    -- Timestamps
    zm.created_at,
    zm.updated_at
FROM
    zone_matches zm
JOIN
    golden_zones gz ON zm.golden_zone_id = gz.golden_id
JOIN
    taxi_zones tz ON zm.source_zone_id = tz.location_id;

-- =================================================================
-- View: vw_pipeline_runs_summary
-- Purpose:
-- Summarizes ETL pipeline run history, including a calculated
-- execution time for completed runs.
-- =================================================================
CREATE OR REPLACE VIEW vw_pipeline_runs_summary AS
SELECT
    pr.run_id,
    pr.job_name,
    pr.status,
    pr.records_processed,
    pr.started_at,
    pr.completed_at,
    -- Calculate execution time only if the run is complete
    CASE
        WHEN pr.completed_at IS NOT NULL THEN
            EXTRACT(EPOCH FROM (pr.completed_at - pr.started_at))
        ELSE NULL
    END AS execution_time_seconds
FROM
    pipeline_runs pr;

-- =================================================================
-- View: vw_audit_log_details
-- Purpose:
-- Provides a detailed view of the audit log for tracking changes
-- to data records.
-- =================================================================
CREATE OR REPLACE VIEW vw_audit_log_details AS
SELECT
    al.audit_id,
    al.table_name,
    al.record_id,
    al.operation,
    al.changed_by,
    al.changed_at,
    al.old_values,
    al.new_values
FROM
    audit_log al;
