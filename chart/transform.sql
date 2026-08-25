-- Deterministic transforms. Inputs: citizenspace_raw and engagementhq_raw.

CREATE OR REPLACE TEMP TABLE engagementhq_agency_rules (
    priority INTEGER,
    field VARCHAR,
    value VARCHAR,
    agency VARCHAR
);

INSERT INTO engagementhq_agency_rules VALUES
    (10, 'url', 'engageagric.engagementhq.com', 'Department of Primary Industries and Regional Development'),
    (10, 'url', 'yoursay.dpird.wa.gov.au', 'Department of Primary Industries and Regional Development'),
    (20, 'url', 'haveyoursaywa.engagementhq.com', 'Department of Planning, Lands and Heritage'),
    (30, 'parent-id', '38135', 'Department of Transport and Major Infrastructure'),
    (30, 'tag', 'dot', 'Department of Transport and Major Infrastructure'),
    (30, 'tag', 'dtmi', 'Department of Transport and Major Infrastructure'),
    (30, 'tag', 'taxi', 'Department of Transport and Major Infrastructure'),
    (30, 'tag', 'charter', 'Department of Transport and Major Infrastructure'),
    (30, 'tag', 'on-demand', 'Department of Transport and Major Infrastructure'),
    (30, 'tag', 'passenger transport', 'Department of Transport and Major Infrastructure'),
    (40, 'parent-id', '37726', 'Main Roads Western Australia'),
    (40, 'tag', 'mrwa', 'Main Roads Western Australia'),
    (40, 'tag', 'main roads', 'Main Roads Western Australia'),
    (40, 'tag', 'hvs', 'Main Roads Western Australia'),
    (40, 'tag', 'heavy vehicle', 'Main Roads Western Australia'),
    (50, 'parent-id', '38267', 'METRONET'),
    (50, 'tag', 'metronet', 'METRONET'),
    (60, 'parent-id', '37724', 'Westport'),
    (60, 'tag', 'westport', 'Westport'),
    (70, 'parent-id', '37725', 'Transperth'),
    (70, 'tag', 'transperth', 'Transperth'),
    (80, 'tag', 'pta', 'Public Transport Authority');

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
        WHEN url ILIKE '%consultation.dmirs.wa.gov.au%' THEN 'Department of Local Government, Industry Regulation and Safety'
        ELSE COALESCE(department, 'Government of Western Australia')
    END AS agency,
    'Western Australia' AS region,
    url,
    TRY_CAST(NULLIF(startdate, '') AS DATE) AS publishdate,
    TRY_CAST(NULLIF(enddate, '') AS DATE) AS expirydate
FROM citizenspace_raw;

CREATE OR REPLACE VIEW engagementhq_std AS
SELECT
    'engagementhq' AS source,
    e.id,
    e.name,
    e.description,
    ARRAY_TO_STRING(COALESCE(e."project-tag-list", []), ',') AS tags,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM unnest(COALESCE(e."project-tag-list", [])) AS tag(value)
            WHERE value ILIKE '%close%'
        ) THEN 'closed'
        WHEN e.state ILIKE 'published' THEN 'open'
        WHEN e.state ILIKE 'archived' THEN 'closed'
        ELSE LOWER(COALESCE(e.state, 'unknown'))
    END AS status,
    COALESCE((
        SELECT rule.agency
        FROM engagementhq_agency_rules AS rule
        WHERE (rule.field = 'url' AND e.url ILIKE '%' || rule.value || '%')
           OR (rule.field = 'parent-id' AND e."parent-id" = rule.value)
           OR (rule.field = 'tag' AND EXISTS (
                SELECT 1 FROM unnest(COALESCE(e."project-tag-list", [])) AS tag(value)
                WHERE value ILIKE '%' || rule.value || '%'
           ))
        ORDER BY rule.priority, rule.value
        LIMIT 1
    ), 'Government of Western Australia') AS agency,
    'Western Australia' AS region,
    e.url,
    TRY_CAST(e."published-at" AS DATE) AS publishdate,
    NULL::DATE AS expirydate
FROM engagementhq_raw AS e;

CREATE OR REPLACE TABLE consultations_final AS
SELECT source, name, description, status, agency, tags, region, url, publishdate, expirydate
FROM (
    SELECT * FROM engagementhq_std
    UNION ALL BY NAME
    SELECT * FROM citizenspace_std
)
WHERE status IN ('open', 'closed');
