-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 09_triggers.sql
-- Purpose: CARBON_RECORD_AUDIT table and BEFORE/AFTER triggers on CARBON_RECORD.
-- Prerequisite: 01_create_database.sql, 02_create_tables.sql, 03_insert_data.sql
-- MySQL: 8.0+ / 26.x (SIGNAL, CHECK, multiple triggers per table/event).
--
-- Emission column: CARBON_RECORD.carbon_footprint DECIMAL(12, 4) NOT NULL
--   Existing table CHECK chk_carbon_footprint already requires carbon_footprint >= 0.
--   The BEFORE triggers add an explicit SIGNAL SQLSTATE '45000' with a clear
--   message. Both treat 0 as valid and reject values < 0.
--
-- Audit table has no foreign key to CARBON_RECORD so DELETE history is kept
-- after the source row is gone.
-- =============================================================================

USE EcoTrack;

-- =============================================================================
-- SECTION 1 – AUDIT LOG TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS CARBON_RECORD_AUDIT (
    audit_id            INT             NOT NULL AUTO_INCREMENT,
    record_id           INT             NOT NULL,
    operation_type      VARCHAR(10)     NOT NULL,
    old_emission_value  DECIMAL(12, 4)  NULL,
    new_emission_value  DECIMAL(12, 4)  NULL,
    operation_timestamp DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_carbon_record_audit PRIMARY KEY (audit_id),
    CONSTRAINT chk_audit_operation_type
        CHECK (operation_type IN ('INSERT', 'UPDATE', 'DELETE'))
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'History of INSERT/UPDATE/DELETE on CARBON_RECORD.carbon_footprint. No FK so deleted records stay in the log.';

DELIMITER $$

-- =============================================================================
-- SECTION 2 – BEFORE INSERT TRIGGER
-- Fires before a new CARBON_RECORD row is written.
-- NEW.carbon_footprint is the value being inserted.
-- =============================================================================
DROP TRIGGER IF EXISTS trg_carbon_record_before_insert $$

CREATE TRIGGER trg_carbon_record_before_insert
BEFORE INSERT ON CARBON_RECORD
FOR EACH ROW
BEGIN
    IF NEW.carbon_footprint < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot insert CARBON_RECORD: carbon_footprint must not be negative.';
    END IF;
END $$

-- =============================================================================
-- SECTION 3 – BEFORE UPDATE TRIGGER
-- Fires before an existing CARBON_RECORD row is changed.
-- NEW.carbon_footprint is the proposed value (other columns may also change).
-- =============================================================================
DROP TRIGGER IF EXISTS trg_carbon_record_before_update $$

CREATE TRIGGER trg_carbon_record_before_update
BEFORE UPDATE ON CARBON_RECORD
FOR EACH ROW
BEGIN
    IF NEW.carbon_footprint < 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot update CARBON_RECORD: carbon_footprint must not be negative.';
    END IF;
END $$

-- =============================================================================
-- SECTION 4 – AFTER INSERT TRIGGER
-- Logs the new record_id and carbon_footprint. old_emission_value is NULL.
-- Writes only to CARBON_RECORD_AUDIT (no write-back to CARBON_RECORD).
-- =============================================================================
DROP TRIGGER IF EXISTS trg_carbon_record_after_insert $$

CREATE TRIGGER trg_carbon_record_after_insert
AFTER INSERT ON CARBON_RECORD
FOR EACH ROW
BEGIN
    INSERT INTO CARBON_RECORD_AUDIT (
        record_id,
        operation_type,
        old_emission_value,
        new_emission_value
    ) VALUES (
        NEW.record_id,
        'INSERT',
        NULL,
        NEW.carbon_footprint
    );
END $$

-- =============================================================================
-- SECTION 5 – AFTER UPDATE TRIGGER
-- Logs OLD and NEW carbon_footprint for the same record_id.
-- =============================================================================
DROP TRIGGER IF EXISTS trg_carbon_record_after_update $$

CREATE TRIGGER trg_carbon_record_after_update
AFTER UPDATE ON CARBON_RECORD
FOR EACH ROW
BEGIN
    INSERT INTO CARBON_RECORD_AUDIT (
        record_id,
        operation_type,
        old_emission_value,
        new_emission_value
    ) VALUES (
        NEW.record_id,
        'UPDATE',
        OLD.carbon_footprint,
        NEW.carbon_footprint
    );
END $$

-- =============================================================================
-- SECTION 6 – AFTER DELETE TRIGGER
-- Logs the removed record_id and its last carbon_footprint.
-- new_emission_value is NULL. No FK, so this row remains after the delete.
-- =============================================================================
DROP TRIGGER IF EXISTS trg_carbon_record_after_delete $$

CREATE TRIGGER trg_carbon_record_after_delete
AFTER DELETE ON CARBON_RECORD
FOR EACH ROW
BEGIN
    INSERT INTO CARBON_RECORD_AUDIT (
        record_id,
        operation_type,
        old_emission_value,
        new_emission_value
    ) VALUES (
        OLD.record_id,
        'DELETE',
        OLD.carbon_footprint,
        NULL
    );
END $$

DELIMITER ;

-- =============================================================================
-- SECTION 7 – TESTING
-- Dedicated test row only. Sample rows from 03_insert_data.sql are not updated
-- or deleted. User and category ids are looked up by unique email / name.
--
-- Successful tests run inside a transaction and COMMIT so that:
--   - the test CARBON_RECORD is inserted, updated, then deleted
--   - audit rows for that record_id remain (the teaching point of no FK)
-- Sample data is unchanged after COMMIT because only the test row is deleted.
--
-- Negative INSERT/UPDATE statements are listed last and commented out so this
-- script can run to completion. Uncomment one at a time to demonstrate SIGNAL.
-- =============================================================================

SET @test_user_id = (
    SELECT user_id
    FROM USERS
    WHERE email = 'aaliya@ecotrack.in'
);

SET @test_category_id = (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Transportation'
);

-- Remove a leftover test row from a previous run of this script (not sample data).
DELETE FROM CARBON_RECORD
 WHERE notes = 'EcoTrack trigger test record (09_triggers.sql)';

-- -----------------------------------------------------------------------------
-- Successful path (INSERT → UPDATE → DELETE) plus audit checks
-- -----------------------------------------------------------------------------
START TRANSACTION;

-- 1. Successful insertion of a valid carbon record (carbon_footprint >= 0).
INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @test_user_id,
    @test_category_id,
    '2026-11-24',
    2.5000,
    'EcoTrack trigger test record (09_triggers.sql)'
);

SET @test_record_id = LAST_INSERT_ID();

SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    category_id      AS category_number,
    record_date      AS activity_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_id = @test_record_id;

-- 2. Successful update of the test carbon record (still non-negative).
UPDATE CARBON_RECORD
   SET carbon_footprint = 3.7500
 WHERE record_id = @test_record_id;

SELECT
    record_id        AS record_number,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_id = @test_record_id;

-- 4a. Audit entries after INSERT and UPDATE (DELETE not yet).
SELECT
    audit_id            AS audit_number,
    record_id           AS record_number,
    operation_type      AS operation,
    old_emission_value  AS old_emissions_kg_co2e,
    new_emission_value  AS new_emissions_kg_co2e,
    operation_timestamp AS logged_at
FROM CARBON_RECORD_AUDIT
WHERE record_id = @test_record_id
ORDER BY audit_id;

-- 3. Successful deletion of the test carbon record only.
DELETE FROM CARBON_RECORD
 WHERE record_id = @test_record_id;

-- 4b. Audit entries after DELETE: INSERT, UPDATE and DELETE for @test_record_id.
--     The carbon record is gone; the audit rows remain because there is no FK.
SELECT
    audit_id            AS audit_number,
    record_id           AS record_number,
    operation_type      AS operation,
    old_emission_value  AS old_emissions_kg_co2e,
    new_emission_value  AS new_emissions_kg_co2e,
    operation_timestamp AS logged_at
FROM CARBON_RECORD_AUDIT
WHERE record_id = @test_record_id
ORDER BY audit_id;

COMMIT;

-- Confirm sample data was not used: the test notes must no longer exist in CARBON_RECORD.
SELECT COUNT(*) AS leftover_trigger_test_rows
FROM CARBON_RECORD
WHERE notes = 'EcoTrack trigger test record (09_triggers.sql)';

-- -----------------------------------------------------------------------------
-- Expected-error demonstrations (do not run as part of the normal script)
-- Uncomment a single statement in a client session to see SIGNAL SQLSTATE 45000.
-- ROLLBACK is shown so a partial insert/update is not left behind if you test
-- these inside an open transaction.
-- -----------------------------------------------------------------------------

-- 5. Attempted insertion of a negative emission value (BEFORE INSERT).
--    Expected: ERROR 1644 (45000) Cannot insert CARBON_RECORD: carbon_footprint must not be negative.
-- START TRANSACTION;
-- INSERT INTO CARBON_RECORD (user_id, category_id, record_date, carbon_footprint, notes)
-- VALUES (
--     @test_user_id,
--     @test_category_id,
--     '2026-11-24',
--     -1.0000,
--     'EcoTrack trigger test record (09_triggers.sql)'
-- );
-- ROLLBACK;

-- 6. Attempted update of the dedicated test row to a negative emission (BEFORE UPDATE).
--    Insert a valid test row first, then uncomment the UPDATE. Expected: ERROR 1644 (45000).
-- START TRANSACTION;
-- INSERT INTO CARBON_RECORD (user_id, category_id, record_date, carbon_footprint, notes)
-- VALUES (
--     @test_user_id,
--     @test_category_id,
--     '2026-11-24',
--     1.0000,
--     'EcoTrack trigger test record (09_triggers.sql)'
-- );
-- UPDATE CARBON_RECORD
--    SET carbon_footprint = -5.0000
--  WHERE notes = 'EcoTrack trigger test record (09_triggers.sql)';
-- ROLLBACK;
