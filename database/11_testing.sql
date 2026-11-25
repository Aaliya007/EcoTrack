-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 11_testing.sql
-- Purpose: End-to-end verification of schema, constraints, CRUD, views,
--          routines, triggers, transactions and indexes.
-- Prerequisite (run in order):
--   01_create_database.sql
--   02_create_tables.sql
--   03_insert_data.sql
--   07_views.sql
--   08_procedures_functions.sql
--   09_triggers.sql
--   10_transactions_indexing.sql
--
-- This file does not permanently change sample rows from 03_insert_data.sql.
-- Dedicated QA rows use email qa.tester@ecotrack.in and notes like
-- 'EcoTrack QA ...'. A final cleanup deletes those rows.
--
-- Statements that must fail (constraints, negative emissions) are commented
-- out so SOURCE 11_testing.sql can finish without an error stop.
-- =============================================================================

-- =============================================================================
-- SECTION 1 – DATABASE AND TABLE VERIFICATION
-- =============================================================================

USE EcoTrack;

SELECT DATABASE() AS current_database;
-- Expected: EcoTrack

SHOW TABLES;
-- Expected base tables: USERS, CATEGORY, SUSTAINABILITY_GOAL, EMISSION_FACTOR,
--   CARBON_RECORD, TRANSPORTATION, FOOD_CONSUMPTION, ELECTRICITY_USAGE,
--   RECOMMENDATION, ACHIEVEMENT
-- Also present after later scripts: CARBON_RECORD_AUDIT, seven VIEWs

DESCRIBE USERS;
DESCRIBE CATEGORY;
DESCRIBE SUSTAINABILITY_GOAL;
DESCRIBE EMISSION_FACTOR;
DESCRIBE CARBON_RECORD;
DESCRIBE TRANSPORTATION;
DESCRIBE FOOD_CONSUMPTION;
DESCRIBE ELECTRICITY_USAGE;
DESCRIBE RECOMMENDATION;
DESCRIBE ACHIEVEMENT;

-- Primary keys, unique keys and check constraints on EcoTrack tables.
SELECT
    TABLE_NAME,
    CONSTRAINT_NAME,
    CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE TABLE_SCHEMA = 'EcoTrack'
ORDER BY TABLE_NAME, CONSTRAINT_TYPE, CONSTRAINT_NAME;

-- Foreign keys: child column -> parent table.column
SELECT
    kcu.TABLE_NAME              AS child_table,
    kcu.COLUMN_NAME             AS child_column,
    kcu.CONSTRAINT_NAME         AS constraint_name,
    kcu.REFERENCED_TABLE_NAME   AS parent_table,
    kcu.REFERENCED_COLUMN_NAME  AS parent_column
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE AS kcu
WHERE kcu.TABLE_SCHEMA = 'EcoTrack'
  AND kcu.REFERENCED_TABLE_NAME IS NOT NULL
ORDER BY kcu.TABLE_NAME, kcu.CONSTRAINT_NAME, kcu.ORDINAL_POSITION;

-- =============================================================================
-- SECTION 2 – CONSTRAINT VALIDATION
-- Each case is documented with the constraint it should hit. Statements are
-- commented so they do not abort the rest of the script.
-- =============================================================================

-- 2.1 Duplicate primary key (USERS.user_id / pk_users)
-- Expected: ERROR 1062 (23000) Duplicate entry
-- INSERT INTO USERS (user_id, name, email, password_hash)
-- SELECT user_id, 'Dup PK', 'dup.pk@ecotrack.in', '00'
-- FROM USERS
-- LIMIT 1;

-- 2.2 Invalid foreign key (CARBON_RECORD.user_id -> USERS.user_id / fk_record_user)
-- Expected: ERROR 1452 (23000) Cannot add or update a child row
-- INSERT INTO CARBON_RECORD (user_id, category_id, record_date, carbon_footprint, notes)
-- SELECT 0, category_id, '2026-11-24', 1.0000, 'EcoTrack QA invalid FK'
-- FROM CATEGORY
-- WHERE category_name = 'Transportation';

-- 2.3 NULL in a NOT NULL column (USERS.name)
-- Expected: ERROR 1048 (23000) Column 'name' cannot be null
-- INSERT INTO USERS (name, email, password_hash)
-- VALUES (NULL, 'null.name@ecotrack.in', '00');

-- 2.4 Duplicate UNIQUE value (USERS.email / uq_users_email)
-- Expected: ERROR 1062 (23000) Duplicate entry for key 'uq_users_email'
-- INSERT INTO USERS (name, email, password_hash)
-- VALUES ('Dup Email', 'aaliya@ecotrack.in', '00');

-- 2.5 CHECK: USERS.email must match chk_users_email ('%_@_%.__%')
-- Expected: ERROR 3819 (HY000) Check constraint 'chk_users_email' is violated
-- INSERT INTO USERS (name, email, password_hash)
-- VALUES ('Bad Email', 'not-an-email', '00');

-- 2.6 CHECK: CARBON_RECORD.carbon_footprint >= 0 (chk_carbon_footprint)
--    The BEFORE INSERT trigger also SIGNALs 45000 for values < 0.
-- Expected: ERROR 1644 (45000) or ERROR 3819 (HY000)
-- INSERT INTO CARBON_RECORD (user_id, category_id, record_date, carbon_footprint, notes)
-- SELECT user_id, (SELECT category_id FROM CATEGORY WHERE category_name = 'Food'),
--        '2026-11-24', -0.5000, 'EcoTrack QA negative CHECK'
-- FROM USERS
-- WHERE email = 'aaliya@ecotrack.in';

-- 2.7 CHECK: ACHIEVEMENT.progress between 0 and 100 (chk_achievement_progress)
-- Expected: ERROR 3819 (HY000)
-- INSERT INTO ACHIEVEMENT (user_id, goal_id, progress, status)
-- SELECT user_id, (SELECT goal_id FROM SUSTAINABILITY_GOAL LIMIT 1),
--        150.00, 'IN_PROGRESS'
-- FROM USERS
-- WHERE email = 'aaliya@ecotrack.in';

-- 2.8 CHECK: ACHIEVEMENT.status domain (chk_achievement_status)
-- Expected: ERROR 3819 (HY000)
-- INSERT INTO ACHIEVEMENT (user_id, goal_id, progress, status)
-- SELECT user_id, (SELECT goal_id FROM SUSTAINABILITY_GOAL LIMIT 1),
--        10.00, 'DONE'
-- FROM USERS
-- WHERE email = 'aaliya@ecotrack.in';

-- =============================================================================
-- SECTION 3 – CRUD TESTING
-- Dedicated QA user + one carbon record. Sample users are not updated/deleted.
-- =============================================================================

INSERT INTO USERS (name, email, password_hash, phone, address)
SELECT
    'QA Tester',
    'qa.tester@ecotrack.in',
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    '+919000111000',
    'QA Lab, Pune, Maharashtra'
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1
    FROM USERS
    WHERE email = 'qa.tester@ecotrack.in'
);

SET @qa_user_id = (
    SELECT user_id
    FROM USERS
    WHERE email = 'qa.tester@ecotrack.in'
);

SET @qa_category_id = (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Transportation'
);

-- Remove a leftover QA carbon row from a previous run.
DELETE FROM CARBON_RECORD
 WHERE notes LIKE 'EcoTrack QA%'
    OR user_id = @qa_user_id;

-- Create: valid carbon activity header (actual columns, valid FKs).
INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @qa_user_id,
    @qa_category_id,
    '2026-11-24',
    2.2500,
    'EcoTrack QA CRUD insert'
);

SET @qa_record_id = LAST_INSERT_ID();

-- Read
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    category_id      AS category_number,
    record_date      AS activity_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_id = @qa_record_id;
-- Expected: carbon_footprint = 2.2500

-- Update
UPDATE CARBON_RECORD
   SET carbon_footprint = 3.5000,
       notes = 'EcoTrack QA CRUD update'
 WHERE record_id = @qa_record_id;

-- Read after update
SELECT
    record_id        AS record_number,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_id = @qa_record_id;
-- Expected: carbon_footprint = 3.5000, notes mention update

-- Delete the QA carbon row only (QA user is kept for SECTION 5 empty-log test).
DELETE FROM CARBON_RECORD
 WHERE record_id = @qa_record_id;

SELECT COUNT(*) AS crud_record_still_present
FROM CARBON_RECORD
WHERE record_id = @qa_record_id;
-- Expected: 0

-- =============================================================================
-- SECTION 4 – VIEW TESTING
-- Seven views from 07_views.sql
-- =============================================================================

SELECT TABLE_NAME AS view_name
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'EcoTrack'
ORDER BY TABLE_NAME;
-- Expected: CARBON_ACTIVITY_DETAILS, CATEGORY_EMISSION_SUMMARY,
--   ELECTRICITY_EMISSION_DETAILS, FOOD_EMISSION_DETAILS, HIGH_EMISSION_USERS,
--   TRANSPORTATION_EMISSION_DETAILS, USER_CARBON_SUMMARY

SELECT *
FROM USER_CARBON_SUMMARY
ORDER BY total_emissions_kg_co2e DESC, user_name ASC;
-- QA Tester should appear with 0 emissions after the CRUD delete above.

SELECT *
FROM CATEGORY_EMISSION_SUMMARY
ORDER BY total_emissions_kg_co2e DESC;

SELECT *
FROM CARBON_ACTIVITY_DETAILS
ORDER BY user_name ASC, activity_date ASC;

SELECT *
FROM TRANSPORTATION_EMISSION_DETAILS
ORDER BY user_name ASC, activity_date ASC;

SELECT *
FROM FOOD_EMISSION_DETAILS
ORDER BY user_name ASC, activity_date ASC;

SELECT *
FROM ELECTRICITY_EMISSION_DETAILS
ORDER BY user_name ASC, activity_date ASC;

SELECT *
FROM HIGH_EMISSION_USERS
ORDER BY total_emissions_kg_co2e DESC;
-- Expected: users whose SUM(carbon_footprint) > 100 (Reyansh, Aaliya, Aditya
-- in the original sample; QA Tester is excluded).

-- =============================================================================
-- SECTION 5 – STORED PROCEDURE AND FUNCTION TESTING
-- Routines from 08_procedures_functions.sql. IDs looked up by unique email /
-- category_name, not assumed AUTO_INCREMENT values.
-- =============================================================================

SET @sample_user_id = (
    SELECT user_id
    FROM USERS
    WHERE email = 'aaliya@ecotrack.in'
);

SET @sample_user_id_low = (
    SELECT user_id
    FROM USERS
    WHERE email = 'anshika@ecotrack.in'
);

SET @sample_category_id = (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Electricity'
);

CALL GetUserCarbonSummary(@sample_user_id);
CALL GetUserCarbonSummary(@sample_user_id_low);

-- User with no carbon records: QA Tester (logs were deleted in SECTION 3).
CALL GetUserCarbonSummary(@qa_user_id);
-- Expected: total_emissions_kg_co2e = 0, carbon_record_count = 0

-- Unknown user_id: empty result set (no USERS row).
CALL GetUserCarbonSummary(0);

CALL GetCategoryEmissions(@sample_category_id);

CALL GetTopEmissionUsers(3);

CALL GetCarbonRecordsByDate('2026-10-01', '2026-10-15');

CALL GetUserCarbonRecords(@sample_user_id);

-- QA Tester has no logs: empty result set.
CALL GetUserCarbonRecords(@qa_user_id);

SELECT
    @sample_user_id                               AS user_number,
    CalculateUserCarbonFootprint(@sample_user_id) AS total_emissions_kg_co2e,
    GetTotalCarbonRecords(@sample_user_id)        AS carbon_record_count,
    GetEmissionLevel(
        CalculateUserCarbonFootprint(@sample_user_id)
    )                                             AS emission_level;

SELECT
    @qa_user_id                               AS user_number,
    CalculateUserCarbonFootprint(@qa_user_id) AS total_emissions_kg_co2e,
    GetTotalCarbonRecords(@qa_user_id)        AS carbon_record_count,
    GetEmissionLevel(
        CalculateUserCarbonFootprint(@qa_user_id)
    )                                         AS emission_level;
-- Expected for QA Tester: 0, 0, 'Low'

SELECT 4.8384   AS sample_kg_co2e, GetEmissionLevel(4.8384)   AS emission_level;
SELECT 50.0000  AS sample_kg_co2e, GetEmissionLevel(50.0000)  AS emission_level;
SELECT 152.5200 AS sample_kg_co2e, GetEmissionLevel(152.5200) AS emission_level;
SELECT NULL     AS sample_kg_co2e, GetEmissionLevel(NULL)     AS emission_level;
-- Expected: Low, Moderate, High, Unknown

-- =============================================================================
-- SECTION 6 – TRIGGER TESTING
-- Triggers from 09_triggers.sql on CARBON_RECORD. Dedicated QA notes only.
-- =============================================================================

SELECT TRIGGER_NAME, EVENT_MANIPULATION, ACTION_TIMING, EVENT_OBJECT_TABLE
FROM INFORMATION_SCHEMA.TRIGGERS
WHERE TRIGGER_SCHEMA = 'EcoTrack'
ORDER BY ACTION_TIMING, EVENT_MANIPULATION;
-- Expected: trg_carbon_record_before_insert/update,
--           trg_carbon_record_after_insert/update/delete

INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @qa_user_id,
    @qa_category_id,
    '2026-11-24',
    1.1000,
    'EcoTrack QA TRIGGER'
);

SET @qa_trigger_record_id = LAST_INSERT_ID();

SELECT
    audit_id           AS audit_number,
    record_id          AS record_number,
    operation_type     AS operation,
    old_emission_value AS old_emissions_kg_co2e,
    new_emission_value AS new_emissions_kg_co2e
FROM CARBON_RECORD_AUDIT
WHERE record_id = @qa_trigger_record_id
ORDER BY audit_id;
-- Expected: INSERT, old NULL, new 1.1000

UPDATE CARBON_RECORD
   SET carbon_footprint = 2.2000
 WHERE record_id = @qa_trigger_record_id;

SELECT
    audit_id           AS audit_number,
    operation_type     AS operation,
    old_emission_value AS old_emissions_kg_co2e,
    new_emission_value AS new_emissions_kg_co2e
FROM CARBON_RECORD_AUDIT
WHERE record_id = @qa_trigger_record_id
ORDER BY audit_id;
-- Expected: INSERT then UPDATE (1.1000 -> 2.2000)

DELETE FROM CARBON_RECORD
 WHERE record_id = @qa_trigger_record_id;

SELECT
    audit_id           AS audit_number,
    record_id          AS record_number,
    operation_type     AS operation,
    old_emission_value AS old_emissions_kg_co2e,
    new_emission_value AS new_emissions_kg_co2e
FROM CARBON_RECORD_AUDIT
WHERE record_id = @qa_trigger_record_id
ORDER BY audit_id;
-- Expected: INSERT, UPDATE, DELETE (old 2.2000, new NULL).
-- The carbon row is gone; audit remains because CARBON_RECORD_AUDIT has no FK.

-- BEFORE INSERT / BEFORE UPDATE rejection of negative carbon_footprint.
-- Uncomment one statement at a time. Expected: ERROR 1644 (45000) from SIGNAL.
-- INSERT INTO CARBON_RECORD (user_id, category_id, record_date, carbon_footprint, notes)
-- VALUES (@qa_user_id, @qa_category_id, '2026-11-24', -1.0000, 'EcoTrack QA TRIGGER neg insert');
--
-- INSERT INTO CARBON_RECORD (user_id, category_id, record_date, carbon_footprint, notes)
-- VALUES (@qa_user_id, @qa_category_id, '2026-11-24', 1.0000, 'EcoTrack QA TRIGGER neg update');
-- UPDATE CARBON_RECORD
--    SET carbon_footprint = -5.0000
--  WHERE notes = 'EcoTrack QA TRIGGER neg update';

-- =============================================================================
-- SECTION 7 – TRANSACTION TESTING
-- InnoDB DML only. Reversible QA rows; sample data is not changed.
-- =============================================================================

START TRANSACTION;

INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @qa_user_id,
    @qa_category_id,
    '2026-11-24',
    5.0000,
    'EcoTrack QA TXN commit'
);

SET @qa_txn_commit_id = LAST_INSERT_ID();

COMMIT;

SELECT COUNT(*) AS committed_row_count
FROM CARBON_RECORD
WHERE record_id = @qa_txn_commit_id;
-- Expected: 1

START TRANSACTION;

INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @qa_user_id,
    @qa_category_id,
    '2026-11-24',
    6.0000,
    'EcoTrack QA TXN rollback'
);

SET @qa_txn_rollback_id = LAST_INSERT_ID();

ROLLBACK;

SELECT COUNT(*) AS rolled_back_row_count
FROM CARBON_RECORD
WHERE record_id = @qa_txn_rollback_id
   OR notes = 'EcoTrack QA TXN rollback';
-- Expected: 0

START TRANSACTION;

UPDATE CARBON_RECORD
   SET carbon_footprint = 7.0000
 WHERE record_id = @qa_txn_commit_id;

SAVEPOINT sp_qa_after_first_update;

UPDATE CARBON_RECORD
   SET carbon_footprint = 8.0000
 WHERE record_id = @qa_txn_commit_id;

ROLLBACK TO SAVEPOINT sp_qa_after_first_update;

COMMIT;

SELECT carbon_footprint AS emissions_after_savepoint
FROM CARBON_RECORD
WHERE record_id = @qa_txn_commit_id;
-- Expected: 7.0000 (second update undone; first update committed)

DELETE FROM CARBON_RECORD
 WHERE record_id = @qa_txn_commit_id
    OR notes LIKE 'EcoTrack QA TXN%';

-- =============================================================================
-- SECTION 8 – INDEX AND EXPLAIN VERIFICATION
-- Secondary indexes from 10_transactions_indexing.sql
--   idx_carbon_record_record_date
--   idx_carbon_record_carbon_footprint
-- Demo index idx_demo_carbon_record_notes is dropped in that script and
-- should not appear.
-- =============================================================================

SHOW INDEX FROM USERS;
SHOW INDEX FROM CARBON_RECORD;

SELECT
    INDEX_NAME,
    COLUMN_NAME,
    NON_UNIQUE,
    SEQ_IN_INDEX
FROM INFORMATION_SCHEMA.STATISTICS
WHERE TABLE_SCHEMA = 'EcoTrack'
  AND TABLE_NAME = 'CARBON_RECORD'
  AND INDEX_NAME IN (
        'idx_carbon_record_record_date',
        'idx_carbon_record_carbon_footprint',
        'idx_demo_carbon_record_notes'
      )
ORDER BY INDEX_NAME, SEQ_IN_INDEX;
-- Expected: the two idx_carbon_record_* indexes; demo index absent.

EXPLAIN
SELECT record_id, record_date, carbon_footprint
FROM CARBON_RECORD
WHERE user_id = @sample_user_id;

EXPLAIN
SELECT record_id, record_date, carbon_footprint
FROM CARBON_RECORD
WHERE record_date BETWEEN '2026-10-01' AND '2026-10-15';

EXPLAIN
SELECT u.name, cr.record_id, cr.carbon_footprint
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id;

EXPLAIN
SELECT record_id, carbon_footprint
FROM CARBON_RECORD
WHERE carbon_footprint > 50;
-- Date and emission predicates should use type = range on the secondary indexes.
-- user_id lookup / join should use fk_record_user (InnoDB FK index).

-- =============================================================================
-- FINAL CLEANUP – dedicated QA user only (CASCADE any leftover QA logs)
-- =============================================================================

DELETE FROM USERS
 WHERE email = 'qa.tester@ecotrack.in';

SELECT COUNT(*) AS leftover_qa_users
FROM USERS
WHERE email = 'qa.tester@ecotrack.in';
-- Expected: 0

SELECT COUNT(*) AS leftover_qa_carbon_rows
FROM CARBON_RECORD
WHERE notes LIKE 'EcoTrack QA%';
-- Expected: 0

SELECT COUNT(*) AS sample_user_count
FROM USERS
WHERE email IN (
    'aaliya@ecotrack.in',
    'trisha@ecotrack.in',
    'reyansh@ecotrack.in',
    'anshika@ecotrack.in',
    'aditya@ecotrack.in'
);
-- Expected: 5 (original sample still present)
