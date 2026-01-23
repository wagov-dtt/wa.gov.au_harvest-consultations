-- Standardize EngagementHQ data
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
    WHEN url ILIKE '%engageagric.engagementhq.com%' OR url ILIKE '%yoursay.dpird.wa.gov.au%'
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

-- Standardize CitizenSpace data
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
  TRY_CAST(startdate AS DATE) AS publishdate,
  TRY_CAST(enddate AS DATE) AS expirydate
FROM citizenspace_raw;

-- Union and filter to final table
CREATE OR REPLACE TABLE consultations_final AS
SELECT source, id, name, description, status, tags, agency, region, url, publishdate, expirydate, CURRENT_TIMESTAMP AS loaded_at
FROM (SELECT * FROM engagementhq_std UNION ALL BY NAME SELECT * FROM citizenspace_std)
WHERE status IN ('open', 'closed');
