-- =================================================================
-- File: queries/examples.sql
-- Description: Example Athena queries for validation and analysis.
-- =================================================================

-- =================================================================
-- Validation Queries
-- =================================================================

-- Query 1: Preview Bronze data
-- Description: Check the raw data in the bronze layer.
SELECT * FROM "bronze_db"."bronze_transactions_yellow_taxi" LIMIT 10;

-- Query 2: Preview Silver data
-- Description: Check the cleaned and partitioned data in the silver layer.
SELECT * FROM "silver_db"."silver_yellow_taxi" LIMIT 10;

-- Query 3: Preview Gold data (Daily Summary)
-- Description: Check one of the aggregated gold tables.
SELECT * FROM "gold_db"."gold_daily_summary" ORDER BY trip_date DESC LIMIT 10;

-- Query 4: Count rows in each layer for a specific period
-- Description: Useful for verifying data flow between layers.
SELECT
    (SELECT COUNT(*) FROM "bronze_db"."bronze_transactions_yellow_taxi" WHERE year = '2023' AND month = '01') AS bronze_count,
    (SELECT COUNT(*) FROM "silver_db"."silver_yellow_taxi" WHERE pickup_year = 2023 AND pickup_month = 1) AS silver_count;


-- =================================================================
-- Business Queries
-- =================================================================

-- Query 5: Top 10 Busiest Days
-- Description: Identify the days with the highest number of trips from the daily summary table.
SELECT
    trip_date,
    total_trips,
    total_revenue
FROM "gold_db"."gold_daily_summary"
ORDER BY total_trips DESC
LIMIT 10;

-- Query 6: Vendor Performance Comparison
-- Description: Compare the total revenue and trip count for each vendor on a specific date.
SELECT
    trip_date,
    "vendorid",
    total_revenue,
    trip_count
FROM "gold_db"."gold_vendor_summary"
WHERE trip_date = DATE('2023-01-15') -- Example date
ORDER BY total_revenue DESC;
