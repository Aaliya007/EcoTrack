-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 05_joins_nested_queries.sql
-- Purpose: INNER / LEFT / multi-table joins, subqueries, IN and NOT IN
--          using the EcoTrack schema and sample data.
-- Prerequisite: 01_create_database.sql, 02_create_tables.sql, 03_insert_data.sql
-- Relationships used:
--   USERS.user_id              -> CARBON_RECORD.user_id
--   CATEGORY.category_id       -> CARBON_RECORD.category_id
--   CARBON_RECORD.record_id    -> TRANSPORTATION.record_id        (1:1)
--   CARBON_RECORD.record_id    -> FOOD_CONSUMPTION.record_id      (1:1)
--   CARBON_RECORD.record_id    -> ELECTRICITY_USAGE.record_id     (1:1)
--   EMISSION_FACTOR.factor_id  -> TRANSPORTATION.factor_id
--   EMISSION_FACTOR.factor_id  -> FOOD_CONSUMPTION.factor_id
--   EMISSION_FACTOR.factor_id  -> ELECTRICITY_USAGE.factor_id
-- =============================================================================

USE EcoTrack;

-- =============================================================================
-- 1. INNER JOIN
-- =============================================================================

-- Users together with each carbon record they have logged.
SELECT
    u.user_id          AS user_number,
    u.name             AS user_name,
    u.email            AS email_address,
    cr.record_id       AS record_number,
    cr.record_date     AS log_date,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes           AS record_notes
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
ORDER BY u.name, cr.record_date;

-- Carbon records with the category name from CATEGORY (not only category_id).
SELECT
    cr.record_id        AS record_number,
    cr.record_date      AS log_date,
    cat.category_name   AS activity_category,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes            AS record_notes
FROM CARBON_RECORD AS cr
INNER JOIN CATEGORY AS cat
        ON cr.category_id = cat.category_id
ORDER BY cat.category_name, cr.record_date;

-- Transportation activity rows with the user who owns the parent carbon record.
SELECT
    u.name              AS user_name,
    cr.record_date      AS log_date,
    t.mode              AS travel_mode,
    t.vehicle_type      AS vehicle,
    t.distance_km       AS distance_km,
    t.fuel_type         AS fuel,
    cr.carbon_footprint AS emissions_kg_co2e
FROM TRANSPORTATION AS t
INNER JOIN CARBON_RECORD AS cr
        ON t.record_id = cr.record_id
INNER JOIN USERS AS u
        ON cr.user_id = u.user_id
ORDER BY u.name, cr.record_date;

-- Food consumption rows with the owning user.
SELECT
    u.name              AS user_name,
    cr.record_date      AS log_date,
    f.food_type         AS food_item,
    f.quantity          AS quantity,
    f.unit              AS unit,
    cr.carbon_footprint AS emissions_kg_co2e
FROM FOOD_CONSUMPTION AS f
INNER JOIN CARBON_RECORD AS cr
        ON f.record_id = cr.record_id
INNER JOIN USERS AS u
        ON cr.user_id = u.user_id
ORDER BY u.name, cr.record_date;

-- Electricity usage rows with the owning user.
SELECT
    u.name              AS user_name,
    cr.record_date      AS log_date,
    e.kwh               AS electricity_kwh,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes            AS record_notes
FROM ELECTRICITY_USAGE AS e
INNER JOIN CARBON_RECORD AS cr
        ON e.record_id = cr.record_id
INNER JOIN USERS AS u
        ON cr.user_id = u.user_id
ORDER BY u.name, cr.record_date;

-- Detailed travel report: user, log, category, distance and the emission factor used.
SELECT
    u.name              AS user_name,
    cat.category_name   AS activity_category,
    cr.record_date      AS log_date,
    t.mode              AS travel_mode,
    t.vehicle_type      AS vehicle,
    t.distance_km       AS distance_km,
    t.fuel_type         AS fuel,
    ef.activity_name    AS factor_name,
    ef.factor_value     AS factor_kg_co2e_per_unit,
    ef.unit             AS factor_unit,
    cr.carbon_footprint AS emissions_kg_co2e
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
INNER JOIN CATEGORY AS cat
        ON cr.category_id = cat.category_id
INNER JOIN TRANSPORTATION AS t
        ON cr.record_id = t.record_id
INNER JOIN EMISSION_FACTOR AS ef
        ON t.factor_id = ef.factor_id
ORDER BY cr.carbon_footprint DESC;

-- =============================================================================
-- 2. LEFT JOIN
-- =============================================================================

-- All registered users, even if they have no rows in CARBON_RECORD.
-- With the current sample data every user has logs; unmatched users would show NULL record columns.
SELECT
    u.user_id           AS user_number,
    u.name              AS user_name,
    u.email             AS email_address,
    cr.record_id        AS record_number,
    cr.record_date      AS log_date,
    cr.carbon_footprint AS emissions_kg_co2e
FROM USERS AS u
LEFT JOIN CARBON_RECORD AS cr
       ON u.user_id = cr.user_id
ORDER BY u.name, cr.record_date;

-- All emission categories, even if no carbon records use them yet.
SELECT
    cat.category_id     AS category_number,
    cat.category_name   AS activity_category,
    cr.record_id        AS record_number,
    cr.carbon_footprint AS emissions_kg_co2e
FROM CATEGORY AS cat
LEFT JOIN CARBON_RECORD AS cr
       ON cat.category_id = cr.category_id
ORDER BY cat.category_name, cr.record_date;

-- =============================================================================
-- 3. MULTIPLE TABLE JOINS
-- =============================================================================

-- Comprehensive log report: user + carbon record + category name.
SELECT
    u.name              AS user_name,
    u.email             AS email_address,
    cr.record_id        AS record_number,
    cr.record_date      AS log_date,
    cat.category_name   AS activity_category,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes            AS record_notes
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
INNER JOIN CATEGORY AS cat
        ON cr.category_id = cat.category_id
ORDER BY u.name, cr.record_date;

-- Same grain as CARBON_RECORD, with optional subtype columns.
-- Each record matches at most one of TRANSPORTATION, FOOD_CONSUMPTION or ELECTRICITY_USAGE,
-- so LEFT JOIN on all three does not duplicate rows.
SELECT
    u.name              AS user_name,
    cat.category_name   AS activity_category,
    cr.record_date      AS log_date,
    cr.carbon_footprint AS emissions_kg_co2e,
    t.mode              AS travel_mode,
    t.vehicle_type      AS vehicle,
    t.distance_km       AS distance_km,
    t.fuel_type         AS fuel,
    f.food_type         AS food_item,
    f.quantity          AS food_quantity,
    f.unit              AS food_unit,
    e.kwh               AS electricity_kwh,
    cr.notes            AS record_notes
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
INNER JOIN CATEGORY AS cat
        ON cr.category_id = cat.category_id
LEFT JOIN TRANSPORTATION AS t
       ON cr.record_id = t.record_id
LEFT JOIN FOOD_CONSUMPTION AS f
       ON cr.record_id = f.record_id
LEFT JOIN ELECTRICITY_USAGE AS e
       ON cr.record_id = e.record_id
ORDER BY u.name, cat.category_name, cr.record_date;

-- =============================================================================
-- 4. NESTED QUERIES / SUBQUERIES
-- =============================================================================

-- Users whose total emissions are greater than the average of all users' totals.
SELECT
    u.user_id                          AS user_number,
    u.name                             AS user_name,
    SUM(cr.carbon_footprint)           AS total_emissions_kg_co2e
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
GROUP BY u.user_id, u.name
HAVING SUM(cr.carbon_footprint) > (
    SELECT AVG(user_total.total_emissions)
    FROM (
        SELECT SUM(carbon_footprint) AS total_emissions
        FROM CARBON_RECORD
        GROUP BY user_id
    ) AS user_total
)
ORDER BY total_emissions_kg_co2e DESC;

-- Individual carbon records above the overall average carbon_footprint.
SELECT
    cr.record_id        AS record_number,
    cr.user_id          AS user_number,
    cr.record_date      AS log_date,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes            AS record_notes
FROM CARBON_RECORD AS cr
WHERE cr.carbon_footprint > (
    SELECT AVG(carbon_footprint)
    FROM CARBON_RECORD
)
ORDER BY cr.carbon_footprint DESC;

-- Users who have logged at least one carbon record.
SELECT
    u.user_id AS user_number,
    u.name    AS user_name,
    u.email   AS email_address
FROM USERS AS u
WHERE EXISTS (
    SELECT 1
    FROM CARBON_RECORD AS cr
    WHERE cr.user_id = u.user_id
);

-- Users who have not logged any carbon record.
-- Returns no rows with the current sample data, because every user has logs.
SELECT
    u.user_id AS user_number,
    u.name    AS user_name,
    u.email   AS email_address
FROM USERS AS u
WHERE NOT EXISTS (
    SELECT 1
    FROM CARBON_RECORD AS cr
    WHERE cr.user_id = u.user_id
);

-- The user whose summed carbon_footprint is the highest.
SELECT
    u.user_id                AS user_number,
    u.name                   AS user_name,
    SUM(cr.carbon_footprint) AS total_emissions_kg_co2e
FROM USERS AS u
INNER JOIN CARBON_RECORD AS cr
        ON u.user_id = cr.user_id
GROUP BY u.user_id, u.name
HAVING SUM(cr.carbon_footprint) = (
    SELECT MAX(user_total.total_emissions)
    FROM (
        SELECT SUM(carbon_footprint) AS total_emissions
        FROM CARBON_RECORD
        GROUP BY user_id
    ) AS user_total
);

-- Categories whose total emissions exceed the average of category totals.
SELECT
    cat.category_id          AS category_number,
    cat.category_name        AS activity_category,
    SUM(cr.carbon_footprint) AS category_total_kg_co2e
FROM CATEGORY AS cat
INNER JOIN CARBON_RECORD AS cr
        ON cat.category_id = cr.category_id
GROUP BY cat.category_id, cat.category_name
HAVING SUM(cr.carbon_footprint) > (
    SELECT AVG(category_total.total_emissions)
    FROM (
        SELECT SUM(carbon_footprint) AS total_emissions
        FROM CARBON_RECORD
        GROUP BY category_id
    ) AS category_total
)
ORDER BY category_total_kg_co2e DESC;

-- =============================================================================
-- 5. IN AND NOT IN
-- =============================================================================

-- Carbon records whose category is Food or Electricity.
SELECT
    cr.record_id        AS record_number,
    cr.record_date      AS log_date,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes            AS record_notes
FROM CARBON_RECORD AS cr
WHERE cr.category_id IN (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name IN ('Food', 'Electricity')
)
ORDER BY cr.record_date;

-- Users who have at least one transportation carbon record.
SELECT
    u.user_id AS user_number,
    u.name    AS user_name,
    u.email   AS email_address
FROM USERS AS u
WHERE u.user_id IN (
    SELECT cr.user_id
    FROM CARBON_RECORD AS cr
    INNER JOIN TRANSPORTATION AS t
            ON cr.record_id = t.record_id
);

-- Carbon records that are not electricity logs.
SELECT
    cr.record_id        AS record_number,
    cr.record_date      AS log_date,
    cr.carbon_footprint AS emissions_kg_co2e,
    cr.notes            AS record_notes
FROM CARBON_RECORD AS cr
WHERE cr.category_id NOT IN (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Electricity'
)
ORDER BY cr.record_date;

-- Users who have never logged a domestic-flight transportation row.
SELECT
    u.user_id AS user_number,
    u.name    AS user_name,
    u.email   AS email_address
FROM USERS AS u
WHERE u.user_id NOT IN (
    SELECT cr.user_id
    FROM CARBON_RECORD AS cr
    INNER JOIN TRANSPORTATION AS t
            ON cr.record_id = t.record_id
    INNER JOIN EMISSION_FACTOR AS ef
            ON t.factor_id = ef.factor_id
    WHERE ef.activity_name = 'Domestic flight'
);
