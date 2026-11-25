-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 08_procedures_functions.sql
-- Purpose: Stored procedures and stored functions over the EcoTrack schema.
-- Prerequisite: 01_create_database.sql, 02_create_tables.sql, 03_insert_data.sql
--
-- Emission grain:
--   Totals, averages and counts use CARBON_RECORD.carbon_footprint / record_id.
--   Activity subtype tables are not joined in these routines, so a record is
--   never counted more than once.
--
-- Test CALL / SELECT statements at the end look up sample keys by unique
-- email and category_name so they do not assume a particular AUTO_INCREMENT id.
-- =============================================================================

USE EcoTrack;

-- =============================================================================
-- SECTION 1 – STORED PROCEDURES
-- =============================================================================

DELIMITER $$

-- -----------------------------------------------------------------------------
-- 1. GetUserCarbonSummary
-- IN  p_user_id : USERS.user_id
-- Result set    : name, total kg CO2e, number of carbon records
--
-- LEFT JOIN CARBON_RECORD so a registered user with no logs still appears,
-- with total_emissions_kg_co2e = 0 and carbon_record_count = 0.
-- If p_user_id does not exist, the result set is empty.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS GetUserCarbonSummary $$

CREATE PROCEDURE GetUserCarbonSummary(IN p_user_id INT)
READS SQL DATA
BEGIN
    SELECT
        u.user_id                             AS user_number,
        u.name                                AS user_name,
        u.email                               AS email_address,
        COALESCE(SUM(cr.carbon_footprint), 0) AS total_emissions_kg_co2e,
        COUNT(cr.record_id)                   AS carbon_record_count
    FROM USERS AS u
    LEFT JOIN CARBON_RECORD AS cr
           ON u.user_id = cr.user_id
    WHERE u.user_id = p_user_id
    GROUP BY u.user_id, u.name, u.email;
END $$

-- -----------------------------------------------------------------------------
-- 2. GetCategoryEmissions
-- IN  p_category_id : CATEGORY.category_id
-- Result set        : category name, total, average, record count
--
-- LEFT JOIN CARBON_RECORD so a category with no logs still appears.
-- AVG is NULL when there are no records (there is no average of an empty set).
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS GetCategoryEmissions $$

CREATE PROCEDURE GetCategoryEmissions(IN p_category_id INT)
READS SQL DATA
BEGIN
    SELECT
        cat.category_id                       AS category_number,
        cat.category_name                     AS activity_category,
        COALESCE(SUM(cr.carbon_footprint), 0) AS total_emissions_kg_co2e,
        AVG(cr.carbon_footprint)              AS average_emissions_kg_co2e,
        COUNT(cr.record_id)                   AS carbon_record_count
    FROM CATEGORY AS cat
    LEFT JOIN CARBON_RECORD AS cr
           ON cat.category_id = cr.category_id
    WHERE cat.category_id = p_category_id
    GROUP BY cat.category_id, cat.category_name;
END $$

-- -----------------------------------------------------------------------------
-- 3. GetTopEmissionUsers
-- IN  p_user_count : how many users to return (highest totals first)
--
-- LEFT JOIN includes users with no logs (total 0) if p_user_count is large
-- enough to reach them. Invalid or NULL p_user_count is treated as 0 rows.
-- LIMIT may use an INT routine parameter in MySQL stored programs.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS GetTopEmissionUsers $$

CREATE PROCEDURE GetTopEmissionUsers(IN p_user_count INT)
READS SQL DATA
BEGIN
    DECLARE v_limit INT;

    IF p_user_count IS NULL OR p_user_count < 1 THEN
        SET v_limit = 0;
    ELSE
        SET v_limit = p_user_count;
    END IF;

    SELECT
        u.user_id                             AS user_number,
        u.name                                AS user_name,
        u.email                               AS email_address,
        COALESCE(SUM(cr.carbon_footprint), 0) AS total_emissions_kg_co2e,
        COUNT(cr.record_id)                   AS carbon_record_count
    FROM USERS AS u
    LEFT JOIN CARBON_RECORD AS cr
           ON u.user_id = cr.user_id
    GROUP BY u.user_id, u.name, u.email
    ORDER BY total_emissions_kg_co2e DESC, u.name ASC
    LIMIT v_limit;
END $$

-- -----------------------------------------------------------------------------
-- 4. GetCarbonRecordsByDate
-- IN  p_start_date, p_end_date : inclusive DATE bounds on CARBON_RECORD.record_date
--
-- Joins USERS and CATEGORY for name and category_name.
-- Dates are ordered with LEAST / GREATEST so the caller may pass them in
-- either order. If either date is NULL, no rows are returned.
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS GetCarbonRecordsByDate $$

CREATE PROCEDURE GetCarbonRecordsByDate(
    IN p_start_date DATE,
    IN p_end_date   DATE
)
READS SQL DATA
BEGIN
    SELECT
        cr.record_id         AS record_number,
        cr.record_date       AS activity_date,
        u.user_id            AS user_number,
        u.name               AS user_name,
        u.email              AS email_address,
        cat.category_id      AS category_number,
        cat.category_name    AS activity_category,
        cr.carbon_footprint  AS emissions_kg_co2e,
        cr.notes             AS record_notes
    FROM CARBON_RECORD AS cr
    INNER JOIN USERS AS u
            ON cr.user_id = u.user_id
    INNER JOIN CATEGORY AS cat
            ON cr.category_id = cat.category_id
    WHERE p_start_date IS NOT NULL
      AND p_end_date   IS NOT NULL
      AND cr.record_date BETWEEN LEAST(p_start_date, p_end_date)
                             AND GREATEST(p_start_date, p_end_date)
    ORDER BY cr.record_date ASC, u.name ASC;
END $$

-- -----------------------------------------------------------------------------
-- 5. GetUserCarbonRecords
-- IN  p_user_id : USERS.user_id
-- Result set    : every CARBON_RECORD for that user, with category name
--
-- INNER JOIN is enough for the records themselves. If the user has no logs,
-- the result set is empty (use GetUserCarbonSummary to see a zero total).
-- -----------------------------------------------------------------------------
DROP PROCEDURE IF EXISTS GetUserCarbonRecords $$

CREATE PROCEDURE GetUserCarbonRecords(IN p_user_id INT)
READS SQL DATA
BEGIN
    SELECT
        cr.record_id         AS record_number,
        cr.record_date       AS activity_date,
        u.user_id            AS user_number,
        u.name               AS user_name,
        cat.category_id      AS category_number,
        cat.category_name    AS activity_category,
        cr.carbon_footprint  AS emissions_kg_co2e,
        cr.notes             AS record_notes
    FROM USERS AS u
    INNER JOIN CARBON_RECORD AS cr
            ON u.user_id = cr.user_id
    INNER JOIN CATEGORY AS cat
            ON cr.category_id = cat.category_id
    WHERE u.user_id = p_user_id
    ORDER BY cr.record_date ASC, cr.record_id ASC;
END $$

-- =============================================================================
-- SECTION 2 – STORED FUNCTIONS
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. CalculateUserCarbonFootprint
-- Returns the sum of CARBON_RECORD.carbon_footprint for p_user_id.
-- COALESCE turns NULL (no matching rows) into 0, including unknown user ids.
-- DECIMAL(16,4) is wider than carbon_footprint DECIMAL(12,4) so the sum fits.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS CalculateUserCarbonFootprint $$

CREATE FUNCTION CalculateUserCarbonFootprint(p_user_id INT)
RETURNS DECIMAL(16, 4)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(16, 4);

    SELECT COALESCE(SUM(carbon_footprint), 0)
      INTO v_total
      FROM CARBON_RECORD
     WHERE user_id = p_user_id;

    RETURN v_total;
END $$

-- -----------------------------------------------------------------------------
-- 2. GetTotalCarbonRecords
-- Returns COUNT of CARBON_RECORD rows for p_user_id (0 if none).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS GetTotalCarbonRecords $$

CREATE FUNCTION GetTotalCarbonRecords(p_user_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_record_count INT;

    SELECT COUNT(*)
      INTO v_record_count
      FROM CARBON_RECORD
     WHERE user_id = p_user_id;

    RETURN v_record_count;
END $$

-- -----------------------------------------------------------------------------
-- 3. GetEmissionLevel
-- Classifies a kg CO2e value. Does not read tables (NO SQL).
--
-- Thresholds (documented for the DBMS report):
--   NULL                  -> 'Unknown'
--   <  10  kg CO2e        -> 'Low'
--                          typical short trips and small food logs in the sample
--                          (see 04_basic_queries.sql: 1–10 kg as moderate-small logs)
--   10 to 100 kg CO2e     -> 'Moderate'
--                          includes many household electricity bills below the
--                          high-user cutoff
--   > 100 kg CO2e         -> 'High'
--                          same numeric cutoff as HIGH_EMISSION_USERS and
--                          @user_total_emission_threshold in 06_aggregate_groupby_having.sql
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS GetEmissionLevel $$

CREATE FUNCTION GetEmissionLevel(p_emissions_kg_co2e DECIMAL(16, 4))
RETURNS VARCHAR(20)
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_level VARCHAR(20);

    IF p_emissions_kg_co2e IS NULL THEN
        SET v_level = 'Unknown';
    ELSEIF p_emissions_kg_co2e < 10 THEN
        SET v_level = 'Low';
    ELSEIF p_emissions_kg_co2e <= 100 THEN
        SET v_level = 'Moderate';
    ELSE
        SET v_level = 'High';
    END IF;

    RETURN v_level;
END $$

DELIMITER ;

-- =============================================================================
-- SECTION 3 – TESTING
-- Sample keys are resolved by unique email / category_name, not hardcoded ids.
-- =============================================================================

SET @test_user_id = (
    SELECT user_id
    FROM USERS
    WHERE email = 'aaliya@ecotrack.in'
);

SET @test_user_id_low = (
    SELECT user_id
    FROM USERS
    WHERE email = 'anshika@ecotrack.in'
);

SET @test_category_id = (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Electricity'
);

-- Procedures
CALL GetUserCarbonSummary(@test_user_id);
CALL GetUserCarbonSummary(@test_user_id_low);

-- Unknown user: empty result (no matching USERS row).
CALL GetUserCarbonSummary(0);

CALL GetCategoryEmissions(@test_category_id);

CALL GetTopEmissionUsers(3);

-- Inclusive range used in 04_basic_queries.sql (first half of October 2026).
CALL GetCarbonRecordsByDate('2026-10-01', '2026-10-15');

CALL GetUserCarbonRecords(@test_user_id);

-- Functions
SELECT
    @test_user_id                              AS user_number,
    CalculateUserCarbonFootprint(@test_user_id) AS total_emissions_kg_co2e,
    GetTotalCarbonRecords(@test_user_id)        AS carbon_record_count,
    GetEmissionLevel(
        CalculateUserCarbonFootprint(@test_user_id)
    )                                           AS emission_level;

SELECT
    @test_user_id_low                                   AS user_number,
    CalculateUserCarbonFootprint(@test_user_id_low)     AS total_emissions_kg_co2e,
    GetTotalCarbonRecords(@test_user_id_low)            AS carbon_record_count,
    GetEmissionLevel(
        CalculateUserCarbonFootprint(@test_user_id_low)
    )                                                   AS emission_level;

-- Unknown user id: functions return 0, classified as Low.
SELECT
    CalculateUserCarbonFootprint(0) AS total_emissions_kg_co2e,
    GetTotalCarbonRecords(0)        AS carbon_record_count;

-- GetEmissionLevel bands (Low / Moderate / High / Unknown).
SELECT 4.8384  AS sample_kg_co2e, GetEmissionLevel(4.8384)  AS emission_level;
SELECT 50.0000 AS sample_kg_co2e, GetEmissionLevel(50.0000) AS emission_level;
SELECT 152.5200 AS sample_kg_co2e, GetEmissionLevel(152.5200) AS emission_level;
SELECT NULL    AS sample_kg_co2e, GetEmissionLevel(NULL)    AS emission_level;
