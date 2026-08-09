-- =================================================================
-- 011_drop_legacy_golden_zone_unique.sql
--
-- Description:
-- Drops the legacy UNIQUE(borough, zone) constraint on golden_zones.
--
-- Why this is required:
-- The constraint originates from the pre-SCD2 schema (schema.sql), where
-- golden_zones held exactly one row per zone. Under SCD Type 2 a business
-- key may have many row versions, and every version after the first repeats
-- the same (borough, zone) pair whenever only a non-key attribute changed
-- (for example service_zone). sp_upsert_golden_zone would therefore fail with
-- a unique_violation on its INSERT step and the 'UPDATED' path could never
-- succeed.
--
-- Uniqueness for the current row is already enforced by the partial index
-- idx_golden_locationid_current / uix_golden_zones_current, which is the
-- correct SCD2 equivalent. This migration validates that a replacement index
-- exists before dropping anything.
--
-- Scope note:
-- Deliberately limited to golden_zones. The vendors table is frozen as a
-- historical implementation and has no active writer, so its legacy
-- constraints are intentionally left untouched.
--
-- Idempotent: safe to re-run.
-- =================================================================

BEGIN;

DO $$
BEGIN
    -- 1. Refuse to proceed unless the SCD2 replacement index is in place.
    --    Do not drop a uniqueness guarantee without its successor.
    IF to_regclass('public.idx_golden_locationid_current') IS NULL
       AND to_regclass('public.uix_golden_zones_current') IS NULL THEN
        RAISE EXCEPTION
            'Prerequisite failed: no partial unique index on golden_zones current rows. Expected idx_golden_locationid_current or uix_golden_zones_current.';
    END IF;

    -- 2. Confirm there is at most one current row per business key.
    IF EXISTS (
        SELECT 1
        FROM golden_zones
        WHERE is_current = TRUE
        GROUP BY location_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Data integrity failed: duplicate current rows exist for a location_id. Resolve before dropping the constraint.';
    END IF;

    -- 3. Drop the legacy constraint that blocks SCD2 versioning.
    ALTER TABLE golden_zones DROP CONSTRAINT IF EXISTS golden_zones_borough_zone_key;

    RAISE NOTICE '011_drop_legacy_golden_zone_unique.sql completed. golden_zones can now version under SCD Type 2.';
END;
$$;

COMMIT;

-- Verification (run after applying):
--   SELECT conname FROM pg_constraint
--   WHERE conrelid = 'golden_zones'::regclass AND contype = 'u';
-- Expect: no row named golden_zones_borough_zone_key.

-- End of 011_drop_legacy_golden_zone_unique.sql
