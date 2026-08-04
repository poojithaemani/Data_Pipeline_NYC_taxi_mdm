-- services/database/tests/test_vendor.sql
--
-- Simple, repeatable tests for sp_upsert_vendor
-- Tests cover:
-- 1) Insert new record
-- 2) Same record_hash => NO_CHANGE
-- 3) Different record_hash => new version created
--
-- NOTE: Run these in a development/staging database only.
-- The script cleans up the test vendor at start so it can be re-run.

-- Test parameters
\set test_vendor_id 99999
\set v1 'hash_v1'
\set v2 'hash_v2'

-- Cleanup
DELETE FROM vendors WHERE vendor_id = :test_vendor_id;

-- Test 1: Insert new record
-- Expect: one row inserted with version = 1, is_current = TRUE
CALL sp_upsert_vendor(:test_vendor_id, 'Test Vendor', :v1, NULL, NULL);
SELECT vendor_row_id, vendor_id, vendor_name, record_hash, version, is_current, effective_date, end_date
FROM vendors WHERE vendor_id = :test_vendor_id ORDER BY created_at;

-- Test 2: Same record_hash -> NO_CHANGE
-- Expect: still one current row with version = 1
CALL sp_upsert_vendor(:test_vendor_id, 'Test Vendor', :v1, NULL, NULL);
SELECT COUNT(*) AS total_rows, SUM(CASE WHEN is_current THEN 1 ELSE 0 END) AS current_count,
       MAX(version) AS max_version
FROM vendors WHERE vendor_id = :test_vendor_id;

-- Test 3: Different record_hash -> new version
-- Expect: previous row expired (is_current = FALSE), new row inserted with version = 2
CALL sp_upsert_vendor(:test_vendor_id, 'Test Vendor Updated', :v2, NULL, NULL);
SELECT vendor_row_id, vendor_id, vendor_name, record_hash, version, is_current, effective_date, end_date
FROM vendors WHERE vendor_id = :test_vendor_id ORDER BY version;

-- Cleanup (optional)
-- DELETE FROM vendors WHERE vendor_id = :test_vendor_id;

-- End of test script
