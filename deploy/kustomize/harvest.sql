-- harvest.sql — DuckDB SQL pipeline for harvesting consultations.
-- Run:  duckdb -c ".read harvest.sql"
-- MySQL target configured via env vars: MYSQL_HOST, MYSQL_USER, MYSQL_PWD, MYSQL_DATABASE

WITH
config(portal_type, url) AS (VALUES
    ('citizenspace',  'https://consultation.health.wa.gov.au'),
    ('citizenspace',  'https://consult.dwer.wa.gov.au'),
    ('citizenspace',  'https://consultation.dmirs.wa.gov.au'),
    ('engagementhq',  'https://www.mysaytransport.wa.gov.au'),
    ('engagementhq',  'https://haveyoursaywa.engagementhq.com'),
    ('engagementhq',  'https://yoursay.dpird.wa.gov.au')
),

cs_raw AS (
    SELECT 'citizenspace' AS source, c.url AS portal_url, api.*
    FROM config c
    JOIN LATERAL (
        SELECT * FROM read_json(c.url || '/api/2.3/json_search_results?fields=extended')
    ) api ON true
    WHERE c.portal_type = 'citizenspace'
),

ehq_token AS (
    SELECT url, regexp_extract(read_text(url), 'data-thunder="([^"]*)"', 1) AS token
    FROM config
    WHERE portal_type = 'engagementhq'
),

ehq_project AS (
    SELECT 'engagementhq' AS source, t.url AS portal_url, unnest(resp.data) AS p
    FROM ehq_token t
    JOIN LATERAL (
        SELECT * FROM read_json(
            t.url || '/api/v2/projects?per_page=10000',
            extra_http_headers => MAP {'Authorization': 'Bearer ' || t.token}
        )
    ) resp ON true
),

ehq_raw AS (
    SELECT source, portal_url,
        p.id                             AS id,
        p.attributes.state               AS state,
        p.attributes."published-at"      AS "published-at",
        p.attributes.type                AS type,
        p.attributes.name                AS name,
        p.attributes.description         AS description,
        p.attributes."visibility-mode"   AS "visibility-mode",
        p.attributes."image-url"         AS "image-url",
        p.attributes."project-tag-list"  AS "project-tag-list",
        p.attributes."view-count"        AS "view-count",
        p.attributes."parent-id"         AS "parent-id",
        p.links.self                     AS project_url
    FROM ehq_project
),

cs AS (
    SELECT
        source,
        title                              AS name,
        overview                           AS description,
        LOWER(status)                      AS status,
        CASE
            WHEN portal_url ILIKE 'https://consultation.health.wa.gov.au/%'
                THEN 'Department of Health'
            WHEN portal_url ILIKE 'https://consult.dwer.wa.gov.au/%'
                THEN 'Department of Water and Environmental Regulation'
            WHEN portal_url ILIKE 'https://consultation.dmirs.wa.gov.au/%'
                THEN 'Department of Energy, Mines, Industry Regulation and Safety'
            ELSE department
        END                                AS agency,
        NULL                               AS tags,
        'Western Australia'                AS region,
        portal_url                         AS url,
        startdate::DATE                    AS publishdate,
        enddate::DATE                      AS expirydate
    FROM cs_raw
),

ehq AS (
    SELECT
        source, name, description,
        array_to_string("project-tag-list", ',')                           AS tags,
        CASE
            WHEN array_to_string("project-tag-list", ',') ILIKE '%close%'
                THEN 'closed'
            WHEN state ILIKE 'published'  THEN 'open'
            WHEN state ILIKE 'archived'   THEN 'closed'
            ELSE LOWER(state)
        END                                                                AS status,
        CASE
            WHEN project_url ILIKE 'https://engageagric.engagementhq.com/%'
              OR project_url ILIKE 'https://yoursay.dpird.wa.gov.au/%'
                THEN 'Department of Primary Industries and Regional Development'
            WHEN project_url ILIKE 'https://haveyoursaywa.engagementhq.com/%'
                THEN 'Department of Planning, Lands and Heritage'
            WHEN "parent-id" = '38135'
              OR array_to_string("project-tag-list", ',') ILIKE '%dot%'
                THEN 'Department of Transport'
            WHEN "parent-id" = '37726'
              OR array_to_string("project-tag-list", ',') ILIKE '%mrwa%'
              OR array_to_string("project-tag-list", ',') ILIKE '%main roads%'
                THEN 'Main Roads Western Australia'
            WHEN "parent-id" = '38267'
              OR array_to_string("project-tag-list", ',') ILIKE '%metronet%'
                THEN 'METRONET'
            WHEN "parent-id" = '37724'
              OR array_to_string("project-tag-list", ',') ILIKE '%westport%'
                THEN 'Westport'
            WHEN "parent-id" = '37725'
              OR array_to_string("project-tag-list", ',') ILIKE '%transperth%'
                THEN 'Transperth'
            WHEN array_to_string("project-tag-list", ',') ILIKE '%pta%'
                THEN 'Public Transport Authority'
            ELSE 'Government of Western Australia'
        END                                                                AS agency,
        'Western Australia'                                                AS region,
        project_url                                                        AS url,
        "published-at"::DATE                                               AS publishdate,
        NULL::DATE                                                         AS expirydate
    FROM ehq_raw
),

consultations AS (
    SELECT * FROM (
        SELECT * FROM cs
        UNION ALL BY NAME
        SELECT * FROM ehq
    )
    WHERE status IN ('open', 'closed')
)

CREATE OR REPLACE TABLE consultations AS SELECT * FROM consultations;

-- MySQL target (env vars: MYSQL_HOST, MYSQL_USER, MYSQL_PWD, MYSQL_DATABASE)
-- https://duckdb.org/docs/current/core_extensions/mysql#configuration
ATTACH '' AS mysqldb (TYPE mysql);
CREATE OR REPLACE TABLE mysqldb.consultations AS SELECT * FROM consultations;
