MODEL (
  name mysay.view,
  kind VIEW
);

SELECT
  'mysay' AS source,
  name,
  description,
  state AS status,
  agency,
  ARRAY_TO_STRING("project-tag-list", ',') AS tags,
  'Western Australia' AS region,
  url,
  "published-at"::DATE AS publishdate,
  NULL::DATE AS expirydate
FROM mysay.api