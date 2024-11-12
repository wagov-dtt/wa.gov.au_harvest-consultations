MODEL (
  name citizenspace.view,
  kind VIEW
);

SELECT
  'citizenspace' AS source,
  title AS name,
  overview AS description,
  status,
  department AS agency,
  'Western Australia' AS region,
  url,
  startdate::DATE AS publishdate,
  enddate::DATE AS expirydate
FROM citizenspace.api