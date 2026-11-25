-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 10_transactions_indexing.sql
-- Purpose: Transaction control (COMMIT, ROLLBACK, SAVEPOINT), secondary indexes,
--          index inspection/drop, and EXPLAIN plans for EcoTrack queries.
-- Prerequisite: 01_create_database.sql, 02_create_tables.sql, 03_insert_data.sql
-- Optional: 09_triggers.sql (AFTER INSERT/UPDATE/DELETE on CARBON_RECORD will
--           write CARBON_RECORD_AUDIT in the same transaction; ROLLBACK undoes
--           those audit rows too).
--
-- Engine: every table in 02_create_tables.sql is ENGINE = InnoDB, so DML can
-- be committed or rolled back. DDL (CREATE/DROP INDEX) is not transactional
-- in the same way and is not wrapped in START TRANSACTION here.
--
-- Existing indexes (do not recreate):
--   USERS.email              UNIQUE uq_users_email
--   USERS.phone              UNIQUE uq_users_phone
--   CARBON_RECORD.record_id  PRIMARY KEY
--   CARBON_RECORD (record_id, user_id) UNIQUE uq_record_user
--   CARBON_RECORD.user_id    InnoDB FK index fk_record_user
--   CARBON_RECORD.category_id InnoDB FK index fk_record_category
--   TRANSPORTATION.record_id UNIQUE uq_transport_record (covers FK)
--   TRANSPORTATION.factor_id InnoDB FK index fk_transport_factor
--   FOOD_CONSUMPTION.record_id UNIQUE uq_food_record
--   FOOD_CONSUMPTION.factor_id InnoDB FK index fk_food_factor
--   ELECTRICITY_USAGE.record_id UNIQUE uq_electricity_record
--   ELECTRICITY_USAGE.factor_id InnoDB FK index fk_electricity_factor
-- New indexes below are only on columns that are searched/filtered and are
-- not already a PK, UNIQUE key, or FK index: record_date and carbon_footprint.
-- =============================================================================

USE EcoTrack;

-- =============================================================================
-- SECTION 1 – TRANSACTIONS
-- Dedicated test rows only. Sample rows from 03_insert_data.sql are not
-- updated or deleted. Keys are looked up by unique email / category_name.
-- =============================================================================

SET @txn_user_id = (
    SELECT user_id
    FROM USERS
    WHERE email = 'aaliya@ecotrack.in'
);

SET @txn_category_id = (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Transportation'
);

SET @txn_factor_id = (
    SELECT factor_id
    FROM EMISSION_FACTOR
    WHERE activity_name = 'Petrol private car'
);

-- Remove leftover test rows from a previous run of this script (CASCADE
-- also removes any 1:1 TRANSPORTATION / RECOMMENDATION children).
DELETE FROM CARBON_RECORD
 WHERE notes LIKE 'EcoTrack txn test%';

-- -----------------------------------------------------------------------------
-- 1. START TRANSACTION and COMMIT
-- Insert a valid carbon record, commit, then confirm it is visible to later
-- statements (durable in InnoDB after COMMIT).
-- -----------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @txn_user_id,
    @txn_category_id,
    '2026-11-24',
    2.5000,
    'EcoTrack txn test COMMIT'
);

SET @txn_commit_record_id = LAST_INSERT_ID();

COMMIT;

SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_id = @txn_commit_record_id;
-- Expected: one row. The INSERT survived COMMIT.

-- -----------------------------------------------------------------------------
-- 2. START TRANSACTION and ROLLBACK
-- Insert a second test row, then ROLLBACK. LAST_INSERT_ID() still holds the
-- allocated AUTO_INCREMENT value, but the row must not exist after ROLLBACK.
-- -----------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @txn_user_id,
    @txn_category_id,
    '2026-11-24',
    1.2500,
    'EcoTrack txn test ROLLBACK'
);

SET @txn_rollback_record_id = LAST_INSERT_ID();

SELECT
    record_id AS record_number,
    notes     AS record_notes
FROM CARBON_RECORD
WHERE record_id = @txn_rollback_record_id;
-- Expected inside the transaction: one row (not yet durable).

ROLLBACK;

SELECT
    COUNT(*) AS rolled_back_row_count
FROM CARBON_RECORD
WHERE record_id = @txn_rollback_record_id
   OR notes = 'EcoTrack txn test ROLLBACK';
-- Expected: 0. ROLLBACK undid the INSERT.

-- -----------------------------------------------------------------------------
-- 3. SAVEPOINT
-- Update the committed test row twice. ROLLBACK TO SAVEPOINT undoes only the
-- second UPDATE. COMMIT then keeps the first UPDATE.
-- -----------------------------------------------------------------------------
START TRANSACTION;

UPDATE CARBON_RECORD
   SET carbon_footprint = 4.0000
 WHERE record_id = @txn_commit_record_id;

SAVEPOINT sp_after_first_update;

UPDATE CARBON_RECORD
   SET carbon_footprint = 9.0000
 WHERE record_id = @txn_commit_record_id;

SELECT carbon_footprint AS emissions_before_savepoint_rollback
FROM CARBON_RECORD
WHERE record_id = @txn_commit_record_id;
-- Expected here: 9.0000 (second update, still uncommitted).

ROLLBACK TO SAVEPOINT sp_after_first_update;

SELECT carbon_footprint AS emissions_after_savepoint_rollback
FROM CARBON_RECORD
WHERE record_id = @txn_commit_record_id;
-- Expected: 4.0000 (second update undone; first update kept).

COMMIT;

SELECT
    record_id        AS record_number,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_id = @txn_commit_record_id;
-- Expected after COMMIT: carbon_footprint = 4.0000, not 9.0000 or 2.5000.

-- -----------------------------------------------------------------------------
-- 4. Multiple DML statements in one transaction (atomic unit of work)
-- Header row + 1:1 TRANSPORTATION child + RECOMMENDATION, then COMMIT.
-- If any statement failed, ROLLBACK would undo all three.
-- -----------------------------------------------------------------------------
START TRANSACTION;

INSERT INTO CARBON_RECORD (
    user_id,
    category_id,
    record_date,
    carbon_footprint,
    notes
) VALUES (
    @txn_user_id,
    @txn_category_id,
    '2026-11-24',
    4.8000,
    'EcoTrack txn test MULTI'
);

SET @txn_multi_record_id = LAST_INSERT_ID();

INSERT INTO TRANSPORTATION (
    record_id,
    mode,
    vehicle_type,
    distance_km,
    fuel_type,
    factor_id
) VALUES (
    @txn_multi_record_id,
    'Private car',
    'Hatchback',
    25.00,
    'Petrol',
    @txn_factor_id
);

INSERT INTO RECOMMENDATION (
    user_id,
    record_id,
    title,
    description,
    suggested_action
) VALUES (
    @txn_user_id,
    @txn_multi_record_id,
    'Txn-test tip',
    'Created inside 10_transactions_indexing.sql multi-statement transaction.',
    'Delete this recommendation with the parent test carbon record.'
);

COMMIT;

SELECT
    cr.record_id        AS record_number,
    cr.carbon_footprint AS emissions_kg_co2e,
    t.transport_id      AS transport_number,
    t.distance_km       AS distance_km,
    r.rec_id            AS recommendation_number,
    r.title             AS recommendation_title
FROM CARBON_RECORD AS cr
INNER JOIN TRANSPORTATION AS t
        ON t.record_id = cr.record_id
INNER JOIN RECOMMENDATION AS r
        ON r.record_id = cr.record_id
       AND r.user_id = cr.user_id
WHERE cr.record_id = @txn_multi_record_id;
-- Expected: one joined row; all three inserts became visible together.

-- Remove dedicated test rows so sample data is unchanged after this section.
-- FK ON DELETE CASCADE clears TRANSPORTATION and RECOMMENDATION children.
DELETE FROM CARBON_RECORD
 WHERE record_id IN (@txn_commit_record_id, @txn_multi_record_id)
    OR notes LIKE 'EcoTrack txn test%';

SELECT COUNT(*) AS leftover_txn_test_rows
FROM CARBON_RECORD
WHERE notes LIKE 'EcoTrack txn test%';
-- Expected: 0.

-- =============================================================================
-- SECTION 2 – CREATING INDEXES
-- Inspect current indexes first. CREATE INDEX IF NOT EXISTS so a re-run does
-- not fail. PK / UNIQUE / FK indexes listed in the header are left alone.
-- =============================================================================

SHOW INDEX FROM USERS;
SHOW INDEX FROM CARBON_RECORD;
SHOW INDEX FROM TRANSPORTATION;
SHOW INDEX FROM FOOD_CONSUMPTION;
SHOW INDEX FROM ELECTRICITY_USAGE;

-- EXPLAIN before the new date / emission indexes (baseline for SECTION 4).
-- record_date and carbon_footprint currently have no secondary index, so these
-- plans typically show type = ALL (full scan of CARBON_RECORD) on a small
-- sample table. After CREATE INDEX, the same queries should show type = range
-- and a key name of idx_carbon_record_record_date / idx_carbon_record_carbon_footprint.
EXPLAIN
SELECT record_id, record_date, carbon_footprint
FROM CARBON_RECORD
WHERE record_date BETWEEN '2026-10-01' AND '2026-10-15';

EXPLAIN
SELECT record_id, carbon_footprint, notes
FROM CARBON_RECORD
WHERE carbon_footprint > 50;

-- Skip USERS.email: already UNIQUE uq_users_email.
-- Skip CARBON_RECORD.user_id / category_id: already InnoDB FK indexes.
-- Skip subtype record_id / factor_id: UNIQUE or FK indexes already exist.

-- Date range filters (04_basic_queries, GetCarbonRecordsByDate).
CREATE INDEX IF NOT EXISTS idx_carbon_record_record_date
    ON CARBON_RECORD (record_date);

-- Emission filters (WHERE carbon_footprint > n, ORDER BY carbon_footprint).
CREATE INDEX IF NOT EXISTS idx_carbon_record_carbon_footprint
    ON CARBON_RECORD (carbon_footprint);

-- =============================================================================
-- SECTION 3 – INDEX MANAGEMENT
-- =============================================================================

-- 1. Indexes on every EcoTrack base table (quick catalogue).
SHOW INDEX FROM USERS;
SHOW INDEX FROM CATEGORY;
SHOW INDEX FROM SUSTAINABILITY_GOAL;
SHOW INDEX FROM EMISSION_FACTOR;
SHOW INDEX FROM CARBON_RECORD;
SHOW INDEX FROM TRANSPORTATION;
SHOW INDEX FROM FOOD_CONSUMPTION;
SHOW INDEX FROM ELECTRICITY_USAGE;
SHOW INDEX FROM RECOMMENDATION;
SHOW INDEX FROM ACHIEVEMENT;

-- 2. USERS indexes (PK, UNIQUE email, UNIQUE phone).
SHOW INDEX FROM USERS;

-- 3. CARBON_RECORD indexes (PK, UNIQUE (record_id, user_id), FK user_id,
--    FK category_id, plus the two secondary indexes created above).
SHOW INDEX FROM CARBON_RECORD;

-- 4. Dedicated demonstration index only — not used by FKs or application queries.
--    Prefix length keeps the index small on VARCHAR(500) utf8mb4 notes.
CREATE INDEX IF NOT EXISTS idx_demo_carbon_record_notes
    ON CARBON_RECORD (notes(40));

SHOW INDEX FROM CARBON_RECORD
 WHERE Key_name = 'idx_demo_carbon_record_notes';
-- Expected: at least one row (the demo index exists).

DROP INDEX idx_demo_carbon_record_notes ON CARBON_RECORD;

-- 5. Confirm the demonstration index is gone. Do not drop PK, UNIQUE, FK, or
--    idx_carbon_record_record_date / idx_carbon_record_carbon_footprint.
SHOW INDEX FROM CARBON_RECORD
 WHERE Key_name = 'idx_demo_carbon_record_notes';
-- Expected: empty result.

-- =============================================================================
-- SECTION 4 – QUERY PERFORMANCE ANALYSIS (EXPLAIN)
--
-- How to read EXPLAIN (MySQL 8 / 26):
--   type  ALL    full table scan (no usable index for the predicate)
--   type  ref    non-unique index lookup (typical for FK user_id / category_id)
--   type  range  index range scan (BETWEEN, >, < on an indexed column)
--   type  const  single-row lookup by primary/unique key
--   key          name of the index actually chosen (NULL = no index)
--   rows         optimizer's row estimate
--   Extra        Using where / Using index / Using filesort / ...
--
-- Before vs after (practical on this schema):
--   User-id and USERS ⋈ CARBON_RECORD joins already used fk_record_user,
--   so those plans should look similar to the pre-index baseline.
--   Date-range and carbon_footprint > 50 should change from type ALL
--   (SECTION 2 baseline) to type range on the new secondary indexes.
-- =============================================================================

SET @explain_user_id = (
    SELECT user_id
    FROM USERS
    WHERE email = 'aaliya@ecotrack.in'
);

-- 1. Carbon records by user ID (FK index fk_record_user; already present).
EXPLAIN
SELECT
    record_id,
    record_date,
    carbon_footprint,
    notes
FROM CARBON_RECORD
WHERE user_id = @explain_user_id;

-- 2. Carbon records in a date range (idx_carbon_record_record_date).
EXPLAIN
SELECT
    record_id,
    user_id,
    record_date,
    carbon_footprint
FROM CARBON_RECORD
WHERE record_date BETWEEN '2026-10-01' AND '2026-10-15';

-- 3. Join USERS and CARBON_RECORD (nested loop on pk_users + fk_record_user).
EXPLAIN
SELECT
    u.user_id,
    u.name,
    u.email,
    cr.record_id,
    cr.record_date,
    cr.carbon_footprint
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id;

-- 4a. After-index plan for emission filter (compare with SECTION 2 baseline).
EXPLAIN
SELECT
    record_id,
    user_id,
    carbon_footprint,
    notes
FROM CARBON_RECORD
WHERE carbon_footprint > 50;

-- 4b. After-index plan for the same date filter as SECTION 2.
EXPLAIN
SELECT
    record_id,
    record_date,
    carbon_footprint
FROM CARBON_RECORD
WHERE record_date BETWEEN '2026-10-01' AND '2026-10-15';
