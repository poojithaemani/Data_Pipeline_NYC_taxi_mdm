-- =================================================================
-- 010_finalize_scd_constraints.sql
--
-- Description:
-- Finalizes the SCD Type 2 schema by removing legacy UNIQUE constraints
-- on business keys that conflict with the versioning model. This script
-- is idempotent and includes pre-flight validation checks.
--
-- This script should only be run AFTER:
-- 1. All prior migrations (001-009) have been successfully applied.
-- 2. The primary keys have been switched to surrogate keys.
-- 3. The replacement partial unique indexes have been created.
--
-- Why these constraints?
-- - `vendors_vendor_id_key`: Prevents inserting a new version for an existing vendor_id.
-- - `golden_zones_golden_id_key`: Prevents inserting a new version for an existing golden_id.
-- =================================================================

BEGIN;

DO $$
DECLARE
    v_duplicate_found BOOLEAN;
BEGIN
    -- 1. Validate there are no duplicate current rows for business keys.
    -- This confirms data integrity before dropping the global unique constraints.
    SELECT EXISTS (
        SELECT 1 FROM vendors WHERE is_current = true GROUP BY vendor_id HAVING COUNT(*) > 1
        UNION ALL
        SELECT 1 FROM golden_zones WHERE is_current = true GROUP BY location_id HAVING COUNT(*) > 1
    ) INTO v_duplicate_found;

    IF v_duplicate_found THEN
        RAISE EXCEPTION 'Data integrity failed: Found duplicate current rows for a business key. Cannot proceed.';
    END IF;

    -- 2. Validate the replacement partial unique indexes exist, providing specific errors.
    -- This is critical. Do not drop the global unique constraint until its replacement is in place.
    IF to_regclass('public.idx_vendors_vendorid_current') IS NULL THEN
        RAISE EXCEPTION 'Prerequisite failed: Missing required index idx_vendors_vendorid_current.';
    END IF;

    IF to_regclass('public.idx_golden_locationid_current') IS NULL THEN
        RAISE EXCEPTION 'Prerequisite failed: Missing required index idx_golden_locationid_current.';
    END IF;

    -- 3. Drop legacy UNIQUE constraints that conflict with SCD Type 2 logic.
    -- NOTE: The constraint names `vendors_vendor_id_key` and `golden_zones_golden_id_key`
    -- should be verified against the target database before running in production.
    ALTER TABLE vendors DROP CONSTRAINT IF EXISTS vendors_vendor_id_key;
    ALTER TABLE golden_zones DROP CONSTRAINT IF EXISTS golden_zones_golden_id_key;

    RAISE NOTICE '010_finalize_scd_constraints.sql completed successfully. Schema finalized for SCD Type 2.';
END;
$$;

COMMIT;
