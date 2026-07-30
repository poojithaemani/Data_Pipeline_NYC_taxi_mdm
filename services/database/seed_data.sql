-- =================================================================
-- File: services/database/seed_data.sql
-- Project: NYC Taxi MDM Data Pipeline
--
-- Description:
-- Seeds small, static master/reference data required by the application.
-- This script is idempotent and can be executed multiple times safely.
--
-- Large reference datasets (e.g., Taxi Zones) are intentionally excluded
-- and are loaded through the data ingestion pipeline.
-- =================================================================

BEGIN;

-- =================================================================
-- Vendors
-- Description:
-- Inserts the master list of taxi vendors.
-- Existing vendors are skipped using ON CONFLICT.
-- =================================================================

INSERT INTO vendors (vendor_name)
VALUES
    ('Creative Mobile Technologies'),
    ('VeriFone Inc.')
ON CONFLICT (vendor_name) DO NOTHING;

COMMIT;

-- =================================================================
-- Taxi Zones
--
-- This table is NOT populated by this SQL script.
--
-- Data is loaded by the ingestion/ETL pipeline from the official source:
--
-- https://d37ci6vzurychx.cloudfront.net/misc/taxi+_zone_lookup.csv
--
-- ETL Responsibilities:
--   1. Download latest CSV
--   2. Validate data
--   3. Clean missing values
--   4. UPSERT records into taxi_zones
--
-- UPSERT Strategy:
--
-- INSERT ...
-- ON CONFLICT (location_id)
-- DO UPDATE SET
--     borough = EXCLUDED.borough,
--     zone = EXCLUDED.zone,
--     service_zone = EXCLUDED.service_zone;
--
-- This ensures new zones are inserted and existing zones are updated
-- whenever the source dataset changes.
-- =================================================================