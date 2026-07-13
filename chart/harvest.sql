-- harvest.sql — DuckDB SQL pipeline for harvesting consultations
-- Rendered by Helm so db.table can set the target table name.
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

-- Deterministic business logic lives separately so it can be fixture-tested.
.read /etc/config/transform.sql

SELECT source, status, count(*) AS rows
FROM consultations_final
GROUP BY source, status
ORDER BY source, status;

-- ============================================================================
-- 5b. Schema guard: fail the pipeline if output shape or row count regresses
-- ============================================================================
SELECT CASE
    WHEN columns = ['source', 'name', 'description', 'status', 'agency', 'tags', 'region', 'url', 'publishdate', 'expirydate']
    THEN 'schema: ok'
    ELSE error('Schema mismatch. Expected 10 columns: source,name,description,status,agency,tags,region,url,publishdate,expirydate. Got: ' || array_to_string(columns, ','))
END AS schema_check
FROM (
    SELECT array_agg(column_name ORDER BY ordinal_position) AS columns
    FROM information_schema.columns
    WHERE table_name = 'consultations_final'
);

SELECT CASE
    WHEN cnt >= 10 AND cnt <= 50000
    THEN 'rowcount: ok'
    ELSE error('Row count out of bounds: ' || cnt || ' (expected 10-50000)')
END AS rowcount_check
FROM (
    SELECT count(*) AS cnt FROM consultations_final
);

-- ============================================================================
-- 6. Mirror to MySQL using env vars (MYSQL_HOST, MYSQL_USER, MYSQL_PWD, MYSQL_DATABASE)
--    Matches old/harvest.py export behaviour: replace the whole output table.
-- ============================================================================
ATTACH '' AS mysqldb (TYPE mysql);
CREATE OR REPLACE TABLE mysqldb.{{ .Values.db.table }} AS
SELECT * FROM consultations_final;
