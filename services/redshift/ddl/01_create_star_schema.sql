-- =================================================================
-- services/redshift/ddl/01_create_star_schema.sql
--
-- Creates the taxi_analytics star schema in Redshift Serverless
-- (namespace nyc-taxi-mdm, workgroup nyc-taxi-mdm-wg, database
-- taxi_analytics).
--
-- Constraints:
--   Redshift accepts PRIMARY KEY, FOREIGN KEY and UNIQUE but never
--   enforces them; there is no NOT ENFORCED keyword because informational
--   is the only mode available. They are declared purely so the query
--   planner can eliminate redundant joins and apply uniqueness-aware
--   optimisations. Actual integrity is guaranteed upstream by the Silver
--   cleaning rules, the golden_zones partial unique index and zone_matches,
--   and is proven by 03_reconciliation.sql - never by the engine.
--
-- Distribution:
--   Every dimension is DISTSTYLE ALL, so it is replicated to all nodes and
--   joins to it need no redistribution at all. That is precisely why
--   fact_trips is EVEN rather than keyed: a DISTKEY on pickup_location_id
--   would buy nothing against a replicated dimension, could only ever serve
--   one of the two zone joins, and would introduce real skew because NYC
--   pickups concentrate heavily in a handful of zones.
--
-- Sorting:
--   Every analytical query filters by time. date_key is monotonic with
--   pickup_datetime, so sorting on the timestamp lets zone maps prune
--   date_key predicates as well.
--
-- Execution order:
--   Dimensions first - Redshift requires a referenced column to already
--   carry a PRIMARY KEY or UNIQUE constraint before a FOREIGN KEY can
--   name it.
-- =================================================================

-- =================================================================
-- dim_zone - the MDM-mastered zone dimension (265 rows)
--
-- golden_zone_row_id is carried so any warehouse row can be traced back
-- to the exact SCD Type 2 version in RDS that produced it.
-- =================================================================
CREATE TABLE IF NOT EXISTS dim_zone (
    location_id        SMALLINT      NOT NULL,
    borough            VARCHAR(50)   NOT NULL,
    zone               VARCHAR(100)  NOT NULL,
    service_zone       VARCHAR(50)   NOT NULL,
    golden_zone_row_id BIGINT        NOT NULL,
    version            SMALLINT      NOT NULL,
    PRIMARY KEY (location_id)
)
DISTSTYLE ALL
SORTKEY (location_id);

-- =================================================================
-- dim_date - gap-free calendar over the fact's pickup date range (33 rows)
-- =================================================================
CREATE TABLE IF NOT EXISTS dim_date (
    date_key    INTEGER    NOT NULL,
    full_date   DATE       NOT NULL,
    year        SMALLINT   NOT NULL,
    month       SMALLINT   NOT NULL,
    day         SMALLINT   NOT NULL,
    day_of_week SMALLINT   NOT NULL,
    day_name    VARCHAR(9) NOT NULL,
    is_weekend  BOOLEAN    NOT NULL,
    PRIMARY KEY (date_key)
)
DISTSTYLE ALL
SORTKEY (date_key);

-- =================================================================
-- dim_payment - full TLC payment code set (7 rows)
--
-- All seven codes are loaded even though only 1-5 occur in the current
-- data, so a later month containing code 0 or 6 cannot orphan a fact row.
-- =================================================================
CREATE TABLE IF NOT EXISTS dim_payment (
    payment_type        SMALLINT    NOT NULL,
    payment_description VARCHAR(30) NOT NULL,
    PRIMARY KEY (payment_type)
)
DISTSTYLE ALL
SORTKEY (payment_type);

-- =================================================================
-- fact_trips - one row per Silver trip (2,851,125 rows)
--
-- No surrogate key. Silver has no stable natural trip identifier, nothing
-- downstream needs one, and a Redshift IDENTITY column would renumber every
-- trip on each reload because values are assigned non-deterministically
-- across slices.
--
-- vendorid is a degenerate dimension: no authoritative vendor master exists
-- for this project, and the data contains a vendor code (7) that no
-- available source can even name.
--
-- NOT NULL is applied only to the grain and foreign-key columns, which the
-- frozen Silver job guarantees via dropna and its positive-value filters.
-- The measures stay nullable: Silver never validates tip_amount or
-- total_amount, so today's zero-null state is data luck, not a contract.
-- =================================================================
CREATE TABLE IF NOT EXISTS fact_trips (
    vendorid            SMALLINT      NOT NULL,
    pickup_datetime     TIMESTAMP     NOT NULL,
    dropoff_datetime    TIMESTAMP     NOT NULL,
    date_key            INTEGER       NOT NULL,
    pickup_location_id  SMALLINT      NOT NULL,
    dropoff_location_id SMALLINT      NOT NULL,
    payment_type        SMALLINT      NOT NULL,
    passenger_count     SMALLINT      NOT NULL,
    trip_distance       DECIMAL(10,2),
    fare_amount         DECIMAL(10,2),
    tip_amount          DECIMAL(10,2),
    total_amount        DECIMAL(10,2),
    FOREIGN KEY (date_key)            REFERENCES dim_date(date_key),
    FOREIGN KEY (pickup_location_id)  REFERENCES dim_zone(location_id),
    FOREIGN KEY (dropoff_location_id) REFERENCES dim_zone(location_id),
    FOREIGN KEY (payment_type)        REFERENCES dim_payment(payment_type)
)
DISTSTYLE EVEN
COMPOUND SORTKEY (pickup_datetime);

-- End of 01_create_star_schema.sql
