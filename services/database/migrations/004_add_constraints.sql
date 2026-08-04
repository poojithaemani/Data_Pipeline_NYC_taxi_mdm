-- =================================================================
-- 004_add_constraints.sql
-- Add SCD-related CHECK constraints and (safe) NOT NULL promotion where applicable.
-- Use guarded blocks to be idempotent.
-- =================================================================

BEGIN;

-- Vendors: CHECK(version >= 1)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vendors_chk_version_gte_1'
  ) THEN
    ALTER TABLE vendors ADD CONSTRAINT vendors_chk_version_gte_1 CHECK (version >= 1);
  END IF;
END
$$;

-- Vendors: CHECK(end_date IS NULL OR end_date > effective_date)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vendors_chk_end_after_effective'
  ) THEN
    ALTER TABLE vendors ADD CONSTRAINT vendors_chk_end_after_effective CHECK (end_date IS NULL OR end_date > effective_date);
  END IF;
END
$$;

-- Golden_zones: CHECK(version >= 1)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'golden_zones_chk_version_gte_1'
  ) THEN
    ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_chk_version_gte_1 CHECK (version >= 1);
  END IF;
END
$$;

-- Golden_zones: CHECK(end_date IS NULL OR end_date > effective_date)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'golden_zones_chk_end_after_effective'
  ) THEN
    ALTER TABLE golden_zones ADD CONSTRAINT golden_zones_chk_end_after_effective CHECK (end_date IS NULL OR end_date > effective_date);
  END IF;
END
$$;

-- Promote NOT NULL for SCD columns only if there are no NULLs
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM vendors WHERE version IS NULL) = 0 THEN
    ALTER TABLE vendors ALTER COLUMN version SET NOT NULL;
  END IF;
  IF (SELECT COUNT(*) FROM vendors WHERE is_current IS NULL) = 0 THEN
    ALTER TABLE vendors ALTER COLUMN is_current SET NOT NULL;
  END IF;
  IF (SELECT COUNT(*) FROM vendors WHERE effective_date IS NULL) = 0 THEN
    ALTER TABLE vendors ALTER COLUMN effective_date SET NOT NULL;
  END IF;

  IF (SELECT COUNT(*) FROM golden_zones WHERE version IS NULL) = 0 THEN
    ALTER TABLE golden_zones ALTER COLUMN version SET NOT NULL;
  END IF;
  IF (SELECT COUNT(*) FROM golden_zones WHERE is_current IS NULL) = 0 THEN
    ALTER TABLE golden_zones ALTER COLUMN is_current SET NOT NULL;
  END IF;
  IF (SELECT COUNT(*) FROM golden_zones WHERE effective_date IS NULL) = 0 THEN
    ALTER TABLE golden_zones ALTER COLUMN effective_date SET NOT NULL;
  END IF;
END
$$;

COMMIT;

-- End of 004_add_constraints.sql
