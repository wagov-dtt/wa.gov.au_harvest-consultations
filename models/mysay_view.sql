MODEL (
  name mysay.view,
  kind VIEW
);

SELECT
  'mysay' AS source,
  name,
  description,
  state AS status,
  ARRAY_TO_STRING("project-tag-list", ',') AS tags,
  CASE
    WHEN "parent-id" = '38135' OR tags ILIKE '%dot%'
    THEN 'Department of Transport'
    WHEN "parent-id" = '37726' OR tags ILIKE '%mrwa%' OR tags ILIKE '%main roads%'
    THEN 'Main Roads Western Australia'
    WHEN "parent-id" = '38267' OR tags ILIKE '%metronet%'
    THEN 'METRONET'
    WHEN "parent-id" = '37724' OR tags ILIKE '%westport%'
    THEN 'Westport'
    WHEN "parent-id" = '37725' OR tags ILIKE '%transperth%'
    THEN 'Transperth'
    WHEN tags ILIKE '%pta%'
    THEN 'Public Transport Authority'
    ELSE 'Government of Western Australia'
  END AS agency,
  'Western Australia' AS region,
  url,
  "published-at"::DATE AS publishdate,
  NULL::DATE AS expirydate
FROM mysay.api
WHERE
  status ILIKE 'published' OR status ILIKE 'archived'