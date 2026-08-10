-- =================================================================
-- services/database/audit_golden_zones.sql
--
-- Description:
-- Installs the audit producer for golden_zones, satisfying the MDM
-- "Audit History" requirement and giving the existing audit_log table
-- its first writer.
--
-- Why a trigger:
--   A trigger captures every golden-record lifecycle event regardless of
--   which client performs it, without modifying sp_upsert_golden_zone or
--   golden_zone_etl.py (both frozen). Under SCD Type 2 this records three
--   distinct event types:
--     * INSERT - a new business key arrives (version 1)
--     * UPDATE - the current row is expired (is_current -> FALSE, end_date set)
--     * INSERT - the replacement version is written (version N+1)
--
-- SCD2 safety:
--   The trigger is AFTER (never BEFORE), so it cannot alter the row being
--   written and cannot change SCD Type 2 behaviour. It performs a single
--   INSERT into audit_log and nothing else.
--
-- record_id:
--   Stores location_id, the business key, so audit history can be grouped
--   per zone across all versions.
--
-- Idempotency:
--   CREATE OR REPLACE FUNCTION plus DROP TRIGGER IF EXISTS / CREATE TRIGGER,
--   matching the pattern already used in schema.sql. Safe to re-run.
--
-- Safety:
--   Adds one function and one trigger. Alters no column, constraint, index,
--   existing trigger, or stored procedure.
-- =================================================================

-- =================================================================
-- Function: fn_audit_golden_zones
-- =================================================================
CREATE OR REPLACE FUNCTION fn_audit_golden_zones()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (
        table_name,
        record_id,
        operation,
        changed_by,
        old_values,
        new_values
    ) VALUES (
        'golden_zones',
        COALESCE(NEW.location_id, OLD.location_id)::VARCHAR,
        TG_OP,
        current_user,
        CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) ELSE NULL END,
        to_jsonb(NEW)
    );

    -- AFTER trigger: the return value is ignored, and the written row is
    -- never modified.
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- =================================================================
-- Trigger: trg_audit_golden_zones
-- =================================================================
DROP TRIGGER IF EXISTS trg_audit_golden_zones ON golden_zones;

CREATE TRIGGER trg_audit_golden_zones
    AFTER INSERT OR UPDATE ON golden_zones
    FOR EACH ROW
    EXECUTE FUNCTION fn_audit_golden_zones();

-- =================================================================
-- Verification (read-only)
-- =================================================================
SELECT tgname AS trigger_name,
       pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE c.relname = 'golden_zones'
  AND NOT t.tgisinternal
ORDER BY tgname;

-- End of audit_golden_zones.sql
