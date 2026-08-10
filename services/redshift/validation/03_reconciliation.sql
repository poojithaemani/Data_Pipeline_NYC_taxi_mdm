-- =================================================================
-- services/redshift/validation/03_reconciliation.sql
--
-- Full reconciliation of the taxi_analytics star schema.
--
-- Two kinds of check live here:
--
--   Sections A-I and O-Q run entirely inside Redshift and return an
--   explicit PASS / FAIL verdict.
--
--   Sections J-N reconcile Redshift against the frozen Gold Delta tables,
--   which Redshift cannot read. Each emits the Redshift-side aggregate in
--   the exact shape of its Gold counterpart so a cross-engine harness can
--   diff it against the same query run in Athena. Gold is never modified.
--
-- Two traps this file encodes deliberately:
--
--   1. gold_db.payment_summary.total_amount does NOT contain total_amount.
--      The frozen yellow_taxi_gold_etl.py computes
--      F.sum("fare_amount").alias("total_amount"). Comparing the fact's
--      total_amount against it would show a phantom 51% shortfall
--      (79,198,239 vs 52,389,613). Section L therefore compares trip
--      counts only.
--
--   2. Gold stores revenue as DOUBLE and accumulates it in a
--      non-deterministic order, so the same logical sum differs between
--      Gold tables in the tenth decimal place. fact_trips uses
--      DECIMAL(10,2), which sums exactly, so the tolerance belongs on the
--      Gold side: compare ROUND(gold, 2) within +/- 0.01.
-- =================================================================

-- =================================================================
-- A-D. Row counts
-- =================================================================
SELECT 'A. fact_trips count'  AS check_name, COUNT(*) AS actual, 2851125 AS expected,
       CASE WHEN COUNT(*) = 2851125 THEN 'PASS' ELSE 'FAIL' END AS verdict FROM fact_trips
UNION ALL
SELECT 'B. dim_zone count',    COUNT(*), 265,
       CASE WHEN COUNT(*) = 265 THEN 'PASS' ELSE 'FAIL' END FROM dim_zone
UNION ALL
SELECT 'C. dim_date count',    COUNT(*), 33,
       CASE WHEN COUNT(*) = 33 THEN 'PASS' ELSE 'FAIL' END FROM dim_date
UNION ALL
SELECT 'D. dim_payment count', COUNT(*), 7,
       CASE WHEN COUNT(*) = 7 THEN 'PASS' ELSE 'FAIL' END FROM dim_payment
ORDER BY check_name;

-- =================================================================
-- E-H. Referential integrity and required keys
-- =================================================================
SELECT 'E. unresolved pickup locations' AS check_name, COUNT(*) AS actual, 0 AS expected,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM fact_trips f
LEFT JOIN dim_zone z ON z.location_id = f.pickup_location_id
WHERE z.location_id IS NULL

UNION ALL
SELECT 'F. unresolved dropoff locations', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_trips f
LEFT JOIN dim_zone z ON z.location_id = f.dropoff_location_id
WHERE z.location_id IS NULL

UNION ALL
SELECT 'F2. unresolved payment types', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_trips f
LEFT JOIN dim_payment p ON p.payment_type = f.payment_type
WHERE p.payment_type IS NULL

UNION ALL
SELECT 'F3. unresolved date keys', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_trips f
LEFT JOIN dim_date d ON d.date_key = f.date_key
WHERE d.date_key IS NULL

UNION ALL
SELECT 'G. duplicate dim_zone keys', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT location_id FROM dim_zone GROUP BY location_id HAVING COUNT(*) > 1) dz

UNION ALL
SELECT 'G2. duplicate dim_date keys', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT date_key FROM dim_date GROUP BY date_key HAVING COUNT(*) > 1) dd

UNION ALL
SELECT 'G3. duplicate dim_payment keys', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT payment_type FROM dim_payment GROUP BY payment_type HAVING COUNT(*) > 1) dp

UNION ALL
SELECT 'H. fact rows with NULL required keys', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM fact_trips
WHERE vendorid            IS NULL
   OR pickup_datetime     IS NULL
   OR dropoff_datetime    IS NULL
   OR date_key            IS NULL
   OR pickup_location_id  IS NULL
   OR dropoff_location_id IS NULL
   OR payment_type        IS NULL
   OR passenger_count     IS NULL
ORDER BY check_name;

-- =================================================================
-- I. Star-schema join - every fact row must resolve through all four
--    dimensions simultaneously, not just one at a time.
-- =================================================================
SELECT 'I. full star join resolves' AS check_name,
       COUNT(*) AS actual, 2851125 AS expected,
       CASE WHEN COUNT(*) = 2851125 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM fact_trips f
JOIN dim_zone    zp ON zp.location_id  = f.pickup_location_id
JOIN dim_zone    zd ON zd.location_id  = f.dropoff_location_id
JOIN dim_date    d  ON d.date_key      = f.date_key
JOIN dim_payment p  ON p.payment_type  = f.payment_type;

-- A worked example proving the dimensions actually carry business meaning.
SELECT zp.borough      AS pickup_borough,
       zd.borough      AS dropoff_borough,
       d.day_name,
       p.payment_description,
       COUNT(*)               AS trips,
       ROUND(SUM(f.fare_amount), 2) AS fare_revenue
FROM fact_trips f
JOIN dim_zone    zp ON zp.location_id = f.pickup_location_id
JOIN dim_zone    zd ON zd.location_id = f.dropoff_location_id
JOIN dim_date    d  ON d.date_key     = f.date_key
JOIN dim_payment p  ON p.payment_type = f.payment_type
GROUP BY 1, 2, 3, 4
ORDER BY trips DESC
LIMIT 10;

-- =================================================================
-- J. Daily trip counts   -> compare with gold_db.daily_summary
--    (trip_date, total_trips)
-- =================================================================
SELECT d.full_date AS trip_date, COUNT(*) AS trip_count
FROM fact_trips f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date
ORDER BY d.full_date;

-- =================================================================
-- K. Vendor counts       -> compare with gold_db.vendor_summary
--    (trip_date, vendorid, trip_count)
--    vendorid is degenerate: read straight off the fact, no dim_vendor.
-- =================================================================
SELECT d.full_date AS trip_date, f.vendorid, COUNT(*) AS trip_count
FROM fact_trips f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date, f.vendorid
ORDER BY d.full_date, f.vendorid;

-- =================================================================
-- L. Payment counts      -> compare with gold_db.payment_summary
--    (trip_date, payment_type, trip_count)
--    COUNTS ONLY. Do not compare amounts against
--    payment_summary.total_amount - that column holds SUM(fare_amount).
-- =================================================================
SELECT d.full_date AS trip_date, f.payment_type, COUNT(*) AS trip_count
FROM fact_trips f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date, f.payment_type
ORDER BY d.full_date, f.payment_type;

-- =================================================================
-- M. Hourly counts       -> compare with gold_db.hourly_summary
--    (trip_date, pickup_hour, trip_count)
-- =================================================================
SELECT d.full_date AS trip_date,
       DATE_PART(hour, f.pickup_datetime)::SMALLINT AS pickup_hour,
       COUNT(*) AS trip_count
FROM fact_trips f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY 1, 2
ORDER BY 1, 2;

-- =================================================================
-- N. Revenue             -> compare with gold_db.daily_summary.total_revenue
--    Gold's total_revenue is SUM(fare_amount), correctly named here.
--    Compare ROUND(gold, 2) within +/- 0.01.
-- =================================================================
-- The averages use SUM/COUNT rather than AVG: Redshift's AVG over a
-- DECIMAL(10,2) column returns a DECIMAL(10,2), which would silently
-- truncate the comparison to two decimal places. Division widens the scale
-- and keeps the tie-out meaningful.
SELECT d.full_date AS trip_date,
       ROUND(SUM(f.fare_amount), 2)                  AS fare_revenue,
       ROUND(SUM(f.fare_amount) / COUNT(*), 4)       AS average_fare,
       ROUND(SUM(f.trip_distance) / COUNT(*), 4)     AS average_distance
FROM fact_trips f
JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date
ORDER BY d.full_date;

-- Global figures. The overall average must be SUM/COUNT, never the mean of
-- the 33 daily averages - the days carry unequal weight (66,640 to 110,982
-- trips), so averaging averages gives the wrong answer.
SELECT ROUND(SUM(fare_amount), 2)                          AS total_fare_revenue,
       ROUND(SUM(fare_amount) / COUNT(*), 10)              AS weighted_average_fare,
       ROUND(SUM(trip_distance) / COUNT(*), 10)            AS weighted_average_distance,
       ROUND(SUM(total_amount), 2)                         AS total_amount_sum
FROM fact_trips;

-- =================================================================
-- O. The location_id = 99999 test fixture must never reach the warehouse.
--    Its golden_zones version 2 is is_current = TRUE, so a naive
--    `WHERE is_current` returns 266 rows. The zone_matches join excludes
--    it structurally; this check proves that held.
-- =================================================================
SELECT 'O. dim_zone excludes fixture 99999' AS check_name,
       COUNT(*) AS actual, 0 AS expected,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS verdict
FROM dim_zone
WHERE location_id = 99999 OR borough ILIKE 'Test%' OR zone ILIKE 'Test%'

UNION ALL
SELECT 'O2. dim_zone ids all within 1..265', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM dim_zone
WHERE location_id NOT BETWEEN 1 AND 265

UNION ALL
-- =================================================================
-- P. Every dimension row must carry complete MDM lineage and attributes.
-- =================================================================
SELECT 'P. dim_zone rows fully populated', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM dim_zone
WHERE golden_zone_row_id IS NULL
   OR version            IS NULL
   OR borough            IS NULL OR BTRIM(borough)      = ''
   OR zone               IS NULL OR BTRIM(zone)         = ''
   OR service_zone       IS NULL OR BTRIM(service_zone) = ''

UNION ALL
SELECT 'P2. dim_zone golden_zone_row_id unique', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT golden_zone_row_id FROM dim_zone
      GROUP BY golden_zone_row_id HAVING COUNT(*) > 1) gz

UNION ALL
SELECT 'P3. dim_date has no calendar gaps', COUNT(*), 0,
       CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT DATEDIFF(day, MIN(full_date), MAX(full_date)) + 1 AS span,
             COUNT(*) AS n_rows
      FROM dim_date) cal
WHERE span <> n_rows
ORDER BY check_name;

-- =================================================================
-- Q. Physical design - confirm the declared distribution and sort keys
--    actually took effect.
--
-- Expected:
--   fact_trips   diststyle EVEN,       sortkey1 pickup_datetime
--   dim_zone     diststyle ALL,        sortkey1 location_id
--   dim_date     diststyle ALL,        sortkey1 date_key
--   dim_payment  diststyle ALL,        sortkey1 payment_type
-- =================================================================
SELECT "table" AS table_name,
       diststyle,
       sortkey1,
       sortkey_num,
       tbl_rows::BIGINT AS approx_rows,
       unsorted,
       skew_rows
FROM svv_table_info
WHERE "table" IN ('fact_trips', 'dim_zone', 'dim_date', 'dim_payment')
ORDER BY "table";

-- Confirm the declared informational constraints are registered.
SELECT c.relname AS table_name, con.conname AS constraint_name, con.contype AS constraint_type
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
WHERE c.relname IN ('fact_trips', 'dim_zone', 'dim_date', 'dim_payment')
ORDER BY c.relname, con.contype, con.conname;

-- End of 03_reconciliation.sql
