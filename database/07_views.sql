-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 07_views.sql
-- Purpose: Create application views over the EcoTrack schema.
-- Prerequisite: 01_create_database.sql, 02_create_tables.sql, 03_insert_data.sql
--
-- Emission grain:
--   Totals and averages use CARBON_RECORD.carbon_footprint only.
--   TRANSPORTATION, FOOD_CONSUMPTION and ELECTRICITY_USAGE are 1:1 details of
--   a carbon record. They are joined only in the activity-detail views, never
--   when aggregating, so emissions are not double-counted.
--
-- HIGH_EMISSION_USERS threshold:
--   100 kg CO2e, the same user-total threshold used in 06_aggregate_groupby_having.sql.
--   MySQL views cannot reference session variables, so the value is written
--   in the view definition.
-- =============================================================================

USE EcoTrack;

-- =============================================================================
-- 1. USER_CARBON_SUMMARY
-- One row per registered user: identity, summed kg CO2e, and log count.
-- LEFT JOIN keeps users who have not logged any carbon records.
-- COUNT(cr.record_id) is 0 for those users; SUM is coalesced to 0.
-- =============================================================================
CREATE OR REPLACE VIEW USER_CARBON_SUMMARY AS
SELECT
    u.user_id                             AS user_number,
    u.name                                AS user_name,
    u.email                               AS email_address,
    COALESCE(SUM(cr.carbon_footprint), 0) AS total_emissions_kg_co2e,
    COUNT(cr.record_id)                   AS carbon_record_count
FROM USERS AS u
LEFT JOIN CARBON_RECORD AS cr
       ON u.user_id = cr.user_id
GROUP BY u.user_id, u.name, u.email;

-- =============================================================================
-- 2. CATEGORY_EMISSION_SUMMARY
-- One row per emission category: totals, average per record, and record count.
-- LEFT JOIN keeps categories that have no carbon records yet.
-- =============================================================================
CREATE OR REPLACE VIEW CATEGORY_EMISSION_SUMMARY AS
SELECT
    cat.category_id                       AS category_number,
    cat.category_name                     AS activity_category,
    COALESCE(SUM(cr.carbon_footprint), 0) AS total_emissions_kg_co2e,
    AVG(cr.carbon_footprint)              AS average_emissions_kg_co2e,
    COUNT(cr.record_id)                   AS carbon_record_count
FROM CATEGORY AS cat
LEFT JOIN CARBON_RECORD AS cr
       ON cat.category_id = cr.category_id
GROUP BY cat.category_id, cat.category_name;

-- =============================================================================
-- 3. CARBON_ACTIVITY_DETAILS
-- One row per carbon record, with the owning user and category name.
-- INNER JOIN is correct: CARBON_RECORD.user_id and category_id are NOT NULL
-- foreign keys, so every record has a user and a category.
-- Activity subtype tables are not joined here, so each record appears once.
-- =============================================================================
CREATE OR REPLACE VIEW CARBON_ACTIVITY_DETAILS AS
SELECT
    u.user_id            AS user_number,
    u.name               AS user_name,
    u.email              AS email_address,
    cr.record_id         AS record_number,
    cr.record_date       AS activity_date,
    cat.category_id      AS category_number,
    cat.category_name    AS activity_category,
    cr.carbon_footprint  AS emissions_kg_co2e,
    cr.notes             AS record_notes
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
INNER JOIN CATEGORY AS cat
        ON cr.category_id = cat.category_id;

-- =============================================================================
-- 4. TRANSPORTATION_EMISSION_DETAILS
-- Travel subtype rows (1:1 with CARBON_RECORD) plus user, record and factor.
-- INNER JOIN from TRANSPORTATION: only records that have a travel row appear.
-- record_id is UNIQUE on TRANSPORTATION, so this view does not duplicate logs.
-- =============================================================================
CREATE OR REPLACE VIEW TRANSPORTATION_EMISSION_DETAILS AS
SELECT
    u.user_id             AS user_number,
    u.name                AS user_name,
    u.email               AS email_address,
    cr.record_id          AS record_number,
    cr.record_date        AS activity_date,
    t.transport_id        AS transport_number,
    t.mode                AS travel_mode,
    t.vehicle_type        AS vehicle,
    t.distance_km         AS distance_km,
    t.fuel_type           AS fuel,
    ef.activity_name      AS factor_name,
    ef.factor_value       AS factor_kg_co2e_per_unit,
    ef.unit               AS factor_unit,
    cr.carbon_footprint   AS emissions_kg_co2e,
    cr.notes              AS record_notes
FROM TRANSPORTATION AS t
INNER JOIN CARBON_RECORD AS cr
        ON t.record_id = cr.record_id
INNER JOIN USERS AS u
        ON cr.user_id = u.user_id
INNER JOIN EMISSION_FACTOR AS ef
        ON t.factor_id = ef.factor_id;

-- =============================================================================
-- 5. FOOD_EMISSION_DETAILS
-- Food subtype rows (1:1 with CARBON_RECORD) plus user, record and factor.
-- record_id is UNIQUE on FOOD_CONSUMPTION, so each food log appears once.
-- =============================================================================
CREATE OR REPLACE VIEW FOOD_EMISSION_DETAILS AS
SELECT
    u.user_id             AS user_number,
    u.name                AS user_name,
    u.email               AS email_address,
    cr.record_id          AS record_number,
    cr.record_date        AS activity_date,
    f.food_id             AS food_number,
    f.food_type           AS food_item,
    f.quantity            AS quantity,
    f.unit                AS unit,
    ef.activity_name      AS factor_name,
    ef.factor_value       AS factor_kg_co2e_per_unit,
    ef.unit               AS factor_unit,
    cr.carbon_footprint   AS emissions_kg_co2e,
    cr.notes              AS record_notes
FROM FOOD_CONSUMPTION AS f
INNER JOIN CARBON_RECORD AS cr
        ON f.record_id = cr.record_id
INNER JOIN USERS AS u
        ON cr.user_id = u.user_id
INNER JOIN EMISSION_FACTOR AS ef
        ON f.factor_id = ef.factor_id;

-- =============================================================================
-- 6. ELECTRICITY_EMISSION_DETAILS
-- Electricity subtype rows (1:1 with CARBON_RECORD) plus user, record and factor.
-- record_id is UNIQUE on ELECTRICITY_USAGE, so each usage row appears once.
-- =============================================================================
CREATE OR REPLACE VIEW ELECTRICITY_EMISSION_DETAILS AS
SELECT
    u.user_id             AS user_number,
    u.name                AS user_name,
    u.email               AS email_address,
    cr.record_id          AS record_number,
    cr.record_date        AS activity_date,
    e.usage_id            AS usage_number,
    e.kwh                 AS electricity_kwh,
    ef.activity_name      AS factor_name,
    ef.factor_value       AS factor_kg_co2e_per_unit,
    ef.unit               AS factor_unit,
    cr.carbon_footprint   AS emissions_kg_co2e,
    cr.notes              AS record_notes
FROM ELECTRICITY_USAGE AS e
INNER JOIN CARBON_RECORD AS cr
        ON e.record_id = cr.record_id
INNER JOIN USERS AS u
        ON cr.user_id = u.user_id
INNER JOIN EMISSION_FACTOR AS ef
        ON e.factor_id = ef.factor_id;

-- =============================================================================
-- 7. HIGH_EMISSION_USERS
-- Users whose summed carbon_footprint is greater than 100 kg CO2e.
-- INNER JOIN excludes users with no logs (their total would not exceed the
-- threshold). HAVING filters after grouping; WHERE cannot use SUM().
-- =============================================================================
CREATE OR REPLACE VIEW HIGH_EMISSION_USERS AS
SELECT
    u.user_id                AS user_number,
    u.name                   AS user_name,
    u.email                  AS email_address,
    SUM(cr.carbon_footprint) AS total_emissions_kg_co2e,
    COUNT(cr.record_id)      AS carbon_record_count
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
GROUP BY u.user_id, u.name, u.email
HAVING SUM(cr.carbon_footprint) > 100;

-- =============================================================================
-- TEST SELECTS
-- Display the contents of every view created above.
-- ORDER BY is applied here (not inside the views) so results are readable.
-- =============================================================================

-- 1. Every user with total emissions and log count (zero logs still appear).
SELECT *
FROM USER_CARBON_SUMMARY
ORDER BY total_emissions_kg_co2e DESC, user_name ASC;

-- 2. Totals and averages for each emission category.
SELECT *
FROM CATEGORY_EMISSION_SUMMARY
ORDER BY total_emissions_kg_co2e DESC;

-- 3. User + record + category for every carbon log.
SELECT *
FROM CARBON_ACTIVITY_DETAILS
ORDER BY user_name ASC, activity_date ASC;

-- 4. Transportation activities with owning user and emission factor.
SELECT *
FROM TRANSPORTATION_EMISSION_DETAILS
ORDER BY user_name ASC, activity_date ASC;

-- 5. Food consumption activities with owning user and emission factor.
SELECT *
FROM FOOD_EMISSION_DETAILS
ORDER BY user_name ASC, activity_date ASC;

-- 6. Electricity usage activities with owning user and emission factor.
SELECT *
FROM ELECTRICITY_EMISSION_DETAILS
ORDER BY user_name ASC, activity_date ASC;

-- 7. Users whose total footprint exceeds 100 kg CO2e.
SELECT *
FROM HIGH_EMISSION_USERS
ORDER BY total_emissions_kg_co2e DESC;
