-- =================================================================
-- 007_prepare_pk_switch.sql
--
-- Description:
-- Prepares for the primary key switch on golden_zones by dropping the
-- foreign key constraint from zone_matches. This resolves the dependency
-- that prevents dropping the original primary key.
--
-- This is the first step in the final sequence to adopt surrogate PKs.
-- =================================================================

BEGIN;

-- Drop the FK on zone_matches that references the original golden_zones PK.
-- This constraint will be recreated later to point to the new surrogate PK.
ALTER TABLE zone_matches DROP CONSTRAINT IF EXISTS zone_matches_golden_zone_id_fkey;

COMMIT;