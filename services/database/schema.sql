-- =================================================================
-- services/database/schema.sql
--
-- Description:
-- This script defines the database schema for the NYC Taxi MDM project.
-- It is designed to be idempotent and can be executed multiple times
-- without causing errors or creating duplicate objects.
--
-- Best Practices:
-- - Uses `CREATE TABLE IF NOT EXISTS` to prevent errors on re-runs.
-- - Uses `CREATE OR REPLACE FUNCTION` for the timestamp utility.
-- - Uses `DROP TRIGGER IF EXISTS ...; CREATE TRIGGER ...;` for idempotency.
-- - Uses `TIMESTAMPTZ` for all timestamp columns to store timezone information.
-- =================================================================

-- =================================================================
-- Function: update_updated_at_column
-- Description:
-- This trigger function automatically updates the `updated_at` column
-- to the current timestamp whenever a row is updated.
-- =================================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- =================================================================
-- Table: vendors
-- Description: Stores the master list of taxi vendors.
-- =================================================================
CREATE TABLE IF NOT EXISTS vendors (
  vendor_id SERIAL PRIMARY KEY,
  vendor_name VARCHAR(255) NOT NULL UNIQUE,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

DROP TRIGGER IF EXISTS update_vendors_updated_at ON vendors;
CREATE TRIGGER update_vendors_updated_at
  BEFORE UPDATE ON vendors
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =================================================================
-- Table: taxi_zones
-- Description: Stores the raw taxi zone reference data, loaded from external source.
-- =================================================================
CREATE TABLE IF NOT EXISTS taxi_zones (
  location_id INT PRIMARY KEY,
  borough VARCHAR(255) NOT NULL,
  zone VARCHAR(255) NOT NULL,
  service_zone VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

DROP TRIGGER IF EXISTS update_taxi_zones_updated_at ON taxi_zones;
CREATE TRIGGER update_taxi_zones_updated_at
  BEFORE UPDATE ON taxi_zones
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =================================================================
-- Table: golden_zones
-- Description:
-- This is the master data table for taxi zones. It stores the canonical,
-- clean, and de-duplicated version of zone information.
-- The business key is `(borough, zone)`.
-- =================================================================
CREATE TABLE IF NOT EXISTS golden_zones (
  golden_id SERIAL PRIMARY KEY,
  borough VARCHAR(255) NOT NULL,
  zone VARCHAR(255) NOT NULL,
  service_zone VARCHAR(255),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(borough, zone) -- A zone name must be unique within a borough
);

DROP TRIGGER IF EXISTS update_golden_zones_updated_at ON golden_zones;
CREATE TRIGGER update_golden_zones_updated_at
  BEFORE UPDATE ON golden_zones
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =================================================================
-- Table: zone_matches
-- Description:
-- Stores the relationships between source taxi zones and their
-- corresponding golden records as determined by the matching engine.
-- =================================================================
CREATE TABLE IF NOT EXISTS zone_matches (
  match_id SERIAL PRIMARY KEY,
  golden_zone_id INT NOT NULL REFERENCES golden_zones(golden_id),
  source_zone_id INT NOT NULL REFERENCES taxi_zones(location_id),
  confidence_score DECIMAL(5, 4) NOT NULL CHECK (confidence_score >= 0 AND confidence_score <= 1),
  status VARCHAR(20) NOT NULL CHECK (status IN ('pending', 'confirmed', 'rejected')),
  operation VARCHAR(20) NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP -- Corrected typo from TIMSTAMPTZ
);

DROP TRIGGER IF EXISTS update_zone_matches_updated_at ON zone_matches;
CREATE TRIGGER update_zone_matches_updated_at
  BEFORE UPDATE ON zone_matches
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- =================================================================
-- Table: pipeline_runs
-- Description:
-- Logs every execution of an ETL/data pipeline job.
-- =================================================================
CREATE TABLE IF NOT EXISTS pipeline_runs (
  run_id VARCHAR(255) PRIMARY KEY,
  job_name VARCHAR(255) NOT NULL,
  status VARCHAR(50) NOT NULL,
  records_processed BIGINT,
  started_at TIMESTAMPTZ NOT NULL,
  completed_at TIMESTAMPTZ,
  execution_time_seconds BIGINT
);

-- =================================================================
-- Table: audit_log
-- Description:
-- Tracks all changes (inserts, updates, deletes) to critical data,
-- such as golden records, for traceability and governance.
-- =================================================================
CREATE TABLE IF NOT EXISTS audit_log (
  audit_id SERIAL PRIMARY KEY,
  table_name VARCHAR(255) NOT NULL,
  record_id VARCHAR(255),
  operation VARCHAR(50) NOT NULL, -- e.g., 'INSERT', 'UPDATE', 'DELETE'
  changed_by VARCHAR(255) NOT NULL,
  changed_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  old_values JSONB,
  new_values JSONB
);
