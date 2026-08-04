-- services/database/tests/test_golden_zone.sql
--
-- Simple tests for sp_upsert_golden_zone
-- Tests cover:
-- 1) Insert new record
-- 2) Same record_hash => NO_CHANGE
-- 3) Different record_hash => new version created
--
-- NOTE: Run these in a development/staging database only.
-- The script cleans up the test location at start so it can be re-run.

-- Test parameters
\set test_location_id 99999
\set v1 'hash_v1'
\set v2 'hash_v2'

-- Cleanup
DELETE FROM golden_zones WHERE location_id = :test_location_id;

-- Test 1: Insert new record
-- Expect: one row inserted with version = 1, is_current = TRUE
CALL sp_upsert_golden_zone(:test_location_id, 'TestBorough', 'TestZone', 'TestService', :'hash_v1', NULL, NULL);
SELECT golden_zone_row_id, location_id, borough, zone, service_zone, record_hash, version, is_current, effective_date, end_date
FROM golden_zones WHERE location_id = :test_location_id ORDER BY effective_date;

-- Test 2: Same record_hash -> NO_CHANGE
CALL sp_upsert_golden_zone(:test_location_id, 'TestBorough', 'TestZone', 'TestService', :'hash_v1', NULL, NULL);
SELECT COUNT(*) AS total_rows, SUM(CASE WHEN is_current THEN 1 ELSE 0 END) AS current_count,
       MAX(version) AS max_version
FROM golden_zones WHERE location_id = :test_location_id;

-- Test 3: Different record_hash -> new version
CALL sp_upsert_golden_zone(:test_location_id, 'TestBorough', 'TestZone Updated', 'TestService', :'hash_v2', NULL, NULL);
SELECT golden_zone_row_id, location_id, borough, zone, service_zone, record_hash, version, is_current, effective_date, end_date
FROM golden_zones WHERE location_id = :test_location_id ORDER BY version;

-- Cleanup (optional)
-- DELETE FROM golden_zones WHERE location_id = :test_location_id;

-- End of test script
