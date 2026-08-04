-- services/database/procedures/sp_upsert_golden_zone.sql
--
-- SCD Type 2 upsert for golden_zones.
--
-- CALL contract:
-- CALL sp_upsert_golden_zone(
--   p_location_id INT,
--   p_borough TEXT,
--   p_zone TEXT,
--   p_service_zone TEXT,
--   p_record_hash TEXT,
--   p_effective_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--   OUT p_status TEXT
-- );
--
-- Returns p_status one of: 'INSERTED', 'UPDATED', 'NO_CHANGE'.
--
-- Design notes:
--  - Uses location_id as the business key.
--  - Uses SELECT ... FOR UPDATE to serialize access to the current row (row-level locking).
--  - No advisory locks, no triggers, no audit tables.
--  - Does not set created_at/updated_at explicitly; the table defaults/triggers handle timestamps.
--  - p_effective_date is optional; COALESCE(p_effective_date, CURRENT_TIMESTAMP) is used for effective_date and end_date.
--
CREATE OR REPLACE PROCEDURE sp_upsert_golden_zone(
    p_location_id INT,
    p_borough TEXT,
    p_zone TEXT,
    p_service_zone TEXT,
    p_record_hash TEXT,
    p_effective_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    OUT p_status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_row_id BIGINT;
    v_record_hash TEXT;
    v_version INT;
BEGIN
    -- Input validation: location_id (business key) must be provided
    IF p_location_id IS NULL THEN
        RAISE EXCEPTION 'p_location_id must not be null';
    END IF;

    -- 1) Find the current active row for this business key and lock it for update
    SELECT golden_zone_row_id, record_hash, version
    INTO v_row_id, v_record_hash, v_version
    FROM golden_zones
    WHERE location_id = p_location_id
      AND is_current = TRUE
    FOR UPDATE;

    -- 2) No current row found -> insert as version 1
    IF NOT FOUND THEN
        INSERT INTO golden_zones (
            location_id,
            borough,
            zone,
            service_zone,
            record_hash,
            version,
            is_current,
            effective_date,
            end_date
        ) VALUES (
            p_location_id,
            p_borough,
            p_zone,
            p_service_zone,
            p_record_hash,
            1,
            TRUE,
            COALESCE(p_effective_date, CURRENT_TIMESTAMP),
            NULL
        )
        RETURNING golden_zone_row_id INTO v_row_id;

        p_status := 'INSERTED';
        RETURN;
    END IF;

    -- 3) Current row exists: compare record_hash values
    IF v_record_hash IS NOT DISTINCT FROM p_record_hash THEN
        -- No change detected; do not modify the table
        p_status := 'NO_CHANGE';
        RETURN;
    END IF;

    -- 4) Change detected: expire current row (set is_current = FALSE, set end_date)
    UPDATE golden_zones
    SET is_current = FALSE,
        end_date = COALESCE(p_effective_date, CURRENT_TIMESTAMP)
    WHERE golden_zone_row_id = v_row_id
      AND is_current = TRUE;

    -- 5) Insert new row with incremented version and is_current = TRUE
    INSERT INTO golden_zones (
        location_id,
        borough,
        zone,
        service_zone,
        record_hash,
        version,
        is_current,
        effective_date,
        end_date
    ) VALUES (
        p_location_id,
        p_borough,
        p_zone,
        p_service_zone,
        p_record_hash,
        COALESCE(v_version, 0) + 1,
        TRUE,
        COALESCE(p_effective_date, CURRENT_TIMESTAMP),
        NULL
    )
    RETURNING golden_zone_row_id INTO v_row_id;

    p_status := 'UPDATED';
    RETURN;

EXCEPTION
    WHEN unique_violation THEN
        -- Surface unique constraint violations to the caller; Glue may retry if appropriate.
        RAISE;
    WHEN OTHERS THEN
        -- Surface unexpected errors
        RAISE;
END;
$$;
