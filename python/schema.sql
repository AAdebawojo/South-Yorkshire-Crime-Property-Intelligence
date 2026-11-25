-- =====================================================================
--  CrimeData  -  schema for data.police.uk API (South Yorkshire)
--  PostgreSQL 12+.  Safe to run more than once (IF NOT EXISTS everywhere).
--  The Python loader runs this automatically; you can also run it
--  yourself in DBeaver (SQL Editor > Execute SQL Script, Alt+X).
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS police;

-- ---------------------------------------------------------------------
-- Reference tables
-- ---------------------------------------------------------------------

-- /api/forces  and  /api/forces/{id}
CREATE TABLE IF NOT EXISTS police.forces (
    force_id        VARCHAR(50)  PRIMARY KEY,          -- e.g. 'south-yorkshire'
    force_name      VARCHAR(200) NOT NULL,
    url             TEXT,
    telephone       VARCHAR(50),
    description     TEXT
);

-- /api/crimes-street-dates  (months the API currently holds)
CREATE TABLE IF NOT EXISTS police.available_months (
    month           DATE PRIMARY KEY                    -- first day of month
);

-- /api/crime-categories
CREATE TABLE IF NOT EXISTS police.crime_categories (
    category_code   VARCHAR(60)  PRIMARY KEY,          -- e.g. 'burglary'
    category_name   VARCHAR(200) NOT NULL              -- e.g. 'Burglary'
);

-- outcome codes seen in /api/outcomes-at-location
CREATE TABLE IF NOT EXISTS police.outcome_categories (
    outcome_code    VARCHAR(80)  PRIMARY KEY,          -- e.g. 'local-resolution'
    outcome_name    VARCHAR(255) NOT NULL
);

-- ---------------------------------------------------------------------
-- Neighbourhoods
-- ---------------------------------------------------------------------

-- /api/{force}/neighbourhoods  +  /api/{force}/{id}
CREATE TABLE IF NOT EXISTS police.neighbourhoods (
    neighbourhood_id    VARCHAR(60)  PRIMARY KEY,
    force_id            VARCHAR(50)  NOT NULL REFERENCES police.forces(force_id),
    neighbourhood_name  VARCHAR(255) NOT NULL,
    description         TEXT,
    population          INTEGER,
    url_force           TEXT,
    centre_latitude     NUMERIC(9,6),
    centre_longitude    NUMERIC(9,6),
    email               VARCHAR(255),
    telephone           VARCHAR(100),
    website             TEXT,
    boundary_wkt        TEXT,          -- POLYGON((lng lat, ...)) - usable with PostGIS ST_GeomFromText(boundary_wkt, 4326)
    loaded_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- /api/{force}/{id}/boundary  (one row per boundary vertex)
CREATE TABLE IF NOT EXISTS police.neighbourhood_boundary_points (
    neighbourhood_id    VARCHAR(60)  NOT NULL REFERENCES police.neighbourhoods(neighbourhood_id) ON DELETE CASCADE,
    point_order         INTEGER      NOT NULL,
    latitude            NUMERIC(10,7) NOT NULL,
    longitude           NUMERIC(10,7) NOT NULL,
    PRIMARY KEY (neighbourhood_id, point_order)
);

-- ---------------------------------------------------------------------
-- Crime facts
-- ---------------------------------------------------------------------

-- Anonymised map points ("On or near ...").  location.street.id in the API.
CREATE TABLE IF NOT EXISTS police.locations (
    location_id         BIGINT       PRIMARY KEY,
    street_name         VARCHAR(255),
    latitude            NUMERIC(9,6) NOT NULL,
    longitude           NUMERIC(9,6) NOT NULL,
    neighbourhood_id    VARCHAR(60)  REFERENCES police.neighbourhoods(neighbourhood_id)
);
CREATE INDEX IF NOT EXISTS ix_locations_neighbourhood ON police.locations(neighbourhood_id);

-- /api/crimes-street/all-crime  and  /api/crimes-no-location
CREATE TABLE IF NOT EXISTS police.crimes (
    crime_id              BIGINT       PRIMARY KEY,     -- API id (not a police reference)
    persistent_id         VARCHAR(64),                  -- stable 64-char id; empty for anti-social behaviour
    category_code         VARCHAR(60)  NOT NULL REFERENCES police.crime_categories(category_code),
    crime_month           DATE         NOT NULL,
    location_id           BIGINT       REFERENCES police.locations(location_id),  -- NULL = crime with no location
    location_type         VARCHAR(10),                  -- 'Force' or 'BTP' (British Transport Police)
    location_subtype      VARCHAR(100),
    context               TEXT,
    latest_outcome        VARCHAR(255),                 -- outcome_status.category
    latest_outcome_month  DATE,                         -- outcome_status.date
    force_id              VARCHAR(50)  NOT NULL DEFAULT 'south-yorkshire' REFERENCES police.forces(force_id),
    loaded_at             TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ix_crimes_month         ON police.crimes(crime_month);
CREATE INDEX IF NOT EXISTS ix_crimes_category      ON police.crimes(category_code);
CREATE INDEX IF NOT EXISTS ix_crimes_location      ON police.crimes(location_id);
CREATE INDEX IF NOT EXISTS ix_crimes_persistent_id ON police.crimes(persistent_id);

-- /api/outcomes-at-location  (full outcome history; join to crimes on persistent_id)
CREATE TABLE IF NOT EXISTS police.outcomes (
    outcome_row_id      BIGSERIAL    PRIMARY KEY,
    persistent_id       VARCHAR(64)  NOT NULL,
    crime_id            BIGINT,                         -- API id as given in the outcome record
    outcome_code        VARCHAR(80)  NOT NULL REFERENCES police.outcome_categories(outcome_code),
    outcome_month       DATE         NOT NULL,
    person_id           BIGINT,
    crime_category_code VARCHAR(60),
    crime_month         DATE,
    location_id         BIGINT       REFERENCES police.locations(location_id),
    loaded_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_outcomes_natural
    ON police.outcomes (persistent_id, outcome_code, outcome_month, COALESCE(person_id, -1));
CREATE INDEX IF NOT EXISTS ix_outcomes_month ON police.outcomes(outcome_month);

-- ---------------------------------------------------------------------
-- Load bookkeeping (lets the script resume where it stopped)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS police.load_log (
    load_type           VARCHAR(20)  NOT NULL,          -- 'street' or 'no_location'
    neighbourhood_id    VARCHAR(60)  NOT NULL,          -- '_force' for force-wide loads
    month               DATE         NOT NULL,
    status              VARCHAR(10)  NOT NULL,          -- 'done' / 'failed'
    crime_rows          INTEGER,
    outcome_rows        INTEGER,
    error               TEXT,
    loaded_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (load_type, neighbourhood_id, month)
);

CREATE TABLE IF NOT EXISTS police.load_runs (
    run_id              SERIAL       PRIMARY KEY,
    started_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    finished_at         TIMESTAMPTZ,
    api_last_updated    DATE,                           -- /api/crime-last-updated
    months_requested    TEXT,
    tasks_done          INTEGER,
    tasks_failed        INTEGER
);

-- ---------------------------------------------------------------------
-- Convenience views
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW police.v_crimes AS
SELECT  c.crime_id,
        c.persistent_id,
        c.crime_month,
        c.category_code,
        cc.category_name,
        c.location_type,
        c.location_subtype,
        l.location_id,
        l.street_name,
        l.latitude,
        l.longitude,
        n.neighbourhood_id,
        n.neighbourhood_name,
        c.latest_outcome,
        c.latest_outcome_month,
        c.context
FROM        police.crimes            c
JOIN        police.crime_categories  cc ON cc.category_code   = c.category_code
LEFT JOIN   police.locations         l  ON l.location_id      = c.location_id
LEFT JOIN   police.neighbourhoods    n  ON n.neighbourhood_id = l.neighbourhood_id;

CREATE OR REPLACE VIEW police.v_monthly_counts AS
SELECT  crime_month,
        COALESCE(neighbourhood_name, '(no location)') AS neighbourhood_name,
        category_name,
        COUNT(*) AS crime_count
FROM    police.v_crimes
GROUP BY crime_month, COALESCE(neighbourhood_name, '(no location)'), category_name;
