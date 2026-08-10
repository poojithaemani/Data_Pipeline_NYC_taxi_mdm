-- =================================================================
-- services/redshift/load/02_copy_from_s3.sql
--
-- Loads the star schema from the Parquet warehouse snapshot written by
-- pipeline/glue/jobs/warehouse_export_etl.py.
--
-- Source:
--   s3://emani-nyc-taxi-bucket/warehouse/  - plain Snappy Parquet.
--   The Gold Delta tables are deliberately NOT the source: Redshift COPY
--   cannot read Delta Lake, and Gold is pre-aggregated with no dimensional
--   keys, so it cannot supply a trip-grain fact table.
--
-- Credentials:
--   The existing nyc-taxi-mdm-redshift-role, already attached to the
--   namespace and already granted s3:GetObject on the data lake bucket.
--   No IAM change is required for the warehouse/ prefix.
--
-- Parquet and partitioning:
--   COPY reads every file under the prefix and ignores Hive-style path
--   partitioning entirely. fact_trips is therefore written unpartitioned:
--   Spark strips partition columns out of the data files, so a partitioned
--   layout would load date_key as NULL for all 2.85 million rows.
--
-- Order:
--   Dimensions first, then the fact - matching the declared foreign keys.
--   TRUNCATE first so re-running produces the same deterministic snapshot
--   rather than duplicating rows; COPY has no upsert mode.
-- =================================================================

-- =================================================================
-- Dimensions
-- =================================================================
TRUNCATE TABLE dim_zone;

COPY dim_zone
FROM 's3://emani-nyc-taxi-bucket/warehouse/dim_zone/'
IAM_ROLE 'arn:aws:iam::749185461065:role/nyc-taxi-mdm-redshift-role'
FORMAT AS PARQUET;

TRUNCATE TABLE dim_date;

COPY dim_date
FROM 's3://emani-nyc-taxi-bucket/warehouse/dim_date/'
IAM_ROLE 'arn:aws:iam::749185461065:role/nyc-taxi-mdm-redshift-role'
FORMAT AS PARQUET;

TRUNCATE TABLE dim_payment;

COPY dim_payment
FROM 's3://emani-nyc-taxi-bucket/warehouse/dim_payment/'
IAM_ROLE 'arn:aws:iam::749185461065:role/nyc-taxi-mdm-redshift-role'
FORMAT AS PARQUET;

-- =================================================================
-- Fact
-- =================================================================
TRUNCATE TABLE fact_trips;

COPY fact_trips
FROM 's3://emani-nyc-taxi-bucket/warehouse/fact_trips/'
IAM_ROLE 'arn:aws:iam::749185461065:role/nyc-taxi-mdm-redshift-role'
FORMAT AS PARQUET;

-- =================================================================
-- Post-load statistics
--
-- COPY updates statistics automatically for an empty target table, but
-- ANALYZE is run explicitly so the planner has accurate row counts for the
-- star joins immediately.
-- =================================================================
ANALYZE dim_zone;
ANALYZE dim_date;
ANALYZE dim_payment;
ANALYZE fact_trips;

-- =================================================================
-- Load summary (read-only)
-- =================================================================
SELECT 'fact_trips'  AS table_name, COUNT(*) AS rows FROM fact_trips
UNION ALL SELECT 'dim_zone',    COUNT(*) FROM dim_zone
UNION ALL SELECT 'dim_date',    COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_payment', COUNT(*) FROM dim_payment
ORDER BY table_name;

-- End of 02_copy_from_s3.sql
