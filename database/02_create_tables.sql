-- =============================================================================
-- Eco-Track – Carbon Footprint Analyzer
-- Script: 02_create_tables.sql
-- Purpose: Create all 10 schema tables with keys, constraints, and 3NF design.
-- Prerequisite: 01_create_database.sql (database EcoTrack must exist)
-- =============================================================================

USE EcoTrack;

-- -----------------------------------------------------------------------------
-- 1. USERS
-- Registered application users who log carbon-related activity.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS USERS (
    user_id         INT             NOT NULL AUTO_INCREMENT,
    name            VARCHAR(100)    NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    password_hash   VARCHAR(255)    NOT NULL,
    phone           VARCHAR(20)     NULL,
    address         VARCHAR(255)    NULL,
    created_at      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT uq_users_phone UNIQUE (phone),
    CONSTRAINT chk_users_email CHECK (email LIKE '%_@_%.__%'),
    CONSTRAINT chk_users_name CHECK (CHAR_LENGTH(TRIM(name)) > 0)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Application users who own carbon records, goals, and recommendations.';

-- -----------------------------------------------------------------------------
-- 2. CATEGORY
-- Lookup of emission domains (e.g. Transportation, Food, Electricity).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CATEGORY (
    category_id     INT             NOT NULL AUTO_INCREMENT,
    category_name   VARCHAR(80)     NOT NULL,
    description     VARCHAR(500)    NULL,

    CONSTRAINT pk_category PRIMARY KEY (category_id),
    CONSTRAINT uq_category_name UNIQUE (category_name),
    CONSTRAINT chk_category_name CHECK (CHAR_LENGTH(TRIM(category_name)) > 0)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Emission categories used to classify records and emission factors.';

-- -----------------------------------------------------------------------------
-- 3. SUSTAINABILITY_GOAL
-- Shared sustainability targets that users can pursue (independent of users).
-- Placed here because ACHIEVEMENT depends on it; it has no foreign keys.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS SUSTAINABILITY_GOAL (
    goal_id         INT             NOT NULL AUTO_INCREMENT,
    name            VARCHAR(120)    NOT NULL,
    target_date     DATE            NOT NULL,
    description     VARCHAR(500)    NULL,

    CONSTRAINT pk_sustainability_goal PRIMARY KEY (goal_id),
    CONSTRAINT uq_goal_name UNIQUE (name),
    CONSTRAINT chk_goal_name CHECK (CHAR_LENGTH(TRIM(name)) > 0)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Reusable sustainability goals; user progress is stored in ACHIEVEMENT.';

-- -----------------------------------------------------------------------------
-- 4. EMISSION_FACTOR
-- Conversion coefficients (activity → kg CO2e) belonging to one category.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS EMISSION_FACTOR (
    factor_id       INT             NOT NULL AUTO_INCREMENT,
    category_id     INT             NOT NULL,
    activity_name   VARCHAR(120)    NOT NULL,
    factor_value    DECIMAL(12, 6)  NOT NULL,
    unit            VARCHAR(40)     NOT NULL,
    description     VARCHAR(500)    NULL,

    CONSTRAINT pk_emission_factor PRIMARY KEY (factor_id),
    CONSTRAINT uq_factor_activity UNIQUE (category_id, activity_name),
    CONSTRAINT chk_factor_value CHECK (factor_value >= 0),
    CONSTRAINT chk_factor_unit CHECK (CHAR_LENGTH(TRIM(unit)) > 0),
    CONSTRAINT chk_factor_activity CHECK (CHAR_LENGTH(TRIM(activity_name)) > 0),

    CONSTRAINT fk_factor_category
        FOREIGN KEY (category_id)
        REFERENCES CATEGORY (category_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Official emission factors used to convert activity quantities into CO2e.';

-- -----------------------------------------------------------------------------
-- 5. CARBON_RECORD
-- Header row for one logged footprint event (date + total CO2e + category).
-- Detail quantities live in the 1:1 activity tables, not here (3NF).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS CARBON_RECORD (
    record_id           INT             NOT NULL AUTO_INCREMENT,
    user_id             INT             NOT NULL,
    category_id         INT             NOT NULL,
    record_date         DATE            NOT NULL,
    carbon_footprint    DECIMAL(12, 4)  NOT NULL,
    notes               VARCHAR(500)    NULL,

    CONSTRAINT pk_carbon_record PRIMARY KEY (record_id),
    CONSTRAINT uq_record_user UNIQUE (record_id, user_id),
    CONSTRAINT chk_carbon_footprint CHECK (carbon_footprint >= 0),

    CONSTRAINT fk_record_user
        FOREIGN KEY (user_id)
        REFERENCES USERS (user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_record_category
        FOREIGN KEY (category_id)
        REFERENCES CATEGORY (category_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Per-user carbon log headers; activity specifics are in subtype tables.';

-- -----------------------------------------------------------------------------
-- 6. TRANSPORTATION
-- 1:1 detail of a CARBON_RECORD for travel (distance, mode, fuel, factor).
-- record_id is UNIQUE so a record can have at most one transportation row.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS TRANSPORTATION (
    transport_id    INT             NOT NULL AUTO_INCREMENT,
    record_id       INT             NOT NULL,
    mode            VARCHAR(50)     NOT NULL,
    vehicle_type    VARCHAR(50)     NULL,
    distance_km     DECIMAL(10, 2)  NOT NULL,
    fuel_type       VARCHAR(40)     NULL,
    factor_id       INT             NOT NULL,

    CONSTRAINT pk_transportation PRIMARY KEY (transport_id),
    CONSTRAINT uq_transport_record UNIQUE (record_id),
    CONSTRAINT chk_transport_distance CHECK (distance_km > 0),
    CONSTRAINT chk_transport_mode CHECK (CHAR_LENGTH(TRIM(mode)) > 0),

    CONSTRAINT fk_transport_record
        FOREIGN KEY (record_id)
        REFERENCES CARBON_RECORD (record_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_transport_factor
        FOREIGN KEY (factor_id)
        REFERENCES EMISSION_FACTOR (factor_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Transportation activity details linked 1:1 with a carbon record.';

-- -----------------------------------------------------------------------------
-- 7. FOOD_CONSUMPTION
-- 1:1 detail of a CARBON_RECORD for food (type, quantity, unit, factor).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS FOOD_CONSUMPTION (
    food_id         INT             NOT NULL AUTO_INCREMENT,
    record_id       INT             NOT NULL,
    food_type       VARCHAR(80)     NOT NULL,
    quantity        DECIMAL(10, 2)  NOT NULL,
    unit            VARCHAR(30)     NOT NULL,
    factor_id       INT             NOT NULL,

    CONSTRAINT pk_food_consumption PRIMARY KEY (food_id),
    CONSTRAINT uq_food_record UNIQUE (record_id),
    CONSTRAINT chk_food_quantity CHECK (quantity > 0),
    CONSTRAINT chk_food_type CHECK (CHAR_LENGTH(TRIM(food_type)) > 0),
    CONSTRAINT chk_food_unit CHECK (CHAR_LENGTH(TRIM(unit)) > 0),

    CONSTRAINT fk_food_record
        FOREIGN KEY (record_id)
        REFERENCES CARBON_RECORD (record_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_food_factor
        FOREIGN KEY (factor_id)
        REFERENCES EMISSION_FACTOR (factor_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Food consumption details linked 1:1 with a carbon record.';

-- -----------------------------------------------------------------------------
-- 8. ELECTRICITY_USAGE
-- 1:1 detail of a CARBON_RECORD for electricity (kWh and factor).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ELECTRICITY_USAGE (
    usage_id        INT             NOT NULL AUTO_INCREMENT,
    record_id       INT             NOT NULL,
    kwh             DECIMAL(10, 2)  NOT NULL,
    factor_id       INT             NOT NULL,

    CONSTRAINT pk_electricity_usage PRIMARY KEY (usage_id),
    CONSTRAINT uq_electricity_record UNIQUE (record_id),
    CONSTRAINT chk_electricity_kwh CHECK (kwh > 0),

    CONSTRAINT fk_electricity_record
        FOREIGN KEY (record_id)
        REFERENCES CARBON_RECORD (record_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_electricity_factor
        FOREIGN KEY (factor_id)
        REFERENCES EMISSION_FACTOR (factor_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Electricity usage details linked 1:1 with a carbon record.';

-- -----------------------------------------------------------------------------
-- 9. RECOMMENDATION
-- Advice generated for a user, optionally tied to a specific carbon record.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RECOMMENDATION (
    rec_id              INT             NOT NULL AUTO_INCREMENT,
    user_id             INT             NOT NULL,
    record_id           INT             NULL,
    title               VARCHAR(150)    NOT NULL,
    description         VARCHAR(500)    NULL,
    suggested_action    VARCHAR(500)    NOT NULL,
    created_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_recommendation PRIMARY KEY (rec_id),
    CONSTRAINT chk_rec_title CHECK (CHAR_LENGTH(TRIM(title)) > 0),
    CONSTRAINT chk_rec_action CHECK (CHAR_LENGTH(TRIM(suggested_action)) > 0),

    CONSTRAINT fk_rec_user
        FOREIGN KEY (user_id)
        REFERENCES USERS (user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_rec_record_user
        FOREIGN KEY (record_id, user_id)
        REFERENCES CARBON_RECORD (record_id, user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Personalized reduction tips for a user; optionally tied to one of that user''s carbon records.';

-- -----------------------------------------------------------------------------
-- 10. ACHIEVEMENT
-- Progress of one user toward one sustainability goal (associative entity).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ACHIEVEMENT (
    achievement_id  INT             NOT NULL AUTO_INCREMENT,
    user_id         INT             NOT NULL,
    goal_id         INT             NOT NULL,
    progress        DECIMAL(5, 2)   NOT NULL DEFAULT 0.00,
    status          VARCHAR(20)     NOT NULL DEFAULT 'IN_PROGRESS',
    badge_name      VARCHAR(80)     NULL,
    achieved_date   DATE            NULL,

    CONSTRAINT pk_achievement PRIMARY KEY (achievement_id),
    CONSTRAINT uq_achievement_user_goal UNIQUE (user_id, goal_id),
    CONSTRAINT chk_achievement_progress CHECK (progress >= 0 AND progress <= 100),
    CONSTRAINT chk_achievement_status
        CHECK (status IN ('IN_PROGRESS', 'ACHIEVED', 'ABANDONED')),
    CONSTRAINT chk_achievement_date
        CHECK (
            (status = 'ACHIEVED' AND achieved_date IS NOT NULL)
            OR (status <> 'ACHIEVED' AND achieved_date IS NULL)
        ),

    CONSTRAINT fk_achievement_user
        FOREIGN KEY (user_id)
        REFERENCES USERS (user_id)
        ON UPDATE CASCADE
        ON DELETE CASCADE,

    CONSTRAINT fk_achievement_goal
        FOREIGN KEY (goal_id)
        REFERENCES SUSTAINABILITY_GOAL (goal_id)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_unicode_ci
  COMMENT = 'Tracks each user''s progress and badge for a sustainability goal.';
