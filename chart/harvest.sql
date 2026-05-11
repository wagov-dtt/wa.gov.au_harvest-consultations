-- harvest.sql — DuckDB SQL pipeline for harvesting consultations
-- Rendered by Helm so mysql.table can set the target table name.
-- MySQL target via DuckDB MySQL env vars: MYSQL_HOST, MYSQL_USER, MYSQL_PWD, MYSQL_DATABASE
-- https://duckdb.org/docs/current/core_extensions/mysql#configuration
--
-- Sources:
--   CitizenSpace — 3 WA government Citizen Space JSON feeds
--   EngagementHQ — 3 WA government EngagementHQ portals. The homepage is read
--                  to extract the anonymous JWT, then /api/v2/projects is read
--                  with an HTTP Authorization header. No Python companion needed.

-- Disable HTTP logging and secret exposure for production safety
SET enable_http_logging = false;
SET allow_unredacted_secrets = false;

LOAD httpfs;
LOAD mysql;

-- Lock down extension loading after required extensions are loaded
SET allow_community_extensions = false;
SET autoinstall_known_extensions = false;
SET autoload_known_extensions = false;

-- EngagementHQ pages can emit a new ETag while DuckDB is reading generated HTML.
SET unsafe_disable_etag_checks = true;

-- ============================================================================
-- 1. Fetch CitizenSpace data from WA Gov APIs
-- ============================================================================
CREATE OR REPLACE TABLE citizenspace_raw AS
SELECT cs.*
FROM read_json(
    [
        'https://consultation.health.wa.gov.au/api/2.3/json_search_results?fields=extended',
        'https://consult.dwer.wa.gov.au/api/2.3/json_search_results?fields=extended',
        'https://consultation.dmirs.wa.gov.au/api/2.3/json_search_results?fields=extended'
    ],
    union_by_name = true
) cs;

-- ============================================================================
-- 2. Fetch EngagementHQ data from WA Gov portals
-- ============================================================================
SET VARIABLE mysaytransport_token = (
    SELECT COALESCE(
        NULLIF(regexp_extract(content, 'eyJ[A-Za-z0-9._-]+', 0), ''),
        NULLIF(regexp_extract(content, 'data-thunder="([^"]*)"', 1), '')
    )
    FROM read_text('https://www.mysaytransport.wa.gov.au/')
);

SET VARIABLE haveyoursaywa_token = (
    SELECT COALESCE(
        NULLIF(regexp_extract(content, 'eyJ[A-Za-z0-9._-]+', 0), ''),
        NULLIF(regexp_extract(content, 'data-thunder="([^"]*)"', 1), '')
    )
    FROM read_text('https://haveyoursaywa.engagementhq.com/')
);

SET VARIABLE yoursay_dpird_token = (
    SELECT COALESCE(
        NULLIF(regexp_extract(content, 'eyJ[A-Za-z0-9._-]+', 0), ''),
        NULLIF(regexp_extract(content, 'data-thunder="([^"]*)"', 1), '')
    )
    FROM read_text('https://yoursay.dpird.wa.gov.au/')
);

-- Fail closed at the upstream trust boundary if a portal stops exposing an auth token.
SELECT CASE
    WHEN length(getvariable('mysaytransport_token')) > 0 THEN true
    ELSE error('EngagementHQ token not found: https://www.mysaytransport.wa.gov.au/')
END AS mysaytransport_token_ok;

SELECT CASE
    WHEN length(getvariable('haveyoursaywa_token')) > 0 THEN true
    ELSE error('EngagementHQ token not found: https://haveyoursaywa.engagementhq.com/')
END AS haveyoursaywa_token_ok;

SELECT CASE
    WHEN length(getvariable('yoursay_dpird_token')) > 0 THEN true
    ELSE error('EngagementHQ token not found: https://yoursay.dpird.wa.gov.au/')
END AS yoursay_dpird_token_ok;

CREATE OR REPLACE TEMPORARY SECRET mysaytransport_api (
    TYPE http,
    SCOPE 'https://www.mysaytransport.wa.gov.au/api/v2/projects',
    EXTRA_HTTP_HEADERS MAP {'Authorization': 'Bearer ' || getvariable('mysaytransport_token')}
);

CREATE OR REPLACE TEMPORARY SECRET haveyoursaywa_api (
    TYPE http,
    SCOPE 'https://haveyoursaywa.engagementhq.com/api/v2/projects',
    EXTRA_HTTP_HEADERS MAP {'Authorization': 'Bearer ' || getvariable('haveyoursaywa_token')}
);

CREATE OR REPLACE TEMPORARY SECRET yoursay_dpird_api (
    TYPE http,
    SCOPE 'https://yoursay.dpird.wa.gov.au/api/v2/projects',
    EXTRA_HTTP_HEADERS MAP {'Authorization': 'Bearer ' || getvariable('yoursay_dpird_token')}
);

CREATE OR REPLACE TABLE engagementhq_raw AS
SELECT
    project.id::VARCHAR AS id,
    project.attributes.name::VARCHAR AS name,
    project.attributes.description::VARCHAR AS description,
    project.attributes.state::VARCHAR AS state,
    project.links.self::VARCHAR AS url,
    CAST(struct_extract(project.attributes, 'published-at') AS VARCHAR) AS "published-at",
    CAST(struct_extract(project.attributes, 'project-tag-list') AS VARCHAR[]) AS "project-tag-list",
    CAST(struct_extract(project.attributes, 'parent-id') AS VARCHAR) AS "parent-id",
    'https://www.mysaytransport.wa.gov.au' AS portal
FROM read_json(
    'https://www.mysaytransport.wa.gov.au/api/v2/projects?per_page=10000',
    maximum_object_size = 100000000
), unnest(data) AS t(project)

UNION ALL

SELECT
    project.id::VARCHAR AS id,
    project.attributes.name::VARCHAR AS name,
    project.attributes.description::VARCHAR AS description,
    project.attributes.state::VARCHAR AS state,
    project.links.self::VARCHAR AS url,
    CAST(struct_extract(project.attributes, 'published-at') AS VARCHAR) AS "published-at",
    CAST(struct_extract(project.attributes, 'project-tag-list') AS VARCHAR[]) AS "project-tag-list",
    CAST(struct_extract(project.attributes, 'parent-id') AS VARCHAR) AS "parent-id",
    'https://haveyoursaywa.engagementhq.com' AS portal
FROM read_json(
    'https://haveyoursaywa.engagementhq.com/api/v2/projects?per_page=10000',
    maximum_object_size = 100000000
), unnest(data) AS t(project)

UNION ALL

SELECT
    project.id::VARCHAR AS id,
    project.attributes.name::VARCHAR AS name,
    project.attributes.description::VARCHAR AS description,
    project.attributes.state::VARCHAR AS state,
    project.links.self::VARCHAR AS url,
    CAST(struct_extract(project.attributes, 'published-at') AS VARCHAR) AS "published-at",
    CAST(struct_extract(project.attributes, 'project-tag-list') AS VARCHAR[]) AS "project-tag-list",
    CAST(struct_extract(project.attributes, 'parent-id') AS VARCHAR) AS "parent-id",
    'https://yoursay.dpird.wa.gov.au' AS portal
FROM read_json(
    'https://yoursay.dpird.wa.gov.au/api/v2/projects?per_page=10000',
    maximum_object_size = 100000000
), unnest(data) AS t(project);

-- ============================================================================
-- 3. Standardize CitizenSpace data (matches old/transforms.sql)
-- ============================================================================
CREATE OR REPLACE VIEW citizenspace_std AS
SELECT
    'citizenspace' AS source,
    id,
    title AS name,
    overview AS description,
    NULL::VARCHAR AS tags,
    LOWER(COALESCE(status, 'unknown')) AS status,
    CASE
        WHEN url ILIKE '%consultation.health.wa.gov.au%' THEN 'Department of Health'
        WHEN url ILIKE '%consult.dwer.wa.gov.au%' THEN 'Department of Water and Environmental Regulation'
        WHEN url ILIKE '%consultation.dmirs.wa.gov.au%' THEN 'Department of Energy, Mines, Industry Regulation and Safety'
        ELSE COALESCE(department, 'Government of Western Australia')
    END AS agency,
    'Western Australia' AS region,
    url,
    TRY_CAST(NULLIF(startdate, '') AS DATE) AS publishdate,
    TRY_CAST(NULLIF(enddate, '') AS DATE) AS expirydate
FROM citizenspace_raw;

-- ============================================================================
-- 4. Standardize EngagementHQ data (matches old/transforms.sql)
-- ============================================================================
CREATE OR REPLACE VIEW engagementhq_std AS
SELECT
    'engagementhq' AS source,
    id,
    name,
    description,
    ARRAY_TO_STRING(COALESCE("project-tag-list", []), ',') AS tags,
    CASE
        WHEN tags ILIKE '%close%' THEN 'closed'
        WHEN state ILIKE 'published' THEN 'open'
        WHEN state ILIKE 'archived' THEN 'closed'
        ELSE LOWER(COALESCE(state, 'unknown'))
    END AS status,
    CASE
        WHEN url ILIKE '%engageagric.engagementhq.com%'
          OR url ILIKE '%yoursay.dpird.wa.gov.au%'
            THEN 'Department of Primary Industries and Regional Development'
        WHEN url ILIKE '%haveyoursaywa.engagementhq.com%'
            THEN 'Department of Planning, Lands and Heritage'
        WHEN "parent-id" = '38135' OR tags ILIKE '%dot%'
            THEN 'Department of Transport'
        WHEN "parent-id" = '37726' OR tags ILIKE '%mrwa%' OR tags ILIKE '%main roads%'
            THEN 'Main Roads Western Australia'
        WHEN "parent-id" = '38267' OR tags ILIKE '%metronet%' THEN 'METRONET'
        WHEN "parent-id" = '37724' OR tags ILIKE '%westport%' THEN 'Westport'
        WHEN "parent-id" = '37725' OR tags ILIKE '%transperth%' THEN 'Transperth'
        WHEN tags ILIKE '%pta%' THEN 'Public Transport Authority'
        ELSE 'Government of Western Australia'
    END AS agency,
    'Western Australia' AS region,
    url,
    TRY_CAST("published-at" AS DATE) AS publishdate,
    NULL::DATE AS expirydate
FROM engagementhq_raw;

-- ============================================================================
-- 5. Union all sources, filter, and write final table
-- ============================================================================
CREATE OR REPLACE TABLE consultations_final AS
SELECT
    source,
    name,
    description,
    status,
    agency,
    tags,
    region,
    url,
    publishdate,
    expirydate
FROM (
    SELECT * FROM engagementhq_std
    UNION ALL BY NAME
    SELECT * FROM citizenspace_std
)
WHERE status IN ('open', 'closed');

SELECT source, status, count(*) AS rows
FROM consultations_final
GROUP BY source, status
ORDER BY source, status;

-- ============================================================================
-- 6. Mirror to MySQL using env vars (MYSQL_HOST, MYSQL_USER, MYSQL_PWD, MYSQL_DATABASE)
--    Matches old/harvest.py export behaviour: replace the whole output table.
-- ============================================================================
ATTACH '' AS mysqldb (TYPE mysql);
CREATE OR REPLACE TABLE mysqldb.{{ .Values.mysql.table }} AS
SELECT * FROM consultations_final;
