-- harvest.sql — DuckDB SQL pipeline for harvesting consultations
-- Run:  duckdb -c ".read harvest.sql"
-- MySQL target via env vars: MYSQL_HOST, MYSQL_USER, MYSQL_PWD, MYSQL_DATABASE
-- https://duckdb.org/docs/current/core_extensions/mysql#configuration

CREATE OR REPLACE TABLE consultations AS
WITH
-- Canonical department names keyed by host pattern (ILIKE)
departments(host_pattern, agency_name) AS (
    VALUES
    ('consultation.health.wa.gov.au',  'Department of Health'),
    ('consult.dwer.wa.gov.au',         'Department of Water and Environmental Regulation'),
    ('consultation.dmirs.wa.gov.au',   'Department of Energy, Mines, Industry Regulation and Safety')
),

-- Fetch Citizen Space JSON feeds
cs_raw AS (
    SELECT 'citizenspace' AS source, cs.*
    FROM read_json([
        'https://consultation.health.wa.gov.au/api/2.3/json_search_results?fields=extended',
        'https://consult.dwer.wa.gov.au/api/2.3/json_search_results?fields=extended',
        'https://consultation.dmirs.wa.gov.au/api/2.3/json_search_results?fields=extended'
    ]) cs
),

-- Normalise to common consultation schema
consultations AS (
    SELECT
        source,
        title                              AS name,
        overview                           AS description,
        LOWER(status)                      AS status,
        COALESCE(d.agency_name, cs_raw.department) AS agency,
        NULL                               AS tags,
        'Western Australia'                AS region,
        url,
        NULLIF(startdate, '')::DATE        AS publishdate,
        NULLIF(enddate, '')::DATE          AS expirydate
    FROM cs_raw
    LEFT JOIN departments d ON url ILIKE ('%' || d.host_pattern || '%')
)
SELECT * FROM consultations
WHERE status IN ('open', 'closed');

-- Mirror to MySQL
ATTACH '' AS mysqldb (TYPE mysql);
CREATE OR REPLACE TABLE mysqldb.consultations AS SELECT * FROM consultations;
