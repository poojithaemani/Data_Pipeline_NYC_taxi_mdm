-- =================================================================
-- services/database/populate_zone_matches.sql
--
-- Description:
-- Populates zone_matches, satisfying the MDM "Matching" requirement.
--
-- Matching strategy:
--   Deterministic exact match on the business key (location_id) between
--   taxi_zones (source records) and the CURRENT version of golden_zones
--   (mastered records). Taxi Zones originate from a single authoritative
--   source file, so exact business-key matching is the correct technique --
--   there is no second source to reconcile probabilistically.
--
-- Idempotency:
--   Guarded by NOT EXISTS on (source_zone_id, golden_zone_row_id).
--   ON CONFLICT is deliberately NOT used: the live schema has no unique
--   constraint on that natural key, and this script does not add one.
--
-- SCD Type 2 awareness:
--   golden_zone_row_id identifies a specific VERSION of a golden record.
--   Re-running after a golden record versions inserts one new match-history
--   row linking the source zone to the new version, preserving the earlier
--   match rather than overwriting it.
--
-- Source-driven join:
--   Driven FROM taxi_zones, so current golden_zones rows that have no
--   source counterpart (for example the location_id = 99999 test fixture)
--   are excluded naturally and cannot violate the source_zone_id FK.
--
-- Safety:
--   INSERT only. Modifies no other table, column, constraint, index,
--   trigger or procedure. Safe to re-run.
-- =================================================================

BEGIN;

INSERT INTO zone_matches (
    golden_zone_id,
    source_zone_id,
    golden_zone_row_id,
    confidence_score,
    status,
    operation
)
SELECT
    g.golden_id,           -- legacy NOT NULL column; FK dropped in migration 007
    t.location_id,         -- FK -> taxi_zones(location_id)
    g.golden_zone_row_id,  -- FK -> golden_zones(golden_zone_row_id)
    1.0000,                -- exact business-key match
    'confirmed',           -- deterministic match requires no manual review
    'insert'               -- new source -> golden-version relationship
FROM taxi_zones t
JOIN golden_zones g
  ON g.location_id = t.location_id
 AND g.is_current = TRUE
WHERE NOT EXISTS (
    SELECT 1
    FROM zone_matches zm
    WHERE zm.source_zone_id     = t.location_id
      AND zm.golden_zone_row_id = g.golden_zone_row_id
);

COMMIT;

-- =================================================================
-- Post-run summary (read-only)
-- =================================================================
SELECT
    COUNT(*)                                            AS total_matches,
    COUNT(DISTINCT source_zone_id)                      AS distinct_source_zones,
    COUNT(*) FILTER (WHERE status = 'confirmed')        AS confirmed,
    COUNT(*) FILTER (WHERE confidence_score = 1.0000)   AS exact_matches,
    COUNT(*) FILTER (WHERE golden_zone_row_id IS NULL)  AS orphans
FROM zone_matches;

-- End of populate_zone_matches.sql
