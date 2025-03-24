MODEL (
  name citizenspace.view,
  kind VIEW
);

SELECT
  'citizenspace' AS source,
  title AS name,
  overview AS description,
  LOWER(status) AS status,
  CASE
    WHEN url ILIKE 'https://consultation.health.wa.gov.au/%'
    THEN 'Department of Health'
    WHEN url ILIKE 'https://consult.dwer.wa.gov.au/%'
    THEN 'Department of Water and Environmental Regulation'
    WHEN url ILIKE 'https://consultation.dmirs.wa.gov.au/%'
    THEN 'Department of Energy, Mines, Industry Regulation and Safety'
    WHEN url ILIKE 'https://consultation.infrastructure.wa.gov.au/%'
    THEN 'Infrastructure Western Australia'
    WHEN url ILIKE 'https://consultation.epa.wa.gov.au/%'
    THEN 'Environmental Protection Authority'        
    ELSE department
  END AS agency,
  NULL AS tags,
  'Western Australia' AS region,
  url,
  startdate::DATE AS publishdate,
  enddate::DATE AS expirydate
FROM citizenspace.api