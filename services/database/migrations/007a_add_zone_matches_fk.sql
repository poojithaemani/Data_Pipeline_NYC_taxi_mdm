-- =================================================================
-- 007a_add_zone_matches_fk.sql
--
-- Description:
-- Adds the foreign key from zone_matches(golden_zone_row_id) to golden_zones(golden_zone_row_id).
-- This migration must be executed AFTER 007_switch_primary_keys.sql has run,
-- ensuring golden_zones.golden_zone_row_id is a PRIMARY KEY.
--
-- Pre-requisites:
-- 1. An index on zone_matches(golden_zone_row_id) should exist (created concurrently).
-- 2. All rows in zone_matches must have a non-NULL golden_zone_row_id.
--
-- Idempotent: Safe to re-run.
-- =================================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage
    WHERE table_name = 'zone_matches' AND constraint_name = 'fk_zone_matches_golden_zone_row'
  ) THEN
    IF (SELECT COUNT(*) FROM zone_matches WHERE golden_zone_row_id IS NULL) > 0 THEN
      RAISE EXCEPTION 'Cannot add foreign key: zone_matches.golden_zone_row_id contains NULL values. Resolve unmapped rows first.';
    ELSE
      ALTER TABLE zone_matches ADD CONSTRAINT fk_zone_matches_golden_zone_row FOREIGN KEY (golden_zone_row_id) REFERENCES golden_zones (golden_zone_row_id);
      RAISE NOTICE 'Foreign key fk_zone_matches_golden_zone_row created successfully.';
    END IF;
  END IF;
END;
$$;

COMMIT;