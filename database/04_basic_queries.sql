-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 04_basic_queries.sql
-- Purpose: Basic SELECT / WHERE / ORDER BY / DISTINCT / LIMIT queries
--          against the EcoTrack schema and sample data.
-- Prerequisite: 01_create_database.sql, 02_create_tables.sql, 03_insert_data.sql
-- Note: There is no separate city column. City is stored inside USERS.address
--       (Locality, City, State), so city filters use LIKE on address.
-- =============================================================================

USE EcoTrack;

-- =============================================================================
-- 1. SELECT QUERIES
-- =============================================================================

-- List every registered EcoTrack user (all columns).
SELECT *
FROM USERS;

-- List every carbon log header stored in CARBON_RECORD.
SELECT *
FROM CARBON_RECORD;

-- Show only the public profile columns from USERS (not password_hash).
SELECT
    user_id     AS user_number,
    name        AS user_name,
    email       AS email_address,
    phone       AS mobile_number,
    address     AS residential_address
FROM USERS;

-- Find users whose address contains a particular city (sample: Mumbai).
SELECT
    user_id AS user_number,
    name    AS user_name,
    email   AS email_address,
    address AS residential_address
FROM USERS
WHERE address LIKE '%Mumbai%';

-- Carbon records logged in the first half of October 2026 (sample data range).
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    category_id      AS category_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE record_date BETWEEN '2026-10-01' AND '2026-10-15';

-- =============================================================================
-- 2. WHERE CLAUSE
-- =============================================================================

-- Records whose total emissions are greater than 50 kg CO2e
-- (sample matches include large grid bills and the DEL–BOM flight).
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE carbon_footprint > 50;

-- Records that belong to the Electricity category (looked up by name, not a hardcoded id).
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE category_id = (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Electricity'
);

-- AND: electricity records that also exceed 100 kg CO2e.
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE category_id = (
        SELECT category_id
        FROM CATEGORY
        WHERE category_name = 'Electricity'
      )
  AND carbon_footprint > 100;

-- OR: records whose notes mention a metro trip or a city bus.
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE notes LIKE '%Metro%'
   OR notes LIKE '%bus%';

-- NOT: carbon records that are not in the Transportation category.
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    category_id      AS category_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE category_id NOT IN (
    SELECT category_id
    FROM CATEGORY
    WHERE category_name = 'Transportation'
);

-- LIKE: users whose name starts with 'A' (Aaliya, Anshika, Aditya in the sample).
SELECT
    user_id AS user_number,
    name    AS user_name,
    email   AS email_address
FROM USERS
WHERE name LIKE 'A%';

-- BETWEEN: moderate emission logs between 1 and 10 kg CO2e (inclusive).
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
WHERE carbon_footprint BETWEEN 1 AND 10;

-- =============================================================================
-- 3. ORDER BY
-- =============================================================================

-- Carbon records from lowest to highest emissions.
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
ORDER BY carbon_footprint ASC;

-- Carbon records from highest to lowest emissions.
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
ORDER BY carbon_footprint DESC;

-- Users in alphabetical order by name.
SELECT
    user_id AS user_number,
    name    AS user_name,
    email   AS email_address,
    address AS residential_address
FROM USERS
ORDER BY name ASC;

-- =============================================================================
-- 4. DISTINCT
-- =============================================================================

-- Unique city names taken from the middle part of USERS.address.
-- Sample addresses follow 'Locality, City, State' (e.g. 'Bandra West, Mumbai, Maharashtra').
SELECT DISTINCT
    TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(address, ',', 2), ',', -1)) AS city
FROM USERS;

-- Unique carbon-activity categories from the CATEGORY lookup table.
SELECT DISTINCT
    category_name AS activity_category
FROM CATEGORY;

-- =============================================================================
-- 5. LIMIT
-- =============================================================================

-- Five carbon records with the highest emissions.
SELECT
    record_id        AS record_number,
    user_id          AS user_number,
    record_date      AS log_date,
    carbon_footprint AS emissions_kg_co2e,
    notes            AS record_notes
FROM CARBON_RECORD
ORDER BY carbon_footprint DESC
LIMIT 5;

-- First five registered users, in the order they were created.
SELECT
    user_id    AS user_number,
    name       AS user_name,
    email      AS email_address,
    created_at AS registered_on
FROM USERS
ORDER BY user_id ASC
LIMIT 5;
